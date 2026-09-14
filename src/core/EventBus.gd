extends Node
## 全局事件总线。
##
## 目的：让系统之间不必互相持有引用。UI 不需要认识玩家，玩家不需要认识 UI，
## 双方都只跟 EventBus 说话。这样任何一方被删掉或替换，另一方都不会崩。
##
## 约定：
##   - 信号名用「主语_动作过去式」，例如 player_died、ability_changed。
##   - 参数尽量传值或轻量数据，别传节点引用（节点会被释放，事件可能晚到）。
##     必须传节点时，接收方要先 is_instance_valid() 判断。

# ---------------------------------------------------------------------------
# 能力
# ---------------------------------------------------------------------------

## 能力集发生变化。gained/lost 是本次变动的能力 id 数组，方便 UI 做"获得/失去"表现。
signal abilities_changed(current: Array, gained: Array, lost: Array)

## 单个能力被使用（用于音效、特效、教学引导）。
signal ability_used(ability_id: StringName)


# ---------------------------------------------------------------------------
# 生命与战斗
# ---------------------------------------------------------------------------

## 任意单位血量变化。who 是节点，接收方需自行判断有效性。
signal health_changed(who: Node, current: int, maximum: int)

## 任意单位受伤。amount 是实际扣除的血量（已过防御计算）。
signal damaged(who: Node, amount: int, source: Node)

## 任意单位死亡。
signal died(who: Node)

## 玩家死亡（单独一个信号，因为 UI/流程要特殊处理）。
signal player_died

## 玩家复活完成。
signal player_respawned(at: Vector2)


# ---------------------------------------------------------------------------
# 世界与流程
# ---------------------------------------------------------------------------

## 请求切换关卡。level_id 对应 LevelRegistry 里的键；entry_id 是目标关卡的入口点名。
signal level_transition_requested(level_id: StringName, entry_id: StringName)

## 关卡加载完成。
signal level_loaded(level_id: StringName)

## 检查点被激活（长凳等）。
signal checkpoint_activated(checkpoint_id: StringName, position: Vector2)

## 玩家在长凳休息完成（血量恢复）。
signal rested_at_bench(checkpoint_id: StringName)


# ---------------------------------------------------------------------------
# 交互
# ---------------------------------------------------------------------------

## 可交互目标进入/离开范围，UI 用它显示"按 F"提示。target 可能为 null（离开）。
signal interact_prompt_changed(target: Node, prompt_text: String)

## 请求播放一段对话。speaker 是说话者显示名，lines 是逐句台词。
## 由 NPC 等交互物触发；DialogPanel 订阅后负责显示与逐句推进。
signal dialog_requested(speaker: String, lines: Array)

## 一段对话播放完毕（对话框关闭）。用于恢复玩家操作、触发后续剧情衔接等。
signal dialog_finished

## 剧情播放请求（预留，剧情编辑器接入点）。
signal cutscene_requested(cutscene_id: StringName)

## 剧情播放结束。
signal cutscene_finished(cutscene_id: StringName)


# ---------------------------------------------------------------------------
# 调试
# ---------------------------------------------------------------------------

## 调试面板要显示的一行信息，任何系统都可以往上丢。
signal debug_message(channel: StringName, text: String)
