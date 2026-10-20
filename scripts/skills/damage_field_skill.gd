class_name DamageFieldSkill
extends SkillData

## 持续伤害领域：在施法位置生成一个固定不动的伤害区域。
##
## 领域一旦生成就与施法者彻底解绑——施法者可以跑开继续打，
## 圈内的其他角色则在 duration 内按 tick_interval 反复掉血，到点自动消散。

const DAMAGE_FIELD_SCRIPT: GDScript = preload("res://scripts/skills/damage_field.gd")

@export_group("伤害领域")
## 作用半径（像素）
@export var radius: float = 220.0
## 每 tick 造成的伤害（会吃施法者的攻击力增益）
@export var damage_per_tick: int = 4
## 两次伤害之间的间隔（秒）
@export var tick_interval: float = 1.0
## 领域存在时间（秒）
@export var duration: float = 20.0
## 领域主色
@export var field_color: Color = Color(0.55, 0.3, 0.9, 0.55)
## 落到世界层时使用的节点名，便于在远程树里辨认
@export var field_node_name: String = "DamageField"


func _execute(caster: CharacterBody2D, _aim_dir: Vector2) -> void:
	if caster == null:
		return
	var parent := caster.get_parent()
	if parent == null:
		return

	# 起手一次扩散反馈，让「圈已经画在这里了」有明确的瞬间
	spawn_ring_fx(caster, radius, field_color, 0.3)

	var field = DAMAGE_FIELD_SCRIPT.new()
	field.name = field_node_name
	field.radius = radius
	field.damage_per_tick = damage_per_tick
	field.tick_interval = maxf(tick_interval, 0.05)
	field.duration = maxf(duration, 0.1)
	field.field_color = field_color
	field.caster = caster

	# 挂到战局世界层，而不是施法者身上：
	# 位置只在这里取一次快照，之后施法者怎么跑都不会带着领域移动。
	parent.add_child(field)
	field.global_position = caster.global_position
