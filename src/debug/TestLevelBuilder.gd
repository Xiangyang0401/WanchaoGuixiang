class_name TestLevelBuilder
extends Node
## 测试关地形生成器。
##
## 【这是临时脚本，不是正式流程】
## 正式关卡应该由你在 Godot 编辑器里用 TileMapLayer 手绘。
## 这个脚本只是为了在还没有美术、也没有手绘地图的情况下，
## 立刻产出一个能验证所有系统的可跑场景。
##
## 用 ASCII 图定义地形，一个字符 = 一格。图例：
##   #  实心地形
##   =  单向平台（可从下方跳上来）
##   .  空
##   P  玩家出生点（default 入口）
##   B  长凳
##   1  巡逻怪
##   2  静止怪
##   E  关卡出口（向右）
##   X  尖刺（危险区）

const SOLID_TILE := Vector2i(0, 0)
const SOLID_ALT_TILE := Vector2i(1, 0)
const ONEWAY_TILE := Vector2i(2, 0)

## 测试关地图。主角 2x4 格，所以纵向尺度整体放大：
## 平台落差按 4~6 格排（约 1~1.5 个身位），通道净空至少 5 格。
## 从左到右依次是：出生区 → 跳跃验证 → 二段跳验证 → 冲刺验证 →
##                 战斗验证 → 长凳 → 尖刺 → 高台（滑翔验证）
const MAP := [
	"..............................................................",
	"..............................................................",
	"..............................................................",
	"..............................................................",
	"..............................................................",
	".........................................................####.",
	"..............................................................",
	"..............................................................",
	"...........................................=====..............",
	"..............................................................",
	"..............................................................",
	".....................................===......................",
	"..............................................................",
	"..............................................................",
	"...............=====..........................................",
	"..............................................................",
	"..............................................................",
	"..................................1...........................",
	"..........1.................................2.........B.......",
	"...P.....####........####...####....####...####...#########...",
	"..#####..####........####...####....####...####...#########...",
	"..#####..####........####...####....####...####...#########...",
	"..#####..............................................XXX......",
	"..#####..............................................###......",
]

## 每格的像素大小，与 GameConfig.TILE_SIZE 一致。
var _tile: int = GameConfig.TILE_SIZE


func build(level: Level) -> void:
	var ts := _load_tileset()
	if ts == null:
		push_error("找不到 TileSet，请先运行 GeneratePlaceholderAssets.gd 生成占位资源")
		return

	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = ts
	level.add_child(ground)
	ground.owner = level

	var platforms := TileMapLayer.new()
	platforms.name = "Platforms"
	platforms.tile_set = ts
	level.add_child(platforms)
	platforms.owner = level

	for y in MAP.size():
		var row: String = MAP[y]
		for x in row.length():
			var c := row[x]
			var cell := Vector2i(x, y)
			match c:
				"#":
					ground.set_cell(cell, 0, SOLID_TILE)
				"=":
					platforms.set_cell(cell, 0, ONEWAY_TILE)
				"P":
					_spawn_entry(level, cell, &"default", true)
				"B":
					_spawn_bench(level, cell)
				"1":
					_spawn_enemy(level, cell, "res://data/enemies/wanderer.tres",
						"res://data/enemies/behavior_patrol.tres")
				"2":
					_spawn_enemy(level, cell, "res://data/enemies/sentinel.tres",
						"res://data/enemies/behavior_stationary.tres")
				"X":
					_spawn_hazard(level, cell)


func _load_tileset() -> TileSet:
	var path := "res://assets/placeholder/tileset.tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as TileSet


func _cell_to_world(cell: Vector2i) -> Vector2:
	# 返回格子中心的世界坐标。
	return Vector2(cell.x * _tile + _tile * 0.5, cell.y * _tile + _tile * 0.5)


## 返回「玩家站在这一格上时，玩家中心应该在的位置」。
##
## 约定：LevelEntry / 检查点存的都是玩家中心坐标，不是地面坐标。
## 直接用格中心的话玩家下半身会陷进地板，落地时被物理挤上来，
## 复活位置就和标记点对不上了。抬多少取决于主角身高，所以走 GameConfig 算。
func _cell_to_player_center(cell: Vector2i) -> Vector2:
	return _cell_to_world(cell) + Vector2(0, GameConfig.player_center_offset_y())


func _spawn_entry(level: Level, cell: Vector2i, id: StringName, is_default: bool) -> void:
	var e := LevelEntry.new()
	e.name = "Entry_" + String(id)
	e.entry_id = id
	e.is_default_respawn = is_default
	level.add_child(e)
	e.owner = level
	# 用 position 而非 global_position：level 此刻可能还没进场景树，
	# global_position 拿不到正确的父级变换。关卡根节点在原点，两者等价。
	e.position = _cell_to_player_center(cell)


func _spawn_bench(level: Level, cell: Vector2i) -> void:
	var packed := load("res://scenes/actors/Bench.tscn") as PackedScene
	if packed == null:
		return
	var b := packed.instantiate() as Node2D
	b.name = "Bench_%d_%d" % [cell.x, cell.y]
	level.add_child(b)
	b.owner = level
	b.position = _cell_to_world(cell)


func _spawn_enemy(level: Level, cell: Vector2i, data_path: String, behavior_path: String) -> void:
	var packed := load("res://scenes/actors/Enemy.tscn") as PackedScene
	if packed == null:
		return
	var e := packed.instantiate() as Enemy
	e.name = "Enemy_%d_%d" % [cell.x, cell.y]
	e.data = load(data_path)
	e.behavior = load(behavior_path)
	level.add_child(e)
	e.owner = level
	e.position = _cell_to_world(cell)


func _spawn_hazard(level: Level, cell: Vector2i) -> void:
	var area := Hitbox.new()
	area.name = "Hazard_%d_%d" % [cell.x, cell.y]
	area.damage = 1
	area.knockback_force = 420.0
	area.continuous = true
	area.tick_interval = 0.6
	area.active_on_ready = true

	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_tile, _tile * 0.5)
	shape.shape = rect
	shape.position = Vector2(0, _tile * 0.25)
	area.add_child(shape)

	var vis := ColorRect.new()
	vis.name = "Visual"
	vis.size = Vector2(_tile, _tile * 0.5)
	vis.position = Vector2(-_tile * 0.5, 0)
	vis.color = Color(0.72, 0.22, 0.24)
	area.add_child(vis)

	level.add_child(area)
	area.position = _cell_to_world(cell)

	# owner 必须在 add_child 之后设，且子节点也要设，
	# 否则 PackedScene.pack() 会把它们当成运行时临时节点丢弃。
	area.owner = level
	shape.owner = level
	vis.owner = level
