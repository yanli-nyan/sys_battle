extends CharacterBody2D

@export var speed: float = 160.0

# 核心：由大脑（玩家控制器或 AI）实时赋值
var move_direction: Vector2 = Vector2.ZERO

func _physics_process(_delta: float) -> void:
	# 仅负责执行移动计算
	velocity = move_direction.normalized() * speed
	move_and_slide()