@tool
class_name LevelExit
extends Area2D
## 关卡边界触发器。玩家走进来就切换到目标关卡。
##
## 按策划要求："相机跟随主角，边界自动切换地图"。
## 所以这是一个纯自动的触发器，不需要按键。
##
## 摆放建议：放在地图最边缘，做成一条竖直的长条区域（高度盖满整个通道），
## 避免玩家跳跃时从上方绕过去。
##
## 【尺寸的唯一真相源是 size_tiles】运行时 _apply_size 会用它覆写
## CollisionShape2D 的 shape 尺寸，所以在编辑器里手拉 shape 是无效的。
## 改尺寸请改 Inspector 里的 size_tiles（单位：格）——@tool 让 shape
## 线框和色块在编辑器里实时跟随，编辑器看到多大实机就多大。
##
## 【调试可视化】运行时出口会画一块半透明色块，用来确认位置和触发是否生效：
##   青色 = 配置正常 | 黄色 = 玩家正在区内 | 红色 = target_level 没配或没注册。
## 开关在 GameConfig.debug_show_level_exits，流程跑通后改 false 即全部透明。

## 目标关卡 id，对应 LevelRegistry 里的键。
@export var target_level: StringName = &"":
	set(value):
		target_level = value
		if Engine.is_editor_hint():
			queue_redraw()

## 目标关卡里的入口点 id。
@export var target_entry: StringName = &"default"

## 触发区尺寸（格）。唯一真相源，运行时用它覆写 shape 尺寸。
@export var size_tiles: Vector2 = Vector2(1.0, 8.0):
	set(value):
		size_tiles = value
		_apply_size()
		queue_redraw()

## 进入后是否需要玩家真的按方向键朝向出口。
## 开启可以避免"被击退撞出地图"的意外切图。
@export var require_input_direction: bool = false

## 出口朝向，配合 require_input_direction 使用。
@export_enum("右:1", "左:-1") var direction: int = 1

## 可视化配色。青色块盖住通道一眼就能看到出口在哪；
## 玩家踩进去变黄，能确认"确实进了触发区"；红色说明这张出口是坏的。
const DEBUG_COLOR_OK := Color(0.25, 0.9, 1.0, 0.22)
const DEBUG_COLOR_ACTIVE := Color(1.0, 0.85, 0.2, 0.5)
const DEBUG_COLOR_BROKEN := Color(1.0, 0.15, 0.15, 0.35)

@onready var _shape: CollisionShape2D = $CollisionShape2D

var _triggered: bool = false
var _player_inside: bool = false


func _ready() -> void:
	# 编辑器里只做尺寸同步和可视化，不连信号、不进物理流程。
	if Engine.is_editor_hint():
		_apply_size()
		queue_redraw()
		return
	collision_layer = 0
	collision_mask = GameConfig.mask([GameConfig.Layer.PLAYER])
	monitorable = false
	_apply_size()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()


func _apply_size() -> void:
	if _shape == null:
		return
	if _shape.shape is RectangleShape2D:
		(_shape.shape as RectangleShape2D).size = size_tiles * GameConfig.TILE_SIZE


## 调试可视化。画在 CollisionShape2D 的实际位置和尺寸上，
## 与真实触发区完全重合（shape 子节点允许不在原点，这里不能假设居中）。
func _draw() -> void:
	if not GameConfig.debug_show_level_exits:
		return
	if _shape == null or not (_shape.shape is RectangleShape2D):
		return
	var size_px: Vector2 = (_shape.shape as RectangleShape2D).size
	var rect := Rect2(_shape.position - size_px * 0.5, size_px)
	var fill := DEBUG_COLOR_OK
	if not _configured_ok():
		fill = DEBUG_COLOR_BROKEN
	elif _player_inside:
		fill = DEBUG_COLOR_ACTIVE
	draw_rect(rect, fill)
	# 描一圈亮边，半透明色块在浅色背景上也能看清边界
	draw_rect(rect, fill.lightened(0.45), false, 2.0)


func _configured_ok() -> bool:
	return target_level != &"" and LevelRegistry.exists(target_level)


## 玩家真实位置是否压在触发区附近（矩形外扩 2 格做近似）。
## 只需拦掉"玩家根本不在这张出口旁边"的误报：正常触发时玩家必然走进
## 触发区（y 方向矩形已盖满整个通道），而误报时玩家在对面入口，相距
## 数十格，2 格容差足够区分。矩形用 shape 的全局中心，不假设节点居中。
func _really_overlaps_player(body: Node2D) -> bool:
	var half: Vector2 = (_shape.shape as RectangleShape2D).size * 0.5
	var rect := Rect2(_shape.global_position - half, half * 2.0)
	return rect.grow(GameConfig.TILE_SIZE * 2.0).has_point(body.global_position)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	# 引擎事件可能偏离几何现实：切图时玩家被瞬移到新入口，但物理 broadphase
	# 要到下一个物理步才同步新位置。间隙里新出口可能基于玩家**旧位置**收到
	# entered 误报——相邻两关出口常在同一 x 上，误报会立刻链式切图，表现
	# 为两关之间无限来回切（疯狂闪屏）。所以用玩家真实位置复核一遍。
	if not _really_overlaps_player(body):
		return
	_player_inside = true
	queue_redraw()
	if _triggered:
		return
	if target_level == &"":
		push_warning("LevelExit 未配置 target_level：%s" % get_path())
		return

	if require_input_direction:
		var x := Input.get_axis(&"move_left", &"move_right")
		if signf(x) != signf(float(direction)):
			return

	_triggered = true
	EventBus.level_transition_requested.emit(target_level, target_entry)


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	_player_inside = false
	queue_redraw()
