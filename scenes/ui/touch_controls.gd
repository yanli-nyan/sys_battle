class_name TouchControls
extends Control

## 移动端触控层：虚拟摇杆 + 攻击/技能按键，零外部素材（全部用 _draw 与 StyleBoxFlat 绘制）。
##
## 本层不认识任何具体角色，只把输入以信号抛出；由战局（battle_world.gd）接线到
## 玩家大脑（PlayerController）。因此同一套 UI 可以复用到任意地图，
## 地图也可以通过 GameMap.touch_controls_override 换成自己的一套。

signal move_input(direction: Vector2)
signal attack_pressed()
signal skill_pressed(slot_index: int)

@export_group("虚拟摇杆")
## 底盘半径；<= 0 时按 Joystick 节点尺寸自动推算
@export var stick_radius: float = 0.0
## 摇杆头半径
@export var stick_knob_radius: float = 34.0
## 死区：拖动距离小于该比例时视为不动
@export_range(0.0, 0.9, 0.01) var stick_dead_zone: float = 0.15

@export_group("行为")
## 在非触控设备（PC）上自动隐藏，避免挡住鼠标操作
@export var auto_hide_on_desktop: bool = true

## 技能按钮上的冷却遮罩脚本（与 PC 端底部 HUD 共用同一套绘制逻辑）
const COOLDOWN_OVERLAY_SCRIPT: GDScript = preload("res://scenes/ui/skill_cooldown_overlay.gd")

@onready var stick: Control = $Joystick
@onready var attack_button: Button = $ActionButtons/AttackButton
@onready var skill_button: Button = $ActionButtons/SkillButton

## 叠在技能按钮上的冷却遮罩；由宿主通过 set_skill_character() 注入角色后才显示
var _cooldown_overlay: Control = null
var _overlay_character: Node = null

var _stick_center: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO
## 当前抓住摇杆的手指编号；-1 空闲，-2 表示鼠标（桌面调试用）
var _active_pointer: int = -1
var _device_visible: bool = true
var _enabled: bool = true


func _ready() -> void:
	_device_visible = not (auto_hide_on_desktop and not _is_touch_device())
	visible = _device_visible and _enabled

	stick.gui_input.connect(_on_stick_gui_input)
	stick.draw.connect(_draw_stick)
	stick.resized.connect(_on_stick_resized)
	attack_button.button_down.connect(_on_attack_button_down)
	skill_button.button_down.connect(_on_skill_button_down)

	_stick_center = stick.size * 0.5
	stick.queue_redraw()

	_setup_cooldown_overlay()


func _is_touch_device() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


## 战局在结算等场合可以整层禁用
func set_controls_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_release_stick()
	visible = _device_visible and _enabled


func is_controls_enabled() -> bool:
	return _enabled


func _on_attack_button_down() -> void:
	attack_pressed.emit()


func _on_skill_button_down() -> void:
	skill_pressed.emit(0)


# ---------- 技能按钮上的冷却遮罩 ----------

## 在技能按钮内侧铺一层冷却遮罩（圆形），让玩家直接在按键上看到「还要等多久」。
## 遮罩由战局的冷却 HUD 同步注入，因此移动端与 PC 端看到的是同一份冷却状态。
func _setup_cooldown_overlay() -> void:
	if _cooldown_overlay != null and is_instance_valid(_cooldown_overlay):
		_cooldown_overlay.queue_free()

	var overlay: Control = COOLDOWN_OVERLAY_SCRIPT.new() as Control
	overlay.name = "CooldownOverlay"
	# 铺满整个按钮；按钮是 120×120 的正方形，遮罩内部按内切圆绘制
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_button.add_child(overlay)
	_cooldown_overlay = overlay


## 注入要显示冷却的角色（通常就是战局里的玩家）；传 null 则隐藏遮罩。
func set_skill_character(character: Node) -> void:
	_overlay_character = character
	if _cooldown_overlay != null and is_instance_valid(_cooldown_overlay):
		_cooldown_overlay.set_character(character)


## 遮罩当前显示的角色（便于调试）
func get_skill_character() -> Node:
	return _overlay_character


# ---------- 摇杆输入 ----------

func _on_stick_gui_input(event: InputEvent) -> void:
	if not _enabled:
		return

	if event is InputEventScreenTouch:
		if event.pressed and _active_pointer == -1:
			_active_pointer = event.index
			_update_stick(event.position)
		elif not event.pressed and event.index == _active_pointer:
			_release_stick()
	elif event is InputEventScreenDrag:
		if event.index == _active_pointer:
			_update_stick(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _active_pointer == -1:
			_active_pointer = -2
			_update_stick(event.position)
		elif not event.pressed and _active_pointer == -2:
			_release_stick()
	elif event is InputEventMouseMotion and _active_pointer == -2:
		_update_stick(event.position)


func _update_stick(local_position: Vector2) -> void:
	var radius := _get_stick_radius()
	if radius <= 0.0:
		return

	var offset := local_position - _stick_center
	if offset.length() > radius:
		offset = offset.normalized() * radius
	_knob_offset = offset

	# 死区之外按比例映射：推得越远走得越快
	var strength := offset.length() / radius
	var direction := Vector2.ZERO
	if strength > stick_dead_zone:
		var scaled := (strength - stick_dead_zone) / maxf(1.0 - stick_dead_zone, 0.001)
		direction = offset.normalized() * clampf(scaled, 0.0, 1.0)

	move_input.emit(direction)
	stick.queue_redraw()


func _release_stick() -> void:
	_active_pointer = -1
	_knob_offset = Vector2.ZERO
	move_input.emit(Vector2.ZERO)
	if is_instance_valid(stick):
		stick.queue_redraw()


func _on_stick_resized() -> void:
	_stick_center = stick.size * 0.5
	stick.queue_redraw()


func _get_stick_radius() -> float:
	if stick_radius > 0.0:
		return stick_radius
	return maxf(minf(stick.size.x, stick.size.y) * 0.5 - 4.0, 1.0)


# ---------- 摇杆绘制 ----------

func _draw_stick() -> void:
	var radius := _get_stick_radius()
	if radius <= 0.0:
		return
	var knob := _stick_center + _knob_offset
	stick.draw_circle(_stick_center, radius, Color(1.0, 1.0, 1.0, 0.12))
	stick.draw_arc(_stick_center, radius, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.45), 3.0, true)
	stick.draw_circle(knob, stick_knob_radius, Color(1.0, 1.0, 1.0, 0.5))
	stick.draw_arc(knob, stick_knob_radius, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.85), 2.0, true)
