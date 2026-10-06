extends Node2D

@onready var character: CharacterBody2D = get_parent().get_parent()
var target: CharacterBody2D = null

func _ready() -> void:
	# 暂时简单粗暴地抓取场景树里的玩家（后续再优化为组检测或动态索敌）
	target = get_tree().get_first_node_in_group("player")

func _process(_delta: float) -> void:
	if not character or not is_instance_valid(target):
		return

	var dist = character.global_position.distance_to(target.global_position)
	
	# 距离大于 30 像素时向玩家移动，靠近后停下准备攻击
	if dist > 30.0:
		var dir = (target.global_position - character.global_position).normalized()
		character.move_direction = dir
	else:
		character.move_direction = Vector2.ZERO
