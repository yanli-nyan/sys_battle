extends Node2D

## 战局宿主：加载地图 → 随机铺开参战者 → 挂载大脑与相机 → 裁判胜负。
##
## 地图以独立场景插入 MapRoot，本脚本只依赖 GameMap 暴露的接口，
## 所以换地图（含每图不同的触控 UI）都不需要改动这里一行代码。
##
## 出场名单是随机的：角色从角色表里抽，位置从地图实际出生点里抽。
## 出生点数量由地图决定（GameMap.get_spawn_count()），这里不写死任何数字。

const CHARACTER_SCENE: PackedScene = preload("res://scenes/characters/base_character.tscn")

const PLAYER_CONTROLLER_SCRIPT: GDScript = preload("res://scenes/characters/player_controller.gd")
const AI_CONTROLLER_SCRIPT: GDScript = preload("res://scenes/characters/ai_controller.gd")

## 默认地图：map_scene 留空时使用
const DEFAULT_MAP_SCENE: PackedScene = preload("res://scenes/maps/arena_test.tscn")
## 默认触控 UI：地图没有自带覆盖时使用
const DEFAULT_TOUCH_CONTROLS: PackedScene = preload("res://scenes/ui/touch_controls.tscn")

## 角色资源目录：character_pool 留空时自动扫描这里，新增角色资源即可自动加入角色表
const CHARACTER_DIR := "res://resources/characters"
## 兜底角色（test）：默认不进随机池，只有随机池里一个能用的角色都没有时才出场
const FALLBACK_CHARACTER: CharacterData = preload("res://resources/characters/test.tres")

@export_group("战局配置")
## 本局要加载的地图场景；留空则使用 DEFAULT_MAP_SCENE
@export var map_scene: PackedScene

@export_group("出场名单")
## 可随机出场的角色表（AI 用）；留空则自动扫描 CHARACTER_DIR 下的全部角色资源
@export var character_pool: Array[CharacterData] = []
## 不想进随机池的角色。只在自动扫描时生效；显式配了 character_pool 就完全以它为准。
## 手里有还没调好的新角色时，把它拖进来就能先不让它出场。
@export var excluded_characters: Array[CharacterData] = []
## 玩家可选角色池；留空则与上面的角色表共用
@export var player_character_pool: Array[CharacterData] = []
## 玩家出场的角色（目前先在这里选）；留空则从玩家角色池随机。
## 外部系统通过 MatchConfig.select_character() 指定时，优先于这一项。
@export var player_character: CharacterData
## 本局参战人数（含玩家）
@export_range(1, 16, 1) var fighter_count: int = 9
## 玩家占用第几个出生点名额（0 起）
@export var player_slot_index: int = 0
## 出生点是否随机挑选；关掉则按 0,1,2… 顺序取用
@export var randomize_spawn_points: bool = true
## 随机种子：0 表示每局重新随机；填固定值可复现同一套出场名单
@export var random_seed: int = 0

@export_group("相机")
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


# ---------- 出场名单 ----------

## 解析角色表：
##   1. 检视面板里配了 character_pool 就直接用（完全按你的意思来，不做过滤）；
##   2. 否则扫描 CHARACTER_DIR，只收「能打、看得见、且没被排除」的角色，其余打印原因；
##      兜底角色 test 默认不进随机池，只有随机池空了才会出场；
##   3. 随机池一个都没有时回退到 FALLBACK_CHARACTER。
## 过滤条件很直白：没有 basic_attack 的角色出不了拳，没有 sprite_texture 的角色在场上隐形，
## 两者都会让新角色看着像 bug，所以默认先挡在外面；想强行启用就往 character_pool 里拖。
func resolve_character_pool() -> Array[CharacterData]:
	var pool: Array[CharacterData] = []
	for item in character_pool:
		if item:
			pool.append(item)
	if not pool.is_empty():
		return pool

	var skipped: Array[String] = []
	var dir := DirAccess.open(CHARACTER_DIR)
	if dir:
		var file_names := dir.get_files()
		file_names.sort()
		for file_name in file_names:
			# 导出后 .tres 会被改写成 .res 或带 .remap 后缀，这里都认
			var clean := file_name.trim_suffix(".remap")
			if not (clean.ends_with(".tres") or clean.ends_with(".res")):
				continue
			var data := load(CHARACTER_DIR.path_join(clean)) as CharacterData
			if data == null:
				continue
			if data.basic_attack == null:
				skipped.append("%s(缺普攻)" % data.character_name)
				continue
			if data.sprite_texture == null:
				skipped.append("%s(缺贴图)" % data.character_name)
				continue
			if data == FALLBACK_CHARACTER:
				skipped.append("%s(兜底角色)" % data.character_name)
				continue
			if excluded_characters.has(data):
				skipped.append("%s(已排除)" % data.character_name)
				continue
			pool.append(data)

	if not skipped.is_empty():
		print("随机池未收录：", ", ".join(skipped))

	if pool.is_empty():
		push_warning("随机池里没有可用角色，回退到兜底角色 %s。" % FALLBACK_CHARACTER.character_name)
		pool.append(FALLBACK_CHARACTER)
	return pool


# ---------- 参战者生成 ----------

## 随机铺开一局：角色从角色表里抽，位置从地图出生点里抽
func spawn_match() -> void:
	if current_map == null:
		push_error("战局没有加载地图，无法生成参战者。")
		return

	var pool := resolve_character_pool()
	if pool.is_empty():
		push_error("角色表为空，无法生成参战者。")
		return
	print("角色表：", _character_names(pool), "（", pool.size(), " 种）")

	var player_pool := _resolve_player_pool(pool)
	print("玩家角色池：", _character_names(player_pool), "（", player_pool.size(), " 种）")
	# 把本局可选的玩家角色同步给外部系统（选人界面等）
	MatchConfig.publish_available_characters(player_pool)

	var total: int = maxi(fighter_count, 1)
	var spawn_total: int = current_map.get_spawn_count()
	if spawn_total > 0 and total > spawn_total:
		push_warning("参战人数 %d 超过地图出生点数 %d，多出的角色会和已有角色叠在同一位置。"
			% [total, spawn_total])

	var rng := RandomNumberGenerator.new()
	if random_seed != 0:
		rng.seed = random_seed
	else:
		rng.randomize()

	var spawn_indices := _pick_spawn_indices(rng, total)
	var slot: int = clampi(player_slot_index, 0, total - 1)
	# 先定玩家角色，再排 AI 名单：玩家这一局用的角色不会落到任何 AI 身上
	var chosen_player := _resolve_player_character(player_pool, rng)
	var roster := _build_roster(pool, total, rng, [chosen_player], slot)
	roster[slot] = chosen_player
	var ai_no: int = 0
	for i in total:
		if i == slot:
			_spawn_fighter(spawn_indices[i], chosen_player, true, "Player")
		else:
			ai_no += 1
			_spawn_fighter(spawn_indices[i], roster[i], false, "AI_%d" % ai_no)

	print("战局开始：%d 名参战者｜地图出生点 %d 个｜随机种子 %d" % [total, spawn_total, rng.seed])
	print("出生点顺序：", spawn_indices)
	print("出场角色：", _character_names(roster), "（第 %d 位是玩家）" % slot)


## 选出本局使用的出生点索引；人数超过出生点数时循环复用
func _pick_spawn_indices(rng: RandomNumberGenerator, count: int) -> Array[int]:
	var result: Array[int] = []
	var spawn_total: int = current_map.get_spawn_count()

	if spawn_total <= 0:
		# 地图一个出生点都没放：全部落在原点，至少不会崩
		for i in count:
			result.append(0)
		return result

	var order: Array[int] = []
	if randomize_spawn_points:
		order = _shuffled_range(spawn_total, rng)
	else:
		for i in spawn_total:
			order.append(i)

	var cursor: int = 0
	while result.size() < count:
		result.append(order[cursor % order.size()])
		cursor += 1
	return result


## 排 AI 名单：洗牌后循环取用，保证每种角色都能上场，人数多于角色种类时才重复。
## exclude 里的角色（玩家这一局用的）一律不排给 AI；skip_index 是玩家自己占的槽位，
## 那个位置留空（由调用方填玩家角色），不消耗 AI 名额。
func _build_roster(pool: Array[CharacterData], count: int, rng: RandomNumberGenerator, exclude: Array[CharacterData] = [], skip_index: int = -1) -> Array[CharacterData]:
	var roster: Array[CharacterData] = []
	roster.resize(count)

	var candidates: Array[CharacterData] = []
	for data in pool:
		if data and not exclude.has(data):
			candidates.append(data)
	if candidates.is_empty():
		# 角色表里除了玩家这一局用的之外没别人了，只能让 AI 用同款，否则场上凑不够人
		if not exclude.is_empty():
			push_warning("随机池除玩家角色外没有别的角色，AI 会使用同名角色。")
			candidates = exclude.duplicate()
	if candidates.is_empty():
		return roster

	var order := _shuffled_range(candidates.size(), rng)
	var cursor: int = 0
	for i in count:
		if i == skip_index:
			continue
		roster[i] = candidates[order[cursor % order.size()]]
		cursor += 1
	return roster


func _character_names(roster: Array[CharacterData]) -> String:
	var names: Array[String] = []
	for data in roster:
		names.append(data.character_name if data else "-")
	return ", ".join(names)


## 玩家可选角色池：优先用本场景配的 player_character_pool，留空则与 AI 角色表共用
func _resolve_player_pool(shared_pool: Array[CharacterData]) -> Array[CharacterData]:
	var pool: Array[CharacterData] = []
	for item in player_character_pool:
		if item:
			pool.append(item)
	if not pool.is_empty():
		return pool
	return shared_pool


## 玩家角色解析优先级：
##   1. MatchConfig.select_character() 选定的    —— 外部接口
##   2. 本场景的 player_character 导出项         —— 目前在 Godot 里选
##   3. 从玩家角色池随机
func _resolve_player_character(player_pool: Array[CharacterData], rng: RandomNumberGenerator) -> CharacterData:
	if MatchConfig.has_selection():
		var external: CharacterData = MatchConfig.selected_character
		print("玩家角色：", external.character_name, "（来源：外部接口 MatchConfig）")
		return external

	if player_character:
		print("玩家角色：", player_character.character_name, "（来源：战局场景 player_character）")
		return player_character

	if not player_pool.is_empty():
		var picked: CharacterData = player_pool[rng.randi_range(0, player_pool.size() - 1)]
		print("玩家角色：", picked.character_name, "（来源：玩家角色池随机）")
		return picked

	print("玩家角色：", FALLBACK_CHARACTER.character_name, "（来源：兜底角色，玩家角色池为空）")
	return FALLBACK_CHARACTER


## 用指定随机源打乱 0..count-1
func _shuffled_range(count: int, rng: RandomNumberGenerator) -> Array[int]:
	var result: Array[int] = []
	for i in count:
		result.append(i)
	for i in range(result.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := result[i]
		result[i] = result[j]
		result[j] = swap
	return result


## 生成一名参战者并挂上对应的大脑
func _spawn_fighter(spawn_index: int, data: CharacterData, is_player: bool, node_name: String) -> void:
	var body := CHARACTER_SCENE.instantiate() as CharacterBody2D

	# 位置必须在入树之前设好：两个 CharacterBody2D 在同一坐标注册，
	# 物理引擎的重叠解算会把其中一个弹飞。
	body.position = to_local(current_map.get_spawn_position(spawn_index))
	body.name = node_name
	add_child(body)
	body.add_to_group("fighter")

	body.apply_data(data)

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
