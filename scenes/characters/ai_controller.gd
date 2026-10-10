class_name AIController
extends Node2D

## AI 大脑：在混战中锁定「最近的其它参战者」，靠近后停下普攻。
##
## 目标从 fighter 组里挑，所以 AI 之间也会互相攻击，而不是一起扑向玩家。
## 出刀前摇、战术撤退、技能释放等留给后续的 AI 升级。

@onready var character: CharacterBody2D = get_parent().get_parent()

## 进入该距离就停下开打（略大于判定盒 18 + 受击盒 15 的接触距离）
@export var attack_range: float = 34.0
## 索敌刷新间隔（秒），避免每帧遍历全场
@export var retarget_interval: float = 0.4

## 当前锁定的目标
var target: CharacterBody2D = null

var _retarget_timer: float = 0.0


func _ready() -> void:
	_acquire_target()


func _process(delta: float) -> void:
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = retarget_interval
		_acquire_target()

	if not is_instance_valid(target):
		character.move_direction = Vector2.ZERO
		return

	var dist := character.global_position.distance_to(target.global_position)
	if dist > attack_range:
		character.move_direction = (target.global_position - character.global_position).normalized()
		return

	# 贴到攻击距离内就停下出刀；朝向沿用最后一次移动方向
	character.move_direction = Vector2.ZERO
	character.perform_basic_attack()


## 在 fighter 组里挑选最近的其它参战者
func _acquire_target() -> void:
	var best: CharacterBody2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("fighter"):
		var other := node as CharacterBody2D
		if other == null or other == character or not is_instance_valid(other):
			continue
		var dist := character.global_position.distance_squared_to(other.global_position)
		if dist < best_dist:
			best_dist = dist
			best = other
	target = best
