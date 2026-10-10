class_name AOESkill
extends SkillData

## 范围伤害技能：以自身为中心，对半径内所有敌人结算伤害与径向击退。

@export_group("AOE 伤害属性")
@export var radius: float = 500.0                # 伤害半径（像素）
@export var damage: int = 35                    # 伤害数值
@export var knockback_force: float = 350.0      # 击退力度
@export var wave_color: Color = Color(1.0, 0.4, 0.2, 0.6) # 冲击波颜色（橙红）


func _execute(caster: CharacterBody2D, _aim_dir: Vector2) -> void:
	# 1. 播放轻量冲击波视觉反馈
	spawn_ring_fx(caster, radius, wave_color)

	# 2. 伤害要吃掉施法者身上的攻击力增益
	var actual_damage: int = damage
	if caster.has_method("scale_damage"):
		actual_damage = caster.scale_damage(damage)

	# 3. 结算范围内所有敌人
	for victim in find_enemies_in_radius(caster, radius):
		if not victim.has_method("take_damage"):
			continue
		var knock_dir: Vector2 = (victim.global_position - caster.global_position).normalized()
		if knock_dir == Vector2.ZERO:
			knock_dir = Vector2.RIGHT
		victim.take_damage(actual_damage, knock_dir * knockback_force)
