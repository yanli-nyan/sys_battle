extends Node2D

## 战局宿主：加载地图 → 生成参战者 → 挂载大脑与相机 → 裁判胜负。
##
## 地图以独立场景插入 MapRoot，本脚本只依赖 GameMap 暴露的接口，
## 所以换地图（含每图不同的触控 UI）都不需要改动这里一行代码。

const CHARACTER_SCENE: PackedScene = preload("res://scenes/characters/base_character.tscn")
const PLAYER_DATA: CharacterData = preload("res://resources/characters/test.tres")
const ENEMY_DATA: CharacterData = preload("res://resources/characters/scout.tres")

const PLAYER_CONTROLLER_SCRIPT: GDScript = preload("res://scenes/characters/player_controller.gd")
const AI_CONTROLLER_SCRIPT: GDScript = preload("res://scenes/characters/ai_controller.gd")

## 默认地图：map_scene 留空时使用
const DEFAULT_MAP_SCENE: PackedScene = preload("res://scenes/maps/arena_test.tscn")
## 默认触控 UI：地图没有自带覆盖时使用
const DEFAULT_TOUCH_CONTROLS: PackedScene = preload("res://scenes/ui/touch_controls.tscn")

@export_group("战局配置")
## 本局要加载的地图场景；留空则使用 DEFAULT_MAP_SCENE
@export var map_scene: PackedScene
## 生成的 AI 敌人数量
@export_range(0, 8, 1) var enemy_count: int = 1
## 玩家相机缩放（适配 32×32 像素网格）
@export var camera_zoom: Vector2 = Vector2(2.5, 2.5)

@onready var map_root: Node2D = $MapRoot
@onready var touch_layer: CanvasLayer = $TouchLayer
@onready var game_over_panel: PanelContainer = $UILayer/GameOverPanel
@onready var result_label: Label = $UILayer/GameOverPanel/VBoxContainer/ResultLabel
@onready var restart_button: Button = $UILayer/GameOverPanel/VBoxContainer/RestartButton

## 当前地图的 GameMap 接口（根节点未挂 game_map.gd 时为 null）
var current_map: GameMap = null
var touch_controls: TouchControls = null
var player_instance: CharacterBody2D = null
var player_brain: PlayerController = null

var alive_fighters: Array[CharacterBody2D] = []
var is_match_over: bool = false

var _spawn_cursor: int = 0


func _ready() -> void:
	restart_button.pressed.connect(_on_restart_button_pressed)
	load_map()
	setup_touch_controls()
	spawn_match()


# ---------- 地图装配 ----------

## 把地图场景装进 MapRoot
func load_map() -> void:
	for child in map_root.get_children():
		map_root.remove_child(child)
		child.queue_free()

	var scene: PackedScene = map_scene if map_scene else DEFAULT_MAP_SCENE
	if scene == null:
		push_error("战局没有可加载的地图场景。")
		return

	var instance := scene.instantiate()
	map_root.add_child(instance)
	current_map = instance as GameMap
	if current_map == null:
		push_warning("地图 %s 的根节点没有挂载 game_map.gd，出生点与边界将退化为默认行为。" % instance.name)
	else:
		print("战局地图：", current_map.display_name, "｜出生点 ", current_map.get_spawn_count(), " 个")


# ---------- 触控 UI 装配 ----------

## 组装触控层：地图自带覆盖则用地图的，否则用全局默认层
func setup_touch_controls() -> void:
	for child in touch_layer.get_children():
		touch_layer.remove_child(child)
		child.queue_free()
	touch_controls = null

	var scene: PackedScene = DEFAULT_TOUCH_CONTROLS
	var source := "全局默认"
	if current_map and current_map.has_touch_controls_override():
		scene = current_map.get_touch_controls_scene()
		source = "地图自定义"
	if scene == null:
		return

	var instance := scene.instantiate()
	var controls := instance as TouchControls
	if controls == null:
		push_warning("触控 UI 预制体 %s 的根节点没有挂载 touch_controls.gd，已跳过。" % instance.name)
		instance.queue_free()
		return

	touch_layer.add_child(controls)
	touch_controls = controls
	print("触控 UI：", source, "｜", controls.name, "（非触控设备会自动隐藏）")
	_wire_touch_controls()


# ---------- 参战者生成 ----------

func spawn_match() -> void:
	_spawn_cursor = 0

	if current_map and 1 + enemy_count > current_map.capacity:
		push_warning("参战人数 %d 超过地图 %s 的建议容量 %d，出生点将循环复用。"
			% [1 + enemy_count, current_map.display_name, current_map.capacity])

	# 1. 玩家
	var player := CHARACTER_SCENE.instantiate() as CharacterBody2D
	add_child(player)
	player.global_position = _spawn_position(_take_spawn())
	player.name = "Player"
	player.add_to_group("player")
	player.apply_data(PLAYER_DATA)
	player_instance = player
	_register_fighter(player)

	player_brain = PLAYER_CONTROLLER_SCRIPT.new()
	player_brain.name = "PlayerController"
	player.get_node("Brain").add_child(player_brain)

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.zoom = camera_zoom
	_apply_camera_limits(camera)
	player.add_child(camera)

	# 2. 敌人
	for i in enemy_count:
		var enemy := CHARACTER_SCENE.instantiate() as CharacterBody2D
		add_child(enemy)
		enemy.global_position = _spawn_position(_take_spawn())
		enemy.name = "Enemy_%d" % (i + 1)
		enemy.apply_data(ENEMY_DATA)
		_register_fighter(enemy)

		var ai: AIController = AI_CONTROLLER_SCRIPT.new()
		ai.name = "AIController"
		enemy.get_node("Brain").add_child(ai)

	# 3. 触控输入接线（必须在玩家大脑就绪之后）
	_wire_touch_controls()


## 触控层只抛信号，由战局接线到玩家大脑，保证 UI 与角色解耦
func _wire_touch_controls() -> void:
	if touch_controls == null or player_brain == null:
		return
	# 用 is_connected 兜底，重复装配也不会造成一次按键触发两次
	if not touch_controls.move_input.is_connected(player_brain.set_touch_direction):
		touch_controls.move_input.connect(player_brain.set_touch_direction)
	if not touch_controls.attack_pressed.is_connected(player_brain.request_basic_attack):
		touch_controls.attack_pressed.connect(player_brain.request_basic_attack)
	if not touch_controls.skill_pressed.is_connected(player_brain.request_skill):
		touch_controls.skill_pressed.connect(player_brain.request_skill)


## 出生点按顺序取用，取完循环
func _take_spawn() -> int:
	var index := _spawn_cursor
	_spawn_cursor += 1
	return index


func _spawn_position(index: int) -> Vector2:
	if current_map:
		return current_map.get_spawn_position(index)
	return map_root.global_position


## 把地图边界同步给相机，避免镜头移出地形
func _apply_camera_limits(camera: Camera2D) -> void:
	if current_map == null:
		return
	var bounds := current_map.get_bounds()
	if bounds.size == Vector2.ZERO:
		return
	camera.limit_left = int(bounds.position.x)
	camera.limit_top = int(bounds.position.y)
	camera.limit_right = int(bounds.end.x)
	camera.limit_bottom = int(bounds.end.y)


# ---------- 裁判 ----------

func _register_fighter(fighter: CharacterBody2D) -> void:
	alive_fighters.append(fighter)
	fighter.died.connect(_on_fighter_died)


func _on_fighter_died(victim: CharacterBody2D) -> void:
	if is_match_over:
		return

	alive_fighters.erase(victim)

	# 规则 1：玩家阵亡 -> 直接判负
	if victim == player_instance:
		_end_game(false)
		return

	# 规则 2：场上只剩最后一人，且正是玩家 -> 判胜
	if alive_fighters.size() == 1 and alive_fighters[0] == player_instance:
		_end_game(true)


func _end_game(is_victory: bool) -> void:
	is_match_over = true

	for fighter in alive_fighters:
		if is_instance_valid(fighter):
			fighter.set_physics_process(false)

	# 结算后收起触控层，避免误触
	if touch_controls:
		touch_controls.set_controls_enabled(false)

	game_over_panel.visible = true
	result_label.text = "战斗胜利！" if is_victory else "败北..."
	result_label.modulate = Color.GREEN if is_victory else Color.RED
	print("战局结束：", "胜利" if is_victory else "败北")


func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()
