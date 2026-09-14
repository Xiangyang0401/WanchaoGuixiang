extends SceneTree
## 一次性工具：生成关卡模板 TemplateLevel.tscn。
##
## 解决的问题：新关卡没有参照点——基准地面在哪一行、入口出口放哪个坐标，
## 每张图都靠肉眼猜。模板把这些约定固化成场景，新关卡复制它开工。
##
## 约定（以 Battlefield01 为基准）：
##   - 主地面顶面 = 第 9 行（y=288px），模板预铺一行，画完可擦
##   - Entry_default   = (96, 224)   默认入口/复活点
##   - Entry_from_prev = (64, 224)   从上一关进来的落点
##   - Entry_from_next = (1280, 224) 从下一关进来的落点
##   - ExitLeft / ExitRight 摆好并锁定子节点，改 target_level 即用
##   - 预置 LevelBoundsGuide（红线）+ DesignRuler（假主角标尺）+ Background（未配图）
##
## 用法：Godot --headless --path . --script res://src/tools/BuildLevelTemplate.gd

const OUT := "res://scenes/levels/TemplateLevel.tscn"

## 基准地面行（01 主地面顶面所在行）
const GROUND_ROW := 9
## 模板预铺地面的格数（约 42 屏内可见，画多了自己擦）
const GROUND_COLS := 40


func _initialize() -> void:
	var level := Node2D.new()
	level.name = "TemplateLevel"
	level.set_script(load("res://src/world/Level.gd"))
	level.set("level_id", &"template")
	level.set("display_name", "关卡模板（复制我开工）")
	level.set("bounds_padding_tiles", 1.0)
	var hints: Array[String] = [
		"移动：{action:move_left} {action:move_right}",
		"跳跃：{action:jump}",
	]
	level.set("tutorial_hints", hints)

	# --- 地形层 ---
	var tileset: TileSet = load("res://assets/placeholder/tileset.tres")
	for layer_name in ["Ground", "Platforms", "Decor"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = tileset
		if layer_name == "Decor":
			layer.collision_enabled = false
		level.add_child(layer)
		layer.owner = level

	# 基准地面：第 9 行铺一行 solid（tile 0），作为全关卡的公共地平线参照。
	var ground := level.get_node("Ground") as TileMapLayer
	for x in GROUND_COLS:
		ground.set_cell(Vector2i(x, GROUND_ROW), 0, Vector2i(0, 0))

	# --- 标准点位 ---
	for cfg in [
		["Entry_default", Vector2(96, 224), "default", 1, false],
		["Entry_from_prev", Vector2(64, 224), "from_prev", 1, false],
		["Entry_from_next", Vector2(1280, 224), "from_next", 1, false],
	]:
		var entry := Marker2D.new()
		entry.name = cfg[0]
		entry.position = cfg[1]
		entry.set_script(load("res://src/world/LevelEntry.gd"))
		entry.set("entry_id", StringName(cfg[2]))
		entry.set("facing", cfg[3])
		level.add_child(entry)
		entry.owner = level

	# 默认入口兼复活点
	(level.get_node("Entry_default") as LevelEntry).is_default_respawn = true

	# --- 出口（左右各一，target_level 留空显示红色警告，新关卡自己配）---
	var exit_left := _make_exit("ExitLeft", Vector2(32, 128), Vector2(1.0, 12.0), &"", -1)
	level.add_child(exit_left)
	exit_left.owner = level
	# pack 只保存 owner 挂在场景根上的节点，shape 的 owner 必须指向场景根
	(exit_left.get_node("CollisionShape2D") as Node).owner = level
	var exit_right := _make_exit("ExitRight", Vector2(1280, 128), Vector2(1.0, 12.0), &"", 1)
	level.add_child(exit_right)
	exit_right.owner = level
	(exit_right.get_node("CollisionShape2D") as Node).owner = level

	# --- 背景占位（texture 留空，Inspector 里拖图即用）---
	var bg := (load("res://scenes/world/LevelBackground.tscn") as PackedScene).instantiate()
	bg.name = "Background"
	level.add_child(bg)
	bg.owner = level

	# --- 设计辅助工具（编辑器可见，运行时自隐藏）---
	var guide := (load("res://scenes/tools/LevelBoundsGuide.tscn") as PackedScene).instantiate()
	guide.name = "LevelBoundsGuide"
	guide.position = Vector2(0, 0)
	level.add_child(guide)
	guide.owner = level

	var ruler := (load("res://scenes/tools/DesignRuler.tscn") as PackedScene).instantiate()
	ruler.name = "DesignRuler"
	ruler.position = Vector2(160, 288)  # 站在基准地面上：第 9 行顶面 y=288
	ruler.set("profile", load("res://data/player/default_movement.tres"))
	level.add_child(ruler)
	ruler.owner = level

	var ps := PackedScene.new()
	ps.pack(level)
	var err := ResourceSaver.save(ps, OUT)
	print("模板保存 err=", err, " → ", OUT)
	quit(0)


func _make_exit(exit_name: String, pos: Vector2, size: Vector2, target: StringName, dir: int) -> Area2D:
	var exit_node := Area2D.new()
	exit_node.name = exit_name
	exit_node.position = pos
	exit_node.set_script(load("res://src/world/LevelExit.gd"))
	exit_node.set("size_tiles", size)
	exit_node.set("target_level", target)
	exit_node.set("direction", dir)

	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	shape.shape = RectangleShape2D.new()
	exit_node.add_child(shape)
	# 触发区从地面往上盖：shape 中心放在 x=0、y 相对出口原点上移半高
	shape.position = Vector2(0, -size.y * 32 * 0.5 + 6 * 32)
	shape.owner = exit_node
	return exit_node
