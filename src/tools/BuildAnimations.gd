extends SceneTree
## 一次性工具：把裁剪好的一段跳 / 二段跳帧，追加进 player_frames.tres（SpriteFrames）。
## 保留现有 idle/run/jump/fall 等动画不动，只新增 jump_start（一段跳）和 jump_air（二段跳）。
##
## 用法：Godot --headless --path . --script res://src/tools/BuildAnimations.gd
## 注意：运行前请先跑过一次 --import，让新裁剪帧能被 res:// 加载。

const FRAMES_PATH := "res://data/player/player_frames.tres"

# 一段跳（曲腿蓄力→前倾起跳），帧号 1-based
const JUMP_START_FRAMES := [30, 31, 32, 33, 34, 46, 47, 48, 49, 50, 51, 52]
# 二段跳（直立舒展踮脚），帧号 1-based
const AIR_FRAMES := [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29]

# 冲刺：直接引用 player_run_crop 里前倾幅度最大的 4 帧
# （蹬地→大跨步→收膝→前跨），不用重新生成帧。
const DASH_FRAMES := [1, 12, 11, 7]

# 攻击（待机起手→提膝蓄势→弓步平刺→收招回待机），帧号 1-based（源帧号=产物帧号）。
# 跳过了 AI 误加剑尖白光的 17/18 帧。
# 与帧号一一对应的时长权重（1.0=标准帧）：蓄势段拖出"引而不发"的从容，
# 刺出段压到 0.6 让"唰"的爆发集中在几帧里，收招段 1.4 从容回落——
# 快刺慢收全靠这个权重表，不是靠整体帧率。
const ATTACK_FRAMES := [1, 6, 7, 8, 10, 14, 15, 16, 19, 20, 22, 25, 27, 29, 31, 33]
const ATTACK_DURATIONS := [1.0, 1.0, 1.2, 1.2, 1.2, 1.0, 0.6, 0.6, 0.6, 0.6, 0.6, 1.0, 1.0, 1.0, 1.0, 1.2]

## 播放速度（fps）。一段跳节奏快一些，二段跳空中舒展也要求快速演完。
const JUMP_START_SPEED := 22.0
const AIR_SPEED := 42.0
const DASH_SPEED := 16.0
## 攻击：14.8 个标准帧 @ 16fps ≈ 0.93s 完整出招（蓄势 0.35s → 刺出 0.25s
## → 收招 0.33s），与 MovementProfile 的攻击三段时长对齐。
const ATTACK_SPEED := 16.0


func _initialize() -> void:
	var frames := load(FRAMES_PATH) as SpriteFrames
	if frames == null:
		print("加载 SpriteFrames 失败")
		quit(1)
		return

	_add_anim(frames, "jump_start", "player_jump_start_crop", JUMP_START_FRAMES, false, JUMP_START_SPEED)
	_add_anim(frames, "jump_air", "player_jump_air_crop", AIR_FRAMES, false, AIR_SPEED)
	_add_anim(frames, "dash", "player_run_crop", DASH_FRAMES, true, DASH_SPEED)
	_add_anim(frames, "attack", "player_attack_crop", ATTACK_FRAMES, false, ATTACK_SPEED, ATTACK_DURATIONS)

	print("现有动画：", frames.get_animation_names())
	var err := ResourceSaver.save(frames, FRAMES_PATH)
	print("保存结果 err=", err, " → ", FRAMES_PATH)
	quit(0)


func _add_anim(frames: SpriteFrames, anim_name: String, dir: String, nums: Array, loop: bool, speed: float, durations: Array = []) -> void:
	if frames.has_animation(anim_name):
		frames.remove_animation(anim_name)
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, loop)
	frames.set_animation_speed(anim_name, speed)

	var added := 0
	for n in nums:
		var path := "res://assets/animation/%s/%s.png" % [dir, str(n).pad_zeros(3)]
		var tex: Texture2D = load(path)
		if tex != null:
			# per-frame 时长权重：默认 1.0；攻击动画用它做快刺慢收的节奏。
			var d := 1.0
			if added < durations.size():
				d = durations[added]
			frames.add_frame(anim_name, tex, d)
			added += 1
		else:
			print("  加载失败：", path)
	print("  [%s] 加了 %d 帧" % [anim_name, added])
