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

@onready var visual_sprite: Sprite2D = $Visual/Sprite2D

func _ready() -> void:
	if character_data:
		apply_data(character_data)

func apply_data(data: CharacterData) -> void:
	character_data = data
	current_hp = data.max_hp
	
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

# 普攻接口
func perform_basic_attack() -> void:
	if is_attacking or not character_data or not character_data.basic_attack:
		return
	
	is_attacking = true
	# 此处后续接入具体打击帧与连段逻辑
	# 待攻击动作结束后重置 is_attacking = false

# 技能释放接口
func cast_active_skill(slot_index: int) -> void:
	if is_attacking and not can_cancel_attack:
		return
	
	if slot_index >= 0 and slot_index < runtime_skills.size():
		if runtime_skills[slot_index].try_cast(self, aim_direction):
			is_attacking = false