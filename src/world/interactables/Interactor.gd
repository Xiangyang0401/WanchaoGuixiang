class_name Interactor
extends Area2D
## 交互探测器。挂在玩家身上，负责找出"当前该跟谁交互"并响应 F 键。
##
## 为什么要独立成组件而不是写在 Player 里：
##   交互目标的选择规则（优先级、距离、能力过滤）会随内容增加变复杂，
##   独立出来后 Player 只需要知道"有这么个东西"，两边可以各自演化。

## 探测半径（格）。留 0 表示按主角身高自动取（0.8 个身位）。
##
## 别写死一个小数字：半径小于主角半身高时，脚边的长凳会探测不到，
## 玩家站在长凳上却没有交互提示。
@export var radius_tiles: float = 0.0

## 对话关闭后的交互冷却（毫秒）。
##
## 玩家跳过对话时习惯狂按/按住 F：关掉对话的那次按键之后，紧接着的第二次
## 按键（间隔常小于一帧）会先被 DialogPanel 放行（它已不播放、不拦截），
## 流到这里把刚关的对话立刻又顶开——世界一直暂停，体感就是"按 F 卡死"。
## 关掉后短暂忽略 F 把这段连发余波吸收掉。250ms 一晃而过，正常重聊不受影响。
const REOPEN_GUARD_MS: int = 250

var _candidates: Array[Interactable] = []
var _current: Interactable = null
var _last_prompt: String = ""
var _ignore_interact_until: int = 0

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = GameConfig.mask([GameConfig.Layer.INTERACTABLE])
	monitoring = true
	monitorable = false

	if _shape != null and _shape.shape is CircleShape2D:
		var r := radius_tiles if radius_tiles > 0.0 \
			else GameConfig.PLAYER_TILE_HEIGHT * 0.8
		# duplicate 后再改：CircleShape2D 是场景里的 SubResource，多实例共享。
		var circle := (_shape.shape as CircleShape2D).duplicate() as CircleShape2D
		circle.radius = GameConfig.tiles(r)
		_shape.shape = circle

	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

	# 对话结束：恢复提示；同时启动冷却，吸收玩家连按 F 跳对话的余波
	# （否则紧接的第二次按键会把刚关的对话立刻顶开，见 REOPEN_GUARD_MS 注释）。
	EventBus.dialog_finished.connect(func() -> void:
		_ignore_interact_until = Time.get_ticks_msec() + REOPEN_GUARD_MS
		_refresh_current(true)
	)


func _physics_process(_delta: float) -> void:
	_refresh_current()


## 事件驱动的 F 响应，而不是 _physics_process 里轮询 Input.is_action_just_pressed。
##
## 为什么：全局动作状态是"帧间持久"的，而 DialogPanel 拦截关闭对话的那个 F
## 用的是 set_input_as_handled()——那只会挡住事件的继续传播，不会清掉动作状态里
## 的 just 标记。于是那个 F 会残留到解除暂停后的下一个物理帧，被 Interactor
## 当成一次全新按压，把刚关掉的对话立刻又弹开（玩家体感：按 F 卡死）。
## 改用事件对象后，被 DialogPanel handled 的 F 根本流不到这里，天然没有残留。
func _unhandled_input(event: InputEvent) -> void:
	if _current == null or not event.is_action_pressed(&"interact"):
		return
	if event is InputEventKey and (event as InputEventKey).is_echo():
		# 按住 F 的自动连发不算新按压。否则对话关掉后手没松开，
		# echo 会一遍遍把对话重新顶开，玩家会以为 F 键坏了。
		return
	if Time.get_ticks_msec() < _ignore_interact_until:
		# 对话刚关：吞掉连按余波，等玩家下一次明确的按键。
		return
	_current.interact(get_parent())
	# 交互后立刻刷新，处理 one_shot 目标用完即失效的情况。
	_refresh_current()
	get_viewport().set_input_as_handled()


## 选出优先级最高、其次最近的候选目标。
## force = true 时即使目标与提示没变也重发一次（用于对话结束后恢复提示）。
func _refresh_current(force := false) -> void:
	var owner_node := get_parent()
	var best: Interactable = null
	var best_priority := -999999
	var best_dist := INF

	for c in _candidates:
		if not is_instance_valid(c):
			continue
		if c.get_prompt(owner_node) == "":
			continue
		var d := global_position.distance_squared_to(c.global_position)
		if c.interact_priority > best_priority or (c.interact_priority == best_priority and d < best_dist):
			best = c
			best_priority = c.interact_priority
			best_dist = d

	var prompt := best.get_prompt(owner_node) if best != null else ""
	if force or best != _current or prompt != _last_prompt:
		_current = best
		_last_prompt = prompt
		EventBus.interact_prompt_changed.emit(best, prompt)


func get_current() -> Interactable:
	return _current


func _on_area_entered(area: Area2D) -> void:
	var it := area as Interactable
	if it != null and not _candidates.has(it):
		_candidates.append(it)


func _on_area_exited(area: Area2D) -> void:
	var it := area as Interactable
	if it != null:
		_candidates.erase(it)
