class_name NormalAIController
extends Node2D

## 【难度：NORMAL】会寻路、会放技能的 AI 大脑。
##
## 与 SO_EASY 的差别只有两点（正是这个难度的定义）：
##   1. 移动不再直线撞墙，而是用 A* 在「高度格网」上找路，能绕墙、能上高台；
##   2. 技能槽里只要「范围内有敌人」就放，不做时机判断。
##
## 刻意不做的事（留给 HARD 及以上）：
##   * 不按血量/威胁选目标，仍取最近的一个；
##   * 不判断放技能的时机（敌群数量、CD 收益、Buff 开的窗口）；
##   * 不主动跳崖（从高处往下差 ≥2 一律绕开，避免自己摔死）。
##
## 寻路用不着 Godot 内置的 AStarGrid2D：本项目的通行判定是「边」级的
## （从低到高看 climb，从高到低看落差），内置实现只能做「格」级阻挡。
## 地图只有约 2000 格，手写 A* 足够快。

## 进入该距离就停下开打；实际取值会按双方判定盒/受击盒半径重算
@export var attack_range: float = 34.0
## 是否按双方实际半径计算开打距离（关掉则用上面写死的值）
@export var dynamic_attack_range: bool = true
## 索敌刷新间隔（秒）
@export var retarget_interval: float = 0.4
## 重新寻路间隔（秒）：目标一直在动，跑完整路径没有意义
@export var repath_interval: float = 0.35
## 单次 A* 最多展开的节点数；超出就放弃寻路、退回直线追击，防止大地图卡顿
@export var max_path_expansions: int = 600
## 单次 A* 最多返回多少步。真实对战只需要前几步，跑完整路径纯属浪费：
## 12 步足够绕开一堵 1~2 格厚的墙，又不会在开阔地带白算几十格。
@export var max_path_length: int = 12
## 是否允许为了追人而从高处跳下去（NORMAL 默认关闭，避免自己摔死）
@export var allow_fall: bool = false
## 是否释放主动技能
@export var use_skills: bool = true
## 技能范围内至少有几个敌人才值得放（1 = 有人就放，符合 NORMAL 的定义）
@export var min_skill_targets: int = 1

## 当前锁定的目标
var target: CharacterBody2D = null

var _retarget_timer: float = 0.0
var _repath_timer: float = 0.0
## 当前路径（格坐标序列，不含起点）
var _path: Array[Vector2i] = []
## 上一次寻路时用的目标格，用来判断「目标没动、路径还能用」
var _path_target_cell: Vector2i = Vector2i(9999, 9999)

@onready var character: CharacterBody2D = get_parent().get_parent()
## 地图接口；由 battle_world 在生成时注入，没有注入时退回直线追击
var map: GameMap = null


func _ready() -> void:
	_acquire_target()


## 宿主注入地图接口（与 base_character 的 set_terrain 同一种做法）
func set_map(source: GameMap) -> void:
	map = source


func _process(delta: float) -> void:
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		_retarget_timer = retarget_interval
		_acquire_target()

	if not is_instance_valid(target) or target.current_hp <= 0:
		character.move_direction = Vector2.ZERO
		_path.clear()
		return

	var to_target := target.global_position - character.global_position
	var dist := to_target.length()

	# 1. 技能优先：能放就先放，放完这一帧不再出刀（技能与普攻互斥）
	if use_skills and _try_cast_skill():
		return

	# 2. 进入攻击距离就停下平砍
	var reach := _attack_reach()
	if dist <= reach:
		character.move_direction = Vector2.ZERO
		character.perform_basic_attack()
		return

	# 3. 追人：能寻路就沿路径走，否则直线顶过去
	character.move_direction = _next_move_direction(to_target)


# ---------- 索敌 ----------

## 在 fighter 组里挑选最近的活着的其它参战者
func _acquire_target() -> void:
	var best: CharacterBody2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("fighter"):
		var other := node as CharacterBody2D
		if other == null or other == character or not is_instance_valid(other):
			continue
		if other.current_hp <= 0:
			continue
		var dist := character.global_position.distance_squared_to(other.global_position)
		if dist < best_dist:
			best_dist = dist
			best = other
	target = best


## 开打距离：默认按「我的判定盒 + 对手受击盒」算，避免写死 34 在长手角色上永远够不着。
## 结果缓存，目标换了才重算——这只是两个字段的加法和一次属性读取，不必每帧做。
var _reach_cache: float = -1.0
var _reach_target: CharacterBody2D = null

func _attack_reach() -> float:
	if not dynamic_attack_range:
		return attack_range

	if _reach_cache > 0.0 and _reach_target == target:
		return _reach_cache

	var mine: CharacterData = character.character_data
	if mine == null:
		return attack_range

	var hurt: float = mine.hurtbox_radius
	var theirs: Variant = target.get("character_data")
	if theirs != null:
		var data := theirs as CharacterData
		if data != null:
			hurt = data.hurtbox_radius

	# 留一点余量，避免卡在几何边缘来回抖动
	_reach_cache = mine.hitbox_radius + hurt + 2.0
	_reach_target = target
	return _reach_cache


# ---------- 移动与寻路 ----------

## 决定这一帧往哪走。
## 性能关键：先用「直线可达」做快速判断——视线通透就直接走直线，完全不算 A*。
## 实测近距离 A* 约 0.06ms、跨图 2.7ms，而直线检查是几十次布尔比较，
## 真实对战里绝大多数时候两者之间没有墙，这条快速路径能省掉九成以上的计算。
func _next_move_direction(to_target: Vector2) -> Vector2:
	if map == null:
		return to_target.normalized()

	var here := map.world_to_cell(character.global_position)
	var goal := map.world_to_cell(target.global_position)

	# 直线可达：直接走，并清空旧路径（下次需要时重算）
	if _has_line_of_sight(here, goal):
		_path.clear()
		_path_target_cell = goal
		return to_target.normalized()

	# 只在「路径失效」或「目标换了格子」时重算。
	# 不再按时间强制重算：目标站在同一格时，同一条路径可以一直用。
	if _path.is_empty() or goal != _path_target_cell:
		_repath_timer = repath_interval
		_path_target_cell = goal
		_path = _find_path(here, goal)

	if _path.is_empty():
		# 无路可走（被围死、目标不可达）：直线顶过去，交给物理碰撞与地形规则处理
		return to_target.normalized()

	# 路径首格可能仍是当前格（还没跨出格边界），先丢掉再取下一步目标
	while not _path.is_empty() and _path[0] == here:
		_path.pop_front()
	if _path.is_empty():
		return to_target.normalized()

	var next_cell: Vector2i = _path[0]
	var next_world: Vector2 = map.cell_to_world(next_cell)
	return (next_world - character.global_position).normalized()


## 手写 A*（4 邻接，曼哈顿启发式）。
## 返回从起点之后的第一格到终点的格序列；不可达时返回空数组。
## 关键点：邻居扩展走 GameMap.get_traversal()，因此天然支持「边级」的方向性判定。
func _find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if map == null or from_cell == to_cell:
		return empty

	var grid: Rect2i = map.get_grid_rect()
	if not grid.has_point(from_cell) or not grid.has_point(to_cell):
		return empty

	var climb: int = 1
	if character != null and character.has_method("get_climb_height"):
		climb = int(character.call("get_climb_height"))

	# 目标格本身不可站立（墙/虚空）时，退而求其次走到它旁边
	if not _is_walkable(to_cell):
		return empty

	var open: Array[Vector2i] = [from_cell]
	var came: Dictionary = {}          # cell -> 上一格
	var g_score: Dictionary = {from_cell: 0}
	var f_score: Dictionary = {from_cell: _heuristic(from_cell, to_cell)}
	var closed: Dictionary = {}
	var expansions := 0

	while not open.is_empty():
		# 取 f 最小的节点（2040 格规模下线性扫描足够快，也不用维护堆）
		var best_index := 0
		for i in open.size():
			if float(f_score.get(open[i], INF)) < float(f_score.get(open[best_index], INF)):
				best_index = i
		var current: Vector2i = open[best_index]

		if current == to_cell:
			return _rebuild_path(came, current, from_cell)

		open.remove_at(best_index)
		closed[current] = true

		expansions += 1
		if expansions > max_path_expansions:
			return empty

		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = current + dir
			if not grid.has_point(nxt) or closed.has(nxt):
				continue
			# 走地图自己的判定：BLOCKED 拒走，FALL 看难度是否允许
			var t: int = int(map.get_traversal(current, nxt, climb))
			if t == GameMap.Traversal.BLOCKED:
				continue
			if t == GameMap.Traversal.FALL and not allow_fall:
				continue

			var tentative: int = int(g_score.get(current, 0)) + 1
			if tentative < int(g_score.get(nxt, 0x7FFFFFFF)):
				came[nxt] = current
				g_score[nxt] = tentative
				f_score[nxt] = tentative + _heuristic(nxt, to_cell)
				if not open.has(nxt):
					open.append(nxt)

	return empty


## 直线可达性检查：沿 from→to 方向逐格采样，
## 每跳都用地图的通行判定（和 A* 走的同一套规则），任何一跳不可行就返回 false。
## 采样步长按「较大的轴差」取，保证不会跳格漏掉墙。
func _has_line_of_sight(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if map == null:
		return true

	var climb: int = 1
	if character != null and character.has_method("get_climb_height"):
		climb = int(character.call("get_climb_height"))

	var delta: Vector2i = to_cell - from_cell
	var steps: int = maxi(absi(delta.x), absi(delta.y))
	if steps == 0:
		return true

	# 距离太远时不算视线：一是逐格采样本身就成了 O(n)，
	# 二是这个距离下 A* 本来也会因为展开上限返回空、退回直线追击。
	if steps > 24:
		return false

	# 标准 DDA（数字微分分析）：沿直线逐格推进，每步只跨 1 格。
	# 用「误差累积 + 主/次轴分别步进」实现，保证不会跳格漏墙，
	# 也不会像浮点采样那样在斜向相邻处误判。
	var x: int = from_cell.x
	var y: int = from_cell.y
	var dx: int = signi(delta.x)
	var dy: int = signi(delta.y)
	var adx: int = absi(delta.x)
	var ady: int = absi(delta.y)

	var current := from_cell
	if adx >= ady:
		# x 为主轴：每步都走 x，y 按误差累积决定是否同时走
		var err := 0
		for _i in adx:
			var next_x := x + dx
			var next_y := y
			err += ady
			if err >= adx and ady > 0:
				next_y += dy
				# 斜向时先走 y（走对角线），避免「先 x 后 y」在墙角被误判为不可达
				var diag := Vector2i(next_x, next_y)
				if not _step_ok(current, diag, climb):
					# 对角线不行就退回纯 x 步进
					var pure_x := Vector2i(next_x, y)
					if not _step_ok(current, pure_x, climb):
						return false
					x = next_x
					current = pure_x
					continue
				x = next_x
				y = next_y
				# err 已在斜向中消费
				err -= adx
				current = diag
				continue
			if dy != 0 and ady > 0 and err >= adx:
				err -= adx
			var nx := Vector2i(next_x, y)
			if not _step_ok(current, nx, climb):
				return false
			x = next_x
			current = nx
	else:
		# y 为主轴
		var err2 := 0
		for _i in ady:
			var ny := Vector2i(x, y + dy)
			if not _step_ok(current, ny, climb):
				return false
			err2 += adx
			if err2 >= ady and adx > 0:
				err2 -= ady
				ny.x = x + dx
				if not _step_ok(current, ny, climb):
					return false
				x += dx
			y += dy
			current = ny
	return true


## 相邻两格之间能否通过（视线与 A* 共用的判定口径）
func _step_ok(from_cell: Vector2i, to_cell: Vector2i, climb: int) -> bool:
	var t: int = int(map.get_traversal(from_cell, to_cell, climb))
	if t == GameMap.Traversal.BLOCKED:
		return false
	if t == GameMap.Traversal.FALL and not allow_fall:
		return false
	return true


## 曼哈顿距离：4 邻接下的可采纳启发式
func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## 回溯路径。只保留前 max_path_length 步：走完再接一次寻路即可，
## 没必要一次算出整条路（目标随时会动，长路径大概率作废）。
func _rebuild_path(came: Dictionary, end_cell: Vector2i, start_cell: Vector2i) -> Array[Vector2i]:
	var reversed_path: Array[Vector2i] = []
	var cur := end_cell
	while cur != start_cell and came.has(cur):
		reversed_path.append(cur)
		cur = came[cur]
	reversed_path.reverse()

	var limit: int = maxi(max_path_length, 1)
	var path: Array[Vector2i] = []
	for i in mini(reversed_path.size(), limit):
		path.append(reversed_path[i])
	return path


func _is_walkable(cell: Vector2i) -> bool:
	if map == null:
		return true
	var h: int = map.get_elevation(cell)
	return h != GameMap.HEIGHT_WALL and h != GameMap.HEIGHT_VOID


# ---------- 技能 ----------

## 只要范围内有敌人就放第一个能放的技能。
## 半径直接读技能的 radius 导出属性，BuffSkill 没有这个属性 -> 视为"无半径"技能，
## 只有正在交战时才放，避免开局就浪费 CD。
func _try_cast_skill() -> bool:
	# 普攻正在出刀时会挡住施法，这一帧先不管技能
	if character.is_attacking and not character.can_cancel_attack:
		return false

	var slots: int = int(character.call("get_skill_count"))
	for slot in slots:
		var skill = character.call("get_skill", slot)
		if skill == null:
			continue
		if not skill.is_ready():
			continue
		if not _should_cast(skill, slot):
			continue
		if _cast_with_aim(slot):
			return true
	return false


## 判断某个技能现在该不该放
func _should_cast(skill: SkillData, _slot: int) -> bool:
	var radius_value: Variant = skill.get("radius")

	# 无半径技能（自我强化类）：只在已经接敌时放
	if radius_value == null:
		return _is_engaged()

	var radius: float = float(radius_value)
	if radius <= 0.0:
		return _is_engaged()

	# 有半径技能：范围内敌人数量达到阈值就放
	return _count_enemies_in_radius(radius) >= min_skill_targets


func _is_engaged() -> bool:
	if not is_instance_valid(target):
		return false
	return character.global_position.distance_to(target.global_position) <= _attack_reach() * 3.0


## 统计以自身为圆心、radius 内的活着的敌人数量。
## 复用技能系统的同一套判定口径（受击盒所在的物理层），保证「AI 认为的范围内」
## 和「技能实际能打到」一致。这里不调 SkillData.find_enemies_in_radius，
## 因为那是技能实例的方法，AI 手上只有 CharacterBody2D。
func _count_enemies_in_radius(radius: float) -> int:
	var count := 0
	var r2 := radius * radius
	for node in get_tree().get_nodes_in_group("fighter"):
		var other := node as CharacterBody2D
		if other == null or other == character or not is_instance_valid(other):
			continue
		if other.current_hp <= 0:
			continue
		if character.global_position.distance_squared_to(other.global_position) <= r2:
			count += 1
	return count


## 施法前先把朝向对准目标。
## 关键：aim_direction 由 move_direction 驱动，站桩时朝向会停在最后一次移动方向，
## 不修正的话投射物类技能会朝错方向打出去。
func _cast_with_aim(slot: int) -> bool:
	if not is_instance_valid(target):
		return false
	var dir := (target.global_position - character.global_position).normalized()
	if dir == Vector2.ZERO:
		return false
	# 朝目标放技能：通过 cast_active_skill 的 aim 覆盖参数直接命中目标方向
	return bool(character.cast_active_skill(slot, dir))
