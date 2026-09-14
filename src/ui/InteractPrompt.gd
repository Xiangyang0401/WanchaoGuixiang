class_name InteractPrompt
extends Control
## 交互提示（"按 F 交谈"）—— 出现在交互目标头顶，而不是屏幕中央。
##
## 通过 EventBus 订阅，不认识玩家也不认识长凳。收到 interact_prompt_changed
## 后记住"目标 + 文案"，之后每帧把提示面板投影到目标头顶（把 get_prompt_anchor()
## 给出的世界坐标锚点换算成屏幕坐标）。目标移动、镜头平滑/前瞻都自动跟随。
##
## 为什么挂在 HUD(CanvasLayer) 而不是做成目标节点的子 Label：
##   目标子节点画在 2D 世界层，会被场景里 z 更高的东西盖住，样式还跟 UI 脱节。
##   CanvasLayer 上的面板永远在最上层，一套样式服务所有目标（NPC/长凳/门都复用）。

@export var key_hint: String = "F"

## 面板底边距头顶锚点的留白（像素）。
@export var float_offset: float = 12.0

var _panel: PanelContainer
var _label: Label
var _target: Node = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 本控件只是个"定位容器"：零尺寸钉在屏幕左上，不占屏也不锚定，
	# 面板位置完全由 _update_position 手动指定（覆盖 HUD.tscn 里的全屏锚定）。
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	_build()
	visible = false
	EventBus.interact_prompt_changed.connect(_on_prompt_changed)


func _process(_delta: float) -> void:
	_update_position()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.88)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_panel.add_theme_stylebox_override(&"panel", style)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", 20)
	_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_label.add_theme_constant_override(&"shadow_offset_y", 1)
	_label.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
	_panel.add_child(_label)

	add_child(_panel)


func _on_prompt_changed(target: Node, text: String) -> void:
	_target = target
	var show := target != null and is_instance_valid(target) and text != ""
	visible = show
	if show:
		_label.text = "[%s]  %s" % [key_hint, text]
	_update_position()


## 每帧把面板钉到目标头顶的屏幕位置；目标跑出屏幕就藏起来，别在边缘留残影。
func _update_position() -> void:
	if not visible or not is_instance_valid(_target) or not (_target is Interactable):
		return
	var vp := get_viewport()
	if vp.get_camera_2d() == null:
		return
	# 世界坐标 -> 屏幕像素：canvas transform 已含 current camera 的 zoom/offset。
	# HUD 是独立 CanvasLayer（无自身变换），其子控件的坐标就是屏幕像素，可直接用。
	var screen: Vector2 = vp.get_canvas_transform() * (_target as Interactable).get_prompt_anchor()
	var inside := Rect2(Vector2.ZERO, vp.get_visible_rect().size).grow(8.0).has_point(screen)
	_panel.visible = inside
	if not inside:
		return
	# 面板底边贴在锚点上方 float_offset 处，水平居中。
	_panel.position = screen - Vector2(_panel.size.x * 0.5, _panel.size.y + float_offset)
