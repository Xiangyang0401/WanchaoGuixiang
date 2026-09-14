extends Node
## 一次性工具：生成古战场教学区五张关卡（00/02/03/04/05）。
##
## 为什么用代码生成而不是手画：
##   教学区的缺口宽度、平台落差、高台高度都必须精确贴合玩家能力
##   （一段跳 6.4 格 / 冲刺 7 格 / 二段跳合计 11.6 格），手画容易失之毫厘。
##   代码生成保证数值一致，调整手感参数后可整体重生成；生成后在编辑器里仍可手调。
##
## 为什么做成场景而不是 --script：
##   --script 模式下 autoload 不加载，Level.gd 的依赖链（LevelManager → GameState）
##   解析失败，set_script 会悄悄挂上一个空脚本，生成出没挂脚本的裸关卡。
##   场景方式运行（见下）autoload 齐全，一切正常。
##
## Battlefield01（残垣）是手画的（含 NPC 与既有地形），本工具不碰它。
##
## 地形约定（与 docs/level_conventions.md 一致）：
##   主地面顶面 = 第 9 行，实心往下填到第 17 行，缺口/深渊区域完全无瓦片（无底），
##   左端一堵 12 格高的墙（跳不过去）防止走出左边界。
##
## 难度标定（格）：
##   同层缺口 4 格     —— 一段跳轻松越过（图02）
##   同层缺口 8 格     —— 一段跳只有 7 格跳距，必须跳跃+空中冲刺（图03/05）
##   高台 7 格         —— 一段跳 6.4 格够不着，必须二段跳（图04/05）
##   台阶 1 格         —— 直接跳/走上
##
## 用法：
##   GODOT="/e/Godot/Godot_v4.6.1-stable_win64_console.exe"
##   "$GODOT" --headless --path . res://scenes/tools/GenerateTutorialLevels.tscn
##   生成后跑 SelfTest.tscn 验证出口链。

const OUT_DIR := "res://scenes/levels/"

const TILE := 32
const ROW_GROUND := 9    ## 主地面顶面所在行（顶面 y=288）
const ROW_BOTTOM := 17   ## 实心地形填到的最后一行
const SRC := 0           ## tileset 的 source id

const SOLID := Vector2i(0, 0)
const SOLID_ALT := Vector2i(1, 0)
const ONEWAY := Vector2i(2, 0)

var _ab: Script          ## Abilities.gd，取教学阶段枚举值用（避免硬编码数字）


func _ready() -> void:
	_ab = load("res://src/core/ability/Abilities.gd")
	_build_bf00()
	_build_bf02()
	_build_bf03()
	_build_bf04()
	_build_bf05()
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# 图00 · 苏醒 —— 初始区域：纯平地，只能移动（无跳跃能力）
# ---------------------------------------------------------------------------

func _build_bf00() -> void:
	var d := _build_level(&"battlefield_00", "古战场·苏醒", 30,
		["移动：{action:move_left} {action:move_right}"],
		_ab.Stage.TUTORIAL_AWAKE)
	var g: TileMapLayer = d.ground
	_fill(g, 0, 29, ROW_GROUND)          # 全程平地
	_fill(g, 0, 0, 1)                    # 左墙
	_add_text(d.root, Vector2(480, 150), "{action:move_left} {action:move_right}  移动", 44)
	_add_text(d.root, Vector2(832, 150), "往前走", 36)
	_add_exit(d.root, "ExitRight", 960, &"battlefield_01", &"from_prev", 1)
	_save(d.root, "Battlefield00.tscn")


# ---------------------------------------------------------------------------
# 图02 · 断桥 —— 跳跃教学：起伏 + 平台，平台下方是空的（坠落扣血）
# ---------------------------------------------------------------------------

func _build_bf02() -> void:
	var d := _build_level(&"battlefield_02", "古战场·断桥", 56,
		["跳跃：{action:jump}"], _ab.Stage.TUTORIAL_JUMP)
	var g: TileMapLayer = d.ground
	var p: TileMapLayer = d.platforms

	_fill(g, 0, 9, ROW_GROUND)           # A 起始平地
	# 缺口 10~13（4 格，同层一段跳）—— 无底深渊
	_fill(g, 14, 21, ROW_GROUND)         # B 平地
	_fill(g, 22, 22, 8)                  # 台阶 +1
	_fill(g, 23, 28, 7)                  # C 高台（顶面第 7 行，比主地面高 2 格）
	# 缺口 29~32（4 格，从高台同层跳）—— 无底深渊
	_fill(g, 33, 38, 7)                  # D 高台延续
	_fill(g, 39, 46, ROW_GROUND)         # E 主地面（从高台走下）
	_fill(g, 47, 55, ROW_GROUND)         # F 终点平地
	_fill(g, 0, 0, 1)                    # 左墙

	_oneway(p, 40, 42, 6)                # 单向平台：离地 3 格，一段跳可上
	_oneway(p, 44, 46, 4)                # 单向平台：离地 5 格，一段跳可上

	_add_text(d.root, Vector2(288, 150), "按 {action:jump} 跳过缺口", 40)
	_add_text(d.root, Vector2(1344, 64), "单向平台：从下方可以跳穿上去", 32)
	_add_text(d.root, Vector2(1632, 150), "小心深渊", 32)

	_add_exit(d.root, "ExitLeft", 32, &"battlefield_01", &"from_next", -1)
	_add_exit(d.root, "ExitRight", 1792, &"battlefield_03", &"from_prev", 1)
	_save(d.root, "Battlefield02.tscn")


# ---------------------------------------------------------------------------
# 图03 · 哨塔 —— 冲刺教学：8 格缺口必须跳跃 + 空中冲刺
# ---------------------------------------------------------------------------

func _build_bf03() -> void:
	var d := _build_level(&"battlefield_03", "古战场·哨塔", 60,
		["冲刺：{action:dash}（跳跃中可用）"], _ab.Stage.TUTORIAL_DASH)
	var g: TileMapLayer = d.ground

	_fill(g, 0, 9, ROW_GROUND)           # A 起始平地
	# 缺口 10~17（8 格，一段跳距 7 格不够）—— 无底深渊
	_fill(g, 18, 25, ROW_GROUND)         # B 平地
	_fill(g, 26, 26, 8)                  # 台阶 +1
	_fill(g, 27, 27, 7)                  # 台阶 +1
	_fill(g, 28, 33, 6)                  # C 高台（顶面第 6 行）
	# 缺口 34~41（8 格，从高台同层跳+冲）—— 无底深渊
	_fill(g, 42, 49, 6)                  # D 高台延续
	_fill(g, 50, 59, ROW_GROUND)         # E 主地面（落差 3 格走下）
	_fill(g, 0, 0, 1)                    # 左墙

	_add_text(d.root, Vector2(224, 150), "{action:dash} 冲刺", 40)
	_add_text(d.root, Vector2(448, 96), "跳起后再按 {action:dash}，冲过缺口", 36)
	_add_text(d.root, Vector2(1472, 96), "空中冲刺也能用", 32)

	_add_exit(d.root, "ExitLeft", 32, &"battlefield_02", &"from_next", -1)
	_add_exit(d.root, "ExitRight", 1920, &"battlefield_04", &"from_prev", 1)
	_save(d.root, "Battlefield03.tscn")


# ---------------------------------------------------------------------------
# 图04 · 关口 —— 敌人教学：锋锐切割 1 刀击杀巡逻敌人 + 二段跳制高台
# ---------------------------------------------------------------------------

func _build_bf04() -> void:
	var d := _build_level(&"battlefield_04", "古战场·关口", 60,
		["攻击：{action:attack}　　二段跳：空中再按 {action:jump}"],
		_ab.Stage.YOUNG)
	var g: TileMapLayer = d.ground

	_fill(g, 0, 9, ROW_GROUND)           # A 起始平地
	_fill(g, 10, 11, 8)                  # 上坡台阶 +1
	_fill(g, 12, 33, 7)                  # B 战斗区（顶面第 7 行）
	# 缺口 34~36（3 格，一段跳）
	_fill(g, 37, 43, 7)                  # C 平地
	_fill(g, 44, 45, 8)                  # 下坡台阶
	_fill(g, 46, 59, ROW_GROUND)         # D 主地面
	_fill(g, 49, 52, 2)                  # 二段跳制高台（比地面高 7 格，一段跳 6.4 上不去）
	_fill(g, 0, 0, 1)                    # 左墙

	_add_enemy(d.root, Vector2(688, 200))    # 巡逻敌人（top7 层，中心 = 顶面 - 1.5格/2）
	_add_enemy(d.root, Vector2(912, 200))

	_add_text(d.root, Vector2(160, 150), "{action:attack} 锋锐切割：挥砍敌人", 40)
	_add_text(d.root, Vector2(1456, 150), "空中再按一次 {action:jump}：二段跳", 36)

	_add_exit(d.root, "ExitLeft", 32, &"battlefield_03", &"from_next", -1)
	_add_exit(d.root, "ExitRight", 1920, &"battlefield_05", &"from_prev", 1)
	_save(d.root, "Battlefield04.tscn")


# ---------------------------------------------------------------------------
# 图05 · 归途 —— 综合运用：缺口+冲刺、高台+二段跳、敌人、末端长凳
# ---------------------------------------------------------------------------

func _build_bf05() -> void:
	var d := _build_level(&"battlefield_05", "古战场·归途", 80,
		[], -1)                          # 全能力，本关不再切阶段
	var g: TileMapLayer = d.ground
	var p: TileMapLayer = d.platforms

	_fill(g, 0, 9, ROW_GROUND)           # A 起始平地
	# 缺口 10~17（8 格：跳+冲刺）—— 无底深渊
	_fill(g, 18, 24, ROW_GROUND)         # B 平地 + 敌人
	_fill(g, 25, 25, 8)                  # 台阶 +1
	_fill(g, 26, 31, 7)                  # C 高台 + 敌人
	# 缺口 32~39（8 格：高台同层跳+冲刺）—— 无底深渊
	_fill(g, 40, 45, 7)                  # D 高台延续
	_fill(g, 46, 46, 8)                  # 下台阶
	_fill(g, 47, 58, ROW_GROUND)         # E 主地面 + 敌人
	_oneway(p, 50, 52, 5)                # 单向平台（离地 4 格）
	_oneway(p, 54, 56, 2)                # 单向平台（离地 7 格，需二段跳路线）
	_fill(g, 57, 62, 1, 2, SOLID_ALT)    # 高空悬板（薄板，下方空）
	_fill(g, 63, 77, ROW_GROUND)         # G 终点平地
	_fill(g, 0, 0, 1)                    # 左墙
	_fill(g, 78, 79, 1)                  # 右端封墙（本区终点）

	_add_enemy(d.root, Vector2(688, 264))    # B 区（主地面层）
	_add_enemy(d.root, Vector2(944, 200))    # C 区（top7 层）
	_add_enemy(d.root, Vector2(1664, 264))   # E 区（主地面层）
	_add_bench(d.root, Vector2(2240, 288), &"bench_bf05_end")

	_add_text(d.root, Vector2(160, 150), "把学到的一切用上", 40)
	_add_text(d.root, Vector2(2240, 128), "长凳：按 {action:interact} 休息", 32)
	_add_text(d.root, Vector2(2384, 96), "序章·完（前方待开放）", 36)

	_add_exit(d.root, "ExitLeft", 32, &"battlefield_04", &"from_next", -1)
	_save(d.root, "Battlefield05.tscn")


# ---------------------------------------------------------------------------
# 构建辅助
# ---------------------------------------------------------------------------

func _build_level(id: StringName, display: String, width_tiles: int,
		hints: Array, stage: int) -> Dictionary:
	var level := Node2D.new()
	level.name = String(id).capitalize().replace(" ", "")
	level.set_script(load("res://src/world/Level.gd"))
	level.set("level_id", id)
	level.set("display_name", display)
	level.set("bounds_padding_tiles", 1.0)
	var typed: Array[String] = []
	for h in hints:
		typed.append(h)
	level.set("tutorial_hints", typed)
	if stage >= 0:
		level.set("stage_on_enter", stage)

	var tileset: TileSet = load("res://assets/placeholder/tileset.tres")
	for lname in ["Ground", "Platforms", "Decor"]:
		var layer := TileMapLayer.new()
		layer.name = lname
		layer.tile_set = tileset
		if lname == "Decor":
			layer.collision_enabled = false
		level.add_child(layer)
		layer.owner = level

	# 标准点位（约定见 docs/level_conventions.md）。
	# 注意：入口落点必须离对侧出口触发区 ≥3 格，否则玩家被传送到落点的瞬间
	# 身体（宽 2 格）就压进出口触发区，两关之间会无限来回切图（闪屏）。
	_add_entry(level, "Entry_default", Vector2(96, 224), &"default", 1, true)
	_add_entry(level, "Entry_from_prev", Vector2(128, 224), &"from_prev", 1, false)
	_add_entry(level, "Entry_from_next", Vector2(width_tiles * TILE - 128, 224), &"from_next", -1, false)

	# 背景（fill=LEVEL 模式自动铺满，只换 texture 不调坐标）
	var bg := (load("res://scenes/world/LevelBackground.tscn") as PackedScene).instantiate()
	bg.name = "Background"
	bg.set("texture", load("res://assets/backgrounds/background-test.png"))
	level.add_child(bg)
	bg.owner = level

	# 编辑器辅助（运行时自隐藏）
	var guide := (load("res://scenes/tools/LevelBoundsGuide.tscn") as PackedScene).instantiate()
	guide.name = "LevelBoundsGuide"
	level.add_child(guide)
	guide.owner = level

	var ruler := (load("res://scenes/tools/DesignRuler.tscn") as PackedScene).instantiate()
	ruler.name = "DesignRuler"
	ruler.position = Vector2(160, ROW_GROUND * TILE)
	ruler.set("profile", load("res://data/player/default_movement.tres"))
	level.add_child(ruler)
	ruler.owner = level

	return {
		"root": level,
		"ground": level.get_node("Ground"),
		"platforms": level.get_node("Platforms"),
	}


func _add_entry(level: Node2D, node_name: String, pos: Vector2,
		entry_id: StringName, facing: int, is_default: bool) -> void:
	var e := Marker2D.new()
	e.name = node_name
	e.position = pos
	e.set_script(load("res://src/world/LevelEntry.gd"))
	e.set("entry_id", entry_id)
	e.set("facing", facing)
	e.set("is_default_respawn", is_default)
	level.add_child(e)
	e.owner = level


func _add_exit(level: Node2D, exit_name: String, x: float,
		target: StringName, entry: StringName, dir: int) -> void:
	var e := Area2D.new()
	e.name = exit_name
	e.position = Vector2(x, 128)
	e.set_script(load("res://src/world/LevelExit.gd"))
	e.set("target_level", target)
	e.set("target_entry", entry)
	e.set("size_tiles", Vector2(1.0, 12.0))
	e.set("direction", dir)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	shape.shape = RectangleShape2D.new()
	e.add_child(shape)
	level.add_child(e)
	e.owner = level
	shape.owner = level


## 实心填充：顶面一行 solid，往下 solid_alt 做层次。
func _fill(g: TileMapLayer, x0: int, x1: int, top: int,
		bottom: int = ROW_BOTTOM, tile: Vector2i = SOLID) -> void:
	for x in range(x0, x1 + 1):
		g.set_cell(Vector2i(x, top), SRC, tile)
		for y in range(top + 1, bottom + 1):
			g.set_cell(Vector2i(x, y), SRC, SOLID_ALT)


func _oneway(p: TileMapLayer, x0: int, x1: int, row: int) -> void:
	for x in range(x0, x1 + 1):
		p.set_cell(Vector2i(x, row), SRC, ONEWAY)


func _add_text(level: Node2D, pos: Vector2, text: String, font_size: int = 36) -> void:
	var t := (load("res://scenes/tools/WorldText.tscn") as PackedScene).instantiate()
	t.name = "Note%d" % (level.get_child_count() + 1)
	t.set("text", text)
	t.set("font_size", font_size)
	t.set("show_background", true)
	t.position = pos
	level.add_child(t)
	t.owner = level


## 敌人位置 = 身体中心（Enemy 原点在碰撞体中心）。
func _add_enemy(level: Node2D, pos: Vector2) -> void:
	var e := (load("res://scenes/actors/Enemy.tscn") as PackedScene).instantiate()
	e.name = "Enemy%d" % (level.get_child_count() + 1)
	e.set("data", load("res://data/enemies/wanderer.tres"))
	e.set("behavior", load("res://data/enemies/behavior_patrol.tres"))
	e.position = pos
	level.add_child(e)
	e.owner = level


## 长凳原点 = 脚底（贴地面顶面）。
func _add_bench(level: Node2D, pos: Vector2, checkpoint_id: StringName) -> void:
	var b := (load("res://scenes/actors/Bench.tscn") as PackedScene).instantiate()
	b.name = "Bench_end"
	b.set("checkpoint_id", checkpoint_id)
	b.position = pos
	level.add_child(b)
	b.owner = level


func _save(level: Node2D, filename: String) -> void:
	var ps := PackedScene.new()
	ps.pack(level)
	var err := ResourceSaver.save(ps, OUT_DIR + filename)
	print("生成 %s err=%d" % [filename, err])
