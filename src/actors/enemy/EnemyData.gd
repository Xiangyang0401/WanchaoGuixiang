class_name EnemyData
extends Resource
## 敌人属性配置。一个 .tres 文件 = 一种怪。
##
## 策划工作流：复制一份 .tres，改数值，拖到地图上的 Enemy 节点即可，
## 不需要写任何代码，也不需要新建场景。
##
## 加字段时只改这个文件，所有已有的 .tres 会自动继承默认值，不会破坏现有配置。

@export_group("身份")
@export var display_name: String = "外物"
@export var enemy_id: StringName = &"unknown"

@export_group("生命")
@export var max_hp: int = 3
## 受击后无敌时长（秒）。设得太长会让攻击手感黏滞。
@export var invulnerability_time: float = 0.15
## 击退抗性。0 = 完全被击退，1 = 完全免疫。boss 通常接近 1。
@export_range(0.0, 1.0) var knockback_resistance: float = 0.0

@export_group("接触伤害")
## 碰到玩家造成的伤害。0 表示无接触伤害。
@export var contact_damage: int = 1
## 接触伤害的击退力度（像素/秒）。
@export var contact_knockback: float = 320.0
## 接触伤害的重复间隔（秒）。
@export var contact_interval: float = 0.8

@export_group("移动")
## 移动速度（格/秒）。静止怪填 0。
@export var move_speed_tiles: float = 2.0
## 重力倍率。1.0 = 正常受重力，0 = 悬浮怪。
@export var gravity_scale: float = 1.0

@export_group("巡逻")
## 巡逻范围（格）。以出生点为中心，左右各这么远。
@export var patrol_range_tiles: float = 4.0
## 是否在悬崖边缘转身。开启后不会自己走下悬崖。
@export var turn_at_ledge: bool = true
## 是否撞墙转身。
@export var turn_at_wall: bool = true
## 到达巡逻边界后的停顿时间（秒）。0 = 立刻转身。
@export var patrol_pause: float = 0.0

@export_group("死亡")
## 死亡后尸体停留时间（秒），之后节点被释放。
@export var corpse_duration: float = 0.5
## 掉落物场景（预留，暂未使用）。
@export var drop_scene: PackedScene

@export_group("表现")
## 占位色。正式美术接入前用它区分怪种。
@export var placeholder_color: Color = Color(0.85, 0.25, 0.25)
## 碰撞体尺寸（格）。
@export var size_tiles: Vector2 = Vector2(1.0, 1.0)


func move_speed() -> float:
	return GameConfig.tiles(move_speed_tiles)

func patrol_range() -> float:
	return GameConfig.tiles(patrol_range_tiles)

func size_px() -> Vector2:
	return size_tiles * GameConfig.TILE_SIZE
