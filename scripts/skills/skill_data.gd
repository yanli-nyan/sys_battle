class_name SkillData
extends Resource

## 技能策略基类：统一负责冷却推进与释放接口，具体逻辑由子类实现 _execute()。
##
## 这里同时存放技能与角色之间的「共享词汇」：
##   * MOD_* 是角色身上可被技能临时修改的属性键，由 base_character.gd 的修正系统实现；
##   * find_enemies_in_radius() / spawn_ring_fx() 是范围类技能复用的工具，
##     避免每个新技能都抄一遍空间查询和特效代码。

## 移动速度倍率（< 1 即减速）
const MOD_MOVE_SPEED := &"move_speed"
## 攻击力倍率
const MOD_ATTACK_POWER := &"attack_power"
## 普攻判定盒半径倍率（即攻击距离）
const MOD_ATTACK_RANGE := &"attack_range"
## 生命上限倍率（> 1 即抬高上限，并同步补足等量的当前血量）
const MOD_MAX_HP := &"max_hp"

## 受击盒所在的物理层掩码（Layer 3: Hurtbox）
const HURTBOX_MASK := 4

@export var skill_name: String = "基础技能"
@export var cooldown: float = 1.0
@export var icon: Texture2D

var _current_cooldown: float = 0.0


func update_cooldown(delta: float) -> void:
	if _current_cooldown > 0.0:
		_current_cooldown -= delta


func is_ready() -> bool:
	return _current_cooldown <= 0.0


## 还剩多少秒可用；已就绪时返回 0。给 HUD 的数字倒计时用。
func get_cooldown_remaining() -> float:
	return maxf(_current_cooldown, 0.0)


## 冷却进度 0.0~1.0：1.0 表示刚施放、0.0 表示已就绪。给 HUD 的转圈遮罩用。
## cooldown 配置为 0 或负值时永远返回 0，避免除零。
func get_cooldown_ratio() -> float:
	if cooldown <= 0.0:
		return 0.0
	return clampf(_current_cooldown / cooldown, 0.0, 1.0)


func try_cast(caster: CharacterBody2D, aim_dir: Vector2) -> bool:
	if not is_ready():
		return false
	_current_cooldown = cooldown
	_execute(caster, aim_dir)
	return true


func _execute(_caster: CharacterBody2D, _aim_dir: Vector2) -> void:
	pass


# ---------- 供子类复用的工具 ----------

## 查询以 caster 为圆心、radius 为半径内的所有敌方角色。
## 自动排除施法者自己，并按角色去重（一个角色可能同时有多个受击盒）。
func find_enemies_in_radius(caster: CharacterBody2D, radius: float, max_results: int = 32) -> Array[Node]:
	var space_state := caster.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = caster.global_transform
	query.collision_mask = HURTBOX_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var victims: Array[Node] = []
	for hit in space_state.intersect_shape(query, max_results):
		var hurtbox := hit.collider as Area2D
		if hurtbox == null or hurtbox.owner == caster:
			continue
		var victim := hurtbox.owner
		if victim and not victims.has(victim):
			victims.append(victim)
	return victims


## 在施法位置生成一个自消散的扩散圆环，作为范围技能的视觉反馈（零外部素材）。
func spawn_ring_fx(caster: CharacterBody2D, radius: float, color: Color, lifetime: float = 0.25) -> void:
	var parent := caster.get_parent()
	if parent == null:
		return

	var fx := RingFX.new()
	fx.ring_color = color
	parent.add_child(fx)
	fx.global_position = caster.global_position

	var tween := fx.create_tween().set_parallel(true)
	tween.tween_property(fx, "ring_radius", radius, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(fx, "ring_alpha", 0.0, lifetime)
	tween.chain().tween_callback(fx.queue_free)
