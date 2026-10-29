extends CharacterBody2D

## 普攻判定窗口（秒）。窗口内 Hitbox 保持开启，且不再接受新的出刀请求。
## 固定值，不随攻速变化：攻速只决定「多久能挥下一刀」，不改变单刀的有效帧。
const ATTACK_WINDOW: float = 0.1

# 核心数据引用
@export var character_data: CharacterData

# 运行态技能与朝向数据
var runtime_skills: Array[SkillData] = []
var aim_direction: Vector2 = Vector2.RIGHT
var move_direction: Vector2 = Vector2.ZERO

# 状态控制
var current_hp: int = 100
## 当前生效的生命上限（基础值 × MOD_MAX_HP 倍率）。
## 缓存一份才能在上限抬高时只补「差额」而不是直接回满血。
var _current_max_hp: float = 100.0
var is_attacking: bool = false
var can_cancel_attack: bool = false
var current_combo: int = 0
var combo_timer: float = 0.0
## 距下一次可以出刀还剩多少秒（由 BasicAttackData.attack_rate 决定，见 perform_basic_attack）
var _attack_cooldown: float = 0.0

## 临时属性修正（增益 / 减益）。
## key -> { 来源实例 id -> { "multiplier": float, "remaining": float } }
## 按来源分开存放，同一个技能重复释放只会刷新自己那一条，
## 不同来源（自己的加速 + 敌人的减速）则叠乘，不会互相顶掉。
var _modifiers: Dictionary = {}

signal died(victim: CharacterBody2D)

@onready var hitbox_pivot: Node2D = $HitboxPivot
@onready var hitbox: Area2D = $HitboxPivot/Hitbox
@onready var hitbox_shape: CollisionShape2D = $HitboxPivot/Hitbox/CollisionShape2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var hurtbox_shape: CollisionShape2D = $Hurtbox/CollisionShape2D

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
	_current_max_hp = float(data.max_hp)

	# 换配置等于重新初始化，攻击状态一并归零
	is_attacking = false
	_attack_cooldown = 0.0
	current_combo = 0
	combo_timer = 0.0

	# 换配置等于重新初始化，先清掉旧的临时修正
	clear_modifiers()
	
	# 初始化血条上限与当前值
	if health_bar:
		health_bar.max_value = _current_max_hp
		health_bar.value = current_hp

	# 动态替换贴图与偏移
	if visual_sprite:
		if data.sprite_texture:
			visual_sprite.texture = data.sprite_texture
		visual_sprite.offset = data.texture_offset
	
	# 判定盒 / 受击盒尺寸同样由数据驱动，每个角色可以有各自的攻击距离与体型
	_refresh_hitbox_radius()
	_apply_shape_radius(hurtbox_shape, data.hurtbox_radius, "Hurtbox")

	# 深拷贝技能实例，确保不同角色的冷却独立计算
	runtime_skills.clear()
	for skill in data.active_skills:
		if skill:
			runtime_skills.append(skill.duplicate())

# 把数据里的半径写到碰撞形状上（Hitbox / Hurtbox 共用）。
# 注意：场景里的 SubResource 在所有实例之间是共享的，必须先拷贝再改，
# 否则同屏多个角色会互相覆盖，最后全都变成同一个尺寸。
func _apply_shape_radius(shape_node: CollisionShape2D, radius: float, label: String) -> void:
	if shape_node == null:
		return

	var circle := shape_node.shape as CircleShape2D
	if circle == null:
		push_warning("%s 的碰撞形状不是 CircleShape2D，尺寸配置不会生效。" % label)
		return

	var shaped := circle.duplicate() as CircleShape2D
	shaped.radius = radius
	shape_node.shape = shaped


# ---------- 临时属性修正（增益 / 减益） ----------

## 挂上一段限时的属性修正。source 传技能自身即可：
## 同一来源重复释放只刷新时长与倍率，不会自己叠自己；不同来源则叠乘。
## key 用 SkillData 里的 MOD_* 常量。
func apply_modifier(key: StringName, multiplier: float, duration: float, source: Object = null) -> void:
	var source_id: int = 0
	if source != null:
		source_id = source.get_instance_id()

	if not _modifiers.has(key):
		_modifiers[key] = {}
	_modifiers[key][source_id] = {"multiplier": multiplier, "remaining": duration}
	_on_modifier_changed(key)


## 取某个属性的当前总倍率；没有任何修正时返回 default_value
func get_modifier(key: StringName, default_value: float = 1.0) -> float:
	if not _modifiers.has(key):
		return default_value
	var total := 1.0
	for entry in _modifiers[key].values():
		total *= float(entry["multiplier"])
	return total


## 立刻清空所有修正（换配置或死亡时用）
func clear_modifiers() -> void:
	_modifiers.clear()
	_refresh_hitbox_radius()
	_refresh_max_hp()


func has_modifier(key: StringName) -> bool:
	return _modifiers.has(key)


func _update_modifiers(delta: float) -> void:
	if _modifiers.is_empty():
		return

	var changed: Array[StringName] = []
	for raw_key in _modifiers.keys():
		var key: StringName = raw_key
		var entries: Dictionary = _modifiers[key]
		var expired: Array = []
		for source_id in entries.keys():
			var entry: Dictionary = entries[source_id]
			entry["remaining"] = float(entry["remaining"]) - delta
			if entry["remaining"] <= 0.0:
				expired.append(source_id)
		for source_id in expired:
			entries.erase(source_id)
		if entries.is_empty():
			_modifiers.erase(key)
		if not expired.is_empty():
			changed.append(key)

	for key in changed:
		_on_modifier_changed(key)


func _on_modifier_changed(key: StringName) -> void:
	# 攻击距离是靠判定盒半径实现的，倍率一变就要把形状尺寸重算回去
	if key == SkillData.MOD_ATTACK_RANGE:
		_refresh_hitbox_radius()
	# 生命上限同理：上限一变，血条刻度和当前血量都要跟着重算
	if key == SkillData.MOD_MAX_HP:
		_refresh_max_hp()


## 按「基础半径 × 攻击距离倍率」刷新普攻判定盒
func _refresh_hitbox_radius() -> void:
	var base_radius := 18.0
	if character_data:
		base_radius = character_data.hitbox_radius
	_apply_shape_radius(hitbox_shape, base_radius * get_modifier(SkillData.MOD_ATTACK_RANGE), "Hitbox")


## 按「基础上限 × 生命上限倍率」重算血条上限。
## A 方案：上限抬高时把差额直接补进当前血量（相当于一次只补差额的治疗），
## 上限回落时把当前血量截断到新上限，避免出现「血比上限还多」的怪状态。
func _refresh_max_hp() -> void:
	var base_hp := 100.0
	if character_data:
		base_hp = float(character_data.max_hp)

	var new_max: float = base_hp * get_modifier(SkillData.MOD_MAX_HP)
	var delta := new_max - _current_max_hp
	_current_max_hp = new_max

	if health_bar:
		health_bar.max_value = new_max

	if delta > 0.0:
		# 上限被抬高：把多出来的部分补给当前血量
		current_hp = clampi(int(round(float(current_hp) + delta)), 0, int(round(new_max)))
	else:
		# 上限回落：当前血量不允许超过新上限
		current_hp = mini(current_hp, int(round(new_max)))

	if health_bar:
		health_bar.value = current_hp


## 把基础伤害换算成实际伤害（含攻击力增益）。普攻与技能都走这里，保证 buff 一致生效。
func scale_damage(base_damage: float) -> int:
	return int(round(base_damage * get_modifier(SkillData.MOD_ATTACK_POWER)))

func _physics_process(delta: float) -> void:
	# 0. 推进临时属性修正的计时
	_update_modifiers(delta)

	# 1. 推进所有已装备技能的冷却
	for skill in runtime_skills:
		skill.update_cooldown(delta)

	# 2. 连击计时重置
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			current_combo = 0

	# 2.5 攻速冷却推进
	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	# 3. 基础移动与朝向记录（移速受加速 / 减速影响）
	var speed: float = character_data.move_speed if character_data else 160.0
	speed *= get_modifier(SkillData.MOD_MOVE_SPEED)
	velocity = move_direction.normalized() * speed
	move_and_slide()

	if move_direction.length_squared() > 0.0:
		aim_direction = move_direction.normalized()

	# 让攻击判定轴心实时朝向当前瞄准/移动方向
	if aim_direction.length_squared() > 0.0:
		hitbox_pivot.rotation = aim_direction.angle()

# 执行普攻挥砍
func perform_basic_attack() -> void:
	if is_attacking or _attack_cooldown > 0.0:
		return
	if not character_data or not character_data.basic_attack:
		return

	var data: BasicAttackData = character_data.basic_attack
	if data.damages.is_empty():
		return

	# 连段长度两条防线：combo_count 决定本次能打到第几段，damages 长度是物理上限
	var segments: int = data.damages.size()
	if data.combo_count > 0:
		segments = mini(segments, data.combo_count)
	if current_combo >= segments:
		current_combo = 0

	is_attacking = true
	# 一次挥砍把整个攻速间隔占住，期间 _attack_cooldown 未归零则不会再有新出刀
	_attack_cooldown = maxf(data.attack_rate, ATTACK_WINDOW)

	# 取出当前连段伤害（含攻击力增益）
	var damage: int = scale_damage(data.damages[current_combo])
	hitbox.set_meta("damage", damage) # 将伤害值暂存在 Hitbox 上

	# 激活 Hitbox 直到判定窗口结束
	hitbox.monitoring = true

	var timer = get_tree().create_timer(ATTACK_WINDOW)
	var finished_combo: int = current_combo
	timer.timeout.connect(func():
		hitbox.monitoring = false
		is_attacking = false
		# 只有这一刀还是「最新的一刀」时才推进连段，避免连按把段数推飞
		if current_combo == finished_combo:
			current_combo = (current_combo + 1) % segments
			combo_timer = data.combo_reset_time
	)

# ---------- 技能槽查询（供 HUD 等外部系统读取） ----------

## 本角色实际装备了几个技能槽
func get_skill_count() -> int:
	return runtime_skills.size()


## 取第 slot_index 个技能；越界或为空时返回 null
func get_skill(slot_index: int) -> SkillData:
	if slot_index < 0 or slot_index >= runtime_skills.size():
		return null
	return runtime_skills[slot_index]


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

## 当前生命上限的整数值（已含 MOD_MAX_HP 修正），供技能计算比例上限。
func get_max_hp() -> int:
	return int(round(_current_max_hp))


## 恢复生命值。数值钳制在 [0, 当前生命上限]，上限用 _current_max_hp，
## 所以「壮骨」期间回血也能回得更多。返回实际恢复量，吸了 0 血时调用方靠它判断。
func heal(amount: int) -> int:
	if amount <= 0 or current_hp <= 0:
		return 0

	var before := current_hp
	current_hp = mini(get_max_hp(), current_hp + amount)

	var healed := current_hp - before
	if healed > 0:
		print(name, " 恢复生命: ", healed, " | 剩余 HP: ", current_hp)

	if health_bar and healed > 0:
		health_bar.value = current_hp

	return healed

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