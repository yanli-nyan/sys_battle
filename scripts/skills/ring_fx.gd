class_name RingFX
extends Node2D

## 范围技能的扩散圆环特效（零外部素材）。
##
## 半径与透明度做成真实属性、由 Tween 直接驱动，而不是在 lambda 里改外部变量——
## GDScript 的 lambda 按值捕获局部变量，那样写半径根本不会变。

var ring_radius: float = 10.0:
	set(value):
		ring_radius = value
		queue_redraw()

var ring_alpha: float = 1.0:
	set(value):
		ring_alpha = value
		queue_redraw()

var ring_color: Color = Color(1.0, 0.4, 0.2, 0.6):
	set(value):
		ring_color = value
		queue_redraw()

## 圆环描边宽度（像素）
@export var line_width: float = 3.0


func _draw() -> void:
	draw_circle(Vector2.ZERO, ring_radius, Color(ring_color.r, ring_color.g, ring_color.b, ring_alpha * 0.3))
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 48, Color(ring_color.r, ring_color.g, ring_color.b, ring_alpha), line_width, true)
