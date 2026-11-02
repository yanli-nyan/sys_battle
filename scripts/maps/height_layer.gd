class_name HeightLayer
extends TileMapLayer

## 高度层：本层所有格子共享同一个海拔值。
##
## 用法：地图里每个「不同的可站立高度」放一个 TileMapLayer 并挂上本脚本，
## 在检查器里填 elevation，然后把该高度的地形直接画进这一层——
## 画图即标注，不需要再手工维护任何高度表。
##
## 约束：高度层的 position 必须是 (0,0)。GameMap 用统一的基准层换算格子坐标，
## 高度层一旦有位移，同一世界坐标会被算成不同格子，表就和美术对不上了。

@export var elevation: int = 0


## 供外部（GameMap 等）无需引用本脚本类型即可识别高度层。
## 不依赖 class_name 全局注册，避免 .godot 不可写时类型解析失败。
func is_height_layer() -> bool:
	return true


func _ready() -> void:
	if position != Vector2.ZERO:
		push_warning("高度层 %s 的 position 不是 (0,0)：%s。已强制归零，请改用 Node2D 容器做视觉偏移。" % [name, str(position)])
		position = Vector2.ZERO
