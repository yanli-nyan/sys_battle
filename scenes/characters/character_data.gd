class_name CharacterData
extends Resource

@export_group("基础属性")
@export var character_name: String = "未命名角色"
@export var max_hp: int = 100
@export var move_speed: float = 160.0
@export var attack_speed: float = 1.0

@export_group("地形")
@export var climb_height: int = 1               # 一次能爬升的最大高度差（1=只能上一级台阶）
@export var fall_damage_per_level: int = 10     # 坠落时每超出 1 级高差造成的伤害
@export var fall_stun_time: float = 0.0         # 落地硬直（秒）；0 = 不硬直，纯粹扣血就走

@export_group("碰撞体")
@export var hitbox_radius: float = 18.0        # 普攻判定盒(Hitbox)半径，决定近战攻击距离
@export var hurtbox_radius: float = 15.0       # 受击盒(Hurtbox)半径，决定被打中的难易程度

@export_group("视觉资产")
@export var sprite_texture: Texture2D           # 局内模型贴图 (PNG)
@export var avatar: Texture2D                   # 头像/UI立绘
@export var texture_offset: Vector2 = Vector2.ZERO # 微调不同素材的脚底对齐偏移

@export_group("普通攻击")
@export var basic_attack: BasicAttackData

@export_group("战术技能")
@export var active_skills: Array[SkillData] = []