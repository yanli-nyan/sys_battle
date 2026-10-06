class_name SkillData
extends Resource

@export var skill_name: String = "基础技能"
@export var cooldown: float = 1.0
@export var icon: Texture2D

var _current_cooldown: float = 0.0

func update_cooldown(delta: float) -> void:
	if _current_cooldown > 0.0:
		_current_cooldown -= delta

func is_ready() -> bool:
	return _current_cooldown <= 0.0

func try_cast(caster: CharacterBody2D, aim_dir: Vector2) -> bool:
	if not is_ready():
		return false
	_current_cooldown = cooldown
	_execute(caster, aim_dir)
	return true

func _execute(_caster: CharacterBody2D, _aim_dir: Vector2) -> void:
	pass