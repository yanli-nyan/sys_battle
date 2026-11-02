class_name BuffSkill
extends SkillData

## 自我强化技能：给自己挂一个限时属性修正。
##
## 强化哪一项属性由 stat 下拉选择，配合 multiplier / duration 全部在 .tres 里配置，
## 所以「加速」「增攻」「增射程」这类技能都不需要再写新脚本。

enum Stat {
	MOVE_SPEED,      ## 移动速度
	ATTACK_POWER,    ## 攻击力（普攻与技能伤害一起提升）
	ATTACK_RANGE,    ## 普攻距离（判定盒半径）
	MAX_HP,          ## 生命上限（抬高上限，不补血）
	ATTACK_SPEED,    ## 攻击速度（两次出刀间隔缩短）
}

@export_group("强化自己")
@export var stat: Stat = Stat.MOVE_SPEED
## 属性倍率：1.5 表示提升到 150%
@export var multiplier: float = 1.5
## 持续时间（秒）
@export var duration: float = 5.0
## 施法瞬间的光环颜色，仅作视觉反馈
@export var aura_color: Color = Color(0.4, 1.0, 0.55, 0.8)


func _execute(caster: CharacterBody2D, _aim_dir: Vector2) -> void:
	if caster == null or not caster.has_method("apply_modifier"):
		return
	spawn_ring_fx(caster, 56.0, aura_color, 0.18)
	caster.apply_modifier(_modifier_key(), multiplier, duration, self)


func _modifier_key() -> StringName:
	match stat:
		Stat.ATTACK_POWER:
			return MOD_ATTACK_POWER
		Stat.ATTACK_RANGE:
			return MOD_ATTACK_RANGE
		Stat.MAX_HP:
			return MOD_MAX_HP
		Stat.ATTACK_SPEED:
			return MOD_ATTACK_SPEED
		_:
			return MOD_MOVE_SPEED
