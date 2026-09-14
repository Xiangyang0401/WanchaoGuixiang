extends Node
## 系统自检脚本（headless 运行，不需要人工操作）。
##
## 用法：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . res://scenes/SelfTest.tscn
##
## 为什么走场景而不是 --script：
##   --script 模式下 autoload 不会被加载，GameConfig / EventBus / GameState 全都取不到。
##   自检的意义正是验证真实运行环境，所以必须以场景方式启动。
##
## 它会实际加载主场景、模拟若干物理帧，检查各系统是否按预期工作。
## 这不是替代手动试玩，而是保证「基础管线没断」——
## 场景能加载、玩家能生成、能力切换生效、伤害能结算、复活流程能跑通。
##
## 每次改完核心系统跑一遍，能在你打开编辑器之前就发现低级错误。

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	_start.call_deferred()


func _start() -> void:
	await _run_all()
	_report()
	get_tree().quit(1 if _failures.size() > 0 else 0)


# ---------------------------------------------------------------------------
# 断言工具
# ---------------------------------------------------------------------------

func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  [OK]   %s" % label)
	else:
		var msg := label if detail == "" else "%s  ← %s" % [label, detail]
		print("  [FAIL] %s" % msg)
		_failures.append(msg)


func _eq(label: String, actual, expected) -> void:
	_check(label, actual == expected, "实际 %s，期望 %s" % [str(actual), str(expected)])


## 推进 n 个物理帧。
func _step(n: int = 1) -> void:
	for i in n:
		await get_tree().physics_frame


func _report() -> void:
	print("")
	print("=".repeat(60))
	if _failures.is_empty():
		print("全部通过：%d 项检查" % _checks)
	else:
		print("失败 %d / %d：" % [_failures.size(), _checks])
		for f in _failures:
			print("   - %s" % f)
	print("=".repeat(60))


# ---------------------------------------------------------------------------
# 测试主体
# ---------------------------------------------------------------------------

func _run_all() -> void:
	print("")
	print("=".repeat(60))
	print("万潮归乡 · 系统自检")
	print("=".repeat(60))

	await _test_ability_data()
	await _test_ability_set()
	await _test_scene_boot()


## 1. 能力表数据自洽性（纯数据，不需要场景）
func _test_ability_data() -> void:
	print("\n[1] 能力表数据")

	_eq("阶段数量", Abilities.STAGES.size(), Abilities.Stage.size())

	for key in Abilities.Stage.keys():
		var stage: int = Abilities.Stage[key]
		_check("阶段 %s 已定义" % key, Abilities.STAGES.has(stage))

	# 每个阶段列出的能力都必须在 META 里有条目，否则 UI 会显示成裸 id。
	for stage in Abilities.STAGES.keys():
		var data: Dictionary = Abilities.STAGES[stage]
		for a in data.get("abilities", []):
			_check("能力 %s 有 META 条目" % a, Abilities.META.has(a))

	# 血量惩罚必须单调不减（失去能力不会让上限回升）
	var order := [
		Abilities.Stage.YOUNG, Abilities.Stage.LOST_CLEAVE,
		Abilities.Stage.LOST_DASH, Abilities.Stage.LOST_ALL,
	]
	var prev := -1
	var monotonic := true
	for s in order:
		var p: int = Abilities.STAGES[s]["hp_penalty"]
		if p < prev:
			monotonic = false
		prev = p
	_check("失去阶段的血量惩罚单调不减", monotonic)

	# 文档设定：年轻时自动回血，一无所有之后必须找长凳
	_eq("YOUNG 自动回血", Abilities.STAGES[Abilities.Stage.YOUNG]["auto_regen"], true)
	_eq("LOST_ALL 不自动回血", Abilities.STAGES[Abilities.Stage.LOST_ALL]["auto_regen"], false)
	_eq("MATURE 不自动回血", Abilities.STAGES[Abilities.Stage.MATURE]["auto_regen"], false)


## 2. AbilitySet 快照切换
func _test_ability_set() -> void:
	print("\n[2] 能力集快照切换")

	var s := AbilitySet.new(Abilities.Stage.YOUNG)
	_check("YOUNG 有二段跳", s.has(Abilities.DOUBLE_JUMP))
	_check("YOUNG 有冲刺", s.has(Abilities.DASH))
	_check("YOUNG 有切割", s.has(Abilities.CLEAVE))
	_check("YOUNG 无滑翔", not s.has(Abilities.GLIDE))
	_check("基础能力常驻", s.has(Abilities.WALK) and s.has(Abilities.JUMP) and s.has(Abilities.INTERACT))
	_eq("YOUNG 血量惩罚", s.hp_penalty(), 0)

	# 信号要能正确报出本次的增减。
	# 注意：GDScript 的 lambda 按值捕获局部变量，在闭包里对 var 赋值不会传回外部。
	# 所以这里用 Dictionary（引用类型）原地改，否则断言永远读到初值。
	var rec := {"gained": [], "lost": [], "fired": false}
	s.changed.connect(func(_c, g, l):
		rec["gained"] = g.duplicate()
		rec["lost"] = l.duplicate()
		rec["fired"] = true
	)

	s.set_stage(Abilities.Stage.LOST_CLEAVE)
	_check("切到 LOST_CLEAVE 失去切割", not s.has(Abilities.CLEAVE))
	_check("切割仍保留二段跳", s.has(Abilities.DOUBLE_JUMP))
	_check("changed 报出 lost=cleave", (rec["lost"] as Array).has(Abilities.CLEAVE))
	_eq("LOST_CLEAVE 血量惩罚", s.hp_penalty(), 1)

	s.set_stage(Abilities.Stage.LOST_ALL)
	_check("LOST_ALL 三个能力全失", not s.has(Abilities.DOUBLE_JUMP)
		and not s.has(Abilities.DASH) and not s.has(Abilities.CLEAVE))
	_check("LOST_ALL 基础能力仍在", s.has(Abilities.WALK))
	_eq("LOST_ALL 不自动回血", s.auto_regen(), false)

	s.set_stage(Abilities.Stage.MATURE)
	_check("MATURE 有滑翔", s.has(Abilities.GLIDE))
	_check("MATURE 有洞察", s.has(Abilities.INSIGHT))
	_check("MATURE 有安抚", s.has(Abilities.SOOTHE))
	_check("MATURE 无二段跳", not s.has(Abilities.DOUBLE_JUMP))
	_check("changed 报出 gained 含滑翔", (rec["gained"] as Array).has(Abilities.GLIDE))

	# 重复设置同一阶段不应触发变更
	rec["fired"] = false
	s.set_stage(Abilities.Stage.MATURE)
	_check("重复设置同阶段不触发信号", not rec["fired"])


## 3. 真实场景启动 + 玩家/敌人/伤害/复活
func _test_scene_boot() -> void:
	print("\n[3] 场景启动与运行时")

	var packed := load("res://scenes/Main.tscn") as PackedScene
	_check("Main.tscn 可加载", packed != null)
	if packed == null:
		return

	var main := packed.instantiate()
	get_tree().root.add_child(main)
	await _step(6)

	var mgr := main as LevelManager
	_check("根节点是 LevelManager", mgr != null)
	if mgr == null:
		return

	var player := mgr.get_player()
	_check("玩家已生成", player != null)
	var level := mgr.get_current_level()
	_check("关卡已加载", level != null)
	if player == null or level == null:
		return

	_eq("当前关卡 id", String(GameState.current_level_id), "test")
	_check("关卡有默认入口", level.get_entry(&"default") != null)

	# --- 地形与重力 ---
	var y0 := player.global_position.y
	await _step(45)
	_check("玩家受重力下落并被地形接住", player.is_on_floor(),
		"y: %.1f -> %.1f, on_floor=%s" % [y0, player.global_position.y, str(player.is_on_floor())])

	# --- 相机限位 ---
	var bounds := level.get_world_bounds()
	_check("关卡边界非退化", bounds.size.x > 100 and bounds.size.y > 100,
		"bounds=%s" % str(bounds))

	# --- 敌人生成 ---
	var enemies := get_tree().get_nodes_in_group(&"enemy")
	_check("敌人已生成", enemies.size() >= 3, "数量=%d" % enemies.size())

	# --- 巡逻怪会动 ---
	var patroller: Enemy = null
	for e in enemies:
		if (e as Enemy).behavior is PatrolBehavior:
			patroller = e
			break
	_check("存在巡逻怪", patroller != null)
	if patroller != null:
		await _step(30)
		var x0: float = patroller.global_position.x
		await _step(40)
		_check("巡逻怪发生位移", absf(patroller.global_position.x - x0) > 4.0,
			"位移=%.2f" % absf(patroller.global_position.x - x0))

	# --- 静止怪不动 ---
	var stationary: Enemy = null
	for e in enemies:
		if (e as Enemy).behavior is StationaryBehavior:
			stationary = e
			break
	_check("存在静止怪", stationary != null)
	if stationary != null:
		var sx: float = stationary.global_position.x
		await _step(40)
		_check("静止怪原地不动", absf(stationary.global_position.x - sx) < 2.0,
			"位移=%.2f" % absf(stationary.global_position.x - sx))

	# --- 血量与伤害 ---
	var hp_before: int = player.health.current_hp
	_eq("初始血量满", hp_before, player.health.max_hp)

	var dmg := DamageInfo.create(1, null, 0.0)
	player.health.take_damage(dmg)
	_eq("受伤后血量 -1", player.health.current_hp, hp_before - 1)
	_check("受伤后进入无敌", player.health.is_invulnerable())
	_check("受伤后进入硬直状态", player.state == Player.State.HITSTUN,
		"state=%s" % player.state_name())

	# --- 无敌帧生效 ---
	var hp_mid: int = player.health.current_hp
	player.health.take_damage(DamageInfo.create(1, null, 0.0))
	_eq("无敌帧内二次伤害被挡", player.health.current_hp, hp_mid)

	# --- ignore_invulnerability 能穿透 ---
	var pierce := DamageInfo.create(1, null, 0.0)
	pierce.ignore_invulnerability = true
	player.health.take_damage(pierce)
	_eq("穿透伤害生效", player.health.current_hp, hp_mid - 1)

	# --- 硬直会自然结束 ---
	await _step(30)
	_check("硬直结束回到 NORMAL", player.state == Player.State.NORMAL,
		"state=%s" % player.state_name())

	# --- 能力剥夺影响血上限 ---
	var max_before: int = player.health.max_hp
	GameState.stage = Abilities.Stage.LOST_ALL
	await _step(3)
	_eq("失去三能力后血上限 -3", player.health.max_hp, max_before - 3)
	_check("失去能力后不再自动回血", not player.health.auto_regen)
	_check("玩家能力集已同步", not player.abilities.has(Abilities.DASH))

	# --- 攻击能力被剥夺后，攻击判定不会激活 ---
	player.health.heal_full()
	await _step(2)
	_check("无切割能力时攻击判定关闭", not player.attack_hitbox.is_active())

	# --- 切回年轻，攻击应可用 ---
	GameState.stage = Abilities.Stage.YOUNG
	await _step(3)
	_eq("回到 YOUNG 血上限恢复", player.health.max_hp, max_before)
	_check("回到 YOUNG 恢复自动回血", player.health.auto_regen)
	_check("回到 YOUNG 重新拥有切割", player.abilities.has(Abilities.CLEAVE))

	# --- 死亡与复活 ---
	var kill := DamageInfo.create(999, null, 0.0)
	kill.ignore_invulnerability = true
	player.health.take_damage(kill)
	await _step(2)
	_check("血量归零判定死亡", player.health.is_dead())
	_check("死亡后进入 DEAD 状态", player.state == Player.State.DEAD,
		"state=%s" % player.state_name())

	mgr.respawn_player()
	await _step(3)
	_check("复活后血量回满", player.health.current_hp == player.health.max_hp)
	_check("复活后离开 DEAD 状态", player.state != Player.State.DEAD)
	_check("复活后有保护性无敌", player.health.is_invulnerable())

	var respawn_pos := level.get_default_respawn()
	_check("无检查点时回默认复活点",
		player.global_position.distance_to(respawn_pos) < 4.0,
		"pos=%s expect=%s" % [str(player.global_position), str(respawn_pos)])

	# --- 长凳检查点 ---
	var benches := get_tree().get_nodes_in_group(&"bench")
	_check("测试关有长凳", benches.size() > 0)
	if benches.size() > 0:
		var bench := benches[0] as Bench
		bench.interact(player)
		await _step(2)
		_check("交互长凳后记录检查点", GameState.has_checkpoint())
		_eq("检查点关卡正确", String(GameState.active_checkpoint_level), "test")

		# 再死一次，应该回到长凳而不是默认点
		var kill2 := DamageInfo.create(999, null, 0.0)
		kill2.ignore_invulnerability = true
		player.health.take_damage(kill2)
		await _step(2)
		mgr.respawn_player()
		await _step(3)
		_check("检查点复活优先于默认复活点",
			player.global_position.distance_to(GameState.active_checkpoint_position) < 4.0,
			"pos=%s cp=%s" % [str(player.global_position), str(GameState.active_checkpoint_position)])

	# --- 关卡注册表 ---
	_check("LevelRegistry 含 test", LevelRegistry.exists(&"test"))

	# --- 注册表里每个 id 的场景文件都必须真实存在 ---
	# 漏建文件的话，玩家走到边界切图时会直接卡死，而且只在跑到那一关才暴露。
	for id in LevelRegistry.all_ids():
		var p: String = LevelRegistry.scene_path(id)
		_check("关卡 %s 的场景文件存在" % id, ResourceLoader.exists(p), p)

	await _test_hud_layout(mgr)
	await _test_level_background(mgr)
	await _test_player_visual(mgr, player)
	await _test_camera_framing(mgr, player)
	await _test_dialog(mgr, player)
	await _test_npc_interactor(mgr, player)
	await _test_level_transition(mgr, player)
	await _test_fall_out(mgr, player)

	main.queue_free()
	await _step(2)


## 8. HUD 面板的真实屏幕位置。
##
## 为什么要单独一条：visible=true 只说明节点没被隐藏，跟"玩家能不能看见"
## 是两码事——屏幕外的节点 visible 照样是 true。DialogPanel 就栽在这里：
## 零尺寸容器把 1456px 宽的框顶到了 y=1920（屏幕底边外），逻辑断言全绿，
## 玩家却只看到画面定住，误以为卡死。
##
## 所以这里量的是几何：面板必须有非零尺寸，且完整落在可见区域内。
## 布局类 bug 引擎不会报错（屏幕外 UI 是滑入动画的合法用法），只能靠断言兜。
func _test_hud_layout(mgr: LevelManager) -> void:
	print("\n[8] HUD 面板屏幕位置")

	var hud := mgr.get_node_or_null("HUD")
	_check("HUD 存在", hud != null)
	if hud == null:
		return

	var vr := Rect2(Vector2.ZERO, mgr.get_viewport().get_visible_rect().size)

	# 逐个把面板强制显示出来量一遍，量完还原——不能只测"当前恰好显示"的那些。
	var panels := {
		"DialogPanel": "_panel",
		"TutorialHints": "_panel",
		"InteractPrompt": "_panel",
	}
	for node_name in panels:
		var node := hud.get_node_or_null(node_name) as Control
		_check("HUD/%s 存在且脚本已挂载" % node_name, node != null)
		if node == null:
			continue

		var inner := node.get(panels[node_name]) as Control
		_check("%s 的面板已构建" % node_name, inner != null)
		if inner == null:
			continue

		var old_vis := node.visible
		var old_inner_vis := inner.visible
		node.visible = true
		inner.visible = true
		await get_tree().process_frame
		await get_tree().process_frame

		var r := inner.get_global_rect()
		_check("%s 有真实尺寸" % node_name, r.size.x > 10.0 and r.size.y > 10.0,
			"rect=%s" % str(r))
		_check("%s 完整落在屏幕内" % node_name, vr.encloses(r),
			"rect=%s viewport=%s" % [str(r), str(vr)])

		node.visible = old_vis
		inner.visible = old_inner_vis
	await get_tree().process_frame


## 9. 关卡背景图铺设。
##
## 验的是"策划把图拖进去就能用"：图有没有真的加载、缩放后能不能盖住整个关卡、
## 会不会压在地形前面挡住主角。这三条错一条，画面就是"背景没了/糊了/挡住人了"，
## 但都不会报错——只能靠断言抓。
func _test_level_background(mgr: LevelManager) -> void:
	print("\n[9] 关卡背景图")

	mgr.load_level(&"battlefield_01", &"default")
	await _step(4)
	var level := mgr.get_current_level()
	if level == null:
		_check("背景测试的关卡可用", false)
		return

	var bg := level.get_node_or_null("Background") as LevelBackground
	_check("battlefield_01 挂了 Background", bg != null)
	if bg == null:
		return

	_check("背景图已配置", bg.texture != null)
	_check("背景排在地形之后", bg.z_index < 0, "z_index=%d" % bg.z_index)

	var sprite := bg.get_node_or_null("BackgroundImage") as Sprite2D
	_check("背景 Sprite 已建出", sprite != null)
	if sprite == null or bg.texture == null:
		return
	_check("背景 Sprite 已挂上图", sprite.texture == bg.texture)

	# LEVEL 模式的核心承诺：缩放后必须完全盖住关卡边界，否则边缘会露底色。
	var bounds := level.get_world_bounds()
	var tex := Vector2(bg.texture.get_size()) * sprite.scale
	var covered := Rect2(sprite.global_position - tex * 0.5, tex)
	_check("背景盖住整个关卡", covered.encloses(bounds),
		"背景=%s 关卡=%s" % [str(covered), str(bounds)])

	# 等比缩放：图不能被拉变形（美术给的图比例必须保持）。
	_check("背景等比缩放未变形", is_equal_approx(sprite.scale.x, sprite.scale.y),
		"scale=%s" % str(sprite.scale))


## 10. 主角外观（PlayerVisual）。
##
## 序列帧接入最容易翻车的四个点，都不会报错，只能靠断言抓：
##   1. 动画根本没在播（sprite_frames 没挂上/动画名拼错）→ 角色定在第一帧
##   2. 脚底没对齐 → 角色陷进地里或浮在半空
##   3. 朝向翻了两次 → 按左走人物却朝右
##   4. 缺某个动画时整个人消失 → 只做了 run 就跳一下，角色不见了
##
## 第 2 条量的是几何：素材尺寸、缩放、offset 三者任何一个算错都会被抓到。
func _test_player_visual(mgr: LevelManager, player: Player) -> void:
	print("\n[10] 主角外观")

	var vis := player.get_node_or_null("Visual") as PlayerVisual
	_check("Visual 挂着 PlayerVisual", vis != null)
	if vis == null:
		return

	var anim := vis.get_node_or_null("Anim") as AnimatedSprite2D
	_check("AnimatedSprite2D 已建出", anim != null)
	if anim == null:
		return

	_check("SpriteFrames 已配置", vis.frames != null)
	if vis.frames == null:
		return

	# 【数据驱动】不写死"必须有 run"：跑动素材已弃用，当前只有 idle。
	# 自检锚定在"至少有一个动画可播"上；若将来重建跑动素材，
	# 下面的 has_run 分支会自动覆盖打滑/步频校验，无需再改这里。
	var names := vis.frames.get_animation_names()
	_check("至少有一个动画可播", not names.is_empty())
	if names.is_empty():
		return
	var primary: StringName = &"idle" if vis.frames.has_animation(&"idle") else names[0]
	var has_run: bool = vis.frames.has_animation(&"run")

	_check("主动画至少 4 帧", vis.frames.get_frame_count(primary) >= 4,
		"帧数=%d" % vis.frames.get_frame_count(primary))
	_check("主动画设为循环", vis.frames.get_animation_loop(primary))

	# --- 尺寸与脚底对齐 ---
	# 素材换了、缩放算错了、offset 公式改了，都会在这两条上暴露。
	var tex := anim.sprite_frames.get_frame_texture(primary, 0)
	_check("主动画第 0 帧有纹理", tex != null)
	if tex != null:
		var drawn_h := float(tex.get_height()) * anim.scale.y
		var want_h := GameConfig.tiles(vis.visual_height_tiles)
		_check("外观高度符合设定", absf(drawn_h - want_h) < 2.0,
			"实际=%.1f 期望=%.1f" % [drawn_h, want_h])
		_check("外观等比缩放未变形", is_equal_approx(anim.scale.x, anim.scale.y),
			"scale=%s" % str(anim.scale))

		# 脚底（图片底边，扣掉 foot_padding）应落在碰撞体底边上。
		var body_bottom := GameConfig.tiles(GameConfig.PLAYER_TILE_HEIGHT) * 0.5
		var art_bottom := anim.position.y + drawn_h * 0.5 - drawn_h * vis.foot_padding
		_check("脚底对齐碰撞体底边", absf(art_bottom - body_bottom) < 2.0,
			"脚底=%.1f 体底=%.1f" % [art_bottom, body_bottom])

	# --- 各动画脚底一致（防止画布高度不同导致某个动画浮空/穿地）---
	# 曾出现：scale 按 idle 统一算，但 run 画布(645px) 比 idle(702px) 矮，
	# 脚底公式又用统一 want_h，run 走路浮空 6px。idle 本身不浮空，
	# 所以上面那条抓不到，必须单独量 run——否则改了公式也没人发现修没修好。
	if has_run and vis.frames.has_animation(&"run"):
		vis.update_look(Player.State.NORMAL, Vector2.ZERO, true, 1.0)
		var run_tex := vis.frames.get_frame_texture(&"run", 0)
		if run_tex != null:
			var run_shown := float(run_tex.get_height()) * anim.scale.y
			var run_bottom := anim.position.y + run_shown * 0.5 - run_shown * vis.foot_padding
			var run_body := GameConfig.tiles(GameConfig.PLAYER_TILE_HEIGHT) * 0.5
			_check("run 脚底也贴地（不浮空）", absf(run_bottom - run_body) < 2.0,
				"run脚底=%.1f 体底=%.1f" % [run_bottom, run_body])

	# --- 状态到动画的映射 ---
	# 直接驱动组件，不依赖玩家真的跑起来——物理仿真在自检里不稳定。
	#
	# 注意：不能在两次调用之间 await。Player._post_move 每个物理帧都会
	# 按真实状态覆写一次外观，等一帧就会被"玩家其实站着不动"改回 idle。
	# 设完立刻读，测的才是本组件的映射逻辑本身。
	vis.update_look(Player.State.NORMAL, Vector2.ZERO, true, 1.0)
	_check("移动时非空白（不消失）", vis.current_animation() != &"",
		"实际=%s" % str(vis.current_animation()))
	_check("降级后确实在播（非定格）", anim.is_playing())
	if has_run:
		_check("有 run 时移动播 run", vis.current_animation() == &"run",
			"实际=%s" % str(vis.current_animation()))
	else:
		# 尚无跑动素材（已弃用）：降级链 RUN→IDLE，必须落到 idle 而不是空。
		_check("无 run 时移动降级到 idle 而非空白",
			vis.current_animation() == &"idle",
			"实际=%s" % str(vis.current_animation()))
		_check("降级到 idle 后仍播（非定格）", anim.is_playing())

	vis.update_look(Player.State.NORMAL, Vector2.ZERO, true, 0.0)
	_check("静止时播 idle", vis.current_animation() == &"idle",
		"实际=%s" % str(vis.current_animation()))

	# 缺 jump 动画时必须降级到可播的动画而不是空白。
	# 角色消失是最糟的失败模式（只做了 idle 就跳一下，人不见了）。
	# 降级链 JUMP→RUN→IDLE，最终落到 idle。
	vis.update_look(Player.State.NORMAL, Vector2(0, -100), false, 0.0)
	_check("缺 jump 时降级而非消失", vis.current_animation() != &"",
		"实际=%s" % str(vis.current_animation()))
	_check("降级后 Sprite 仍可见", anim.visible)

	# --- 二段跳 override 触发 ---
	# jump_air 是"触发一瞬间"的动作：trigger_double_jump 强制播一遍，
	# 落地或播完前 update_look 不许把它切走。这锁的是 override 链条本身。
	# 只在有 jump_air 素材时测，没有就跳过（对应"数据驱动不写死"原则）。
	if vis.frames.has_animation(&"jump_air"):
		vis.trigger_double_jump()
		_check("二段跳触发后播 jump_air", vis.current_animation() == &"jump_air",
			"实际=%s" % str(vis.current_animation()))
		# 离地时再调 update_look，应尊重 override 不切走（否则播一帧就被换掉）。
		vis.update_look(Player.State.NORMAL, Vector2(0, -100), false, 0.0)
		_check("空中二段跳不被 update_look 切走", vis.current_animation() == &"jump_air",
			"实际=%s" % str(vis.current_animation()))
		# 落地后 override 解除，回到常规逻辑（静止→idle）。
		vis.update_look(Player.State.NORMAL, Vector2.ZERO, true, 0.0)
		_check("落地后二段跳 override 解除", vis.current_animation() == &"idle",
			"实际=%s" % str(vis.current_animation()))

	# --- 朝向 ---
	# PlayerVisual 自己绝不能翻转，翻转统一由 Player 缩放父节点完成。
	# 两处都翻的话，向左走会翻两次等于没翻，且极难定位。
	player._set_facing(-1)
	await get_tree().process_frame
	_check("朝左时父节点翻转", vis.scale.x < 0.0, "scale.x=%.2f" % vis.scale.x)
	_check("朝左时 Anim 自身不翻转", anim.scale.x > 0.0 and not anim.flip_h,
		"scale.x=%.2f flip_h=%s" % [anim.scale.x, str(anim.flip_h)])
	player._set_facing(1)
	await get_tree().process_frame
	_check("朝右时父节点恢复", vis.scale.x > 0.0, "scale.x=%.2f" % vis.scale.x)

	# --- 播放速度与角色移速的匹配（脚底打滑检测）---
	#
	# 只在有跑动素材时才有意义：没有 run 就没法量"腿摆一个周期人滑多远"。
	# 但 idle 也不是随便什么帧率都行——呼吸循环太慢像定格、太快像抽搐，
	# 帧率必须落在人类可信区间。二者分开处理。
	if has_run:
		# 「脚底打滑」= 腿摆一个周期，人却滑出远超一步能跨的距离。
		# 它不会报错、不影响玩法，但是横版游戏里最掉档次的瑕疵之一，
		# 而且极容易在调完移速后悄悄出现——所以必须让机器盯着。
		#
		# 判据用「步幅 / 身高」而非绝对像素：人跑步一步大约跨 0.6~0.9 个身高，
		# 这个比例与角色大小无关，改 TILE_SIZE 或主角尺寸都不用重调阈值。
		var fps: float = vis.frames.get_animation_speed(&"run")
		_check("run 播放帧率已设置", fps > 0.0, "fps=%.1f" % fps)
		if fps > 0.0:
			var cycle: float = vis.frames.get_frame_count(&"run") / fps
			var body_h: float = GameConfig.tiles(GameConfig.PLAYER_TILE_HEIGHT)
			# 一个周期迈两步，所以除以 2。
			var stride: float = player.profile.run_speed() * cycle * 0.5
			var ratio: float = stride / body_h

			print("      · 步幅 %.0f px = %.2f 身高（周期 %.2fs，移速 %.0f px/s）"
				% [stride, ratio, cycle, player.profile.run_speed()])

			# 上限 1.1：正常跑步 0.6~0.9 身高，留两成余量给"跑得稍夸张"的设计。
			# 别把上限放得更宽——1.3 以上肉眼就能看出腿在原地划、人在滑行了。
			_check("跑动不打滑（步幅在合理区间）", ratio >= 0.4 and ratio <= 1.1,
				"步幅=%.2f 身高，建议 0.6~0.9；偏大就调低 run_speed 或调高 run 的 fps" % ratio)

			# 周期也要在人类可信范围内。帧率开太高会"腿频快进"，
			# 这时步幅比例是达标的，光看上面那条查不出来。
			_check("步频自然（周期在人类范围内）", cycle >= 0.35 and cycle <= 1.1,
				"周期=%.2fs，正常跑步 0.5~0.8s" % cycle)
	else:
		# 无跑动素材：锁 idle 的呼吸循环节奏。
		# 待机通常是人呼吸/微动，一个循环 1.5~4s 像活人；
		# <1s 像在发抖，>5s 像定格，都不自然。
		var idle_fps: float = vis.frames.get_animation_speed(&"idle")
		_check("idle 播放帧率已设置", idle_fps > 0.0, "fps=%.1f" % idle_fps)
		if idle_fps > 0.0:
			var idle_cycle: float = vis.frames.get_frame_count(&"idle") / idle_fps
			print("      · 待机循环 %.2fs（%d 帧 @ %.1f fps）"
				% [idle_cycle, vis.frames.get_frame_count(&"idle"), idle_fps])
			_check("idle 呼吸循环节奏自然", idle_cycle >= 1.0 and idle_cycle <= 5.0,
				"周期=%.2fs，建议 1.5~4s" % idle_cycle)

	vis.update_look(Player.State.NORMAL, Vector2.ZERO, true, 0.0)
	await get_tree().process_frame


## 11. 相机构图与 zoom 解耦。
##
## 这条锁的是一个架构承诺：**改 camera_zoom 不该影响构图**。
##
## 早期 offset/lookahead 用绝对格数，zoom 从 1.0 拉到 2.0 后视野减半，
## 8 格的偏移相对占比翻倍，角色被直接挤出画面底部。改 zoom 是纯观感操作，
## 不该逼着人回头重调另外两个参数——耦合一旦留下，以后每次调视野都要踩一次。
##
## 验法：在几档 zoom 下量"玩家在屏幕上的相对位置"，必须基本一致。
func _test_camera_framing(mgr: LevelManager, player: Player) -> void:
	print("\n[11] 相机构图与缩放解耦")

	var cam := _find_camera(mgr)
	_check("找得到 PlayerCamera", cam != null)
	if cam == null:
		return

	var saved := GameConfig.camera_zoom
	# 静止在地面上量，排除 lookahead 和跟随平滑的干扰。
	player.velocity = Vector2.ZERO

	var ratios: Array[Vector2] = []
	for z in [1.0, 2.0, 3.0]:
		GameConfig.camera_zoom = z
		# 相机每物理帧读一次配置，等几帧让平滑收敛到位。
		await _step(20)
		var view := GameConfig.visible_world_size()
		# 玩家相对屏幕中心的偏移，换算成占屏比例（-0.5~0.5）。
		var d := player.global_position - cam.global_position
		ratios.append(d / view)

	GameConfig.camera_zoom = saved
	await _step(4)

	var base: Vector2 = ratios[0]
	for i in range(1, ratios.size()):
		var r: Vector2 = ratios[i]
		# 容差 0.05 = 5% 屏幕。留这么宽是因为限位在小关卡里会强制夹住相机，
		# 那属于合理行为；真正要抓的是"翻倍级"的构图漂移。
		_check("zoom 变化不影响构图（第 %d 档）" % (i + 1),
			absf(r.y - base.y) < 0.05 and absf(r.x - base.x) < 0.05,
			"基准=%s 实际=%s" % [str(base), str(r)])

	# 构图本身也要合理：角色应在画面中心偏下，而不是贴边或跑到画面外。
	_check("玩家落在画面内", absf(base.y) < 0.5 and absf(base.x) < 0.5,
		"相对位置=%s" % str(base))
	_check("玩家位于画面中心偏下", base.y > 0.0,
		"相对位置=%s（正值表示在中心下方）" % str(base))

	# 配置本身不该再出现绝对格数版本的旧字段，防止有人改回去。
	_check("相机偏移用比例而非绝对格数",
		GameConfig.get("camera_offset_tiles") == null
			and GameConfig.get("camera_lookahead_tiles") == null)


func _find_camera(root: Node) -> PlayerCamera:
	if root is PlayerCamera:
		return root
	for c in root.get_children():
		var r := _find_camera(c)
		if r != null:
			return r
	return null


## 4. NPC 对话：触发 -> 世界暂停 -> 逐句推进 -> 播完恢复。
##
## 验收点：Npc 交互能真的把对话弹出来；播放期间 get_tree().paused；
## F 键（interact action）能逐句推进；最后一句后关闭并解除暂停；
## 关闭后玩家可正常操作。这是"玩家靠 F 聊天"整条链路的机器验证。
func _test_dialog(mgr: LevelManager, player: Player) -> void:
	print("\n[4] NPC 对话")

	var packed := load("res://scenes/actors/Npc.tscn") as PackedScene
	_check("Npc.tscn 可加载", packed != null)
	if packed == null:
		return

	var npc := packed.instantiate() as Npc
	npc.speaker_name = "守桥人"
	npc.lines = ["第一句。", "第二句。", "第三句。"]
	# 放到玩家正下方远处，避免玩家的 Interactor 把它当交互目标（干扰提示状态）。
	npc.global_position = player.global_position + Vector2(0, GameConfig.tiles(40.0))
	mgr.add_child(npc)
	await _step(2)

	var panel := mgr.get_node_or_null("HUD/DialogPanel") as DialogPanel
	_check("HUD 里有 DialogPanel", panel != null)
	if panel == null:
		npc.queue_free()
		return

	# 直接调用 interact（等价于玩家靠近按 F，跳过 Interactor 的距离/优先级判定）。
	npc.interact(player)
	# 注意：暂停后 physics_frame 不再发（paused 节点全停），推进要用 process_frame。
	await get_tree().process_frame
	await get_tree().process_frame
	_check("对话打开后世界暂停", get_tree().paused)
	_check("对话框可见", panel.visible)
	_eq("显示第一句", panel._body_label.text, "第一句。")

	# visible=true 只说明"逻辑上开着"，不代表玩家真能在屏幕上看见它。
	# 曾经出现过"测试全绿但玩家只看到画面定住"的情况，所以这里量真实矩形：
	# 面板必须有非零尺寸，且与可见区域有交集。
	await get_tree().process_frame
	var pr := panel._panel.get_global_rect()
	var vr := Rect2(Vector2.ZERO, panel.get_viewport_rect().size)
	_check("对话框有真实尺寸", pr.size.x > 100.0 and pr.size.y > 30.0, "rect=%s" % str(pr))
	_check("对话框落在屏幕内", vr.encloses(pr), "rect=%s viewport=%s" % [str(pr), str(vr)])

	# 逐句推进：按 F -> 下一句
	_send_f()
	await get_tree().process_frame
	await get_tree().process_frame
	_eq("按 F 推进到第二句", panel._body_label.text, "第二句。")

	_send_f()
	await get_tree().process_frame
	await get_tree().process_frame
	_eq("按 F 推进到第三句", panel._body_label.text, "第三句。")

	# 最后一句后再按 F -> 关闭并恢复
	_send_f()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("最后一句后对话框关闭", not panel.visible)
	_check("对话结束解除暂停", not get_tree().paused)
	_check("对话期间玩家未失控", player.state != Player.State.DEAD)

	npc.queue_free()
	await _step(2)


## 往输入队列塞一个 F 键按下+抬起（走真实输入管线，验证 _unhandled_input 接线）。
func _send_f() -> void:
	var down := InputEventKey.new()
	down.physical_keycode = KEY_F
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_F
	up.pressed = false
	Input.parse_input_event(up)


## 7. 场景放置 NPC + Interactor 真实 F 键链路。
##
## 与 [4] 的差别：Npc 不是代码 new 出来直接 interact() 的，而是关卡场景里
## 摆好的实例，靠玩家身上的 Interactor 在物理帧里探测到 F 按下再触发。
## 这是玩家实际手玩的路径——曾在上面出现过「按 F 卡死」的报告，单独拉一条回归。
## 全程用有界轮询 + process_frame，即使复现出暂停卡死也能干净退出并打印现场。
func _test_npc_interactor(mgr: LevelManager, player: Player) -> void:
	print("\n[7] 场景 NPC 交互链路")

	var old_inv := GameConfig.debug_invincible
	GameConfig.debug_invincible = true

	# 清掉此前测试留下的检查点：否则玩家在本关掉出边界时，复活逻辑会带着
	# 检查点切回别的关卡，把当前关卡（含被测的 Npc）卸载掉，引用就悬空了。
	GameState.reset()
	player.health.heal_full()

	mgr.load_level(&"battlefield_01", &"default")
	await _step(4)
	var level := mgr.get_current_level()
	if level == null:
		_check("场景关卡可用", false)
		GameConfig.debug_invincible = old_inv
		return

	# 找关卡里摆着的 Npc（不是动态 new 的）。
	var npc: Npc = null
	for c in get_tree().get_nodes_in_group(&"interactable"):
		if c is Npc:
			npc = c
			break
	_check("battlefield_01 里放了 Npc", npc != null)
	if npc == null:
		GameConfig.debug_invincible = old_inv
		return
	_eq("Npc 台词已配置", npc.lines.size(), 3)

	var panel := mgr.get_node_or_null("HUD/DialogPanel") as DialogPanel
	_check("HUD 里有 DialogPanel", panel != null)
	var prompt := mgr.get_node_or_null("HUD/InteractPrompt") as InteractPrompt
	_check("HUD 里有 InteractPrompt", prompt != null)
	if panel == null or prompt == null:
		GameConfig.debug_invincible = old_inv
		return

	# 铺一块临时地面：NPC 原点=脚底，地面顶边对齐脚底所在高度，
	# 玩家落上去站稳后 Interactor 能稳定探到 NPC。
	var ground := StaticBody2D.new()
	ground.collision_layer = GameConfig.mask([GameConfig.Layer.WORLD])
	ground.collision_mask = 0
	var gcs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(GameConfig.tiles(24.0), 40.0)
	gcs.shape = rect
	ground.add_child(gcs)
	ground.position = npc.global_position + Vector2(0, 20.0)
	ground.name = "SelftestGround"
	level.add_child(ground)

	player.health.heal_full()
	player.teleport_to(npc.global_position + Vector2(GameConfig.tiles(-1.5), GameConfig.tiles(-4.0)))
	for i in 6:
		await _step(10)
		if player.health.current_hp != player.health.max_hp or player.state_name() != "NORMAL" \
				or player.global_position.distance_to(Vector2(96, 224)) < 40.0:
			print("  诊断-帧%d: pos=%s hp=%d state=%s vy=%.1f" % [
				i * 10, str(player.global_position), player.health.current_hp,
				player.state_name(), player.velocity.y])
	_check("玩家落到 NPC 旁地面", player.is_on_floor(),
		"pos=%s npc=%s" % [str(player.global_position), str(npc.global_position)])

	var it := player.get_node("Interactor") as Interactor
	var picked := it.get_current()
	_check("Interactor 选中了场景 Npc", picked == npc,
		"current=%s" % (String(picked.name) if picked != null else "null"))
	if picked != npc:
		print("  现场-玩家位置: %s  落点距 Npc: %.1fpx" % [
			str(player.global_position),
			player.global_position.distance_to(npc.global_position)])
		print("  现场-Npc 位置: %s  玩家中心偏移: %s" % [
			str(npc.global_position),
			str(player.global_position - npc.global_position)])
		var cand_names: Array[String] = []
		for c in it._candidates:
			cand_names.append(String(c.name) + "@" + str((c as Node2D).global_position))
		print("  现场-候选目标: %s" % str(cand_names))
		ground.queue_free()
		GameConfig.debug_invincible = old_inv
		return

	# 靠近后：头顶提示应已出现且锚定在这个 Npc 上（世界锚定提示的入口检查）。
	_check("靠近后头顶提示出现", prompt.visible and prompt._target == npc,
		"visible=%s target=%s" % [str(prompt.visible),
			String(prompt._target.name) if prompt._target != null else "null"])

	# 真实 F 键：由 Interactor 在物理帧里发现并触发，等价于玩家手按。
	_send_f()
	var opened := false
	for i in 120:
		await get_tree().process_frame
		if get_tree().paused:
			opened = true
			break
	_check("按 F 打开对话（世界暂停）", opened and panel.visible)
	if not (opened and panel.visible):
		_check("现场-暂停", get_tree().paused)
		_check("现场-面板可见", panel.visible)
		_check("现场-面板在播", panel._playing)
		print("  现场-玩家状态: %s" % player.state_name())
		ground.queue_free()
		GameConfig.debug_invincible = old_inv
		return

	# 对话开始：提示要让位（对话框出现在底部，头顶提示若不撤会抢注意力）。
	_check("对话开始提示让位隐藏", not prompt.visible)

	_eq("显示第一句", panel._body_label.text, "你好，年轻人")
	_send_f()
	await get_tree().process_frame
	await get_tree().process_frame
	_eq("按 F 到第二句", panel._body_label.text, "继续往前走吧")
	_send_f()
	await get_tree().process_frame
	await get_tree().process_frame
	_eq("按 F 到第三句", panel._body_label.text, "胜利就在眼前")
	# 最后一句再按 F：等它真正关闭并解除暂停（有界轮询，最多 30 帧）。
	_send_f()
	for i in 30:
		await get_tree().process_frame
		if not panel.visible and not get_tree().paused:
			break
	_check("最后一句后关闭并解除暂停", not panel.visible and not get_tree().paused,
		"visible=%s paused=%s playing=%s" % [str(panel.visible), str(get_tree().paused), str(panel._playing)])

	# 对话结束：Interactor 收到 dialog_finished 会重发提示，玩家还站旁边就该看到。
	_check("对话结束头顶提示恢复", prompt.visible and prompt._target == npc,
		"visible=%s target=%s" % [str(prompt.visible),
			String(prompt._target.name) if prompt._target != null else "null"])

	# 连按回归：玩家狂按 F 跳对话是常见操作。关闭对话后若紧接着（同一帧内）
	# 还有一次按键，它绝不能把对话又顶开——否则玩家感觉"对话关不掉、世界一直
	# 停着"，报出来的现象就是"按 F 卡死"。
	_send_f()
	var reopened := false
	for i in 120:
		await get_tree().process_frame
		if panel.visible or get_tree().paused:
			reopened = true
			break
	_check("关闭后立即再按 F 不重开对话", not reopened,
		"visible=%s paused=%s playing=%s" % [str(panel.visible), str(get_tree().paused), str(panel._playing)])

	# 冷却保护不能误伤正常交互：等冷却过期后再按 F，对话应能正常重新打开。
	# 冷却默认 250ms，这里等 30 物理帧（0.5s@60fps）留足余量。
	await _step(30)
	_send_f()
	var reopened2 := false
	for i in 120:
		await get_tree().process_frame
		if get_tree().paused:
			reopened2 = true
			break
	_check("冷却过后再按 F 能重新对话", reopened2 and panel.visible,
		"visible=%s paused=%s" % [str(panel.visible), str(get_tree().paused)])
	if reopened2 and panel.visible:
		# 打开后立刻补一次 F 把这次对话也关掉，别让它在清理前一直暂停。
		_send_f()
		for i in 30:
			await get_tree().process_frame
			if not panel.visible and not get_tree().paused:
				break

	# 兜底：万一对话没正常关（那本身就是被测 bug），强制恢复，别拖垮后续测试。
	if get_tree().paused:
		get_tree().paused = false
	if panel.visible:
		panel._close()

	ground.queue_free()
	GameConfig.debug_invincible = old_inv
	# 切回 test，保持后续测试起点一致。
	mgr.load_level(&"test", &"default")
	await _step(3)


## 6. 坠落出界兜底。
##
## 地图没封边、或者关卡还没画完时，玩家掉下去必须被捞回来，
## 而不是无限下坠导致游戏卡死。
func _test_fall_out(mgr: LevelManager, player: Player) -> void:
	print("\n[6] 坠落出界兜底")

	var level := mgr.get_current_level()
	if level == null:
		_check("坠落测试有可用关卡", false)
		return

	GameState.reset()
	GameState.stage = Abilities.Stage.YOUNG
	await _step(2)
	player.health.heal_full()
	var hp_before: int = player.health.current_hp

	var bottom := level.get_world_bounds().end.y
	player.teleport_to(Vector2(player.global_position.x, bottom + GameConfig.tiles(40.0)))
	await _step(6)

	_check("坠落后被捞回关卡范围内",
		player.global_position.y < bottom,
		"y=%.1f bottom=%.1f" % [player.global_position.y, bottom])
	_eq("坠落扣血且未被顺手回满", player.health.current_hp, hp_before - mgr.fall_damage)
	_check("坠落后速度已清零", absf(player.velocity.y) < 200.0,
		"vy=%.1f" % player.velocity.y)

	# 血量不足以承受坠落时应当正常死亡，而不是卡在半空。
	while player.health.current_hp > mgr.fall_damage:
		var d := DamageInfo.create(1, null, 0.0)
		d.ignore_invulnerability = true
		player.health.take_damage(d)
	player.teleport_to(Vector2(player.global_position.x, bottom + GameConfig.tiles(40.0)))
	await _step(6)
	_check("残血坠落触发死亡", player.health.is_dead())


## 5. 跨关卡切图。
##
## 这是「玩家跨关持久存在」这一架构决策的验收点：
## 切图时玩家节点不能被销毁，血量/能力等运行时状态必须原样带过去，
## 相机限位要跟着换，旧关卡要真的被卸掉。
func _test_level_transition(mgr: LevelManager, player: Player) -> void:
	print("\n[5] 跨关卡切换")

	var old_level := mgr.get_current_level()
	var old_bounds := old_level.get_world_bounds()

	# 先制造一个可辨识的状态，切图后应当原样保留。
	GameState.stage = Abilities.Stage.LOST_DASH
	await _step(2)
	player.health.heal_full()
	player.health.take_damage(DamageInfo.create(1, null, 0.0))
	var hp_before: int = player.health.current_hp
	var player_id := player.get_instance_id()

	mgr.load_level(&"battlefield_01", &"default")
	await _step(4)

	var new_level := mgr.get_current_level()
	_check("切到 battlefield_01", new_level != null and new_level != old_level)
	if new_level == null:
		return

	_eq("GameState 关卡 id 已更新", String(GameState.current_level_id), "battlefield_01")
	_eq("关卡自身 level_id 与注册表一致", String(new_level.level_id), "battlefield_01")
	_check("旧关卡已从场景树卸下", not is_instance_valid(old_level) or not old_level.is_inside_tree())

	_eq("玩家是同一个实例（未被销毁重建）", player.get_instance_id(), player_id)
	_eq("血量跨关保留", player.health.current_hp, hp_before)
	_check("能力集跨关保留", not player.abilities.has(Abilities.DASH)
		and player.abilities.has(Abilities.DOUBLE_JUMP))

	var entry := new_level.get_entry(&"default")
	_check("模板关有 default 入口", entry != null)
	if entry != null:
		# 只比 X 和「是否在入口附近」。模板关还没画地形，玩家会一直自由落体，
		# 等几帧之后 Y 必然偏离，那是重力正常工作的表现，不是放置错误。
		_check("玩家被放到入口的水平位置",
			absf(player.global_position.x - entry.global_position.x) < 4.0,
			"x=%.1f entry.x=%.1f" % [player.global_position.x, entry.global_position.x])
		_check("玩家出现在入口附近（未落到别处）",
			absf(player.global_position.y - entry.global_position.y) < 64.0,
			"y=%.1f entry.y=%.1f" % [player.global_position.y, entry.global_position.y])

	_check("模板关有 from_prev 入口", new_level.get_entry(&"from_prev") != null)
	_check("模板关有 from_next 入口", new_level.get_entry(&"from_next") != null)

	# 空关卡（还没画瓦片）不能让相机限位退化成一个点，否则一进图就黑屏。
	var new_bounds := new_level.get_world_bounds()
	_check("空关卡也有可用的相机边界",
		new_bounds.size.x > 100 and new_bounds.size.y > 100,
		"bounds=%s（旧=%s）" % [str(new_bounds), str(old_bounds)])

	# 出口配置必须指向真实存在的关卡，否则玩家走过去会卡在原地。
	for node in new_level.find_children("*", "Area2D", true, false):
		var ex := node as LevelExit
		if ex == null:
			continue
		_check("出口 %s 指向已注册关卡" % ex.name,
			LevelRegistry.exists(ex.target_level), String(ex.target_level))

	# 切回去，确认双向可达且不会残留。
	mgr.load_level(&"test", &"default")
	await _step(4)
	_eq("能切回 test", String(GameState.current_level_id), "test")
	_check("切回后玩家仍是同一实例", player.get_instance_id() == player_id)
