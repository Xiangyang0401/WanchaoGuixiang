@tool
class_name DesignRuler
extends Node2D
## 编辑器里的关卡设计标尺 —— 一个"假主角"，外加它能跳多高、冲多远。
##
## 【只在编辑器里可见，运行时自动隐藏】
##
## 为什么不只画一个主角轮廓：
##   摆平台时你真正要回答的问题不是"主角多大"，而是
##   "这个平台他跳得上去吗"、"这个坑他冲得过去吗"、"这个洞他钻得进去吗"。
##   所以身高、跳跃高度、冲刺距离、通道净空要一起看，才有决策依据。
##
## 用法：
##   1. 打开关卡，把 scenes/tools/DesignRuler.tscn 拖进场景树
##   2. 把它拖到你要衡量的落脚点上——原点 = 主角**脚底**，不是中心
##   3. 对着标线摆平台
##   4. 不用删，运行时它自己隐藏；想临时关掉就点场景树里的眼睛图标
##
## 【为什么这些数字是 @export 而不是读 GameConfig】
##   @tool 脚本跑在编辑器进程里，而 autoload 单例（GameConfig）在编辑器里
##   不会被实例化——一访问就抛错，整段 _draw 中断，什么都画不出来。
##   这是 @tool 的经典陷阱。所以主角尺寸和瓦片大小在下面自行维护，
##   改 GameConfig 的主角尺寸后，记得把这里的宽高同步一下（Ctrl+F 全局改）。

## 瓦片边长（像素）。必须与 GameConfig.TILE_SIZE 一致，默认 32。
@export var tile_size: int = 32:
	set(v):
		tile_size = v
		if is_node_ready():
			queue_redraw()

@export_group("主角尺寸")
## 主角宽（格）。与 GameConfig.PLAYER_TILE_WIDTH 同步，默认 2。
@export var player_width_tiles: float = 2.0:
	set(v):
		player_width_tiles = v
		if is_node_ready():
			queue_redraw()

## 主角高（格）。与 GameConfig.PLAYER_TILE_HEIGHT 同步，默认 4。
@export var player_height_tiles: float = 4.0:
	set(v):
		player_height_tiles = v
		if is_node_ready():
			queue_redraw()

## 手感参数来源。留空则自动加载默认配置 data/player/default_movement.tres。
## 跳跃高度 / 冲刺距离等全部从这里实时读，调手感时标尺跟着变。
@export var profile: MovementProfile:
	set(v):
		profile = v
		if is_node_ready():
			queue_redraw()

@export_group("显示内容")
## 主角轮廓（实线框）。
@export var show_body: bool = true:
	set(v):
		show_body = v
		if is_node_ready():
			queue_redraw()

## 一段跳 / 二段跳的最高点横线。
@export var show_jump: bool = true:
	set(v):
		show_jump = v
		if is_node_ready():
			queue_redraw()

## 冲刺距离与最大跨坑距离。
@export var show_dash: bool = true:
	set(v):
		show_dash = v
		if is_node_ready():
			queue_redraw()

## 通道净空建议线（身高 + 1 格余量）。
@export var show_clearance: bool = true:
	set(v):
		show_clearance = v
		if is_node_ready():
			queue_redraw()

## 以脚底为基准的格线网格，用来数格子。
@export var show_grid: bool = true:
	set(v):
		show_grid = v
		if is_node_ready():
			queue_redraw()

## 文字标注。摆得密时可以关掉。
@export var show_labels: bool = true:
	set(v):
		show_labels = v
		if is_node_ready():
			queue_redraw()

@export_group("外观")
## 整体不透明度。压低一点免得挡住地形。
@export_range(0.1, 1.0) var opacity: float = 0.9:
	set(v):
		opacity = v
		if is_node_ready():
			queue_redraw()

## 朝向。决定冲刺距离往哪边画。
@export_enum("右:1", "左:-1") var facing: int = 1:
	set(v):
		facing = v
		if is_node_ready():
			queue_redraw()

const C_BODY := Color(0.45, 0.85, 1.0)
const C_JUMP := Color(0.55, 1.0, 0.55)
const C_JUMP2 := Color(0.35, 0.8, 0.45)
const C_DASH := Color(1.0, 0.78, 0.35)
const C_CLEAR := Color(1.0, 0.55, 0.75)
const C_GRID := Color(1.0, 1.0, 1.0, 0.16)

var _font: Font


func _ready() -> void:
	# 运行时彻底隐身。留在场景里不用删，也不会漏进正式画面。
	if not Engine.is_editor_hint():
		visible = false
		set_process(false)
		return
	z_index = 4096          # 压在地形之上，不然刷了瓦片就看不见了
	_reload_profile()
	queue_redraw()


func _reload_profile() -> void:
	if profile == null:
		var p := "res://data/player/default_movement.tres"
		if ResourceLoader.exists(p):
			profile = load(p) as MovementProfile
	if profile == null:
		# 默认配置丢了也给一组保守值，别让标尺一片空白。
		profile = MovementProfile.new()


## 格 -> 像素。只用自己维护的 tile_size，不碰 GameConfig。
func _px(v: float) -> float:
	return v * tile_size


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	_reload_profile()

	var t := float(tile_size)
	var w := _px(player_width_tiles)
	var h := _px(player_height_tiles)

	# 坐标系：原点 = 主角脚底站立点，向上为负 y。
	# 用脚底而不是中心做原点，是因为你摆标尺时对齐的是地面。
	if show_grid:
		_draw_grid(t, w, h)

	if show_body:
		_draw_body(w, h)

	if show_clearance:
		_draw_clearance(t, w, h)

	if show_jump:
		_draw_jump(t, w, h)

	if show_dash:
		_draw_dash(t, h)


# ---------------------------------------------------------------------------
# 各部分绘制
# ---------------------------------------------------------------------------

## 以脚底为基准的格线。数格子比读数字快。
func _draw_grid(t: float, w: float, h: float) -> void:
	var up := int(ceil(_px(profile.jump_height_tiles) / t)) + 3
	var half := w * 0.5
	var span := maxf(half * 3.0, t * 5.0)
	for i in range(-1, up + 1):
		var y := -i * t
		# 每 5 格加重一次，方便快速计数。
		var c := C_GRID
		if i % 5 == 0:
			c = Color(C_GRID.r, C_GRID.g, C_GRID.b, C_GRID.a * 2.2)
		draw_line(Vector2(-span, y), Vector2(span, y), c * _a(), 1.0)


func _draw_body(w: float, h: float) -> void:
	var r := Rect2(Vector2(-w * 0.5, -h), Vector2(w, h))
	draw_rect(r, C_BODY * Color(1, 1, 1, 0.14) * _a(), true)
	draw_rect(r, C_BODY * _a(), false, 2.0)

	# 头部：让"哪边是上"一眼可辨，摆竖井时有用。
	var head := minf(w, h * 0.22)
	draw_rect(Rect2(Vector2(-head * 0.5, -h), Vector2(head, head)),
		C_BODY * _a(), false, 1.5)

	# 脚底基准点，摆的时候对准地面顶边。
	draw_line(Vector2(-w * 0.7, 0), Vector2(w * 0.7, 0), C_BODY * _a(), 3.0)

	_label(Vector2(w * 0.5 + 6, -h * 0.5),
		"主角 %.1f×%.1f 格" % [player_width_tiles, player_height_tiles],
		C_BODY)


## 通道净空建议线：身高 + 1 格。
## 贴着身高画通道，主角过得去但视觉上会顶头，而且落地判定容易卡。
func _draw_clearance(t: float, w: float, h: float) -> void:
	var y := -(h + t)
	var half := w * 1.6
	_dashed(Vector2(-half, y), Vector2(half, y), C_CLEAR, 1.5, 7.0)
	_label(Vector2(half + 6, y), "通道净空建议 %.0f 格" %
		((h + t) / t), C_CLEAR)


func _draw_jump(t: float, w: float, h: float) -> void:
	var half := w * 2.4

	# 一段跳：这是"平台最高能摆多高"的硬上限。
	var j1 := _px(profile.jump_height_tiles)
	_dashed(Vector2(-half, -j1), Vector2(half, -j1), C_JUMP, 2.0, 10.0)
	_label(Vector2(half + 6, -j1), "一段跳顶 %.1f 格 (%.2f 身位)" % [
		profile.jump_height_tiles,
		profile.jump_height_tiles / maxf(player_height_tiles, 0.01)], C_JUMP)

	# 实用高度：别贴着上限摆平台，玩家要在最高点分毫不差才够得到。
	var safe := j1 * 0.8
	_dashed(Vector2(-half * 0.7, -safe), Vector2(half * 0.7, -safe),
		C_JUMP * Color(1, 1, 1, 0.55), 1.0, 6.0)
	_label(Vector2(half * 0.7 + 6, -safe), "舒适落点 %.1f 格" % (safe / t),
		C_JUMP * Color(1, 1, 1, 0.7))

	# 二段跳：从一段跳顶点再往上，是真正的纵向天花板。
	var j2 := j1 + _px(profile.double_jump_height_tiles)
	_dashed(Vector2(-half, -j2), Vector2(half, -j2), C_JUMP2, 2.0, 10.0)
	_label(Vector2(half + 6, -j2), "二段跳顶 %.1f 格  [需能力]" % (j2 / t), C_JUMP2)


func _draw_dash(t: float, h: float) -> void:
	var d := _px(profile.dash_speed_tiles) * profile.dash_duration
	var y := -h * 0.35
	var x := d * facing

	draw_line(Vector2(0, y), Vector2(x, y), C_DASH * _a(), 2.0)
	# 端点竖线，看清到底冲到哪一格。
	draw_line(Vector2(x, y - t * 0.4), Vector2(x, y + t * 0.4), C_DASH * _a(), 2.0)
	_label(Vector2(x + 8 * facing, y - 16),
		"冲刺 %.1f 格" % (d / t), C_DASH)

	# 最大跨坑：比冲刺距离收一点，留出起跳和落地的余量。
	var gap := d * 0.85
	var gy := y + t * 0.9
	_dashed(Vector2(0, gy), Vector2(gap * facing, gy),
		C_DASH * Color(1, 1, 1, 0.6), 1.5, 6.0)
	_label(Vector2(gap * facing + 8 * facing, gy - 14),
		"坑宽上限 %.1f 格" % (gap / t), C_DASH * Color(1, 1, 1, 0.75))


# ---------------------------------------------------------------------------
# 绘制工具
# ---------------------------------------------------------------------------

func _a() -> Color:
	return Color(1, 1, 1, opacity)


## Godot 没有内置虚线，手动分段。
## 用虚线区分"参考线"和"实体轮廓"，免得看花眼。
func _dashed(a: Vector2, b: Vector2, color: Color, width: float, seg: float) -> void:
	var total := a.distance_to(b)
	if total <= 0.01:
		return
	var dir := (b - a) / total
	var pos := 0.0
	var on := true
	while pos < total:
		var nxt := minf(pos + seg, total)
		if on:
			draw_line(a + dir * pos, a + dir * nxt, color * _a(), width)
		on = not on
		pos = nxt


func _label(pos: Vector2, text: String, color: Color) -> void:
	if not show_labels:
		return
	if _font == null:
		_font = ThemeDB.fallback_font
	if _font == null:
		return
	# 加一层深色描边，压在亮色瓦片上也读得清。
	for o in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		draw_string(_font, pos + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(0, 0, 0, 0.75 * opacity))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color * _a())
