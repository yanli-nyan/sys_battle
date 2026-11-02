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
@export var capacity: int = 9

@export_group("高度")
## 基准海拔：地形层（ground 等）铺出来的格子默认就是这个高度。
## 高度层只负责标记「高出基准」的格子，因此基准值必须显式声明，不靠统计推断。
@export var base_elevation: int = 0

@export_group("战场边界")
## 手工指定边界（地图局部坐标）。留空（size 为 0）时自动从地形推算。
@export var manual_bounds: Rect2 = Rect2()

@export_group("移动端触控")
## 本图专属的触控 UI 预制体；留空时战局回退到全局默认触控层
@export var touch_controls_override: PackedScene

var _spawn_cache: Array[Marker2D] = []


func _ready() -> void:
	refresh_spawn_points()
	# 高度层都是本图的子节点，_ready 时地形数据已就位，可以一次性建表
	build_height_table()


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


## 收集「地形层」：排除挂了 HeightLayer 的高度层，
## 因为高度层通常只盖住一小块区域，把它算进边界会让相机范围偏大。
func _collect_tile_layers(node: Node) -> Array[TileMapLayer]:
	var layers: Array[TileMapLayer] = []
	for child in node.get_children():
		var layer := child as TileMapLayer
		if layer and not _is_height_layer(layer):
			layers.append(layer)
		elif layer == null:
			layers.append_array(_collect_tile_layers(child))
	return layers


# ---------- 高度与地形通行 ----------

## 地形通行判定结果。get_traversal() 返回这里的取值。
enum Traversal {
	BLOCKED,      ## 不可通行（墙、虚空、落差太大）
	WALK,         ## 平地
	STAIR_UP,     ## 上坡 / 上台阶（落差在 climb 能力内）
	STAIR_DOWN,   ## 下坡 / 下台阶（落差在可走下坡的范围内）
	FALL,         ## 坠落：落差超过 WALKABLE_DROP，可下但会摔
}

## 墙格的高度标记（不可站立）
const HEIGHT_WALL := 999
## 虚空格的高度标记（没有地面，掉出地图）
const HEIGHT_VOID := -100
## 默认一次能爬升的最大高度差；角色可以用各自的 climb_height 覆盖
const DEFAULT_CLIMB := 1
## 落差多少以内算「正常走下台阶」而不是「坠落」。
## 取 1 表示：相差 1 级（0->1 上、1->0 下）都是免费通行，不受伤；
## 只有往下差 2 级及以上才判 FALL 并结算伤害。
const WALKABLE_DROP := 1

## 地形层（用于推算网格范围与基准坐标）
var _terrain_layers: Array[TileMapLayer] = []
## 所有高度层：elevation -> 层节点
var _height_by_elevation: Dictionary = {}
## 格子 -> 高度；只存非默认高度的格子（稀疏），默认高度见 _default_elevation
var _height_cells: Dictionary = {}
var _default_elevation: int = 0
## 网格范围（格坐标）
var _grid_rect: Rect2i = Rect2i()
var _height_ready := false


## 高度表是否已构建
func is_height_ready() -> bool:
	return _height_ready


## 网格范围（格坐标）。没有地形层时返回 size 为 0 的 Rect2i。
func get_grid_rect() -> Rect2i:
	_ensure_height_table()
	return _grid_rect


## 构建（或重建）高度表。地图图层在运行时被改动后调用即可刷新。
## 规则：同一格出现在多个高度层上时取最高的那个海拔。
func build_height_table() -> void:
	_height_ready = false
	_height_by_elevation.clear()
	_height_cells.clear()
	_grid_rect = Rect2i()
	_terrain_layers = _collect_tile_layers(self)

	# 1. 收集所有高度层（挂了 HeightLayer 的 TileMapLayer），按海拔登记
	var elevations: Array[int] = []
	for layer in _collect_all_tile_layers(self):
		if _is_height_layer(layer):
			var elev: int = int(layer.get("elevation"))
			if not _height_by_elevation.has(elev):
				_height_by_elevation[elev] = layer
				elevations.append(elev)
			else:
				push_warning("高度层 %s 与其他层共用海拔 %d，后出现的层不会参与高度计算。" % [layer.name, elev])

	# 2. 网格范围以地形层为准（高度层通常画不满整张图，不能拿来定边界）
	var found := false
	for layer in _terrain_layers:
		var used := layer.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		_grid_rect = used if not found else _grid_rect.merge(used)
		found = true

	if not found:
		_height_ready = true
		return

	# 3. 铺表：按海拔从低到高写入，高的覆盖低的
	elevations.sort()
	for elevation in elevations:
		var hl: TileMapLayer = _height_by_elevation[elevation]
		for cell in hl.get_used_cells():
			_height_cells[cell] = elevation

	# 3.5 墙：带物理碰撞的地形层，其格子一律标记为 HEIGHT_WALL（优先级最高）
	for layer in _terrain_layers:
		if not _is_wall_layer(layer):
			continue
		for cell in layer.get_used_cells():
			_height_cells[cell] = HEIGHT_WALL

	# 4. 默认高度直接取 base_elevation，不做统计推断。
	#    原因：没有高度层的地图上，统计出来的「多数海拔」可能被个别高台带偏；
	#    基准高度必须是地图作者显式声明的事实，不能靠猜。
	_default_elevation = base_elevation

	_height_ready = true


## 某格的海拔。未铺地形的格子按默认高度处理。
## 返回 HEIGHT_WALL / HEIGHT_VOID 表示不可站立。
func get_elevation(cell: Vector2i) -> int:
	_ensure_height_table()
	if not _grid_rect.has_point(cell):
		return HEIGHT_VOID
	return int(_height_cells.get(cell, _default_elevation))


## 世界坐标 -> 格坐标。所有层共用同一个换算（高度层 position 必须为 0）。
func world_to_cell(world_pos: Vector2) -> Vector2i:
	_ensure_height_table()
	var base := _base_terrain_layer()
	if base == null:
		return Vector2i.ZERO
	return base.local_to_map(base.to_local(world_pos))


## 格坐标 -> 世界坐标（格子左上角中心）
func cell_to_world(cell: Vector2i) -> Vector2:
	_ensure_height_table()
	var base := _base_terrain_layer()
	if base == null:
		return global_position
	return base.to_global(base.map_to_local(cell))


## 世界坐标处的海拔，供肉体的「我现在站在几层」使用
func get_elevation_at(world_pos: Vector2) -> int:
	return get_elevation(world_to_cell(world_pos))


## 从 from_cell 走向 to_cell 是否允许，以及允许的方式。
## climb 是角色一次能爬升的最大高度差（默认 DEFAULT_CLIMB，可传角色的 climb_height）。
## 注意方向不对称：向上超过 climb 是阻挡，向下超过 WALKABLE_DROP 是坠落。
func get_traversal(from_cell: Vector2i, to_cell: Vector2i, climb: int = DEFAULT_CLIMB) -> Traversal:
	var to_h := get_elevation(to_cell)
	if to_h == HEIGHT_WALL or to_h == HEIGHT_VOID:
		return Traversal.BLOCKED
	var from_h := get_elevation(from_cell)
	if from_h == HEIGHT_WALL or from_h == HEIGHT_VOID:
		return Traversal.BLOCKED
	var delta := to_h - from_h
	if delta > 0:
		return Traversal.STAIR_UP if delta <= maxi(climb, 0) else Traversal.BLOCKED
	if delta < 0:
		return Traversal.STAIR_DOWN if -delta <= WALKABLE_DROP else Traversal.FALL
	return Traversal.WALK


## 落差超过多少级算坠落（供角色侧读取，避免跨类访问常量）
func get_walkable_drop() -> int:
	return WALKABLE_DROP


## 便捷布尔版：是否允许走过去（坠落也算「可过去」，由调用方决定怎么处理）
func can_move(from_cell: Vector2i, to_cell: Vector2i, climb: int = DEFAULT_CLIMB) -> bool:
	return get_traversal(from_cell, to_cell, climb) != Traversal.BLOCKED


## 高度优势：高处打低处的加成依据。返回 from 相对 to 的海拔差（同层为 0）。
func get_height_advantage(from_cell: Vector2i, to_cell: Vector2i) -> int:
	return get_elevation(from_cell) - get_elevation(to_cell)


## 是否是高度层：靠 HeightLayer 暴露的 is_height_layer() 识别，
## 不引用 class_name，避免 .godot 不可写时出现「找不到类型」的解析错误。
func _is_height_layer(layer: TileMapLayer) -> bool:
	return layer != null and layer.has_method("is_height_layer")


## 判定一个地形层是不是「墙」：TileSet 里带物理碰撞层即视为阻挡。
## 这样地图作者只要把碰撞层设成 World，就不需要另外打标记。
func _is_wall_layer(layer: TileMapLayer) -> bool:
	var ts: TileSet = layer.tile_set
	return ts != null and ts.get_physics_layers_count() > 0


func _ensure_height_table() -> void:
	if not _height_ready:
		build_height_table()


## 基准层：第一个地形层，所有坐标换算都以它为准
func _base_terrain_layer() -> TileMapLayer:
	if _terrain_layers.is_empty():
		_terrain_layers = _collect_tile_layers(self)
	return _terrain_layers[0] if not _terrain_layers.is_empty() else null


## 收集全部 TileMapLayer（含高度层）
func _collect_all_tile_layers(node: Node) -> Array[TileMapLayer]:
	var layers: Array[TileMapLayer] = []
	for child in node.get_children():
		var layer := child as TileMapLayer
		if layer:
			layers.append(layer)
		else:
			layers.append_array(_collect_all_tile_layers(child))
	return layers


## 本图是否自带触控 UI 覆盖
func has_touch_controls_override() -> bool:
	return touch_controls_override != null


## 战局据此决定用哪套触控 UI；返回 null 表示交由战局使用全局默认层
func get_touch_controls_scene() -> PackedScene:
	return touch_controls_override
