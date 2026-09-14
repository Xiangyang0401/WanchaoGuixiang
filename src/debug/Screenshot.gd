extends Node
## 截图工具：跑起来游戏，等画面稳定，存一张 PNG 后退出。
##
## 用途：改了美术/布局/相机之后，不开编辑器就能确认画面对不对。
## 断言能验"数值对不对"，验不了"看起来对不对"，两者都需要。
##
## 用法：
##   Godot --path . res://scenes/tools/Screenshot.tscn
##   Godot --path . res://scenes/tools/Screenshot.tscn -- --level=battlefield_01 --frames=90
##
## 【不能加 --headless】headless 没有渲染后端，截出来是全黑。
## 这点很容易忘，因为项目里其他工具脚本都是 headless 跑的。

const OUT_DIR := "res://.preview"

var _level: StringName = &"battlefield_01"
var _entry: StringName = &"default"
var _frames: int = 60
var _out: String = "shot.png"

## 每隔多少帧存一张。>1 时可用来抓动画的连续几帧，看动作是否连贯。
var _burst: int = 1
var _burst_gap: int = 4

## 截图期间按住的方向（-1/0/1）。用来抓"跑起来"的样子而不是站桩。
##
## 直接改 Input 状态而不是模拟按键事件：后者要伪造 InputEventKey 并
## 匹配项目的 action 映射，改了键位就失效；前者一行搞定且与键位无关。
var _move: float = 0.0


func _ready() -> void:
	_parse_args()
	# 延后到本节点完全进树之后再挂 Main：
	# _ready 执行期间场景树还在构建，get_tree().root 拿不到，add_child 会炸。
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = ResourceLoader.load(
		"res://scenes/Main.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if packed == null:
		push_error("Main.tscn 加载失败")
		get_tree().quit(1)
		return
	var main: Node = packed.instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	var mgr := _find_manager(main)
	if mgr == null:
		push_error("找不到 LevelManager")
		get_tree().quit(1)
		return

	mgr.load_level(_level, _entry)

	if not is_zero_approx(_move):
		var act := &"move_right" if _move > 0.0 else &"move_left"
		Input.action_press(act, absf(_move))

	# 等若干帧再截：关卡加载、相机吸附、背景缩放都要几帧才稳，
	# 截早了会拍到相机还在飞向玩家的中间态。
	for _i in _frames:
		await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for n in _burst:
		if n > 0:
			for _i in _burst_gap:
				await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var name := _out if _burst == 1 else "%s_%d.png" % [_out.get_basename(), n]
		var path := ProjectSettings.globalize_path(OUT_DIR + "/" + name)
		img.save_png(path)
		print("  截图: ", path)

	get_tree().quit()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0].lstrip("-"):
			"level": _level = StringName(kv[1])
			"entry": _entry = StringName(kv[1])
			"frames": _frames = int(kv[1])
			"out": _out = kv[1]
			"burst": _burst = int(kv[1])
			"gap": _burst_gap = int(kv[1])
			# 临时覆盖相机缩放，用来对比不同视野下的观感。
			# 只影响本次进程，不写回 GameConfig 源文件。
			"zoom": GameConfig.camera_zoom = float(kv[1])
			"move": _move = float(kv[1])


func _find_manager(root: Node) -> LevelManager:
	if root is LevelManager:
		return root
	for c in root.get_children():
		var r := _find_manager(c)
		if r != null:
			return r
	return null
