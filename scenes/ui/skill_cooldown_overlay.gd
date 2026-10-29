extends Control

## 技能按钮上的冷却遮罩（零外部素材，全部 _draw 程序化绘制）。
##
## 与 PC 端底部 HUD（skill_cooldown_hud.gd）共用同一份数据接口：
## 只读角色的 get_skill_count() / get_skill(i)，以及 SkillData 的
## get_cooldown_ratio() / get_cooldown_remaining()。
## 区别只在于：这里不画独立槽位，而是铺在已有的技能按钮上，按内切圆绘制。

## 遮罩色：盖住「还要等」的那部分
@export var mask_color: Color = Color(0.04, 0.05, 0.09, 0.86)
## 边框色（冷却中）
@export var ring_color: Color = Color(1.0, 1.0, 1.0, 0.55)
## 就绪瞬间的高亮色
@export var ready_color: Color = Color(0.45, 1.0, 0.6, 0.95)
## 是否显示数字倒计时
@export var show_seconds: bool = true
## 小于该秒数时显示一位小数
@export var decimal_below: float = 1.0
## 就绪高亮持续时间（秒）
@export var ready_flash_time: float = 0.25

var _character: Node = null
var _ratio: float = 0.0
var _flash_left: float = 0.0
var _was_cooling: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## 由触控层（touch_controls.gd）注入角色；传 null 隐藏
func set_character(character: Node) -> void:
	_character = character
	set_process(character != null)
	if character == null:
		_ratio = 0.0
		_flash_left = 0.0
		_was_cooling = false
		visible = false
		queue_redraw()
		return
	visible = true
	queue_redraw()


## 取第 0 号技能槽的冷却进度；没有技能时按「就绪」处理（不遮罩）
func _read_ratio() -> float:
	if _character == null or not is_instance_valid(_character):
		return 0.0
	if not _character.has_method("get_skill"):
		return 0.0
	var skill: SkillData = _character.get_skill(0)
	if skill == null:
		return 0.0
	if skill.has_method("get_cooldown_ratio"):
		return skill.get_cooldown_ratio()
	return 0.0


func _process(delta: float) -> void:
	var ratio: float = _read_ratio()

	# 从「冷却中」跨到「就绪」的那一帧点亮高亮
	if _was_cooling and ratio <= 0.0:
		_flash_left = ready_flash_time
	_was_cooling = ratio > 0.0

	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)

	# 冷却走秒或高亮衰减时才需要重绘
	if not is_equal_approx(ratio, _ratio) or _flash_left > 0.0:
		_ratio = ratio
		queue_redraw()


func _draw() -> void:
	if _character == null:
		return

	var rect := Rect2(Vector2.ZERO, size)
	var center := rect.size * 0.5
	var radius: float = minf(rect.size.x, rect.size.y) * 0.5 - 3.0
	if radius <= 0.0:
		return

	# 边框：冷却中偏白，就绪瞬间偏绿
	var border: Color = ring_color
	if _flash_left > 0.0:
		border = ring_color.lerp(ready_color, _flash_left / maxf(ready_flash_time, 0.001))

	# 转圈遮罩：从 12 点方向顺时针覆盖「剩余比例」
	if _ratio > 0.0:
		var start_angle: float = -PI * 0.5
		var sweep: float = TAU * _ratio
		var steps: int = maxi(3, int(sweep / 0.12))
		var pts := PackedVector2Array()
		pts.append(center)
		for s in steps + 1:
			var a: float = start_angle + sweep * float(s) / float(steps)
			pts.append(center + Vector2(cos(a), sin(a)) * radius)
		draw_colored_polygon(pts, mask_color)
		# 遮罩前沿描一条亮线，让剩余量一眼可见
		var edge: float = start_angle + sweep
		draw_line(center, center + Vector2(cos(edge), sin(edge)) * radius,
			Color(border.r, border.g, border.b, 0.85), 2.0, true)
		draw_arc(center, radius, 0.0, TAU, 48, Color(border.r, border.g, border.b, 0.7), 2.0, true)

	# 数字倒计时
	if show_seconds and _character.has_method("get_skill"):
		var skill: SkillData = _character.get_skill(0)
		if skill != null:
			var remain: float = skill.get_cooldown_remaining()
			if remain > 0.0:
				var font := ThemeDB.fallback_font
				var font_size: int = maxi(16, int(radius * 0.9))
				var text: String = str(ceili(remain)) if remain >= decimal_below else ("%.1f" % remain)
				var y: float = center.y + font.get_ascent(font_size) * 0.5
				draw_string(font, Vector2(center.x - radius, y), text,
					HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, Color(1, 1, 1, 0.95))
