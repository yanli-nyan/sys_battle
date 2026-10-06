extends Node2D

@onready var character: CharacterBody2D = get_parent().get_parent()

# 虚拟摇杆等移动端 UI 注入的方向向量（无触控时保持 Vector2.ZERO）
var touch_vector: Vector2 = Vector2.ZERO

func _process(_delta: float) -> void:
	if not character:
		return

	# 1. 读取 PC 端（键盘 / 物理手柄）输入
	var keyboard_vector: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)

	# 2. 混合 PC 输入与移动端触控输入（谁有输入就以谁为主）
	var final_vector: Vector2 = keyboard_vector
	if touch_vector.length_squared() > 0.0:
		final_vector = touch_vector

	# 3. 注入给 Character 身体
	character.move_direction = final_vector