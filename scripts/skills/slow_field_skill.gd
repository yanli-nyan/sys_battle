class_name SlowFieldSkill
extends SkillData

## 大范围减速：对半径内所有敌人施加限时的移动速度削弱。
## 与自我强化共用同一套属性修正系统，因此和加速 buff 会按来源叠乘，而不是互相顶掉。

@export_group("减速力场")
## 作用半径（像素）
@export var radius: float = 450.0
## 命中后的移动速度倍率，越小越慢
@export_range(0.05, 1.0, 0.05) var speed_multiplier: float = 0.45
## 减速持续时间（秒）
@export var duration: float = 3.0
## 力场圆环颜色
@export var field_color: Color = Color(0.35, 0.6, 1.0, 0.7)


func _execute(caster: CharacterBody2D, _aim_dir: Vector2) -> void:
	spawn_ring_fx(caster, radius, field_color, 0.35)

	for victim in find_enemies_in_radius(caster, radius):
		if victim.has_method("apply_modifier"):
			victim.apply_modifier(MOD_MOVE_SPEED, speed_multiplier, duration, self)
