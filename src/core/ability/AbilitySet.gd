class_name AbilitySet
extends RefCounted
## 能力集运行时容器 —— 一个单位「此刻拥有哪些能力」。
##
## 挂在玩家身上（将来 boss 或特殊 NPC 也可以复用）。
## 对外只暴露 has() 查询和 set_stage() 切换，不提供零散的 add/remove，
## 是为了强制走「快照」路径，避免出现设计上不存在的中间状态。
##
## 唯一例外是 grant()/revoke()，专供调试面板使用，正式流程不要调。

signal changed(current: Array, gained: Array, lost: Array)

var _owned: Dictionary = {}          ## StringName -> true，当集合用
var _stage: Abilities.Stage = Abilities.Stage.YOUNG


func _init(initial_stage: Abilities.Stage = Abilities.Stage.YOUNG) -> void:
	_apply(Abilities.abilities_for_stage(initial_stage), false)
	_stage = initial_stage


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func has(id: StringName) -> bool:
	return _owned.has(id)


## 是否拥有全部列出的能力。
func has_all(ids: Array) -> bool:
	for id in ids:
		if not _owned.has(id):
			return false
	return true


func list() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in _owned.keys():
		out.append(k)
	return out


func get_stage() -> Abilities.Stage:
	return _stage


## 当前阶段的血量上限减值。
func hp_penalty() -> int:
	var data: Dictionary = Abilities.STAGES.get(_stage, {})
	return int(data.get("hp_penalty", 0))


## 当前阶段血量是否自动恢复。
func auto_regen() -> bool:
	var data: Dictionary = Abilities.STAGES.get(_stage, {})
	return bool(data.get("auto_regen", true))


# ---------------------------------------------------------------------------
# 切换
# ---------------------------------------------------------------------------

## 切换到指定阶段。这是正式流程唯一该用的入口。
func set_stage(stage: Abilities.Stage) -> void:
	if stage == _stage:
		return
	_stage = stage
	_apply(Abilities.abilities_for_stage(stage), true)


## 调试用：单独授予一个能力。会让当前状态偏离阶段定义，仅供测试。
func grant(id: StringName) -> void:
	if _owned.has(id):
		return
	_owned[id] = true
	_emit([id], [])


## 调试用：单独剥夺一个能力。
func revoke(id: StringName) -> void:
	if not _owned.has(id):
		return
	_owned.erase(id)
	_emit([], [id])


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _apply(ids: Array, notify: bool) -> void:
	var gained: Array[StringName] = []
	var lost: Array[StringName] = []

	var next: Dictionary = {}
	for id in ids:
		next[id] = true

	for id in next.keys():
		if not _owned.has(id):
			gained.append(id)
	for id in _owned.keys():
		if not next.has(id):
			lost.append(id)

	_owned = next

	if notify:
		_emit(gained, lost)


func _emit(gained: Array, lost: Array) -> void:
	var cur := list()
	changed.emit(cur, gained, lost)
	EventBus.abilities_changed.emit(cur, gained, lost)
