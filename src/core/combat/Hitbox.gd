class_name Hitbox
extends Area2D
## 攻击判定区。命中 Hurtbox 时造成伤害。
##
## 两种工作模式：
##   持续型（continuous = true）：只要重叠就周期性造成伤害。
##                                 敌人的接触伤害、环境热浪用这个。
##   一次性（continuous = false）：激活期间对每个目标只命中一次。
##                                 玩家挥砍、boss 技能用这个。
##
## 默认 disabled，由攻击逻辑显式 activate()。这点很关键：
## 「锋锐切割」被剥夺后，玩家的 Hitbox 永远不会被激活，
## 战斗系统干净地失效，不留任何残留状态。

signal hit_target(target: Hurtbox, info: DamageInfo)

@export var damage: int = 1
@export var knockback_force: float = 260.0

## 持续型伤害模式。
@export var continuous: bool = false

## 持续型的伤害间隔（秒）。
@export var tick_interval: float = 0.6

## 命中后给目标的无敌时长。<0 用目标自身默认值。
@export var invuln_override: float = -1.0

## 伤害标签，传给 DamageInfo，供后续 boss 机制使用。
@export var tags: Array[StringName] = []

## 是否一开机就生效。敌人的接触伤害通常为 true，玩家攻击为 false。
@export var active_on_ready: bool = false

var _active: bool = false
var _already_hit: Dictionary = {}      ## 一次性模式下本次激活已命中的目标
var _tick_timers: Dictionary = {}      ## 持续模式下每个目标的冷却计时


func _ready() -> void:
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	set_physics_process(false)
	if active_on_ready:
		activate()
	else:
		deactivate()


func _physics_process(delta: float) -> void:
	if not continuous or not _active:
		return
	for area in get_overlapping_areas():
		var hb := area as Hurtbox
		if hb == null:
			continue
		var t: float = _tick_timers.get(hb, 0.0) - delta
		if t <= 0.0:
			_strike(hb)
			t = tick_interval
		_tick_timers[hb] = t


# ---------------------------------------------------------------------------
# 开关
# ---------------------------------------------------------------------------

## 启用判定。一次性模式下会清空已命中记录，所以每次挥砍都能重新命中同一目标。
func activate() -> void:
	_active = true
	_already_hit.clear()
	monitoring = true
	set_physics_process(continuous)
	set_deferred(&"monitoring", true)
	if not continuous:
		# 一次性模式：激活瞬间就检查一次当前重叠，避免"贴脸砍空"。
		call_deferred(&"_strike_all_overlapping")


func deactivate() -> void:
	_active = false
	_tick_timers.clear()
	set_physics_process(false)
	set_deferred(&"monitoring", false)


func is_active() -> bool:
	return _active


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _on_area_entered(area: Area2D) -> void:
	if not _active or continuous:
		return
	var hb := area as Hurtbox
	if hb != null:
		_strike(hb)


func _on_area_exited(area: Area2D) -> void:
	_tick_timers.erase(area)


func _strike_all_overlapping() -> void:
	if not _active or continuous:
		return
	for area in get_overlapping_areas():
		var hb := area as Hurtbox
		if hb != null:
			_strike(hb)


func _strike(target: Hurtbox) -> void:
	if target == null or not is_instance_valid(target):
		return
	# 不打自己人：Hitbox 与 Hurtbox 同属一个 owner 时跳过。
	if target.owner != null and target.owner == owner:
		return
	if not continuous:
		if _already_hit.has(target):
			return
		_already_hit[target] = true

	var info := DamageInfo.new()
	info.amount = damage
	info.source = owner if owner != null else get_parent()
	info.origin = global_position
	info.knockback_force = knockback_force
	info.invuln_duration = invuln_override
	info.tags = tags

	if target.apply_damage(info):
		hit_target.emit(target, info)
