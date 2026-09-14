extends Node
## 一次性工具：把 ASCII 图烘焙成真正的关卡场景文件。
##
## 用法：
##   Godot ... --headless --path . res://scenes/tools/BakeTestLevel.tscn
##
## 为什么需要这个：
##   之前 TestLevel 的地形是运行时用 TestLevelBuilder 生成的，
##   场景文件里空空如也 —— 在编辑器里打开画布上什么都没有，更没法改。
##   跑完这个工具后，TestLevel.tscn 变成一个普通场景：
##   瓦片、入口、长凳、敌人全都是实实在在的节点，双击就能编辑。
##
## 【会覆盖 TestLevel.tscn】
##   如果你已经在编辑器里手改过测试关，跑这个会把改动冲掉。
##   ASCII 图只是"第一版草稿"的生成方式，烘焙之后就该以场景文件为准。

const OUT_PATH := "res://scenes/levels/TestLevel.tscn"


func _ready() -> void:
	var level := Level.new()
	level.name = "TestLevel"
	level.level_id = &"test"
	level.display_name = "系统验证关"
	level.bounds_padding_tiles = 1.0

	var builder := TestLevelBuilder.new()
	# 这里传 true：烘焙模式下要把生成的节点 owner 设成 level，
	# 否则 PackedScene.pack() 会认为它们是"运行时临时节点"而全部丢弃，
	# 存出来又是一个空场景。
	builder.build(level)
	builder.free()

	var packed := PackedScene.new()
	var err := packed.pack(level)
	if err != OK:
		push_error("打包失败：%d" % err)
		get_tree().quit(1)
		return

	err = ResourceSaver.save(packed, OUT_PATH)
	level.free()

	if err != OK:
		push_error("保存失败：%d" % err)
		get_tree().quit(1)
		return

	print("[烘焙] 测试关已写入：", OUT_PATH)
	print("       现在可以在编辑器里直接打开并编辑它。")
	get_tree().quit()
