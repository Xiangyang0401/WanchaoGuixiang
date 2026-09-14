class_name DialogPanel
extends Control
## 底部对话字幕框。一次显示一句，按 F 逐句推进。
##
## 职责边界：
##   - 只负责"播一段台词"的显示与推进，不关心谁触发的、台词哪来的。
##   - 台词经 EventBus.dialog_requested(speaker, lines) 送来，播完发
##     EventBus.dialog_finished。NPC、剧情触发器都能复用，无需改这里。
##
## 播放期间整个游戏暂停（玩家被锁住、敌人也停），播完自动恢复。
## 暂停是对"锁住不能动"最省心的实现——不用给玩家/敌人各写一套禁用逻辑，
## 也不会有对话到一半被小怪打断的破事。代价是世界会"定住"，
## 对短篇叙事游戏的对话场景完全可以接受。
##
## 为什么 process_mode = ALWAYS：
##   一旦 get_tree().paused = true，默认(Pausable)的节点连输入都收不到。
##   本面板必须保持活着才能收 F 推进、才能把自己关掉把暂停解除。

## 对话框距屏幕底部的距离（像素）。
@export var bottom_margin: float = 120.0
## 面板最大宽度（像素）。
@export var max_width: float = 1400.0

var _panel: PanelContainer
var _speaker_label: Label
var _body_label: Label
var _hint_label: Label

var _speaker: String = ""
var _lines: Array[String] = []
var _index: int = 0
var _playing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	EventBus.dialog_requested.connect(_on_dialog_requested)


func _unhandled_input(event: InputEvent) -> void:
	if not _playing or not event.is_action_pressed(&"interact"):
		return
	_advance()
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# 播放控制
# ---------------------------------------------------------------------------

func _on_dialog_requested(speaker: String, lines: Array) -> void:
	# 若已经有一段在播（理论上不会：世界已暂停，NPC 的 F 进不来），忽略。
	if _playing:
		return
	_speaker = speaker
	# 拷贝一份：调用方（NPC 场景数据）可能之后被改动，播放期间不受影响。
	_lines = []
	for l in lines:
		_lines.append(str(l))
	_index = 0

	# 隐藏"按 F 交谈"的靠近提示，避免和对话框抢注意力。
	EventBus.interact_prompt_changed.emit(null, "")
	_render()
	visible = true
	_playing = true
	get_tree().paused = true


func _advance() -> void:
	_index += 1
	if _index >= _lines.size():
		_close()
		return
	_render()


func _close() -> void:
	_playing = false
	visible = false
	get_tree().paused = false
	EventBus.dialog_finished.emit()
	# 提示恢复由 Interactor 监听 dialog_finished 后重发，这里不要再发一次清空——
	# 那会把刚恢复的头顶提示又盖掉（打开时已在 _on_dialog_requested 清过一次）。
	#
	# 注意：关闭用的这个 F 键会不会被 Interactor 立刻捡到、把对话又弹开，
	# 由 Interactor 的输入机制保证（事件驱动 + 本面板 set_input_as_handled），
	# 不在这里额外处理——靠系统清"残留输入"只会清不干净还容易误伤。


func _render() -> void:
	var is_last := _index >= _lines.size() - 1

	if _lines.is_empty():
		# 策划漏填台词：对话框照开，直接给一句人话提示，别静默。
		_speaker_label.text = _speaker
		_body_label.text = "[未配置台词：在 NPC 的 lines 里填几句]"
	else:
		_speaker_label.text = _speaker
		_body_label.text = InputHints.fill_text(_lines[_index])

	# 尾部提示：非最后一句显示"继续"，最后一句显示"结束"。
	_hint_label.text = "[F] %s" % ("继续" if not is_last else "结束")


# ---------------------------------------------------------------------------
# UI 构建
# ---------------------------------------------------------------------------

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 外层容器：底部居中
	#
	# 不要用 CenterContainer + PRESET_CENTER_BOTTOM：那个预设把容器压成
	# 零尺寸并贴在底边上，1400px 宽的正文塞进去会把面板整个顶到屏幕外
	# （实测底边 y=1920，屏幕外）——世界已暂停但看不到框，玩家体感就是"卡死"。
	# 改成直接给面板做锚定：锚点=底边中央，向上、向两侧生长，
	# 尺寸由 PanelContainer 的最小尺寸自然撑开，不依赖任何容器算宽高。
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
	style.bg_color = Color(0.04, 0.04, 0.07, 0.86)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.12)
	_panel.add_theme_stylebox_override(&"panel", style)
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override(&"font_size", 24)
	_speaker_label.add_theme_color_override(&"font_color", Color(1.0, 0.83, 0.55))
	_speaker_label.add_theme_constant_override(&"shadow_offset_x", 2)
	_speaker_label.add_theme_constant_override(&"shadow_offset_y", 2)
	_speaker_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	col.add_child(_speaker_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(max_width, 0)
	_body_label.add_theme_font_size_override(&"font_size", 30)
	_body_label.add_theme_color_override(&"font_color", Color(0.94, 0.94, 0.98))
	_body_label.add_theme_constant_override(&"shadow_offset_x", 2)
	_body_label.add_theme_constant_override(&"shadow_offset_y", 2)
	_body_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	col.add_child(_body_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override(&"font_size", 18)
	_hint_label.add_theme_color_override(&"font_color", Color(0.7, 0.7, 0.78))
	col.add_child(_hint_label)
