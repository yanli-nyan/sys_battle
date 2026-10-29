class_name LifestealAOESkill
extends SkillData

## 范围吸血技能：以自身为中心结算一次范围伤害，再按「实际打掉的血量」回流给自己。
##
## 与其他范围技能的区别：回血量按实际造成的伤害折算，而不是固定数值。
## 因此打空完全不回血（技能整个浪费），打在满血目标上收益也偏低，
## 唯一的高收益时机是「敌人已经掉血、自己还活着」——也就是残血反打。

@export_group("虹吸参数")
## 作用半径（像素）
@export var radius: float = 220.0
## 基础伤害（会吃施法者的攻击力增益）
@export var damage: int = 20
## 吸血系数：0.6 表示把实际打掉血量的 60% 加回自己身上
@export_range(0.0, 2.0, 0.05) var lifesteal_ratio: float = 0.6
## 环形特效颜色（粉紫，呼应大脑果实的配色）
@export var wave_color: Color = Color(1.0, 0.62, 0.86, 0.7)


func _execute(caster: CharacterBody2D, _aim_dir: Vector2) -> void:
	# 1. 施法瞬间的范围反馈
	spawn_ring_fx(caster, radius, wave_color, 0.3)

	if caster == null:
		return

	# 2. 伤害同样要吃攻击力增益，和普攻 / 其他技能保持同一套换算
	var actual_damage: int = damage
	if caster.has_method("scale_damage"):
		actual_damage = caster.scale_damage(damage)

	# 3. 逐个结算，并把真正打掉的血量累加起来
	#    take_damage() 没有返回值，所以这里用「扣血前的 HP」反推实际伤害值：
	#    目标只剩 5 血时打出 20 点，只能吸到 3 点，符合直觉。
	var drained: float = 0.0
	for victim in find_enemies_in_radius(caster, radius):
		if not victim.has_method("take_damage"):
			continue

		var hp_before: int = int(victim.current_hp)
		victim.take_damage(actual_damage)
		var hp_after: int = int(victim.current_hp) if is_instance_valid(victim) else 0
		drained += float(max(0, hp_before - hp_after))

	# 4. 回流：总量按系数折算，向下取整，打空则一滴都回不了
	var heal_amount := int(floor(drained * lifesteal_ratio))
	if heal_amount > 0 and caster.has_method("heal"):
		caster.heal(heal_amount)
