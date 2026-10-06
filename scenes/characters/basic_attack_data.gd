class_name BasicAttackData
extends Resource

@export var combo_count: int = 3           # 最大连段数（如三段平砍）
@export var combo_reset_time: float = 0.8  # 多长时间不接下一击则重置回第1段
@export var damages: Array[int] = [15, 15, 30] # 各段平砍伤害（第三段重击）
@export var attack_rate: float = 0.35      # 两次平砍之间的最小间隔