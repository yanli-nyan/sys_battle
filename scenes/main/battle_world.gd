extends Node2D

## 战局宿主：加载地图 → 按出生点铺开参战者 → 挂载大脑与相机 → 裁判胜负。
##
## 地图以独立场景插入 MapRoot，本脚本只依赖 GameMap 暴露的接口，
## 所以换地图（含每图不同的触控 UI）都不需要改动这里一行代码。

const CHARACTER_SCENE: PackedScene = preload("res://scenes/characters/base_character.tscn")
## 默认参战角色数据。目前所有角色都先用 test 顶替，
## 后续要做「每人一套属性/技能」时，把 fighter_data 换成列表即可。
const DEFAULT_FIGHTER_DATA: CharacterData = preload("res://resources/characters/test.tres")

const PLAYER_CONTROLLER_SCRIPT: GDScript = preload("res://scenes/characters/player_controller.gd")
const AI_CONTROLLER_SCRIPT: GDScript = preload("res://scenes/characters/ai_controller.gd")

## 默认地图：map_scene 留空时使用
const DEFAULT_MAP_SCENE: PackedScene = preload("res://scenes/maps/arena_test.tscn")
## 默认触控 UI：地图没有自带覆盖时使用
const DEFAULT_TOUCH_CONTROLS: PackedScene = preload("res://scenes/ui/touch_controls.tscn")

@export_group("战局配置")
## 本局要加载的地图场景；留空则使用 DEFAULT_MAP_SCENE
@export var map_scene: PackedScene
## 参战者统一使用的角色数据；留空则使用 DEFAULT_FIGHTER_DATA
@export var fighter_data: CharacterData
## 本局参战人数（含玩家）。按顺序占用地图出生点，超出时 GameMap 会自动循环复用。
@export_range(1, 16, 1) var fighter_count: int = 9
## 玩家占用第几个出生点（0 起）
@export var player_spawn_index: int = 0
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

## 在地图出生点上铺开参战者：1 个玩家 + 其余全 AI。
## 出生点数不够时由 GameMap 循环复用出生点。
func spawn_match() -> void:
	if current_map == null:
		push_error("战局没有加载地图，无法生成参战者。")
		return

	var total: int = maxi(fighter_count, 1)
	var spawn_total: int = current_map.get_spawn_count()
	if spawn_total > 0 and total > spawn_total:
		push_warning("参战人数 %d 超过地图出生点数 %d，多出的角色会和已有角色叠在同一位置。"
			% [total, spawn_total])

	var player_slot: int = clampi(player_spawn_index, 0, total - 1)
	_spawn_fighter(player_slot, true, "Player")

	var slot: int = 0
	var spawned: int = 1
	while spawned < total:
		if slot != player_slot:
			_spawn_fighter(slot, false, "AI_%d" % spawned)
			spawned += 1
		slot += 1

	print("战局开始：%d 名参战者（出生点 %d 个）" % [alive_fighters.size(), spawn_total])


## 生成一名参战者并挂上对应的大脑
func _spawn_fighter(spawn_index: int, is_player: bool, node_name: String) -> void:
	var body := CHARACTER_SCENE.instantiate() as CharacterBody2D

	# 位置必须在入树之前设好：两个 CharacterBody2D 在同一坐标注册，
	# 物理引擎的重叠解算会把其中一个弹飞。
	body.position = to_local(current_map.get_spawn_position(spawn_index))
	body.name = node_name
	add_child(body)
	body.add_to_group("fighter")

	body.apply_data(fighter_data if fighter_data else DEFAULT_FIGHTER_DATA)

	if is_player:
		player_instance = body
		body.add_to_group("player")
		_setup_player_brain(body)
	else:
		_setup_ai_brain(body)

	_register_fighter(body)


func _setup_player_brain(body: CharacterBody2D) -> void:
	player_brain = PLAYER_CONTROLLER_SCRIPT.new()
	player_brain.name = "PlayerController"
	body.get_node("Brain").add_child(player_brain)

	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.zoom = camera_zoom
	_apply_camera_limits(camera)
	body.add_child(camera)

	# 触控输入接线（必须在玩家大脑就绪之后）
	_wire_touch_controls()


func _setup_ai_brain(body: CharacterBody2D) -> void:
	var ai: AIController = AI_CONTROLLER_SCRIPT.new()
	ai.name = "AIController"
	body.get_node("Brain").add_child(ai)


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
