class_name DamageInfo
extends RefCounted
## 一次伤害的完整描述。
##
## 所有伤害都通过这个对象传递，而不是裸传一个 int。
## 这样将来要加暴击、元素属性、破防、debuff 附加，只需要往这里加字段，
## 不必修改任何一处 take_damage 的签名——那会牵连所有敌人和玩家代码。

## 伤害数值（正整数）。
var amount: int = 1

## 伤害来源节点（谁打的）。可能为 null（环境伤害）。
var source: Node = null

## 伤害发生的世界坐标，用于决定击退方向和特效位置。
var origin: Vector2 = Vector2.ZERO

## 击退强度（像素/秒）。0 表示不击退。
var knockback_force: float = 0.0

## 强制指定击退方向。为 ZERO 时由受击方自行按 origin 计算。
var knockback_direction: Vector2 = Vector2.ZERO

## 受击后的无敌时长（秒）。<0 表示用受击方的默认值。
var invuln_duration: float = -1.0

## 是否无视无敌帧（某些环境伤害或 boss 技能可能需要）。
var ignore_invulnerability: bool = false

## 伤害类型标签，预留给后续 boss 设计（例如需要特定能力才能免疫的伤害）。
var tags: Array[StringName] = []


static func create(p_amount: int, p_source: Node = null, p_knockback: float = 0.0) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = p_amount
	info.source = p_source
	info.knockback_force = p_knockback
	if p_source != null and p_source is Node2D:
		info.origin = (p_source as Node2D).global_position
	return info


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


## 计算作用于目标的击退向量。
func resolve_knockback(target_position: Vector2) -> Vector2:
	if knockback_force <= 0.0:
		return Vector2.ZERO
	var dir := knockback_direction
	if dir == Vector2.ZERO:
		dir = (target_position - origin)
		# 纯垂直重叠时给一个默认水平方向，避免除零和"原地弹起"的怪异手感。
		if dir.length_squared() < 0.001:
			dir = Vector2.RIGHT
		dir = dir.normalized()
		# 击退略微上抬，手感更好，也能让玩家脱离地面危险区。
		dir.y = min(dir.y, -0.35)
		dir = dir.normalized()
	return dir * knockback_force
