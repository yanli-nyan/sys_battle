class_name DamageField
extends Node2D

## 固定在施法点、限时反复结算伤害的区域。
##
## 关键点：位置只在生成时取一次施法者坐标，之后完全独立——
## 施法者跑多远都不会带着领域走。每 tick 用圆形物理查询收集范围内的受击盒，
## 按 owner 去重后结算伤害；施法者本人永远免疫。
##
## 视觉零外部素材：填充圆 + 描边 + 内圈细弧 + 呼吸/闪烁，全部由 _draw 绘制。

## 区域半径（像素）
var radius: float = 220.0
## 每 tick 的基础伤害（会吃施法者的攻击力增益）
var damage_per_tick: int = 4
## 两次伤害之间的间隔（秒）
var tick_interval: float = 1.0
## 区域总存在时间（秒）
var duration: float = 20.0
## 免疫的施法者；施法者被释放后自动退化成「谁都不排除」
var caster: CharacterBody2D = null
## 区域主色
var field_color: Color = Color(0.55, 0.3, 0.9, 0.55)
## 外圈描边宽度（像素）
var line_width: float = 4.0

## 单次查询最多返回的受击盒数量
const MAX_HITS: int = 64

var _elapsed: float = 0.0
var _tick_timer: float = 0.0
var _pulse: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	_pulse += delta * 2.4

	# 到点就地消散，不给施法者留任何残留节点
	if _elapsed >= duration:
		queue_free()
		return

	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer += maxf(tick_interval, 0.05)
		_apply_tick()

	queue_redraw()


func _draw() -> void:
	var base := field_color
	# 剩余不足 3 秒开始闪烁，提示领域即将消散
	var fade: float = 1.0
	if duration - _elapsed < 3.0:
		fade = 0.35 + 0.65 * absf(sin(_elapsed * 12.0))
	var breathe: float = 0.85 + 0.15 * sin(_pulse)

	draw_circle(Vector2.ZERO, radius, Color(base.r, base.g, base.b, base.a * 0.32 * breathe * fade))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64,
		Color(base.r, base.g, base.b, minf(base.a * 1.7, 1.0) * fade), line_width, true)
	draw_arc(Vector2.ZERO, radius * 0.72, 0.0, TAU, 48,
		Color(base.r, base.g, base.b, base.a * 0.7 * fade), line_width * 0.5, true)


## 结算一次伤害：范围内按角色去重，各受一次伤害（不击退，避免持续伤害把人一直推着走）
func _apply_tick() -> void:
	if damage_per_tick <= 0:
		return

	var actual: int = damage_per_tick
	if is_instance_valid(caster) and caster.has_method("scale_damage"):
		actual = caster.scale_damage(damage_per_tick)

	for victim in _collect_victims():
		if victim.has_method("take_damage"):
			victim.take_damage(actual)


## 收集圆心在本节点 global_position、半径 radius 内的受击盒所属角色（永远排除施法者）
func _collect_victims() -> Array[Node]:
	var victims: Array[Node] = []
	var world := get_world_2d()
	if world == null:
		return victims

	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = SkillData.HURTBOX_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	if is_instance_valid(caster):
		query.exclude = [caster.get_rid()]

	for hit in world.direct_space_state.intersect_shape(query, MAX_HITS):
		var hurtbox := hit.collider as Area2D
		if hurtbox == null:
			continue
		var victim := hurtbox.owner
		if victim == null or victim == caster:
			continue
		if not victims.has(victim):
			victims.append(victim)
	return victims
