class_name TutorialHints
extends Control
## 屏幕底部的教学提示条 —— 显示当前关卡填在 Level.tutorial_hints 里的文案。
##
## 行为：
##   - 关卡加载完成后，读当前 Level 的 tutorial_hints，逐行渲染。
##   - 文案里的 {action:xxx} 由 InputHints 自动替换成玩家真实键名。
##   - 空文案 -> 隐藏自己；切换关卡 -> 刷新内容。
##   - 常驻显示不自动消失（教学关基础操作要一直看得见），
##     靠关卡的 tutorial_hints 留空来"关掉"它。以后要做"学会就消失"，
##     加个淡出即可，不影响本组件的职责边界。
##
## 为什么不把文案直接写在这里：
##   教学内容属于关卡设计，不该埋进 UI 代码。策划在关卡 Inspector 里
##   填 tutorial_hints，这里只负责"显示当前关卡想让我显示的东西"。

## 距屏幕底部的距离（像素）。
@export var bottom_margin: float = 48.0

var _panel: PanelContainer
var _list: VBoxContainer

## 最近一次渲染的关卡，避免重复刷新。
var _shown_level: Node = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	visible = false

	# 游戏一开始（第一关加载）也会触发 level_loaded。
	EventBus.level_loaded.connect(_on_level_loaded)


func _build() -> void:
	# 底部居中的提示面板。
	#
	# 不要套 VBoxContainer + PRESET_CENTER_BOTTOM：那个预设按控件当前尺寸(0,0)
	# 重算 offset 把容器压成零宽；再只改 offset_bottom 会让上边界跑到下边界之下，
	# 高度被 clamp 成 0。而普通 Control 父节点不会按最小尺寸撑开子容器，
	# 于是内容整个溢出到屏幕外（实测 y=1920）——visible 仍是 true，肉眼却看不见。
	# 直接给面板做锚定：底边中央，向上、向两侧生长，尺寸由内容自然撑开。
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	_panel.offset_top = -bottom_margin
	_panel.offset_bottom = -bottom_margin
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.07, 0.72)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_panel.add_theme_stylebox_override(&"panel", style)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 6)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_list)

	add_child(_panel)


func _on_level_loaded(level_id: StringName) -> void:
	# 找当前场景里的 Level 节点。游戏里由 LevelManager 挂着，F6 单关测试也是。
	var level := get_tree().get_first_node_in_group(&"level")
	if level == null:
		_hide_all()
		return
	# 缓存到关卡级，切关后旧节点会被释放，不重复引用
	if level == _shown_level:
		return
	_shown_level = level
	var hints: Array[String] = level.tutorial_hints
	_render(hints)


func _render(hints: Array[String]) -> void:
	# 清掉旧行
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()

	if hints.is_empty():
		visible = false
		return

	for line in hints:
		var label := Label.new()
		label.text = InputHints.fill_text(line)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", 26)
		label.add_theme_color_override(&"font_color", Color(0.92, 0.92, 0.96))
		# 文字投影，背景复杂时也读得清
		label.add_theme_constant_override(&"shadow_offset_x", 2)
		label.add_theme_constant_override(&"shadow_offset_y", 2)
		label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
		_list.add_child(label)

	visible = true


func _hide_all() -> void:
	visible = false
	_shown_level = null
