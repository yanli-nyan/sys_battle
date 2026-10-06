# 在 TouchControls.gd 中
extends CanvasLayer

func _ready() -> void:
	# 如果不是移动端平台（Android / iOS），且当前设备不支持触控，直接隐藏虚拟摇杆
	var is_mobile = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	visible = is_mobile