class_name Health
extends Node
## 血量组件。玩家和敌人共用同一套，避免出现两套并行的生命逻辑。
##
## 数值口径（重要）：
##   内部一律用整数点数。UI 层负责翻译——5 点画 5 颗心。
##   将来想做半颗心，把心的"每颗点数"改成 2，只动 UI，不动这里。
##   boss 有 200 点、小怪有 3 点、玩家有 5 点，全在一个体系里。
##
## 无敌帧：
##   受伤后进入无敌，期间再次受伤会被忽略（除非 DamageInfo.ignore_invulnerability）。
##   无敌状态通过 invulnerability_changed 广播，表现层（闪烁）自己订阅，
##   Health 本身不碰任何视觉。

signal health_changed(current: int, maximum: int)
signal damaged(info: DamageInfo)
signal healed(amount: int)
signal died
signal invulnerability_changed(active: bool)

## 血量上限的基础值。玩家的实际上限还要减去能力阶段惩罚，见 set_max_hp_penalty()。
@export var base_max_hp: int = 5

## 受伤后的默认无敌时长（秒）。
@export var invulnerability_time: float = 0.8

## 是否随时间自动回血。玩家在年轻阶段为 true，成熟阶段为 false（必须找长凳）。
@export var auto_regen: bool = false

## 自动回血间隔（秒），每次回 1 点。
@export var auto_regen_interval: float = 6.0

## 脱离战斗多久后才开始自动回血（秒）。避免边挨打边回血。
@export var auto_regen_delay: float = 3.0

var current_hp: int = 5
var max_hp: int = 5

var _hp_penalty: int = 0
var _invulnerable: bool = false
var _invuln_timer: float = 0.0
var _regen_timer: float = 0.0
var _time_since_damage: float = 999.0
var _dead: bool = false


func _ready() -> void:
	max_hp = maxi(1, base_max_hp - _hp_penalty)
	current_hp = max_hp
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _dead:
		return

	if _invulnerable:
		_invuln_timer -= delta
		if _invuln_timer <= 0.0:
			_set_invulnerable(false)

	_time_since_damage += delta

	if auto_regen and current_hp < max_hp and _time_since_damage >= auto_regen_delay:
		_regen_timer += delta
		if _regen_timer >= auto_regen_interval:
			_regen_timer = 0.0
			heal(1)
	else:
		_regen_timer = 0.0


# ---------------------------------------------------------------------------
# 对外接口
# ---------------------------------------------------------------------------

## 承受一次伤害。返回是否真的造成了伤害（被无敌帧挡掉时返回 false）。
func take_damage(info: DamageInfo) -> bool:
	if _dead:
		return false
	if info.amount <= 0:
		return false
	if _invulnerable and not info.ignore_invulnerability:
		return false
	if GameConfig.debug_invincible and _is_player_owner():
		return false

	current_hp = maxi(0, current_hp - info.amount)
	_time_since_damage = 0.0
	_regen_timer = 0.0

	damaged.emit(info)
	health_changed.emit(current_hp, max_hp)
	EventBus.damaged.emit(get_parent(), info.amount, info.source)
	EventBus.health_changed.emit(get_parent(), current_hp, max_hp)

	if current_hp <= 0:
		_die()
		return true

	var iv := info.invuln_duration if info.invuln_duration >= 0.0 else invulnerability_time
	if iv > 0.0:
		_start_invulnerability(iv)
	return true


func heal(amount: int) -> void:
	if _dead or amount <= 0:
		return
	var before := current_hp
	current_hp = mini(max_hp, current_hp + amount)
	if current_hp == before:
		return
	healed.emit(current_hp - before)
	health_changed.emit(current_hp, max_hp)
	EventBus.health_changed.emit(get_parent(), current_hp, max_hp)


## 回满（长凳休息、复活时用）。
func heal_full() -> void:
	if current_hp == max_hp and not _dead:
		return
	_dead = false
	current_hp = max_hp
	health_changed.emit(current_hp, max_hp)
	EventBus.health_changed.emit(get_parent(), current_hp, max_hp)


## 设置能力阶段带来的血上限惩罚（每失去一个能力 -1）。
## 上限降低时，当前血量会被截断到新上限。
func set_max_hp_penalty(penalty: int) -> void:
	if _hp_penalty == penalty:
		return
	_hp_penalty = penalty
	var old_max := max_hp
	max_hp = maxi(1, base_max_hp - _hp_penalty)
	if max_hp < old_max:
		current_hp = mini(current_hp, max_hp)
	elif max_hp > old_max:
		# 上限回升时把新增的格子也补满，避免出现"有格子但空着"的困惑。
		current_hp += (max_hp - old_max)
	current_hp = clampi(current_hp, 0, max_hp)
	health_changed.emit(current_hp, max_hp)
	EventBus.health_changed.emit(get_parent(), current_hp, max_hp)


func is_invulnerable() -> bool:
	return _invulnerable


func is_dead() -> bool:
	return _dead


## 复活（重置死亡状态并回满）。
func revive() -> void:
	_dead = false
	_invulnerable = false
	_invuln_timer = 0.0
	heal_full()
	_set_invulnerable(false)


## 手动开一段无敌（复活后的保护期等）。
func grant_invulnerability(duration: float) -> void:
	_start_invulnerability(duration)


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _start_invulnerability(duration: float) -> void:
	_invuln_timer = duration
	_set_invulnerable(true)


func _set_invulnerable(active: bool) -> void:
	if _invulnerable == active:
		return
	_invulnerable = active
	invulnerability_changed.emit(active)


func _die() -> void:
	if _dead:
		return
	_dead = true
	_set_invulnerable(false)
	died.emit()
	EventBus.died.emit(get_parent())


func _is_player_owner() -> bool:
	var p := get_parent()
	return p != null and p.is_in_group(&"player")
