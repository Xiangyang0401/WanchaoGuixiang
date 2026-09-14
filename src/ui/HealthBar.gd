class_name HealthBar
extends HBoxContainer
## 点数式血条（参考丝之歌）。
##
## 【数值口径】内部血量是整数点数，UI 只负责翻译。
##   points_per_heart = 1 时，5 点血画 5 颗心。
##   将来想做半颗心，把它改成 2，5 颗心就是 10 点血，只动这里。
##
## UI 不认识玩家节点，只订阅 EventBus，所以玩家被销毁重建也不会崩。

## 每颗心代表多少点血量。
@export var points_per_heart: int = 1

## 心的尺寸（像素）。
@export var heart_size: Vector2 = Vector2(28, 28)
@export var heart_spacing: int = 6

@export var color_full: Color = Color(0.92, 0.30, 0.32)
@export var color_empty: Color = Color(0.25, 0.13, 0.15, 0.8)
## 血上限被能力惩罚砍掉的格子，用更暗的颜色画出来，
## 让玩家直观看到"我曾经有更多的血"。这是主题表达，不是纯功能。
@export var color_lost: Color = Color(0.15, 0.10, 0.12, 0.45)

## 显示因失去能力而消失的血格。
@export var show_lost_capacity: bool = true

var _base_max: int = 5
var _hearts: Array[ColorRect] = []


func _ready() -> void:
	add_theme_constant_override(&"separation", heart_spacing)
	EventBus.health_changed.connect(_on_health_changed)
	EventBus.player_respawned.connect(func(_p): _refresh_from_player())
	call_deferred(&"_refresh_from_player")


func _on_health_changed(who: Node, current: int, maximum: int) -> void:
	if who == null or not is_instance_valid(who):
		return
	if not who.is_in_group(&"player"):
		return
	var player := who as Player
	if player != null:
		_base_max = player.health.base_max_hp
	_render(current, maximum)


func _refresh_from_player() -> void:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return
	var p := players[0] as Player
	if p == null or p.health == null:
		return
	_base_max = p.health.base_max_hp
	_render(p.health.current_hp, p.health.max_hp)


func _render(current: int, maximum: int) -> void:
	var pph := maxi(1, points_per_heart)
	var total_hearts := int(ceil(float(_base_max if show_lost_capacity else maximum) / pph))
	var usable_hearts := int(ceil(float(maximum) / pph))
	var full_hearts := int(floor(float(current) / pph))

	_ensure_heart_count(total_hearts)

	for i in _hearts.size():
		var rect := _hearts[i]
		if i >= usable_hearts:
			rect.color = color_lost            # 因失去能力而消失的格子
		elif i < full_hearts:
			rect.color = color_full
		else:
			rect.color = color_empty


func _ensure_heart_count(n: int) -> void:
	while _hearts.size() < n:
		var r := ColorRect.new()
		r.custom_minimum_size = heart_size
		r.color = color_empty
		add_child(r)
		_hearts.append(r)
	while _hearts.size() > n:
		var r: ColorRect = _hearts.pop_back()
		r.queue_free()
