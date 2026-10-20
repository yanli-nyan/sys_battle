class_name ProjectileSkill
extends SkillData

## 发射投射物技能：朝瞄准方向打出一个直线飞行的道具，
## 命中敌人后施加一次限时属性修正。
##
## 默认配置就是把目标的移动速度取反（multiplier = -1）：
## 中招的人会朝着输入的反方向走，AI 则会一边盯着你一边往后退。

@export_group("投射物")
## 飞行速度（像素/秒）
@export var speed: float = 700.0
## 最大飞行距离（像素），飞完自动消失
@export var max_range: float = 600.0
## 命中判定半径
@export var hit_radius: float = 8.0
## 生成位置相对施法者前移的距离，避免一出生就贴着自己
@export var spawn_offset: float = 26.0
## 投射物贴图；留空则用程序化绘制的小球
@export var projectile_texture: Texture2D
## 投射物颜色（同时用作命中爆点的颜色）
@export var projectile_color: Color = Color(1.0, 0.55, 0.85)

@export_group("命中效果")
## 要修改的属性，用 SkillData 里的 MOD_* 常量
@export var modifier_key: StringName = MOD_MOVE_SPEED
## 属性倍率：-1 表示移动取反
@export var modifier_multiplier: float = -1.0
## 效果持续时间（秒）
@export var modifier_duration: float = 2.5


func _execute(caster: CharacterBody2D, aim_dir: Vector2) -> void:
	var parent := caster.get_parent()
	if parent == null:
		return

	var dir := aim_dir.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT

	var bolt := Projectile.new()
	bolt.speed = speed
	bolt.max_range = max_range
	bolt.hit_radius = hit_radius
	bolt.color = projectile_color
	bolt.texture = projectile_texture
	bolt.modifier_key = modifier_key
	bolt.modifier_multiplier = modifier_multiplier
	bolt.modifier_duration = modifier_duration
	# 用技能实例当作修正来源：同一技能多次命中只刷新同一条，不会互相叠乘
	bolt.modifier_source = self

	parent.add_child(bolt)
	bolt.global_position = caster.global_position + dir * spawn_offset
	bolt.setup(caster, dir)
