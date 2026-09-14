extends Node
## 全局游戏状态 —— 跨关卡存活的数据都放这里。
##
## 职责边界：
##   GameState 只管「状态」，不管「表现」。它不知道玩家节点长什么样，
##   也不负责加载场景（那是 LevelManager 的事）。
##   这样存档功能将来只需要序列化这一个对象。

# ---------------------------------------------------------------------------
# 能力阶段
# ---------------------------------------------------------------------------

## 当前故事阶段。玩家生成时会按这个值初始化能力集。
## 策划调试：直接在调试面板改这个值。
var stage: Abilities.Stage = Abilities.Stage.YOUNG:
	set(value):
		if stage == value:
			return
		stage = value
		stage_changed.emit(value)

signal stage_changed(stage: Abilities.Stage)


# ---------------------------------------------------------------------------
# 复活点
# ---------------------------------------------------------------------------
# 规则（按策划要求）：
#   每个区域有默认复活点；策划可在地图里配置长凳等检查点；
#   检查点复活优先级高于默认复活点。

## 当前激活的检查点。为空表示还没碰过任何检查点，用区域默认复活点。
var active_checkpoint_id: StringName = &""
var active_checkpoint_level: StringName = &""
var active_checkpoint_position: Vector2 = Vector2.ZERO

## 当前所在关卡 id。
var current_level_id: StringName = &""


## 激活一个检查点（长凳等）。
func activate_checkpoint(id: StringName, level_id: StringName, pos: Vector2) -> void:
	active_checkpoint_id = id
	active_checkpoint_level = level_id
	active_checkpoint_position = pos
	EventBus.checkpoint_activated.emit(id, pos)


## 是否有可用的检查点复活点。
func has_checkpoint() -> bool:
	return active_checkpoint_id != &""


# ---------------------------------------------------------------------------
# 关卡进度（预留给存档）
# ---------------------------------------------------------------------------

## 已访问过的关卡集合，用于"回到同一个地方发现它变了"这类判断。
var visited_levels: Dictionary = {}

## 任意剧情标记。剧情编辑器将来往这里写键值，条件判断从这里读。
## 用通用字典而不是硬编码字段，是为了让策划加剧情分支时不用改代码。
var flags: Dictionary = {}


func set_flag(key: StringName, value: Variant = true) -> void:
	flags[key] = value


func get_flag(key: StringName, default_value: Variant = false) -> Variant:
	return flags.get(key, default_value)


func mark_visited(level_id: StringName) -> void:
	visited_levels[level_id] = true


func is_visited(level_id: StringName) -> bool:
	return visited_levels.has(level_id)


# ---------------------------------------------------------------------------
# 重置
# ---------------------------------------------------------------------------

## 回到初始状态（新游戏 / 调试重来）。
func reset() -> void:
	stage = Abilities.Stage.YOUNG
	active_checkpoint_id = &""
	active_checkpoint_level = &""
	active_checkpoint_position = Vector2.ZERO
	visited_levels.clear()
	flags.clear()
