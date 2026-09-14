class_name PlayerVisual
extends Node2D
## 主角外观。把「状态机跑成什么状态」翻译成「播哪个动画」。
##
## 【设计意图】视觉与逻辑彻底解耦。
##   Player.gd 一行都不用知道有没有美术资源、动画叫什么名字、播到第几帧。
##   它只管跑自己的状态机，本组件在旁边看着状态自己决定放什么。
##   这意味着：美术进度和玩法进度可以完全独立推进，互不阻塞。
##
## 【降级策略】没有动画资源时自动退回占位色块。
##   这不是"容错"，是刻意的工作流设计——新动作做到一半、
##   或者临时想验证某个关卡的手感时，缺图不能让游戏跑不起来。
##   所以 frames 为空、或某个状态没配动画，都只是静默降级，不报错。
##
## 【加新动画的方法】不用改代码：
##   1. 把序列帧丢进 res://assets/animation/player_xxx/
##   2. 在 SpriteFrames 资源里建一个同名 animation
##   3. 在下面的 _ANIM 表里加一行映射（这是唯一要碰代码的地方）
##
## 【朝向】本组件不自己翻转，由 Player._set_facing 缩放父节点统一处理。
##   若在这里再翻一次，冲刺等状态下会翻两次等于没翻，极难排查。

## 每个视觉状态对应的动画名。SpriteFrames 里没有这个名字就降级到 fallback。
##
## 为什么不直接用 Player.State：视觉状态比逻辑状态多。
## 逻辑上 NORMAL 一个状态，视觉上要分站立/跑动/上升/下落四种。
enum Look {
	IDLE,
	RUN,
	JUMP,   ## 上升段
	FALL,   ## 下落段
	DOUBLE_JUMP,   ## 空中二段跳（触发一瞬间播一次，播完回落）
	DASH,
	GLIDE,
	ATTACK,
	HURT,
	DEAD,
}

const _ANIM := {
	Look.IDLE: &"idle",
	Look.RUN: &"run",
	Look.JUMP: &"jump_start",
	Look.FALL: &"fall",
	Look.DOUBLE_JUMP: &"jump_air",
	Look.DASH: &"dash",
	Look.GLIDE: &"glide",
	Look.ATTACK: &"attack",
	Look.HURT: &"hurt",
	Look.DEAD: &"dead",
}

## 找不到对应动画时退而求其次播哪个。
## 例如只做了 run 还没做 jump，跳起来会继续播 run——
## 比整个角色消失或定格在第一帧要好得多。
const _FALLBACK := {
	Look.JUMP: Look.RUN,
	Look.FALL: Look.RUN,
	Look.DOUBLE_JUMP: Look.JUMP,
	Look.DASH: Look.RUN,
	Look.GLIDE: Look.FALL,
	Look.ATTACK: Look.IDLE,
	Look.HURT: Look.IDLE,
	Look.DEAD: Look.IDLE,
	Look.RUN: Look.IDLE,
}

## 动画帧集合。留空则整个组件降级为占位色块。
@export var frames: SpriteFrames:
	set(v):
		frames = v
		_refresh_sprite()

## 素材本身的像素高度会随美术改动而变，不能写死缩放值。
## 这里声明"角色在游戏里该有多高（单位：格）"，组件自己反算缩放。
##
## 比主角碰撞体(4格)略高：碰撞体是"骨架"，美术总要溢出一点
## （头发、武器、抬起的脚），完全等高会显得角色被压扁在盒子里。
@export var visual_height_tiles: float = 4.6:
	set(v):
		visual_height_tiles = v
		_refresh_sprite()

## 素材脚底相对图片底边的位置（0=正好在底边，0.05=底部留了5%空白）。
##
## AI 抽帧素材几乎不可能让脚底正好贴着画布底边。这个值让角色
## 站在地面上而不是"陷进去"或"浮在空中"。改素材后要重新量。
@export_range(0.0, 0.3, 0.005) var foot_padding: float = 0.0:
	set(v):
		foot_padding = v
		_refresh_sprite()

## 无美术资源时的占位色块颜色。
@export var placeholder_color: Color = Color(0.85, 0.83, 0.88)

var _sprite: AnimatedSprite2D
var _placeholder: Node2D
var _look: Look = Look.IDLE
## 冲刺残影拖尾（纯视觉特效，跟外观状态走，见 DashGhost 注释）。
var _dash_ghost: DashGhost
## 非空时，update_look 尊重这个 look（优先于常规判断），直到动画播完或落地才解除。
## 用于"触发一瞬间"的动作（二段跳 double_jump），是唯一会短期打断常规外观逻辑的入口。
## 没有它，二段跳动画播一帧就会被 update_look 用速度算出的 jump 切走。
## -1 表示没有强制。
var _forced_look: int = -1
## 攻击动画的强制标记。与 _forced_look 分开的原因：解除条件不同。
## 二段跳的强制"落地即解除"（空中动作，落地就不再有意义）；
## 攻击在地面触发，on_floor 恒 true，若共用会被立即解除，
## 动画播一半就切回 idle（表现就是"只播了抬腿"）。攻击的强制
## 只认"动画播完"，或被受击/死亡打断（见 trigger_attack）。
var _attack_forced: bool = false


func _ready() -> void:
	_build()
	_refresh_sprite()
	# 连接 one-shot 动画播完信号，用于解除二段跳等强制外观。
	_sprite.animation_finished.connect(_on_anim_finished)
	_apply(Look.IDLE, true)


func _build() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Anim"
	_sprite.centered = true
	add_child(_sprite)

	_dash_ghost = DashGhost.new()
	_dash_ghost.name = "DashGhost"
	add_child(_dash_ghost)
	_dash_ghost.setup(_sprite)

	_placeholder = _build_placeholder()
	add_child(_placeholder)


## 占位色块：一个身体 + 一个朝向标记，和接入美术前的表现保持一致。
## 保留朝向标记是有意的——没有它就分不清角色朝哪边，调试关卡时很难受。
func _build_placeholder() -> Node2D:
	var root := Node2D.new()
	root.name = "Placeholder"

	var w := GameConfig.tiles(GameConfig.PLAYER_TILE_WIDTH)
	var h := GameConfig.tiles(GameConfig.PLAYER_TILE_HEIGHT)

	var body := ColorRect.new()
	body.name = "Body"
	body.color = placeholder_color
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.position = Vector2(-w * 0.5, -h * 0.5)
	body.size = Vector2(w, h)
	root.add_child(body)

	var mark := ColorRect.new()
	mark.name = "FaceMark"
	mark.color = Color(0.25, 0.22, 0.3)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := w * 0.28
	mark.position = Vector2(w * 0.12, -h * 0.42)
	mark.size = Vector2(m, m)
	root.add_child(mark)

	return root


## 按 visual_height_tiles 反算缩放，并把脚底对齐到碰撞体底边。
func _refresh_sprite() -> void:
	if _sprite == null:
		return

	var has_art: bool = frames != null and not frames.get_animation_names().is_empty()
	_sprite.visible = has_art
	if _placeholder != null:
		_placeholder.visible = not has_art
	if not has_art:
		return

	_sprite.sprite_frames = frames

	var tex: Texture2D = _first_texture()
	if tex == null:
		return
	var src_h := float(tex.get_height())
	if src_h <= 0.0:
		return

	var want_h := GameConfig.tiles(visual_height_tiles)
	var s := want_h / src_h
	_sprite.scale = Vector2(s, s)

	# 脚底对齐依赖「当前动画的实际显示高度」——不同动画画布高度不同，
	# 用统一 want_h 会让画布矮的动画（如 run 645px）浮空。
	# 这里只负责等比缩放，脚底对齐统一交给 _align_foot。
	_align_foot()


func _first_texture() -> Texture2D:
	# 缩放基准必须固定，不能随"哪个动画名字典序排最前"而漂移——
	# get_animation_names() 返回的是排序后的数组，新加动画（如 double_jump）
	# 会改变字典序，导致基准动画换了、scale 跟着漂移（自检里外观高度就崩）。
	# idle 是角色站立的基准姿态，用它做缩放基准最稳定；没有 idle 再退回第一个。
	var names := frames.get_animation_names()
	if frames.has_animation(&"idle") and frames.get_frame_count(&"idle") > 0:
		return frames.get_frame_texture(&"idle", 0)
	for name in names:
		if frames.get_frame_count(name) > 0:
			return frames.get_frame_texture(name, 0)
	return null


## 由 Player 每帧调用，把逻辑状态翻译成视觉状态。
##
## 传参而不是让本组件反查 Player：组件不持有对 Player 的引用，
## 就能单独丢进测试场景里驱动，也不会因为节点路径变动而失效。
func update_look(state: int, velocity: Vector2, on_floor: bool, input_x: float) -> void:
	# 二段跳这类"触发一瞬间"的动作优先于常规判断：
	# 落地或动画播完（_on_anim_finished）后自动解除，恢复常规逻辑。
	# 否则它会被下面用速度算出的 jump/fall 立刻切走，double_jump 播不成。
	if _forced_look >= 0:
		if on_floor:
			_forced_look = -1
		else:
			_apply(_forced_look as Look, false)
			return

	# 攻击动画强制播完（逻辑状态 0.36s 就结束并恢复操作，演出不受其拖拽；
	# 被打断时由打断方调用 cancel_attack_forced 解除）。
	if _attack_forced:
		_apply(Look.ATTACK, false)
		return

	var next: Look = Look.IDLE

	match state:
		Player.State.DEAD:
			next = Look.DEAD
		Player.State.HITSTUN:
			next = Look.HURT
		Player.State.DASHING:
			next = Look.DASH
		Player.State.GLIDING:
			next = Look.GLIDE
		Player.State.ATTACKING:
			next = Look.ATTACK
		_:
			if not on_floor:
				# 用速度而非"是否按了跳"判断升降：被弹起、被击飞时
				# 没有跳跃输入，但视觉上确实在上升，该播 jump。
				next = Look.FALL if velocity.y > 0.0 else Look.JUMP
			elif absf(input_x) > 0.01:
				next = Look.RUN
			else:
				next = Look.IDLE

	_apply(next, false)
	# 残影只在冲刺期间生成；冲刺结束残影自然淡出，视觉上有个"余韵"
	_dash_ghost.set_active(next == Look.DASH)


## 触发"瞬间动作"视觉（二段跳）：强制播一次 double_jump，播完或落地自动恢复。
## 由 Player 在 _try_jump 的二段跳分支调用。
func trigger_double_jump() -> void:
	_forced_look = Look.DOUBLE_JUMP
	_apply(Look.DOUBLE_JUMP, true)


## 触发攻击动画：强制播完整条 attack（one-shot），播完自动回落常规外观。
## 逻辑上攻击状态只持续 0.36s（前摇+判定+后摇），远短于动画时长；
## 不加这个强制的话动画播一半就被 update_look 切回 idle/run。
## 与 trigger_double_jump 的区别：攻击在地面触发，"落地解除"永远成立，
## 所以这里只认"动画播完"，另给受击/死亡提供 cancel 入口。
func trigger_attack() -> void:
	_attack_forced = true
	_apply(Look.ATTACK, true)


## 外观层面的攻击动画被打断（受击硬直、死亡等）时由 Player 调用。
func cancel_attack_forced() -> void:
	_attack_forced = false


func _on_anim_finished() -> void:
	# 本次强制的 one-shot 播完了，恢复正常外观逻辑（由 update_look 接管）。
	_forced_look = -1
	_attack_forced = false


func _apply(look: Look, force: bool) -> void:
	if look == _look and not force:
		return
	_look = look
	if _sprite == null or not _sprite.visible:
		return

	var name: StringName = _resolve(look)
	if name == &"":
		return
	if _sprite.animation != name or force:
		_sprite.play(name)
		# 动画切换后重新对齐脚底：不同动画画布高度不同，
		# 不重新量的话，切到画布矮的动画（run）会浮空。
		_align_foot()


## 把脚底对齐到碰撞体底边。
##
## scale 是按 idle 统一算的（保证 idle 显示高度 = visual_height_tiles），
## 但各动画画布高度不一（idle 702 / run 645 / jump 672），统一 offset 会浮空。
## 所以这里用「当前动画的实际显示高度」算垂直位置，让脚底永远贴着地面。
## 碰撞体底边 = 碰撞体中心 + body_h/2；脚底 = position + shown/2（扣掉脚底留白）。
func _align_foot() -> void:
	if _sprite == null or not _sprite.visible:
		return
	var anim: StringName = _sprite.animation
	if anim == &"":
		return
	var frame := _sprite.sprite_frames.get_frame_texture(anim, 0)
	if frame == null:
		return
	var shown := float(frame.get_height()) * _sprite.scale.y
	var body_h := GameConfig.tiles(GameConfig.PLAYER_TILE_HEIGHT)
	var foot_gap := GameConfig.tiles(visual_height_tiles) * foot_padding
	_sprite.position = Vector2(0.0, body_h * 0.5 - shown * 0.5 + foot_gap)


## 顺着 _FALLBACK 链找第一个真实存在的动画，全都没有就返回空。
## 加循环上限防止将来有人把 fallback 配成环。
func _resolve(look: Look) -> StringName:
	if frames == null:
		return &""
	var cur := look
	for _i in 8:
		var n: StringName = _ANIM.get(cur, &"")
		if n != &"" and frames.has_animation(n):
			return n
		if not _FALLBACK.has(cur):
			break
		cur = _FALLBACK[cur]
	return &""


## 当前实际播放的动画名，自检和调试面板用。
func current_animation() -> StringName:
	if _sprite == null or not _sprite.visible:
		return &""
	return _sprite.animation
