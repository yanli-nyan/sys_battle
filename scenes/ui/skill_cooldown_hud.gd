extends Control

## 技能冷却 HUD（零外部素材，全部 _draw 程序化绘制）。
##
## 设计要点：
##   * 自己不认识任何角色，只接收宿主注入的「角色」引用，每帧读取其技能槽；
##   * 冷却是「转圈遮罩 + 数字倒计时」双显示：遮罩负责余光感知，数字负责精确判断；
##   * 冷却转就绪的那一帧做一次短暂高亮，解决「按了没反应，不知道是冷却还是没技能」；
##   * 不显示技能名，只做状态指示（按钮/图标由调用方另行决定）。

## 每个槽位图标的外框边长（像素）
@export var slot_size: float = 64.0
## 槽位之间的间距（像素）
@export var slot_gap: float = 12.0
## 是否显示数字倒计时
@export var show_seconds: bool = true
## 冷却剩余小于该秒数时就显示一位小数，让「马上好了」更有反馈
@export var decimal_below: float = 1.0
## 就绪高亮的持续时间（秒）
@export var ready_flash_time: float = 0.25

## 底盘色：没有任何冷却遮罩时露出来的部分，代表「这一块已经可用」
var base_color: Color = Color(0.33, 0.47, 0.68, 0.62)
## 遮罩色：盖住「还要等」的那部分，越暗代表还要等越久
var mask_color: Color = Color(0.04, 0.05, 0.09, 0.86)
var ring_color: Color = Color(1.0, 1.0, 1.0, 0.55)
var ready_color: Color = Color(0.45, 1.0, 0.6, 0.95)
var empty_color: Color = Color(1.0, 1.0, 1.0, 0.18)

## 宿主每帧注入的玩家角色；为 null 时整块隐藏
var _character: Node = null
## 每个槽位上一帧的冷却比值，用于检测「刚好转就绪」的时刻
var _last_ratio: Array[float] = []
var _flash_left: Array[float] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 由宿主（battle_world.gd）每帧调用；传 null 表示本帧没有可显示的角色
func set_character(character: Node) -> void:
	_character = character
	if character == null:
		visible = false
		return
	_sync_slots(character.get_skill_count() if character.has_method("get_skill_count") else 0)
	visible = _last_ratio.size() > 0
	queue_redraw()


## 槽位数量变化时重建辅助数组（角色换装或换人时会发生）
func _sync_slots(count: int) -> void:
	if _last_ratio.size() == count:
		return
	_last_ratio.resize(count)
	_flash_left.resize(count)
	for i in count:
		_last_ratio[i] = 1.0
		_flash_left[i] = 0.0


func _process(delta: float) -> void:
	if not visible or _character == null:
		return

	var count: int = _last_ratio.size()
	var changed := false
	for i in count:
		var skill: SkillData = _character.get_skill(i)
		var ratio: float = 0.0
		if skill != null and skill.has_method("get_cooldown_ratio"):
			ratio = skill.get_cooldown_ratio()

		# 从「冷却中」跨到「就绪」的那一帧点一次高亮
		if _last_ratio[i] > 0.0 and ratio <= 0.0:
			_flash_left[i] = ready_flash_time
		_last_ratio[i] = ratio

		if _flash_left[i] > 0.0:
			_flash_left[i] = maxf(0.0, _flash_left[i] - delta)
			changed = true

		# 冷却在走秒时必须重绘
		if ratio > 0.0:
			changed = true

	if changed:
		queue_redraw()


func _draw() -> void:
	var count: int = _last_ratio.size()
	if count == 0 or _character == null:
		return

	for i in count:
		var origin := Vector2(i * (slot_size + slot_gap), 0.0)
		var skill: SkillData = _character.get_skill(i)
		var rect := Rect2(origin, Vector2(slot_size, slot_size))
	# 空槽（角色没配这个技能位）画淡框，明确「这里没有技能」
		if skill == null:
			draw_rect(rect, empty_color, false, 2.0)
			continue

		var ratio: float = skill.get_cooldown_ratio()
		var center := origin + Vector2(slot_size * 0.5, slot_size * 0.5)
		var radius: float = slot_size * 0.5

		# 底盘用亮色：遮罩扫过去之后露出来的就是「已可用」的部分
		draw_circle(center, radius, base_color)
		# 边框：冷却中偏白、就绪瞬间偏绿
		var border: Color = ring_color
		if _flash_left[i] > 0.0:
			var k: float = _flash_left[i] / maxf(ready_flash_time, 0.001)
			border = ring_color.lerp(ready_color, k)
		draw_arc(center, radius, 0.0, TAU, 48, border, 2.5, true)

		# 转圈遮罩：从 12 点方向顺时针扫过「剩余比例」
		# 剩余比例 1.0 时几乎盖满整圈，降到 0 时遮罩消失 —— 视觉上就是「转圈回满」
		if ratio > 0.0:
			var start_angle: float = -PI * 0.5
			var sweep: float = TAU * ratio
			var steps: int = maxi(3, int(sweep / 0.12))
			var pts := PackedVector2Array()
			pts.append(center)
			for s in steps + 1:
				var a: float = start_angle + sweep * float(s) / float(steps)
				pts.append(center + Vector2(cos(a), sin(a)) * radius)
			draw_colored_polygon(pts, mask_color)
			# 遮罩的前沿描一条亮线，让「剩余量」一眼可见
			var edge: float = start_angle + sweep
			draw_line(center, center + Vector2(cos(edge), sin(edge)) * radius,
				Color(border.r, border.g, border.b, 0.85), 2.0, true)

		# 数字倒计时
		if show_seconds:
			var remain: float = skill.get_cooldown_remaining()
			if remain > 0.0:
				var font := ThemeDB.fallback_font
				var font_size: int = int(slot_size * 0.42)
				var text: String = str(ceili(remain)) if remain >= decimal_below else ("%.1f" % remain)
				# 以圆心为中心：宽度取整圈，水平居中；y 抬半个字高让数字视觉居中
				var x: float = center.x - radius
				var y: float = center.y + font.get_ascent(font_size) * 0.5
				draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_CENTER,
					radius * 2.0, font_size, Color(1, 1, 1, 0.95))
			elif _flash_left[i] > 0.0:
				# 就绪瞬间打一个勾的替代：一个点，避免依赖字体字形支持
				draw_circle(center, slot_size * 0.16, ready_color)
			else:
				draw_circle(center, slot_size * 0.10, Color(1, 1, 1, 0.35))
