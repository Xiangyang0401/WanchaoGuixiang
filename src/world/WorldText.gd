@tool
class_name WorldText
extends Node2D
## 世界里的文字 —— 像背景组件一样摆在关卡里，随镜头滚动。
##
## 和 HUD 提示条的区别：
##   TutorialHints 是屏幕 UI，永远钉在画面某个角落，跟镜头无关；
##   WorldText 是关卡场景的一部分，写在哪就出现在哪——挂在出生点的
##   天空/墙上，玩家走过去抬头就能看到，镜头移开字就离开画面。
##   适合把教学文字"烙进"场景里，做路牌、墙面刻字、地面指引。
##
## 用法：
##   1. 把 scenes/tools/WorldText.tscn 拖进关卡（建议挂在 Decor 附近）
##   2. 填 text，调 font_size / font_color，摆到想出现的位置
##   3. 场景树里上下拖动可调"字在地形前还是后"；想旋转就调节点 Rotation
##
## 原点 = 文字中心（摆位直观）。@tool，编辑器里所见即所得。

@export_multiline var text: String = "提示文字":
	set(v):
		text = v
		if is_node_ready():
			queue_redraw()

## 把 {action:名字} 占位符替换成玩家当前键名（复用 InputHints）。
## 例："移动：{action:move_left} / {action:move_right}"。
@export var parse_actions: bool = true:
	set(v):
		parse_actions = v
		if is_node_ready():
			queue_redraw()

## 字号（像素）。32 = 一格高。
@export_range(8, 200) var font_size: int = 40:
	set(v):
		font_size = v
		if is_node_ready():
			queue_redraw()

@export_group("外观")
@export var font_color: Color = Color(0.96, 0.95, 0.9):
	set(v):
		font_color = v
		if is_node_ready():
			queue_redraw()

## 描边色。亮色背景上也读得清。
@export var outline_color: Color = Color(0.05, 0.05, 0.08, 0.8):
	set(v):
		outline_color = v
		if is_node_ready():
			queue_redraw()

@export_range(0, 10) var outline_width: int = 4:
	set(v):
		outline_width = v
		if is_node_ready():
			queue_redraw()

## 底部半透明衬底，进一步保证可读性。可关掉做纯"刻字"效果。
@export var show_background: bool = false:
	set(v):
		show_background = v
		if is_node_ready():
			queue_redraw()

@export var background_color: Color = Color(0, 0, 0, 0.4):
	set(v):
		background_color = v
		if is_node_ready():
			queue_redraw()

## 衬底比文字外扩的边距（像素）。
@export_range(0, 40) var background_padding: int = 10:
	set(v):
		background_padding = v
		if is_node_ready():
			queue_redraw()

@export_group("对齐")
## 原点相对文字的位置。默认居中，摆位最直观。
@export_enum("居中", "左对齐", "右对齐") var anchor: int = 0:
	set(v):
		anchor = v
		if is_node_ready():
			queue_redraw()

const OFFSETS_8 := [
	Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7),
]

var _font: Font


func _ready() -> void:
	# @tool 脚本没有 GameConfig 等 autoload 依赖，编辑器 / 运行都能画。
	_font = ThemeDB.fallback_font
	queue_redraw()


func _draw() -> void:
	if text.is_empty() or _font == null:
		return

	var shown := InputHints.fill_text(text) if parse_actions else text
	var size := _font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	# draw_string 的 y 是基线，不是文字顶。把文字块垂直居中于原点。
	var baseline := (size.y) * 0.5 - _font.get_descent(font_size) * 0.5

	var origin_x := 0.0
	match anchor:
		0:  # 居中
			origin_x = -size.x * 0.5
		1:  # 左对齐：原点在文字左端
			pass
		2:  # 右对齐：原点在文字右端
			origin_x = -size.x

	# 衬底画在文字底下
	if show_background:
		var pad := float(background_padding)
		var rect := Rect2(origin_x - pad, -size.y * 0.5 - pad * 0.5,
			size.x + pad * 2.0, size.y + pad)
		draw_rect(rect, background_color, true)
		draw_rect(rect, Color(1, 1, 1, 0.15), false, 1.0)

	var pos := Vector2(origin_x, baseline)
	if outline_width > 0:
		var o := float(outline_width)
		for dir in OFFSETS_8:
			draw_string(_font, pos + dir * o, shown, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size, outline_color)
	draw_string(_font, pos, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, font_color)

	# 编辑器辅助：文字是细笔画，光靠点字很难在视口里抓中拖动。
	# 画一圈虚线标出"整块占多大、点哪里能选中"（运行时不画这圈线）。
	if Engine.is_editor_hint():
		var pad := float(background_padding)
		var r := Rect2(origin_x - pad, -size.y * 0.5 - pad * 0.5,
			size.x + pad * 2.0, size.y + pad)
		var c := Color(1, 0.85, 0.2, 0.7)
		var w := 1.0
		draw_dashed_line(r.position, r.position + Vector2(r.size.x, 0), c, w, 5.0)
		draw_dashed_line(r.position + Vector2(r.size.x, 0), r.position + r.size, c, w, 5.0)
		draw_dashed_line(r.position + r.size, r.position + Vector2(0, r.size.y), c, w, 5.0)
		draw_dashed_line(r.position + Vector2(0, r.size.y), r.position, c, w, 5.0)
		# 原点小十字：默认居中时原点=文字中心，方便对位
		draw_line(Vector2(0, -6), Vector2(0, 6), c, w)
		draw_line(Vector2(-6, 0), Vector2(6, 0), c, w)
