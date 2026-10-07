class_name CharacterData
extends Resource

@export_group("基础属性")
@export var character_name: String = "未命名角色"
@export var max_hp: int = 100
@export var move_speed: float = 160.0
@export var attack_speed: float = 1.0

@export_group("视觉资产")
@export var sprite_texture: Texture2D           # 局内模型贴图 (PNG)
@export var avatar: Texture2D                   # 头像/UI立绘
@export var texture_offset: Vector2 = Vector2.ZERO # 微调不同素材的脚底对齐偏移

@export_group("普通攻击")
@export var basic_attack: BasicAttackData

@export_group("战术技能")
@export var active_skills: Array[SkillData] = []