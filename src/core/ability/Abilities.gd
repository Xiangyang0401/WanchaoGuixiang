class_name Abilities
extends RefCounted
## 能力的「字典」——所有能力 id 和阶段快照的唯一定义处。
##
## 设计要点（这是整个项目最核心的架构决策）：
##   能力是数据，不是代码分支。
##   PlayerController 里二段跳/冲刺/滑翔的代码从第一天起就全部写好并常驻，
##   能不能用只取决于运行时查询 ability_set.has(X)。
##   剧情节点做的唯一一件事，是把整个能力集换成另一个快照。
##
## 为什么用「快照」而不是「逐个 add/remove」：
##   逐个加减会产生大量中间状态组合，测试量爆炸，而且很容易加漏导致残留。
##   快照切换保证任意时刻的能力集都是设计上明确存在的状态之一，
##   策划改一个枚举值就能跳到任意阶段做测试，不用打通关。

# ---------------------------------------------------------------------------
# 能力 id
# ---------------------------------------------------------------------------
# 用 StringName 而不是 int 枚举，因为将来能力可能由外部数据（json/资源）配置，
# 字符串 id 跨数据边界更稳，也更好读日志。

## —— 年轻阶段的三个能力（潮的赠礼）——
const DOUBLE_JUMP := &"double_jump"      ## 二段跳：主动对抗重力
const DASH := &"dash"                    ## 疾风冲刺
const CLEAVE := &"cleave"                ## 锋锐切割：唯一的攻击手段

## —— 成熟阶段的三个能力 ——
const GLIDE := &"glide"                  ## 滑翔：顺势而为，从高处飘落
const INSIGHT := &"insight"              ## 洞察：看穿迷雾与幻象（表里世界切换）
const SOOTHE := &"soothe"                ## 安抚：转化障碍，使其成为路径的一部分

## —— 基础能力（永不失去，仅为统一查询接口而存在）——
const WALK := &"walk"
const JUMP := &"jump"                    ## 一段跳
const INTERACT := &"interact"            ## F 键交互


## 所有能力的元数据。UI 显示、调试面板、教学提示都从这里取，不要在别处硬编码文案。
const META := {
	WALK:        {"name": "行走", "desc": "基础移动", "permanent": true},
	JUMP:        {"name": "跳跃", "desc": "基础跳跃", "permanent": true},
	INTERACT:    {"name": "交互", "desc": "与世界对话", "permanent": true},

	DOUBLE_JUMP: {"name": "二段跳", "desc": "在空中再次起跳", "permanent": false},
	DASH:        {"name": "疾风冲刺", "desc": "向前急速突进", "permanent": false},
	CLEAVE:      {"name": "锋锐切割", "desc": "斩断挡在面前的一切", "permanent": false},

	GLIDE:       {"name": "滑翔", "desc": "从高处顺势飘落", "permanent": false},
	INSIGHT:     {"name": "洞察", "desc": "看穿迷雾与幻象", "permanent": false},
	SOOTHE:      {"name": "安抚", "desc": "让障碍成为路径的一部分", "permanent": false},
}


# ---------------------------------------------------------------------------
# 阶段快照
# ---------------------------------------------------------------------------
# 故事推进 = 在这些快照之间切换。策划改这张表就能重排整个能力演化路径，
# 不需要动任何一行控制器代码。
#
# 文档设定：先一个一个失去，全部失去后到达低谷，然后一个一个获得新能力。
# 血量上限 = BASE_MAX_HP - 已失去的年轻能力数（见 Stage.hp_penalty）。

enum Stage {
	TUTORIAL_AWAKE,     ## 教学·苏醒：只能移动与交互（出生点、地图一）
	TUTORIAL_JUMP,      ## 教学·跳跃：解锁一段跳（地图二）
	TUTORIAL_DASH,      ## 教学·冲刺：解锁疾风冲刺（地图三）
	YOUNG,              ## 序章·古战场：三个年轻能力齐全，潮还在
	LOST_CLEAVE,        ## 失去锋锐切割：不再能攻击
	LOST_DASH,          ## 再失去疾风冲刺
	LOST_ALL,           ## 三个都失去，低谷点
	GAINED_SOOTHE,      ## 获得安抚
	GAINED_INSIGHT,     ## 获得洞察
	MATURE,             ## 三个成熟能力齐全，终局
}


## 基础能力，每个快照都自动包含，不必重复列。
const BASE_ABILITIES: Array[StringName] = [WALK, JUMP, INTERACT]


## 阶段定义表。
##   abilities  —— 该阶段额外拥有的能力（BASE_ABILITIES 自动附加）
##   hp_penalty —— 相对基础血上限的减值，对应"每失去一个能力血上限降低1点"
##   auto_regen —— 血量是否随时间自动恢复。
##                 年轻时潮还在照料你，伤会自己好；
##                 成熟后必须找到长凳休息才能恢复——这是主题的机制表达。
const STAGES := {
	Stage.TUTORIAL_AWAKE: {
		"label": "苏醒",
		"abilities": [],
		"remove": [JUMP],
		"hp_penalty": 0,
		"auto_regen": true,
	},
	Stage.TUTORIAL_JUMP: {
		"label": "学会跳跃",
		"abilities": [],
		"hp_penalty": 0,
		"auto_regen": true,
	},
	Stage.TUTORIAL_DASH: {
		"label": "学会冲刺",
		"abilities": [DASH],
		"hp_penalty": 0,
		"auto_regen": true,
	},
	Stage.YOUNG: {
		"label": "年轻",
		"abilities": [DOUBLE_JUMP, DASH, CLEAVE],
		"hp_penalty": 0,
		"auto_regen": true,
	},
	Stage.LOST_CLEAVE: {
		"label": "失去锋锐切割",
		"abilities": [DOUBLE_JUMP, DASH],
		"hp_penalty": 1,
		"auto_regen": true,
	},
	Stage.LOST_DASH: {
		"label": "失去疾风冲刺",
		"abilities": [DOUBLE_JUMP],
		"hp_penalty": 2,
		"auto_regen": true,
	},
	Stage.LOST_ALL: {
		"label": "一无所有",
		"abilities": [],
		"hp_penalty": 3,
		"auto_regen": false,
	},
	Stage.GAINED_SOOTHE: {
		"label": "获得安抚",
		"abilities": [SOOTHE],
		"hp_penalty": 3,
		"auto_regen": false,
	},
	Stage.GAINED_INSIGHT: {
		"label": "获得洞察",
		"abilities": [SOOTHE, INSIGHT],
		"hp_penalty": 3,
		"auto_regen": false,
	},
	Stage.MATURE: {
		"label": "成熟",
		"abilities": [SOOTHE, INSIGHT, GLIDE],
		"hp_penalty": 3,
		"auto_regen": false,
	},
}


## 取某阶段的完整能力列表（含基础能力）。
## 阶段可选 "remove" 列表：从结果里剔除（教学期收走跳跃等基础能力用）。
static func abilities_for_stage(stage: Stage) -> Array[StringName]:
	var out: Array[StringName] = []
	out.append_array(BASE_ABILITIES)
	var data: Dictionary = STAGES.get(stage, {})
	for a in data.get("abilities", []):
		out.append(a)
	for a in data.get("remove", []):
		out.erase(a)
	return out


## 取能力显示名，查不到就返回 id 本身（方便发现配置遗漏）。
static func display_name(id: StringName) -> String:
	var m: Dictionary = META.get(id, {})
	return m.get("name", String(id))


static func stage_label(stage: Stage) -> String:
	var data: Dictionary = STAGES.get(stage, {})
	return data.get("label", "未知阶段")
