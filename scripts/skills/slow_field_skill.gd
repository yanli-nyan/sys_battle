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
## 攻速倍率：减速期间目标的出手速度。1.0 = 不影响，0.6 = 出手间隔变成 1.67 倍
## 意义：单纯减速在 1v1 里几乎零收益（对方只是走得慢一点，照样能打）。
## 减攻速才是真正的压制手段——它直接削减对方的输出，把"控住"变成"打不过"。
@export_range(0.1, 1.0, 0.05) var attack_speed_multiplier: float = 1.0
## 易伤倍率：减速期间目标承受的伤害倍率。1.0 = 无易伤
@export_range(1.0, 2.0, 0.05) var damage_taken_multiplier: float = 1.0
## 自我攻速倍率：施法时同时给自己挂上的攻速加成。
## > 1 表示自己出手变快，配合"拖慢对手"形成攻防差——这是这个技能真正的收益来源。
@export_range(1.0, 2.0, 0.05) var caster_attack_speed_multiplier: float = 1.0
## 力场圆环颜色
@export var field_color: Color = Color(0.35, 0.6, 1.0, 0.7)


func _execute(caster: CharacterBody2D, _aim_dir: Vector2) -> void:
	spawn_ring_fx(caster, radius, field_color, 0.35)

	# 先给自己挂攻速：拖慢对手的同时自己加速，形成攻防差
	if caster_attack_speed_multiplier > 1.0 and caster.has_method("apply_modifier"):
		caster.apply_modifier(MOD_ATTACK_SPEED, caster_attack_speed_multiplier, duration, self)

	for victim in find_enemies_in_radius(caster, radius):
		if not victim.has_method("apply_modifier"):
			continue
		# 移动减速
		victim.apply_modifier(MOD_MOVE_SPEED, speed_multiplier, duration, self)
		# 出手减速
		if attack_speed_multiplier < 1.0:
			victim.apply_modifier(MOD_ATTACK_SPEED, attack_speed_multiplier, duration, self)
		# 易伤
		if damage_taken_multiplier > 1.0:
			victim.apply_modifier(MOD_DAMAGE_TAKEN, damage_taken_multiplier, duration, self)
