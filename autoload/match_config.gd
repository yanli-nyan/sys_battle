extends Node

## 战局配置中介（Autoload 单例，名字就是 MatchConfig）。
##
## 「玩家选哪个角色」的外部接口在这里：选人界面、存档、外部脚本、调试工具，
## 只要拿到这个单例就能指定玩家角色；战局不需要知道选择是从哪来的。
##
## 玩家角色的解析优先级（见 battle_world.gd 的 _resolve_player_character）：
##   1. MatchConfig.select_character() 选定的角色   —— 外部接口
##   2. 战局场景里的 player_character 导出项        —— 目前在 Godot 里选
##   3. 从玩家角色池随机

## 外部选定角色时发出，方便界面即时刷新
signal selection_changed(character: CharacterData)
## 外部选定地图时发出，方便选图界面即时刷新
signal map_changed(map_scene: PackedScene)

## 外部选定的玩家角色；null 表示没有外部选择
var selected_character: CharacterData = null

## 外部选定的地图场景；null 表示没有外部选择
var selected_map: PackedScene = null

## 本局玩家可选的角色池，由战局每局同步过来，供选人界面等外部系统枚举
var available_characters: Array[CharacterData] = []
## 本局可选的地图池，由战局每局同步过来，供选图界面枚举
var available_maps: Array[PackedScene] = []


## 外部系统选定玩家角色（选人界面点确认时调用）
func select_character(character: CharacterData) -> void:
	selected_character = character
	selection_changed.emit(character)


## 按角色名选定，方便外部脚本或配置用字符串指定；选中返回 true
## 需要先有角色池：战局跑过一局后 available_characters 就有内容了，
## 也可以直接调 set_available_characters() 自己灌一份。
func select_character_by_name(character_name: String) -> bool:
	for character in available_characters:
		if character and character.character_name == character_name:
			select_character(character)
			return true
	return false


## 灌入角色池（外部系统自己维护列表时用）
func set_available_characters(pool: Array[CharacterData]) -> void:
	available_characters = pool


## 清空外部选择，退回「战局里选的 / 随机」
func clear_selection() -> void:
	if selected_character == null:
		return
	selected_character = null
	selection_changed.emit(null)


func has_selection() -> bool:
	return selected_character != null


## 战局每局开头调用：把本局实际可选的玩家角色同步给外部系统
func publish_available_characters(pool: Array[CharacterData]) -> void:
	available_characters = pool


# ---------- 地图选择 ----------

## 外部系统选定地图（选图界面点确认时调用）
func select_map(map_scene: PackedScene) -> void:
	selected_map = map_scene
	map_changed.emit(map_scene)


## 按资源路径选定地图，方便外部脚本或配置用字符串指定；选中返回 true
func select_map_by_path(path: String) -> bool:
	if path.is_empty():
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("地图加载失败：%s" % path)
		return false
	select_map(scene)
	return true


## 清空外部地图选择，退回「战局里选的 / 池随机」
func clear_map_selection() -> void:
	if selected_map == null:
		return
	selected_map = null
	map_changed.emit(null)


func has_map_selection() -> bool:
	return selected_map != null


## 战局每局开头调用：把本局实际可选的地图同步给外部系统
func publish_available_maps(pool: Array[PackedScene]) -> void:
	available_maps = pool
