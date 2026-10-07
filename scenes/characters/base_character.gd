extends CharacterBody2D

# 核心数据引用
@export var character_data: CharacterData

# 运行态技能与朝向数据
var runtime_skills: Array[SkillData] = []
var aim_direction: Vector2 = Vector2.RIGHT
var move_direction: Vector2 = Vector2.ZERO

# 状态控制
var current_hp: int = 100
var is_attacking: bool = false
var can_cancel_attack: bool = false
var current_combo: int = 0
var combo_timer: float = 0.0

signal died(victim: CharacterBody2D)

@onready var hitbox_pivot: Node2D = $HitboxPivot
@onready var hitbox: Area2D = $HitboxPivot/Hitbox
@onready var hurtbox: Area2D = $Hurtbox

@onready var visual_sprite: Sprite2D = $Visual/Sprite2D

# base_character.gd 顶部获取节点引用
@onready var health_bar: ProgressBar = $HealthBar

func _ready() -> void:
	if character_data:
		apply_data(character_data)
	# 监听攻击盒碰触到目标的信号
	hitbox.area_entered.connect(_on_hitbox_area_entered)

func apply_data(data: CharacterData) -> void:
	character_data = data
	current_hp = data.max_hp
	
	# 初始化血条上限与当前值
	if health_bar:
		health_bar.max_value = data.max_hp
		health_bar.value = current_hp
	
	# 深拷贝技能实例，确保不同角色的冷却独立计算
	runtime_skills.clear()
	for skill in data.active_skills:
		if skill:
			runtime_skills.append(skill.duplicate())

func _physics_process(delta: float) -> void:
	# 1. 推进所有已装备技能的冷却
	for skill in runtime_skills:
		skill.update_cooldown(delta)

	# 2. 连击计时重置
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			current_combo = 0

	# 3. 基础移动与朝向记录
	var speed = character_data.move_speed if character_data else 160.0
	velocity = move_direction.normalized() * speed
	move_and_slide()

	if move_direction.length_squared() > 0.0:
		aim_direction = move_direction.normalized()

	# 让攻击判定轴心实时朝向当前瞄准/移动方向
	if aim_direction.length_squared() > 0.0:
		hitbox_pivot.rotation = aim_direction.angle()

# 执行普攻挥砍
func perform_basic_attack() -> void:
	if is_attacking or not character_data or not character_data.basic_attack:
		return
	
	is_attacking = true
	
	# 取出当前连段伤害
	var damage = character_data.basic_attack.damages[current_combo]
	hitbox.set_meta("damage", damage) # 将伤害值暂存在 Hitbox 上
	
	# 激活 Hitbox 0.1 秒后立即关闭（挥砍判定窗口）
	hitbox.monitoring = true
	
	var timer = get_tree().create_timer(0.1)
	timer.timeout.connect(func():
		hitbox.monitoring = false
		is_attacking = false
		current_combo = (current_combo + 1) % character_data.basic_attack.damages.size()
	)

# 技能释放接口
func cast_active_skill(slot_index: int) -> void:
	if is_attacking and not can_cancel_attack:
		return
	
	if slot_index >= 0 and slot_index < runtime_skills.size():
		if runtime_skills[slot_index].try_cast(self, aim_direction):
			is_attacking = false


# 攻击盒命中了某个受击盒
func _on_hitbox_area_entered(other_hurtbox: Area2D) -> void:
	# 排除自身：不能砍到自己
	if other_hurtbox.owner == self:
		return
	
	var victim = other_hurtbox.owner
	if victim and victim.has_method("take_damage"):
		var damage: int = hitbox.get_meta("damage", 10)
		var knockback_dir: Vector2 = (victim.global_position - global_position).normalized()
		victim.take_damage(damage, knockback_dir * 200.0)

# 承受伤害
func take_damage(amount: int, knockback_impulse: Vector2 = Vector2.ZERO) -> void:
	current_hp = maxi(0, current_hp - amount)
	print(name, " 受到伤害: ", amount, " | 剩余 HP: ", current_hp)

	# 动态刷新血条显示
	if health_bar:
		health_bar.value = current_hp


	# 受击红闪效果
	var tween = create_tween()
	visual_sprite.modulate = Color.RED
	tween.tween_property(visual_sprite, "modulate", Color.WHITE, 0.15)

	if current_hp <= 0:
		die()

func die() -> void:
	print(name, " 阵亡！")
	died.emit(self)
	queue_free()