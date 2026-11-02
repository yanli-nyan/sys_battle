class_name SoEasyAIController
extends Node2D

## 【难度：SO_EASY】最朴素的 AI 大脑：锁定「最近的其它参战者」，直线靠近，贴脸后停下平砍。
##
## 已知弱点（正是这个难度"简单"的来源，也是后续难度要解决的问题）：
##   * 不会绕墙，被挡住就一直顶着走；
##   * 不会看地形高度，被高台挡住就原地卡死；
##   * 从不释放主动技能，也不考虑攻击距离与自身判定盒的实际关系；
##   * 目标选择只看直线距离，不评估血量、不评估威胁。
##
## 升级时不要改这个文件——另建一个 .gd，让 battle_world 通过 ai_difficulty 选过去。

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
		if other.current_hp <= 0:
			continue
		var dist := character.global_position.distance_squared_to(other.global_position)
		if dist < best_dist:
			best_dist = dist
			best = other
	target = best
