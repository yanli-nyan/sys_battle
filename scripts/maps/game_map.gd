class_name GameMap
extends Node2D

## 地图基类 —— 只描述「战场长什么样」，不参与任何战局逻辑。
##
## 战局（battle_world.gd）只通过本类暴露的接口读取地图信息，
## 因此新增一张地图 = 新建一个根节点挂载/继承本脚本的 .tscn，战局代码一行都不用改。
##
## 约定：
##   * 出生点放在名为 SpawnPoints 的 Node2D 下，子节点为 Marker2D；
##   * 墙体等物理阻挡用 collision_layer = 1 (World) 的 TileMapLayer；
##   * 触控 UI 若要逐图定制，给 touch_controls_override 指定预制体即可。

const SPAWN_POINTS_NODE_NAME := "SpawnPoints"

@export_group("地图信息")
## 地图显示名，用于 UI 与调试输出
@export var display_name: String = "未命名地图"
## 本图建议的最大参战人数（出生点不足时会循环复用，不会报错）
@export var capacity: int = 8

@export_group("战场边界")
## 手工指定边界（地图局部坐标）。留空（size 为 0）时自动从地形推算。
@export var manual_bounds: Rect2 = Rect2()

@export_group("移动端触控")
## 本图专属的触控 UI 预制体；留空时战局回退到全局默认触控层
@export var touch_controls_override: PackedScene

var _spawn_cache: Array[Marker2D] = []


func _ready() -> void:
	refresh_spawn_points()


## 重新扫描出生点；运行时动态增删出生点后调用即可生效
func refresh_spawn_points() -> void:
	_spawn_cache.clear()
	var root := get_node_or_null(SPAWN_POINTS_NODE_NAME)
	if root:
		_collect_markers(root)
	if _spawn_cache.is_empty():
		# 没有按约定放置 SpawnPoints 时退化为全场景搜索，避免地图作者一脚踩空
		_collect_markers(self)


func _collect_markers(node: Node) -> void:
	for child in node.get_children():
		var marker := child as Marker2D
		if marker and not _spawn_cache.has(marker):
			_spawn_cache.append(marker)
		_collect_markers(child)


## 全部出生点，按节点顺序
func get_spawn_points() -> Array[Marker2D]:
	if _spawn_cache.is_empty():
		refresh_spawn_points()
	return _spawn_cache


func get_spawn_count() -> int:
	return get_spawn_points().size()


## 第 index 个出生点；越界时循环复用，任意人数都能落位
func get_spawn_point(index: int) -> Marker2D:
	var points := get_spawn_points()
	if points.is_empty():
		return null
	return points[posmod(index, points.size())]


## 第 index 个出生点的全局坐标；地图没有出生点时回退到地图原点
func get_spawn_position(index: int) -> Vector2:
	var point := get_spawn_point(index)
	return point.global_position if point else global_position


## 战场边界（全局坐标）。返回 size 为 0 的 Rect2 表示无法推算。
func get_bounds() -> Rect2:
	if manual_bounds.size != Vector2.ZERO:
		return Rect2(manual_bounds.position + global_position, manual_bounds.size)
	return _bounds_from_terrain()


## 从所有 TileMapLayer 的已用区域推算边界（适合地面铺满整张图的地图）
func _bounds_from_terrain() -> Rect2:
	var bounds := Rect2()
	var found := false
	for layer in _collect_tile_layers(self):
		var used := layer.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		var tile_size := Vector2(32.0, 32.0)
		if layer.tile_set:
			tile_size = Vector2(layer.tile_set.tile_size)
		var layer_rect := Rect2(Vector2(used.position) * tile_size, Vector2(used.size) * tile_size)
		layer_rect.position += layer.global_position
		bounds = layer_rect if not found else bounds.merge(layer_rect)
		found = true
	return bounds


func _collect_tile_layers(node: Node) -> Array[TileMapLayer]:
	var layers: Array[TileMapLayer] = []
	for child in node.get_children():
		var layer := child as TileMapLayer
		if layer:
			layers.append(layer)
		else:
			layers.append_array(_collect_tile_layers(child))
	return layers


## 本图是否自带触控 UI 覆盖
func has_touch_controls_override() -> bool:
	return touch_controls_override != null


## 战局据此决定用哪套触控 UI；返回 null 表示交由战局使用全局默认层
func get_touch_controls_scene() -> PackedScene:
	return touch_controls_override
