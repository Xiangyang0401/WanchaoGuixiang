class_name Interactable
extends Area2D
## 可交互物基类。长凳、NPC、门、剧情触发器都继承它。
##
## 设计意图：策划在地图里放一个继承本类的场景，填几个导出参数就能用，
## 不需要写代码。需要特殊行为时再重写 _on_interact()。

signal interacted(by: Node)

## 靠近时显示的提示文字。
@export var prompt_text: String = "交互"

## 是否只能交互一次。
@export var one_shot: bool = false

## 需要拥有哪些能力才能交互。留空表示无要求。
## 例如某些障碍只有"安抚"能力才能转化。
@export var required_abilities: Array[StringName] = []

## 不满足能力要求时的提示。留空则完全不显示提示。
@export var locked_prompt: String = ""

## 交互优先级。同时有多个目标在范围内时，数值大的优先。
## 注意：不能叫 priority，那是 Area2D 的内置属性。
@export var interact_priority: int = 0

var _used: bool = false


func _ready() -> void:
	collision_layer = GameConfig.mask([GameConfig.Layer.INTERACTABLE])
	collision_mask = 0
	monitorable = true
	monitoring = false
	add_to_group(&"interactable")


## 当前是否可被指定单位交互。
func can_interact(by: Node) -> bool:
	if one_shot and _used:
		return false
	if required_abilities.is_empty():
		return true
	var set := _get_abilities(by)
	if set == null:
		return false
	return set.has_all(required_abilities)


## 返回此刻应显示的提示文字。空字符串表示不显示。
func get_prompt(by: Node) -> String:
	if one_shot and _used:
		return ""
	if not can_interact(by):
		return locked_prompt
	return prompt_text


## 交互提示的世界坐标锚点（通常取物体头顶上方一点）。
##
## 默认用交互碰撞框的顶边中心——大多数物件碰撞框顶部≈可见头顶。
## 造型特别高/矮的物件可以重写，比如把提示挂到某块装饰上面。
func get_prompt_anchor() -> Vector2:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var top := cs.position.y - (cs.shape as RectangleShape2D).size.y * 0.5
		return to_global(Vector2(0, top))
	if cs != null and cs.shape is CircleShape2D:
		var top := cs.position.y - (cs.shape as CircleShape2D).radius
		return to_global(Vector2(0, top))
	return global_position + Vector2(0, -GameConfig.tiles(2.0))


## 由 Interactor 调用。子类重写 _on_interact 实现具体行为。
func interact(by: Node) -> void:
	if not can_interact(by):
		return
	_used = true
	interacted.emit(by)
	_on_interact(by)


## 子类重写此方法。
func _on_interact(_by: Node) -> void:
	pass


func _get_abilities(by: Node) -> AbilitySet:
	if by == null:
		return null
	if by is Player:
		return (by as Player).abilities
	return null
