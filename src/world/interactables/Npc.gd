class_name Npc
extends Interactable
## 可对话的 NPC —— 摆进关卡，玩家靠近按 F 弹对话。
##
## 设定用法（策划向）：
##   1. 把 scenes/actors/Npc.tscn 拖进关卡，摆到地面平台上
##   2. Inspector 里填 speaker_name（对话框里显示的名字）和 lines（台词，一行一句）
##   3. 填完 F6 跑起来：靠近 -> NPC 头顶出现 "[F] 交谈"，按 F -> 底部弹出对话框，
##      再按 F 逐句推进，最后一句按完关闭。走开再回来按 F 会从头再聊一遍。
##
## 行为约定：
##   - 一段对话播完自动关闭，NPC 可无限次重聊（one_shot = false）。
##   - 对话期间整个世界暂停（玩家被锁住不能动，敌人也不动），播完恢复。
##   - 台词只在 NPC 处配置；想用一段话的角色对话时，把整段台词的
##     说话人前缀写进行文本（例如 "[老婆婆] 你也来了。"）即可，无需改代码。
##
## 关于外观：目前是占位人形（身体+头两块色块），尺寸按格、可调颜色，
## 和长凳/主角同一套"格驱动"逻辑。主角改尺寸时这里不用动。

@export_group("对话")
## 对话框里显示的名字。留空则显示"？"（提示策划漏填）。
@export var speaker_name: String = ""
## 台词，一行一句，按 F 顺序播放。
## Inspector 里点数组右侧 + 逐条添加。
@export var lines: Array[String] = []

@export_group("外观")
## 占位人形的尺寸（格）：宽 x 高。
## 原点在脚底：摆到地面时让节点原点贴平台顶边即可。
@export var size_tiles: Vector2 = Vector2(1.5, 3.0)
## 身体主色。头会自动用同色系浅一档，方便一眼认成"人"。
@export var body_color: Color = Color(0.42, 0.52, 0.62)

## 头顶显示名字（运行与编辑均可见）。多 NPC 同屏时方便策划辨认谁是谁。
@export var show_name_tag: bool = false


func _ready() -> void:
	super._ready()
	# NPC 不消耗：可以反复交谈（每次重播同一段台词）。
	one_shot = false
	if prompt_text == "交互":
		prompt_text = "交谈"
	_apply_size()
	if show_name_tag:
		_build_name_tag()


func _on_interact(_by: Node) -> void:
	# 没配台词时也正常弹框，让策划在对话框里直接看到"漏填了"。
	var who := speaker_name if speaker_name != "" else "？"
	EventBus.dialog_requested.emit(who, lines)


## 按 size_tiles 重建交互框与人形占位。像素值不写死，主角改尺寸不牵连。
func _apply_size() -> void:
	var w := size_tiles.x * GameConfig.TILE_SIZE
	var h := size_tiles.y * GameConfig.TILE_SIZE

	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null:
		var rect := cs.shape as RectangleShape2D
		rect = rect.duplicate() as RectangleShape2D if rect != null else RectangleShape2D.new()
		rect.size = Vector2(w, h)
		cs.shape = rect
		# 原点=脚底，碰撞框中心抬到身体中央。
		cs.position = Vector2(0, -h * 0.5)

	# 身体占下方 70%，头占上方 30%。
	var body_h := h * 0.7
	_fit_rect("Visual/Body", Vector2(-w * 0.5, -h), Vector2(w, body_h))
	_fit_rect("Visual/Head", Vector2(-w * 0.28, -h), Vector2(w * 0.56, h - body_h))
	# 颜色也联动：身体用 body_color，头浅一档（闭眼也能认出是"人"）。
	var head_color := body_color.lightened(0.22)
	_set_rect_color("Visual/Body", body_color)
	_set_rect_color("Visual/Head", head_color)


func _fit_rect(path: String, pos: Vector2, size: Vector2) -> void:
	var r := get_node_or_null(path) as ColorRect
	if r == null:
		return
	r.offset_left = pos.x
	r.offset_top = pos.y
	r.offset_right = pos.x + size.x
	r.offset_bottom = pos.y + size.y


func _set_rect_color(path: String, color: Color) -> void:
	var r := get_node_or_null(path) as ColorRect
	if r != null:
		r.color = color


func _build_name_tag() -> void:
	var tag := Label.new()
	tag.text = speaker_name if speaker_name != "" else "未命名"
	tag.position = Vector2(-60, -GameConfig.tiles(size_tiles.y) - 24)
	tag.size = Vector2(120, 24)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override(&"font_size", 18)
	tag.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.9))
	add_child(tag)
