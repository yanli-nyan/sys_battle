extends Node2D

# 1. 引用通用肉体预制体
const CHARACTER_SCENE: PackedScene = preload("res://scenes/characters/base_character.tscn")

# 2. 引用数据模板 (.tres)
const PLAYER_DATA: CharacterData = preload("res://resources/characters/test.tres")
const ENEMY_DATA: CharacterData = preload("res://resources/characters/scout.tres")

# 3. 引用大脑控制器脚本
const PLAYER_CONTROLLER_SCRIPT = preload("res://scenes/characters/player_controller.gd")
const AI_CONTROLLER_SCRIPT = preload("res://scenes/characters/ai_controller.gd")

@onready var spawn_points: Node2D = $SpawnPoints

func _ready() -> void:
	spawn_match()

func spawn_match() -> void:
	# 获取所有出生点节点
	var spawns = spawn_points.get_children()
	if spawns.size() < 2:
		push_error("出生点数量不足 2 个！")
		return

	# --- 1. 在 Spawn1 出生点生成玩家 ---
	var player = CHARACTER_SCENE.instantiate()
	add_child(player)
	player.global_position = spawns[0].global_position
	player.name = "Player"
	player.add_to_group("player") # 打上分组供 AI 索敌
	player.apply_data(PLAYER_DATA)

	# 为玩家动态挂载大脑 (PlayerController) 和摄像机
	var p_brain = Node2D.new()
	p_brain.name = "PlayerController"
	p_brain.set_script(PLAYER_CONTROLLER_SCRIPT)
	player.get_node("Brain").add_child(p_brain)

	# 挂载跟随相机
	var camera = Camera2D.new()
	camera.zoom = Vector2(2.5, 2.5) # 设置适合 32x32 的适中视野缩放
	p_brain.add_child(camera)

	# --- 2. 在 Spawn2 出生点生成敌人 (AI) ---
	var enemy = CHARACTER_SCENE.instantiate()
	add_child(enemy)
	enemy.global_position = spawns[1].global_position
	enemy.name = "Enemy_Scout"
	enemy.apply_data(ENEMY_DATA)

	# 为敌人动态挂载 AI 大脑
	var ai_brain = Node2D.new()
	ai_brain.name = "AIController"
	ai_brain.set_script(AI_CONTROLLER_SCRIPT)
	enemy.get_node("Brain").add_child(ai_brain)
