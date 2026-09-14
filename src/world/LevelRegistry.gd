class_name LevelRegistry
extends RefCounted
## 关卡注册表 —— 关卡 id 到场景文件的映射。
##
## 为什么不直接在 LevelExit 里填场景路径：
##   填路径的话，改文件名或挪目录会让所有引用它的出口失效，而且很难查。
##   用 id 中转后，改文件只需要动这一张表。
##
## 策划新增一张地图的流程：
##   1. 复制 scenes/levels/ 下的模板，改名
##   2. 在这张表里加一行
##   3. 在相邻地图放 LevelExit，填上新 id

const LEVELS := {
	# —— 古战场（序章·初始区域）——
	&"battlefield_01": "res://scenes/levels/Battlefield01.tscn",
	&"battlefield_02": "res://scenes/levels/Battlefield02.tscn",
	&"battlefield_03": "res://scenes/levels/Battlefield03.tscn",
	&"battlefield_04": "res://scenes/levels/Battlefield04.tscn",

	# —— 调试 ——
	&"test": "res://scenes/levels/TestLevel.tscn",
}


## 注意：不能叫 get_path。类名字面量本身是个 Script（Resource 子类），
## 它自带无参的 get_path()，同名静态方法会被内置方法压住，调用时报参数数量不符。
static func scene_path(level_id: StringName) -> String:
	return LEVELS.get(level_id, "")


static func exists(level_id: StringName) -> bool:
	return LEVELS.has(level_id)


static func all_ids() -> Array:
	return LEVELS.keys()
