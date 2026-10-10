class_name AOESkill
extends SkillData

@export_group("AOE 伤害属性")
@export var radius: float = 500.0                # 伤害半径（像素）
@export var damage: int = 35                    # 伤害数值
@export var knockback_force: float = 350.0      # 击退力度
@export var wave_color: Color = Color(1.0, 0.4, 0.2, 0.6) # 冲击波颜色（橙红）

func _execute(caster: CharacterBody2D, _aim_dir: Vector2) -> void:
	# 1. 播放轻量冲击波视觉反馈
	_spawn_visual_fx(caster)

	# 2. 空间几何查询 Hurtbox（Layer 3 = 掩码值 4）
	var space_state = caster.get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var circle = CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = caster.global_transform
	
	# Layer 3 对应的位掩码为 4 (1 << 2)
	query.collision_mask = 4 
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var hits = space_state.intersect_shape(query, 32)
	for hit in hits:
		var hurtbox = hit.collider as Area2D
		if not hurtbox or hurtbox.owner == caster:
			continue # 排除自己
		
		var victim = hurtbox.owner
		if victim and victim.has_method("take_damage"):
			var knock_dir = (victim.global_position - caster.global_position).normalized()
			if knock_dir == Vector2.ZERO:
				knock_dir = Vector2.RIGHT
			victim.take_damage(damage, knock_dir * knockback_force)

# 生成一个自消散的圆形冲击波节点
func _spawn_visual_fx(caster: CharacterBody2D) -> void:
	var fx = Node2D.new()
	fx.global_position = caster.global_position
	caster.get_parent().add_child(fx)

	var current_r = 10.0
	var alpha = 1.0

	fx.draw.connect(func():
		fx.draw_circle(Vector2.ZERO, current_r, Color(wave_color.r, wave_color.g, wave_color.b, alpha * 0.3))
		fx.draw_arc(Vector2.ZERO, current_r, 0.0, TAU, 32, Color(wave_color.r, wave_color.g, wave_color.b, alpha), 3.0)
	)

	var tween = fx.create_tween().set_parallel(true)
	tween.tween_method(func(val: float):
		current_r = val
		fx.queue_redraw()
	, 10.0, radius, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tween.tween_method(func(val: float):
		alpha = val
		fx.queue_redraw()
	, 1.0, 0.0, 0.25)

	tween.chain().tween_callback(fx.queue_free)