extends Node
## 一次性工具：生成占位美术资源和默认 TileSet。
##
## 用法：
##   1. 先生成 PNG：  Godot ... --headless --path . res://scenes/tools/GeneratePlaceholderAssets.tscn
##   2. 再导入资源：  Godot ... --headless --path . --import
##   3. 再跑一次第 1 步，此时 TileSet 会引用已导入的 tiles.png
##
## 分两趟的原因：
##   PNG 刚写到磁盘时引擎还没导入它，此刻 load() 拿不到 CompressedTexture2D。
##   如果退而求其次用 Image.load() 直接读像素造 ImageTexture，
##   纹理就会被**内嵌进 tileset.tres**，变成一坨几十 KB 的像素数组。
##   那样美术换了 tiles.png 也不生效，等于把占位图焊死在项目里。
##   所以宁可跑两趟，也要让 TileSet 走正常的 ext_resource 引用。
##
## 正式美术接入后，只需替换 tiles.png 并在 TileSet 里重新绘制碰撞，
## 所有已摆好的地图不受影响（瓦片 id 不变）。

const TILE := GameConfig.TILE_SIZE
const OUT_DIR := "res://assets/placeholder"

const WORLD_LAYER_MASK := 1

## 图集里每种瓦片的定义：名字 + 颜色
const TILE_DEFS := [
	{"name": "solid",     "color": Color(0.36, 0.33, 0.40)},  # 0 实心地形
	{"name": "solid_alt", "color": Color(0.28, 0.26, 0.32)},  # 1 实心地形（深，做层次）
	{"name": "oneway",    "color": Color(0.52, 0.46, 0.38)},  # 2 单向平台
	{"name": "hazard",    "color": Color(0.72, 0.22, 0.24)},  # 3 危险区（尖刺）
	{"name": "deco",      "color": Color(0.20, 0.19, 0.24)},  # 4 纯装饰，无碰撞
]


## 是否给每格画一圈亮边。
##
## 默认关：占位地形要的是"一眼看清地面在哪"，格子网格反而把画面切碎，
## 远看像马赛克，还会干扰对关卡体量的判断。
## 需要数格子调关卡尺寸时临时开一下，别长期开着。
@export var draw_tile_borders: bool = false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var img_path := _generate_atlas()
	_generate_tileset(img_path)
	get_tree().quit()


func _generate_atlas() -> String:
	var count := TILE_DEFS.size()
	var img := Image.create(TILE * count, TILE, false, Image.FORMAT_RGBA8)

	for i in count:
		var def: Dictionary = TILE_DEFS[i]
		var c: Color = def["color"]
		for x in TILE:
			for y in TILE:
				var col := c
				if draw_tile_borders:
					var on_edge := x == 0 or y == 0 or x == TILE - 1 or y == TILE - 1
					if on_edge:
						col = c.lightened(0.18)
				img.set_pixel(i * TILE + x, y, col)

	var path := OUT_DIR + "/tiles.png"
	img.save_png(ProjectSettings.globalize_path(path))
	print("  生成图集：", path)
	return path


func _generate_tileset(img_path: String) -> void:
	# 必须拿到「已导入」的纹理，这样存出来的 tileset.tres 才是 ext_resource 引用。
	# 拿不到就直接罢工——生成一个内嵌像素的 TileSet 比不生成更糟，
	# 因为它看起来能用，实际把占位图焊死了，换美术时毫无反应还很难查。
	if not ResourceLoader.exists(img_path):
		print("  [跳过 TileSet] tiles.png 尚未被引擎导入。")
		print("  请先运行：Godot --headless --path . --import，然后再跑一次本工具。")
		return

	var tex := load(img_path) as Texture2D
	if tex == null:
		print("  [跳过 TileSet] 加载纹理失败：", img_path)
		return

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)

	# 物理层 0：世界碰撞
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, WORLD_LAYER_MASK)
	ts.set_physics_layer_collision_mask(0, 0)

	var source := TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Vector2i(TILE, TILE)

	var full := PackedVector2Array([
		Vector2(-TILE * 0.5, -TILE * 0.5),
		Vector2(TILE * 0.5, -TILE * 0.5),
		Vector2(TILE * 0.5, TILE * 0.5),
		Vector2(-TILE * 0.5, TILE * 0.5),
	])
	# 单向平台只占上边缘一小条，玩家可以从下方穿过。
	var top_strip := PackedVector2Array([
		Vector2(-TILE * 0.5, -TILE * 0.5),
		Vector2(TILE * 0.5, -TILE * 0.5),
		Vector2(TILE * 0.5, -TILE * 0.5 + 6),
		Vector2(-TILE * 0.5, -TILE * 0.5 + 6),
	])

	# 先建 tile，再把 source 挂进 TileSet，最后才写碰撞。
	# 顺序不能变：TileData 的物理层是从所属 TileSet 继承的，
	# source 未加入 TileSet 时，tile_data 看不到物理层，写碰撞会越界报错。
	for i in TILE_DEFS.size():
		source.create_tile(Vector2i(i, 0))

	ts.add_source(source, 0)

	for i in TILE_DEFS.size():
		var coord := Vector2i(i, 0)
		var td := source.get_tile_data(coord, 0)
		var def: Dictionary = TILE_DEFS[i]
		var tname: String = def["name"]

		match tname:
			"solid", "solid_alt":
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, full)
			"oneway":
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, top_strip)
				td.set_collision_polygon_one_way(0, 0, true)
			"hazard":
				# 危险区不做地形碰撞，靠单独的 Area2D 处理伤害，
				# 否则玩家会被尖刺"挡住"而不是"受伤"。
				pass
			_:
				pass

	var out := OUT_DIR + "/tileset.tres"
	var err := ResourceSaver.save(ts, out)
	if err != OK:
		push_error("TileSet 保存失败：%d" % err)
	else:
		print("  生成 TileSet：", out)
