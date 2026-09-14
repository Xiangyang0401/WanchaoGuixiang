@tool
class_name LevelBoundsGuide
extends Node2D
## 编辑器里的关卡边界引导 —— 回答两个问题：
##   1. 玩家跑到哪会「跑出镜头」？
##   2. 传送点 / 墙该放在哪？
##
## 【为什么需要它】
##   相机 limit 会「内收半屏」，让视野边缘（而非相机中心）恰好贴住地形边界，
##   这样长关卡两端不会露出地图外的空白。但代价是：玩家的物理活动范围
##   （整个地形）可以大于相机能跟随到的范围——相机在某个位置就停下，
##   玩家却还能继续往外跑，从而离开镜头画面。
##   于是你需要在关卡两端的「离开镜头点」附近放置传送点或墙。
##   但是「离开镜头点」到底在哪、它会随你铺的地形长度怎么变、该把传送点
##   放进去几个身位才不穿帮……这些光靠肉眼很难估，这个工具就是来画的。
##
## 【用法】
##   1. 打开关卡，把 scenes/tools/LevelBoundsGuide.tscn 拖进场景树
##      （建议放到关卡根下，或任何能看见全局的位置，不遮挡也行）
##   2. 不用配置任何东西 —— 它自动扫描本场景所有 TileMapLayer 的已用区域，
##      合并出真实地形边界，再结合相机参数画出红线。
##   3. 你铺长 / 铺短地形，红线会自动跟着变（每帧重算）。
##   4. 不用删，运行时它自己隐藏。
##
## 【怎么读这张图】
##   两个极端红区（左右各一个）= 玩家离开镜头 / 到达地形边缘的区间。
##   红线本身 = 玩家中心到达这里时，视野边缘恰好停在屏幕边缘，
##   再往外半步就完全出屏。所以：
##     → 传送点（LevelExit）放在红线**内侧**一个身位（绿色线）最稳：
##       玩家还没出屏、还没穿帮，就切到下一关。
##     → 想用「墙」封死也可以，墙放在红线内侧即可。
##   中间的「相机中心可移动范围」虚线，是给你理解镜头为什么会停用的参考。

## 瓦片边长（像素）。必须与 GameConfig.TILE_SIZE 一致，默认 32。
## 不直接读 GameConfig：autoload 单例在编辑器里不会实例化，
## @tool 一访问就抛错（DesignRuler 同款坑）。
@export var tile_size: int = 32:
	set(v):
		tile_size = v
		if is_node_ready():
			queue_redraw()

## 相机缩放。必须与 GameConfig.camera_zoom 一致，默认 0.8。
@export var camera_zoom: float = 0.8:
	set(v):
		camera_zoom = v
		if is_node_ready():
			queue_redraw()

## 逻辑视口尺寸。必须与 GameConfig.VIEWPORT_WIDTH/HEIGHT 一致。
@export var viewport: Vector2 = Vector2(1920, 1080):
	set(v):
		viewport = v
		if is_node_ready():
			queue_redraw()

## 关卡边界外扩余量（格）。与关卡根节点的 bounds_padding_tiles 一致。
## 这个值来自 Level 节点，不是本工具的，所以留给你手动对齐。
@export var padding_tiles: float = 1.0:
	set(v):
		padding_tiles = v
		if is_node_ready():
			queue_redraw()

@export_group("显示内容")
@export var show_edges: bool = true:
	set(v):
		show_edges = v
		if is_node_ready():
			queue_redraw()
@export var show_camera_range: bool = true:
	set(v):
		show_camera_range = v
		if is_node_ready():
			queue_redraw()
@export var show_labels: bool = true:
	set(v):
		show_labels = v
		if is_node_ready():
			queue_redraw()

## 离开镜头的红区半宽（像素）。视野边缘之外往里收这段算「警戒区」。
const EDGE_ZONE: float = 48.0
## 建议放传送点/墙的内收距离（格）。一个身位（玩家宽 2 格）→ 一半。
const TRANSFER_INSET_TILES: float = 1.0

const C_OUTSIDE := Color(1.0, 0.35, 0.3)         ## 红 —— 玩家会离开镜头
const C_CAMERA := Color(0.55, 0.8, 1.0, 0.9)     ## 蓝 —— 镜头中心可移动范围
const C_LABEL := Color(1.0, 0.95, 0.85)
const C_FONT_BG := Color(0, 0, 0, 0.8)

var _font: Font
var _bounds: Rect2 = Rect2()
var _valid: bool = false
## 一屏可视世界尺寸（像素），由 viewport / zoom 算出。
var _view: Vector2 = Vector2.ZERO


func _ready() -> void:
	if not Engine.is_editor_hint():
		visible = false
		set_process(false)
		return
	z_index = 4095           # 略低于 DesignRuler(4096)，别盖住它的文字
	set_process(true)        # 每帧重算，地形铺完立刻反映


func _process(_delta: float) -> void:
	# 编辑器里每帧重算边界 + 重绘，确保「改地形后红线自动跟着变」。
	_recalculate()
	queue_redraw()


func _recalculate() -> void:
	_view = viewport / maxf(camera_zoom, 0.01)

	var edges := _scene_bounds()
	if edges.size == Vector2.ZERO:
		_bounds = Rect2()
		_valid = false
		return
	_bounds = edges.grow(tile_size * padding_tiles)
	_valid = _bounds.size.x > 0.0


## 扫描当前编辑场景里所有 TileMapLayer 的已用区域（与 Level._auto_bounds 同逻辑），
## 再合并成世界坐标下的 Rect2。
func _scene_bounds() -> Rect2:
	var root := get_tree().edited_scene_root
	if root == null:
		return Rect2()
	return _merge_tile_layers(root)


func _merge_tile_layers(node: Node) -> Rect2:
	var result := Rect2()
	var found := false
	for child in node.get_children():
		var layer := child as TileMapLayer
		if layer != null:
			var used := layer.get_used_rect()
			if used.size != Vector2i.ZERO:
				var cell := layer.tile_set.tile_size if layer.tile_set != null else Vector2i(tile_size, tile_size)
				var r := Rect2(Vector2(used.position * cell), Vector2(used.size * cell))
				r.position = layer.to_global(r.position)
				r.size *= layer.global_scale
				if not found:
					result = r
					found = true
				else:
					result = result.merge(r)
		# 递归合并子节点里可能存在的 TileMapLayer（嵌套层次不安全，但保险）。
		var sub := _merge_tile_layers(child)
		if sub.size != Vector2.ZERO:
			if not found:
				result = sub
				found = true
			else:
				result = result.merge(sub)
	return result


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if not _valid:
		# 找不到任何 TileMapLayer 时给一个提示，别静默。
		_draw_message("未找到 TileMapLayer，无法计算边界", Color(1, 0.6, 0.2))
		return

	# 本工具的原点设为关卡边界左上角，画起来从 0 坐标出发更直观。
	# 注意：工具节点本身放在关卡根下，位置通常是 (0,0)，所以这里用世界坐标。
	var x0 := _bounds.position.x
	var x1 := _bounds.end.x

	if show_camera_range:
		_draw_camera_range()

	if show_edges:
		_draw_edges(x0, x1)

	if show_labels:
		_draw_labels(x0, x1)


## 画左右两个「离开镜头」红区 + 建议传送点绿线。
func _draw_edges(x0: float, x1: float) -> void:
	var inset := tile_size * TRANSFER_INSET_TILES

	# 红线画在**地形边界本体**（x0 / x1），这才是「玩家中心到达即出屏」的位置。
	# 红区从边界往屏幕内延伸 EDGE_ZONE，作为「靠近边界就容易出屏」的视觉警戒带。
	_draw_side_edge(x0, x0 + EDGE_ZONE)     # 左边界 -> 往屏幕内(x 增大方向)收
	_draw_side_edge(x1 - EDGE_ZONE, x1)     # 右边界 -> 往屏幕内(x 减小方向)收

	# 建议放传送点/墙的两条绿虚线（边界内侧一个身位）：放这里玩家还没出屏就切图。
	_dashed(Vector2(x0 + inset, -_view.y * 0.6), Vector2(x0 + inset, _view.y * 0.6),
		Color(0.45, 1.0, 0.55), 2.5, 8.0)
	_dashed(Vector2(x1 - inset, -_view.y * 0.6), Vector2(x1 - inset, _view.y * 0.6),
		Color(0.45, 1.0, 0.55), 2.5, 8.0)


## 画一条边界线 + 朝屏幕内侧的警戒红区（[za, zb] 是警戒带横坐标，za<zb）。
func _draw_side_edge(x_edge: float, zx: float) -> void:
	var top := -_view.y * 0.6
	var bottom := _view.y * 0.6
	# 警戒红区（半透明填充）：从 x_edge 往屏幕内侧延伸到 zx。
	var rect := Rect2(Vector2(minf(x_edge, zx), top), Vector2(absf(zx - x_edge), bottom - top))
	draw_rect(rect, Color(C_OUTSIDE.r, C_OUTSIDE.g, C_OUTSIDE.b, 0.14), true)

	# 红线（边界本体）画在 x_edge 上。
	draw_line(Vector2(x_edge, top), Vector2(x_edge, bottom), Color(C_OUTSIDE.r, C_OUTSIDE.g, C_OUTSIDE.b, 0.95), 3.0)


## 画相机中心可移动范围（长关卡才有意义）。
func _draw_camera_range() -> void:
	if _bounds.size.x <= _view.x:
		# 短关卡：整个地形都能装进一屏，相机不会停，画不出来也无妨。
		return

	var clamp_left := _bounds.position.x + _view.x * 0.5
	var clamp_right := _bounds.end.x - _view.x * 0.5
	var top := -_view.y * 0.55
	var bottom := _view.y * 0.55

	# 相机中心可移动范围：两条蓝色竖线
	draw_line(Vector2(clamp_left, top), Vector2(clamp_left, bottom),
		Color(C_CAMERA.r, C_CAMERA.g, C_CAMERA.b, 0.55), 1.5)
	draw_line(Vector2(clamp_right, top), Vector2(clamp_right, bottom),
		Color(C_CAMERA.r, C_CAMERA.g, C_CAMERA.b, 0.55), 1.5)


func _draw_labels(x0: float, x1: float) -> void:
	var inset := tile_size * TRANSFER_INSET_TILES
	var top := -_view.y * 0.62

	_label(Vector2(x0 + inset, top), "左传送点建议位置", Color(0.45, 1.0, 0.55))
	_label(Vector2(x1 - inset - 180, top), "右传送点建议位置", Color(0.45, 1.0, 0.55))

	# 顶部中央说明关卡与屏幕比例
	var wide_tiles := _bounds.size.x / tile_size
	var screen_tiles := _view.x / tile_size
	_label(Vector2((x0 + x1) * 0.5 - 220, top),
		"关卡宽 %.0f 格  相机一屏 %.0f 格  %s" % [
			wide_tiles, screen_tiles,
			"玩家会跑出镜头" if wide_tiles > screen_tiles else "整关都能进镜头"],
		C_LABEL)


func _draw_message(text: String, color: Color) -> void:
	_label(Vector2(-300, -150), text, color)


# ---------------------------------------------------------------------------
# 绘制工具
# ---------------------------------------------------------------------------

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
			draw_line(a + dir * pos, a + dir * nxt, color, width)
		on = not on
		pos = nxt


func _label(pos: Vector2, text: String, color: Color) -> void:
	if not show_labels:
		return
	if _font == null:
		_font = ThemeDB.fallback_font
	if _font == null:
		return
	for o in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		draw_string(_font, pos + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(C_FONT_BG.r, C_FONT_BG.g, C_FONT_BG.b, 0.85))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)
