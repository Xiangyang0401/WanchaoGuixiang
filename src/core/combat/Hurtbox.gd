class_name Hurtbox
extends Area2D
## 受击判定区。挂在任何可被伤害的单位上，负责把伤害转交给 Health。
##
## 为什么受击区要独立于本体碰撞体：
##   本体碰撞体负责"撞墙"，受击区负责"挨打"，两者形状和层级需求完全不同。
##   分开后，敌人可以有一个大的受击区（好打中）和一个小的本体（好走位），
##   而且开关无敌时只需要禁用受击区，不影响物理移动。

signal hurt(info: DamageInfo)

## 关联的血量组件。留空则自动在父节点下查找。
@export var health_path: NodePath

var _health: Health


func _ready() -> void:
	if health_path.is_empty():
		_health = _find_health()
	else:
		_health = get_node_or_null(health_path) as Health

	if _health == null:
		push_warning("Hurtbox 找不到 Health 组件：%s" % get_path())

	# 受击区只检测重叠，不参与物理推挤。
	monitorable = true
	monitoring = false


## 由 Hitbox 调用。返回是否真的造成了伤害。
func apply_damage(info: DamageInfo) -> bool:
	if _health == null:
		return false
	var applied := _health.take_damage(info)
	if applied:
		hurt.emit(info)
	return applied


func get_health() -> Health:
	return _health


func _find_health() -> Health:
	var p := get_parent()
	if p == null:
		return null
	for child in p.get_children():
		if child is Health:
			return child
	return null
