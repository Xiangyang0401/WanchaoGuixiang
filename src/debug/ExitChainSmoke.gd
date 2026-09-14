extends Node
## 临时冒烟：验证出口→入口传送链不会形成来回切图死循环（闪屏）。
## 做法：正常流程启动（bf_00），把玩家瞬移到右出口触发区里，
## 等切图完成后记录落点，再连续跑几百帧物理，
## 断言期间没有发生第二次切图（没有回弹）。
## 用完可删。

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var mgr: LevelManager = get_parent() as LevelManager
	if mgr == null:
		# 直接 F6 运行本场景时兜底：自己加载 Main。
		var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate() as LevelManager
		get_tree().root.add_child.call_deferred(main)
		get_tree().current_scene = main
		await get_tree().process_frame
		await get_tree().process_frame
		mgr = main

	var player := mgr.get_player()
	print("[smoke] 起始关: ", GameState.current_level_id)

	# 记录每一次切图请求与完成，用于诊断回弹。
	EventBus.level_transition_requested.connect(
		func(id, entry): print("[smoke]   请求切图 → ", id, " / ", entry))
	EventBus.level_loaded.connect(
		func(id): print("[smoke]   加载完成: ", id, " 玩家@", mgr.get_player().global_position))

	var visited: Array[String] = []
	GameState.stage_changed.connect(func(_s): pass)

	# 依次冲过每一关的右出口：把玩家直接放进右出口触发区中心。
	var order := [&"battlefield_00", &"battlefield_01", &"battlefield_02", &"battlefield_03", &"battlefield_04"]
	for target in order:
		# 确保在目标关上。
		if GameState.current_level_id != target:
			mgr.load_level(target, &"default")
			await get_tree().process_frame
			await get_tree().process_frame
		var level := mgr.get_current_level()
		var exit_right: LevelExit = null
		for node in level.find_children("*", "Area2D", true, false):
			var ex := node as LevelExit
			if ex != null and ex.direction > 0:
				exit_right = ex
				break
		if exit_right == null:
			print("[smoke] ", target, " 无右出口（终点关），跳过")
			continue

		visited.append(String(target))
		# 玩家放进触发区中心（shape 可能相对节点有偏移，以 shape 全局位置为准）。
		var shape := exit_right.get_node("CollisionShape2D") as CollisionShape2D
		player.teleport_to(shape.global_position + Vector2(0, 96))
		# 等待切图发生。
		var switched := false
		for i in 60:
			await get_tree().physics_frame
			if GameState.current_level_id != target:
				switched = true
				break
		print("[smoke] ", target, " → ", GameState.current_level_id, " switched=", switched)
		if not switched:
			print("[smoke] FAIL: 右出口未触发切图: ", target)
			get_tree().quit(1)
			return
		await get_tree().physics_frame

		# 关键断言：落点稳定后 60 帧内不得再切图（否则就是回弹循环）。
		var after_switch := GameState.current_level_id
		var bounce := false
		for i in 60:
			await get_tree().physics_frame
			if GameState.current_level_id != after_switch:
				bounce = true
				break
		if bounce:
			print("[smoke] FAIL: 切图后被回弹（", after_switch, " → ", GameState.current_level_id, "）——入口与出口触发区重叠")
			get_tree().quit(1)
			return
		print("[smoke] 落点稳定: ", after_switch)

	print("[smoke] 全部通过：右向出口链 ", " → ".join(visited), " 无回弹")
	get_tree().quit(0)
