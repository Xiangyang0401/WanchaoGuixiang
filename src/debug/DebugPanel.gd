class_name DebugPanel
extends PanelContainer
## 调试面板（F1 开关）。
##
## 这是给策划的工具，不是给程序的。核心能力：
##   - 一键跳到任意能力阶段，不用打通关就能测试后期内容
##   - 实时拖相机 zoom，找到你满意的观感
##   - 看到玩家当前状态机、速度、能力集，排查手感问题
##   - 无敌模式，专心测关卡结构不被怪打断
##
## 面板本身不持有任何游戏逻辑，所有操作都通过 GameState / GameConfig 走正规路径，
## 所以在面板里做的任何事，和游戏正常流程做的事效果完全一致。

var _player: Player
var _stage_option: OptionButton
var _info: RichTextLabel
var _invincible_check: CheckBox
var _ability_list: VBoxContainer


func _ready() -> void:
	visible = GameConfig.debug_visible
	_build_ui()
	set_process(true)
	# 面板不该拦住游戏输入。
	mouse_filter = Control.MOUSE_FILTER_PASS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		GameConfig.debug_visible = not GameConfig.debug_visible
		visible = GameConfig.debug_visible
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	_ensure_player()
	_update_info()


# ---------------------------------------------------------------------------
# UI 构建
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	custom_minimum_size = Vector2(460, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.88)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.corner_radius_bottom_right = 6
	add_theme_stylebox_override(&"panel", style)

	# 面板内容比较高，套一层滚动容器，
	# 免得在小窗口或高 zoom 下够不到底部的控件。
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 620
	add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 8)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var title := Label.new()
	title.text = "调试面板  (F1 隐藏)"
	title.add_theme_font_size_override(&"font_size", 15)
	root.add_child(title)

	root.add_child(HSeparator.new())

	# —— 能力阶段切换 ——
	var stage_row := HBoxContainer.new()
	root.add_child(stage_row)
	var stage_label := Label.new()
	stage_label.text = "阶段"
	stage_label.custom_minimum_size.x = 48
	stage_row.add_child(stage_label)

	_stage_option = OptionButton.new()
	_stage_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in Abilities.Stage.keys():
		var v: int = Abilities.Stage[key]
		_stage_option.add_item("%s  (%s)" % [Abilities.stage_label(v), key], v)
	_stage_option.item_selected.connect(_on_stage_selected)
	stage_row.add_child(_stage_option)

	# —— 相机 ——
	root.add_child(HSeparator.new())
	var cam_title := Label.new()
	cam_title.text = "相机（拖到满意后写回 GameConfig.gd）"
	root.add_child(cam_title)

	_add_slider(root, "缩放", 0.5, 4.0, 0.1,
		GameConfig.camera_zoom,
		func(v: float): GameConfig.camera_zoom = v,
		func() -> String:
			var s := GameConfig.visible_world_size() / GameConfig.TILE_SIZE
			return "%.2fx  (%.0f×%.0f 格)" % [GameConfig.camera_zoom, s.x, s.y])

	# 垂直偏移：负值让相机上移，主角在画面里偏下，上方视野更多。
	# 单位是"占半屏的比例"而非格数，这样调完缩放不用回来重调这里。
	# 同时显示等效格数，方便对照关卡尺寸判断。
	_add_slider(root, "上下位移", -0.6, 0.3, 0.01,
		GameConfig.camera_offset_ratio.y,
		func(v: float): GameConfig.camera_offset_ratio.y = v,
		func() -> String:
			var v := GameConfig.camera_offset_ratio.y
			var hint := "居中" if is_zero_approx(v) else ("画面抬高" if v < 0.0 else "画面下移")
			var t := v * GameConfig.visible_world_size().y * 0.5 / GameConfig.TILE_SIZE
			return "%.2f  (%.1f 格, %s)" % [v, t, hint])

	_add_slider(root, "左右位移", -0.4, 0.4, 0.01,
		GameConfig.camera_offset_ratio.x,
		func(v: float): GameConfig.camera_offset_ratio.x = v,
		func() -> String:
			var t := GameConfig.camera_offset_ratio.x \
				* GameConfig.visible_world_size().x * 0.5 / GameConfig.TILE_SIZE
			return "%.2f  (%.1f 格)" % [GameConfig.camera_offset_ratio.x, t])

	_add_slider(root, "前瞻", 0.0, 0.5, 0.01,
		GameConfig.camera_lookahead_ratio,
		func(v: float): GameConfig.camera_lookahead_ratio = v,
		func() -> String:
			var t := GameConfig.camera_lookahead_ratio \
				* GameConfig.visible_world_size().x * 0.5 / GameConfig.TILE_SIZE
			return "%.2f  (%.1f 格)" % [GameConfig.camera_lookahead_ratio, t])

	_add_slider(root, "跟随", 0.0, 20.0, 0.5,
		GameConfig.camera_smoothing,
		func(v: float): GameConfig.camera_smoothing = v,
		func() -> String:
			var v := GameConfig.camera_smoothing
			return "硬跟随" if is_zero_approx(v) else "%.1f" % v)

	# 纵向跟随单独一轴：必须明显快于水平跟随，否则跳跃/下落时镜头追不上、
	# 主角在画面里上下窜动（观感=镜头晃动、头晕）。0 = 纵向硬跟。
	_add_slider(root, "纵向跟随", 0.0, 60.0, 0.5,
		GameConfig.camera_smoothing_y,
		func(v: float): GameConfig.camera_smoothing_y = v,
		func() -> String:
			var v := GameConfig.camera_smoothing_y
			return "硬跟随" if is_zero_approx(v) else "%.1f" % v)

	var copy_btn := Button.new()
	copy_btn.text = "复制当前相机参数到剪贴板"
	copy_btn.pressed.connect(_on_copy_camera)
	root.add_child(copy_btn)

	root.add_child(HSeparator.new())

	# —— 开关 ——
	_invincible_check = CheckBox.new()
	_invincible_check.text = "无敌模式"
	_invincible_check.toggled.connect(func(on): GameConfig.debug_invincible = on)
	root.add_child(_invincible_check)

	# —— 按钮 ——
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override(&"separation", 6)
	root.add_child(btn_row)

	var heal_btn := Button.new()
	heal_btn.text = "回满血"
	heal_btn.pressed.connect(_on_heal)
	btn_row.add_child(heal_btn)

	var kill_btn := Button.new()
	kill_btn.text = "自杀"
	kill_btn.pressed.connect(_on_suicide)
	btn_row.add_child(kill_btn)

	var respawn_btn := Button.new()
	respawn_btn.text = "回复活点"
	respawn_btn.pressed.connect(_on_respawn)
	btn_row.add_child(respawn_btn)

	root.add_child(HSeparator.new())

	# —— 能力开关列表 ——
	var ab_title := Label.new()
	ab_title.text = "能力（点击单独开关）"
	root.add_child(ab_title)

	_ability_list = VBoxContainer.new()
	root.add_child(_ability_list)
	_build_ability_toggles()

	root.add_child(HSeparator.new())

	# —— 实时信息 ——
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.custom_minimum_size.y = 150
	_info.scroll_active = false
	root.add_child(_info)


## 构造一行「标签 + 滑块」，返回值标签供后续刷新。
##
## on_change 负责写回配置，fmt 负责把当前值渲染成人看的文字。
## 拆成两个回调是因为显示格式各不相同（倍数 / 格数 / "硬跟随"）。
func _add_slider(parent: Node, title: String, lo: float, hi: float, step: float,
		initial: float, on_change: Callable, fmt: Callable) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = title
	name_label.custom_minimum_size.x = 64
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 130
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size.x = 116
	value_label.text = fmt.call()
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float):
		on_change.call(v)
		value_label.text = fmt.call()
	)
	return value_label


## 把当前相机参数按 GameConfig.gd 的写法输出，方便直接粘回源码。
func _on_copy_camera() -> void:
	var o := GameConfig.camera_offset_ratio
	var text := "var camera_zoom: float = %.2f\n" % GameConfig.camera_zoom \
		+ "var camera_smoothing: float = %.1f\n" % GameConfig.camera_smoothing \
		+ "var camera_smoothing_y: float = %.1f\n" % GameConfig.camera_smoothing_y \
		+ "var camera_lookahead_ratio: float = %.2f\n" % GameConfig.camera_lookahead_ratio \
		+ "var camera_offset_ratio: Vector2 = Vector2(%.2f, %.2f)" % [o.x, o.y]
	DisplayServer.clipboard_set(text)
	print("[调试面板] 相机参数已复制：\n", text)


func _build_ability_toggles() -> void:
	var ids := [
		Abilities.DOUBLE_JUMP, Abilities.DASH, Abilities.CLEAVE,
		Abilities.GLIDE, Abilities.INSIGHT, Abilities.SOOTHE,
	]
	for id in ids:
		var cb := CheckBox.new()
		cb.text = Abilities.display_name(id)
		cb.set_meta(&"ability_id", id)
		cb.toggled.connect(_on_ability_toggled.bind(id))
		_ability_list.add_child(cb)


# ---------------------------------------------------------------------------
# 回调
# ---------------------------------------------------------------------------

func _on_stage_selected(index: int) -> void:
	var stage: int = _stage_option.get_item_id(index)
	GameState.stage = stage
	# 玩家如果开了 override_stage，改 GameState 不会生效，这里直接推一把。
	if _player != null and _player.override_stage:
		_player.abilities.set_stage(stage)


func _on_ability_toggled(on: bool, id: StringName) -> void:
	if _player == null:
		return
	if on:
		_player.abilities.grant(id)
	else:
		_player.abilities.revoke(id)


func _on_heal() -> void:
	if _player != null:
		_player.health.heal_full()


func _on_suicide() -> void:
	if _player == null:
		return
	var info := DamageInfo.new()
	info.amount = 9999
	info.ignore_invulnerability = true
	_player.health.take_damage(info)


func _on_respawn() -> void:
	var mgr := _find_level_manager()
	if mgr != null:
		mgr.respawn_player()


# ---------------------------------------------------------------------------
# 信息刷新
# ---------------------------------------------------------------------------

func _ensure_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return
	_player = players[0] as Player
	_sync_ability_checks()


func _sync_ability_checks() -> void:
	if _player == null:
		return
	for child in _ability_list.get_children():
		var cb := child as CheckBox
		if cb == null:
			continue
		var id: StringName = cb.get_meta(&"ability_id")
		cb.set_pressed_no_signal(_player.abilities.has(id))


func _update_info() -> void:
	if _player == null:
		_info.text = "[color=#ff8888]未找到玩家节点[/color]"
		return

	_sync_ability_checks()

	var h := _player.health
	var ab := _player.abilities
	var vel := _player.velocity
	var pos := _player.global_position
	var tile_pos := pos / GameConfig.TILE_SIZE

	var lines := []
	lines.append("[b]状态[/b]  %s%s" % [
		_player.state_name(),
		"  [color=#ffd479](无敌)[/color]" if h.is_invulnerable() else ""
	])
	lines.append("[b]血量[/b]  %d / %d   (基础上限 %d, 惩罚 -%d)" % [
		h.current_hp, h.max_hp, h.base_max_hp, ab.hp_penalty()
	])
	lines.append("[b]回血[/b]  %s" % ("自动" if h.auto_regen else "仅长凳"))
	lines.append("[b]阶段[/b]  %s" % Abilities.stage_label(ab.get_stage()))
	lines.append("[b]位置[/b]  %.1f, %.1f 格" % [tile_pos.x, tile_pos.y])
	lines.append("[b]速度[/b]  %.0f, %.0f  (%.1f 格/秒)" % [
		vel.x, vel.y, vel.length() / GameConfig.TILE_SIZE
	])
	lines.append("[b]接地[/b]  %s   [b]朝向[/b] %s" % [
		"是" if _player.is_on_floor() else "否",
		"右" if _player.facing > 0 else "左"
	])
	lines.append("[b]关卡[/b]  %s" % String(GameState.current_level_id))
	lines.append("[b]检查点[/b]  %s" % (
		String(GameState.active_checkpoint_id) if GameState.has_checkpoint() else "无（用默认复活点）"
	))
	lines.append("[b]敌人[/b]  %d" % get_tree().get_nodes_in_group(&"enemy").size())

	_info.text = "\n".join(lines)


func _find_level_manager() -> LevelManager:
	var n := get_tree().current_scene
	if n is LevelManager:
		return n as LevelManager
	for child in n.get_children():
		if child is LevelManager:
			return child as LevelManager
	return null
