class_name PlayerController
extends Node2D

## 玩家大脑：把 PC 键鼠输入与移动端触控输入统一翻译成对肉体的指令。
##
## 触控层（TouchControls）不直接操作角色，只抛信号；由战局把信号接到
## 下面三个公开方法上，因此同一套触控 UI 可以复用到任意角色与任意地图。

@onready var character: CharacterBody2D = get_parent().get_parent()

## 虚拟摇杆注入的方向向量（无触控时保持 Vector2.ZERO）
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


func _unhandled_input(event: InputEvent) -> void:
	# 空格键：普通攻击
	if event.is_action_pressed("ui_accept"):
		request_basic_attack()

	# E 键等价于 1 号槽；数字键 1-9 直接对应技能槽 0-8
	if event is InputEventKey and event.pressed and not event.echo:
		var slot := _slot_from_keycode(event.keycode)
		if slot >= 0:
			request_skill(slot)


## 数字键 1..9 映射到技能槽 0..8，其余按键返回 -1
func _slot_from_keycode(keycode: Key) -> int:
	if keycode == KEY_E:
		return 0
	if keycode >= KEY_1 and keycode <= KEY_9:
		return int(keycode) - int(KEY_1)
	return -1


# ---------- 供触控层 / 外部系统调用的公开接口 ----------

## 写入摇杆方向（长度 0~1，Vector2.ZERO 表示松手）
func set_touch_direction(direction: Vector2) -> void:
	touch_vector = direction


## 请求一次普通攻击
func request_basic_attack() -> void:
	if character:
		character.perform_basic_attack()


## 请求释放第 slot_index 个主动技能
func request_skill(slot_index: int) -> void:
	if character:
		character.cast_active_skill(slot_index)
