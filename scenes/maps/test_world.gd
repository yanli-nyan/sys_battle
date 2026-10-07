extends Node2D

const CHARACTER_SCENE: PackedScene = preload("res://scenes/characters/base_character.tscn")
const PLAYER_DATA: CharacterData = preload("res://resources/characters/test.tres")
const ENEMY_DATA: CharacterData = preload("res://resources/characters/scout.tres")

const PLAYER_CONTROLLER_SCRIPT = preload("res://scenes/characters/player_controller.gd")
const AI_CONTROLLER_SCRIPT = preload("res://scenes/characters/ai_controller.gd")

@onready var spawn_points: Node2D = $SpawnPoints

# UI 节点引用
@onready var game_over_panel: PanelContainer = $CanvasLayer/GameOverPanel
@onready var result_label: Label = $CanvasLayer/GameOverPanel/VBoxContainer/ResultLabel
@onready var restart_button: Button = $CanvasLayer/GameOverPanel/VBoxContainer/RestartButton

# 裁判状态维护
var alive_fighters: Array[CharacterBody2D] = []
var player_instance: CharacterBody2D = null
var is_match_over: bool = false

func _ready() -> void:
	# 绑定重新开始按钮点击事件
	restart_button.pressed.connect(_on_restart_button_pressed)
	spawn_match()

func spawn_match() -> void:
	var spawns = spawn_points.get_children()
	if spawns.size() < 2:
		return

	# 1. 生成玩家
	var player = CHARACTER_SCENE.instantiate()
	add_child(player)
	player.global_position = spawns[0].global_position
	player.name = "Player"
	player.add_to_group("player")
	player.apply_data(PLAYER_DATA)
	player_instance = player
	_register_fighter(player)

	# 挂载大脑与相机
	var p_brain = Node2D.new()
	p_brain.name = "PlayerController"
	p_brain.set_script(PLAYER_CONTROLLER_SCRIPT)
	player.get_node("Brain").add_child(p_brain)

	var camera = Camera2D.new()
	camera.zoom = Vector2(2.5, 2.5)
	p_brain.add_child(camera)

	# 2. 生成敌人
	var enemy = CHARACTER_SCENE.instantiate()
	add_child(enemy)
	enemy.global_position = spawns[1].global_position
	enemy.name = "Enemy_Scout"
	enemy.apply_data(ENEMY_DATA)
	_register_fighter(enemy)

	var ai_brain = Node2D.new()
	ai_brain.name = "AIController"
	ai_brain.set_script(AI_CONTROLLER_SCRIPT)
	enemy.get_node("Brain").add_child(ai_brain)

# 注册选手并接入死亡监听
func _register_fighter(fighter: CharacterBody2D) -> void:
	alive_fighters.append(fighter)
	fighter.died.connect(_on_fighter_died)

# 选手阵亡回调
func _on_fighter_died(victim: CharacterBody2D) -> void:
	if is_match_over:
		return

	# 从存活列表移出
	alive_fighters.erase(victim)

	# 规则 1：玩家自身阵亡 -> 直接判负
	if victim == player_instance:
		_end_game(false)
		return

	# 规则 2：场上只剩最后一人，且正是玩家 -> 判胜
	if alive_fighters.size() == 1 and alive_fighters[0] == player_instance:
		_end_game(true)

# 战局结算
func _end_game(is_victory: bool) -> void:
	is_match_over = true
	
	# 冻结场上剩余实体的物理运算
	for fighter in alive_fighters:
		if is_instance_valid(fighter):
			fighter.set_physics_process(false)

	# 弹出 UI 提示
	game_over_panel.visible = true
	if is_victory:
		result_label.text = "战斗胜利！"
		result_label.modulate = Color.GREEN
	else:
		result_label.text = "败北..."
		result_label.modulate = Color.RED

# 重启场景
func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()