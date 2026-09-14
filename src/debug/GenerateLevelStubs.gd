extends Node
## 一次性工具：为 LevelRegistry 里已登记但文件缺失的关卡，生成空壳场景模板。
##
## 用法：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . res://scenes/tools/GenerateLevelStubs.tscn
##
## 为什么走场景而不是 --script：
##   --script 模式下 autoload 不加载，而 LevelExit / Level 都引用了 GameConfig，
##   脚本会编译失败，结果是生成出一堆「没挂脚本的裸节点」的假模板。
##
## 生成的模板包含：
##   Level 根节点（已填 level_id / display_name）
##   Ground / Platforms / Decor 三个 TileMapLayer（已挂占位 TileSet）
##   Entry_default 入口（同时是默认复活点）
##   Entry_from_prev / Entry_from_next 两个衔接入口
##   ExitLeft / ExitRight 两个边界切图触发器（已填好前后关卡 id）
##
## 打开场景后直接用 TileMapLayer 画地形、拖动入口和出口位置即可。
## 已存在的场景文件不会被覆盖——手绘的地形不会被这个脚本冲掉。

const TILE := GameConfig.TILE_SIZE
const TILESET_PATH := "res://assets/placeholder/tileset.tres"
const OUT_DIR := "res://scenes/levels"

## 古战场序章的关卡序列。顺序决定了左右出口互相指向谁。
const CHAIN := [
	{"id": "battlefield_01", "file": "Battlefield01", "name": "古战场·残垣"},
	{"id": "battlefield_02", "file": "Battlefield02", "name": "古战场·断桥"},
	{"id": "battlefield_03", "file": "Battlefield03", "name": "古战场·哨塔"},
	{"id": "battlefield_04", "file": "Battlefield04", "name": "古战场·关口"},
]


func _ready() -> void:
	var made := 0
	var skipped := 0
	for i in CHAIN.size():
		var path := "%s/%s.tscn" % [OUT_DIR, CHAIN[i]["file"]]
		if ResourceLoader.exists(path):
			print("  跳过（已存在）：", path)
			skipped += 1
			continue
		if _build(i, path) == OK:
			print("  生成：", path)
			made += 1
	print("[关卡模板] 新建 %d 个，跳过 %d 个。" % [made, skipped])
	get_tree().quit()


func _build(index: int, out_path: String) -> int:
	var info: Dictionary = CHAIN[index]

	var root := Level.new()
	root.name = info["file"]
	root.level_id = StringName(info["id"])
	root.display_name = info["name"]
	root.bounds_padding_tiles = 1.0

	var ts: TileSet = load(TILESET_PATH) as TileSet

	# 三层分工：碰撞地形 / 单向平台 / 纯装饰。
	# 分层是为了让"能站的"和"只是好看的"在编辑时互不干扰。
	for layer_name in ["Ground", "Platforms", "Decor"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = ts
		if layer_name == "Decor":
			# 装饰层不参与碰撞，画错也不会影响手感。
			layer.collision_enabled = false
		root.add_child(layer)
		layer.owner = root

	# 入口点。default 兼作本关默认复活点。
	# Y 坐标按「玩家中心」摆：脚底贴第 9 格的顶面。
	# 抬升量由 GameConfig 按主角身高算，改主角尺寸时这里自动跟。
	var stand_y := float(TILE * 9) + GameConfig.player_center_offset_y() - TILE * 0.5
	_add_entry(root, "Entry_default", &"default", Vector2(TILE * 3, stand_y), 1, true)
	_add_entry(root, "Entry_from_prev", &"from_prev", Vector2(TILE * 2, stand_y), 1, false)
	_add_entry(root, "Entry_from_next", &"from_next", Vector2(TILE * 40, stand_y), -1, false)

	# 边界出口。首关没有左邻、末关没有右邻，对应的出口就不生成。
	if index > 0:
		_add_exit(root, "ExitLeft", StringName(CHAIN[index - 1]["id"]), &"from_next",
			Vector2(0, TILE * 4), -1)
	if index < CHAIN.size() - 1:
		_add_exit(root, "ExitRight", StringName(CHAIN[index + 1]["id"]), &"from_prev",
			Vector2(TILE * 42, TILE * 4), 1)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		push_error("打包失败：%s（%d）" % [out_path, err])
		return err
	return ResourceSaver.save(packed, out_path)


func _add_entry(root: Level, node_name: String, id: StringName,
		pos: Vector2, facing: int, is_default: bool) -> void:
	var e := LevelEntry.new()
	e.name = node_name
	e.entry_id = id
	e.facing = facing
	e.is_default_respawn = is_default
	e.position = pos
	root.add_child(e)
	e.owner = root


func _add_exit(root: Level, node_name: String, target_level: StringName,
		target_entry: StringName, pos: Vector2, direction: int) -> void:
	var area := LevelExit.new()
	area.name = node_name
	area.target_level = target_level
	area.target_entry = target_entry
	area.direction = direction
	area.position = pos

	# LevelExit 用 @onready 取 $CollisionShape2D，节点名不能改。
	# 尺寸交给 size_tiles，在 _ready 里会覆写这里的初值。
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TILE, TILE * 12)
	shape.shape = rect
	area.add_child(shape)

	root.add_child(area)
	area.owner = root
	shape.owner = root
	# size_tiles 的 setter 会去动 _shape，必须等节点进树、@onready 生效后再设。
	area.size_tiles = Vector2(1.0, 12.0)
