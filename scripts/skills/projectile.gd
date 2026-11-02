class_name Projectile
extends Area2D

## 直线飞行的投射物（零外部素材：默认用 _draw 画一个小球，也可以挂贴图）。
##
## 命中 Hurtbox 后对目标施加一次限时属性修正，然后自毁；撞到墙（World 层）同样自毁。
##
## 修正的「来源」由发射它的技能传进来，而不是用投射物自己：
## 否则同一个技能连续命中两次会变成两条来源，-1 × -1 = +1，效果反而抵消了。

## 命中后要修改的属性键（用 SkillData 里的 MOD_*）；留空表示只撞击、不施加效果
var modifier_key: StringName = &""
var modifier_multiplier: float = 1.0
var modifier_duration: float = 0.0
## 修正来源，通常就是发射它的那个技能实例
var modifier_source: Object = null

## 附加的易伤修正（可选）。设了就让目标在 modifier_duration 内多受伤害，
## 意义：单纯「让对手走反方向」在 1v1 里几乎无收益（AI 会重新寻路绕回来），
## 补一层易伤才让投射物类技能具备真正的输出价值。
var vulnerability_multiplier: float = 1.0

var direction: Vector2 = Vector2.RIGHT
var speed: float = 700.0
var max_range: float = 600.0
var hit_radius: float = 8.0
var color: Color = Color(1.0, 0.55, 0.85)
## 留空则用程序化绘制的小球
var texture: Texture2D = null

var _caster: Node = null
var _travelled: float = 0.0
var _spent: bool = false


func _ready() -> void:
	collision_layer = 0
	# 同时盯着 World（撞墙消失）和 Hurtbox（命中角色）
	collision_mask = 1 | SkillData.HURTBOX_MASK
	monitoring = true
	monitorable = false

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = hit_radius
	shape.shape = circle
	add_child(shape)

	if texture != null:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		add_child(sprite)

	draw.connect(_draw_projectile)


## 由技能在入树后立刻调用：记录谁发射的、朝哪个方向飞
func setup(caster: Node2D, aim_dir: Vector2) -> void:
	_caster = caster
	direction = aim_dir.normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	if _spent:
		return

	var step := direction * speed * delta
	global_position += step
	_travelled += step.length()

	if _resolve_hit():
		return

	if _travelled >= max_range:
		_spend()


## 返回 true 表示这一帧已经消耗掉（命中角色或撞墙）
func _resolve_hit() -> bool:
	# 先看受击盒：命中角色就把效果打上去
	for area in get_overlapping_areas():
		var hurtbox := area as Area2D
		if hurtbox == null:
			continue
		var victim := hurtbox.owner
		if victim == null or victim == _caster:
			continue
		_apply_effect(victim)
		_spend()
		return true

	# 再看实体：撞到墙（TileMapLayer）或别的角色身体就消失
	for body in get_overlapping_bodies():
		if body == _caster:
			continue
		_spend()
		return true

	return false


func _apply_effect(victim: Node) -> void:
	if not victim.has_method("apply_modifier"):
		return
	# 主效果（乱向弹 = 移动取反）
	if modifier_key != &"":
		victim.apply_modifier(modifier_key, modifier_multiplier, modifier_duration, modifier_source)
	# 附加易伤：同一个来源，同一条修正，重复命中只刷新不叠加
	if vulnerability_multiplier > 1.0:
		victim.apply_modifier(SkillData.MOD_DAMAGE_TAKEN, vulnerability_multiplier, modifier_duration, modifier_source)


func _spend() -> void:
	if _spent:
		return
	_spent = true
	_burst()
	queue_free()


## 命中/消散时的小爆点，复用范围技能的圆环特效
func _burst() -> void:
	var parent := get_parent()
	if parent == null:
		return

	var fx := RingFX.new()
	fx.ring_color = color
	fx.ring_radius = hit_radius
	fx.ring_alpha = 0.9
	fx.line_width = 2.0
	parent.add_child(fx)
	fx.global_position = global_position

	var tween := fx.create_tween().set_parallel(true)
	tween.tween_property(fx, "ring_radius", hit_radius * 5.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(fx, "ring_alpha", 0.0, 0.22)
	tween.chain().tween_callback(fx.queue_free)


func _draw_projectile() -> void:
	if texture != null:
		return
	draw_circle(Vector2.ZERO, hit_radius, color)
	draw_arc(Vector2.ZERO, hit_radius * 1.9, 0.0, TAU, 24,
		Color(color.r, color.g, color.b, color.a * 0.4), 2.0, true)
