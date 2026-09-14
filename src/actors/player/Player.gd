class_name Player
extends CharacterBody2D
## 主角控制器。
##
## 【架构核心】能力是数据，不是代码分支。
##   二段跳、冲刺、滑翔、攻击的代码从第一天起就全部写好并常驻在这里，
##   能不能用只取决于运行时查询 abilities.has(...)。
##   剧情推进时只需要 GameState.stage = XXX，控制器无需任何改动。
##
##   千万不要为了"现在还没做滑翔"就把代码删掉或注释掉——
##   那会导致后面加回来时要重新处理状态机交互，得不偿失。
##
## 【状态机】用显式枚举而非隐式布尔组合。
##   布尔组合（is_dashing && is_attacking && !is_hurt）会随功能增加指数爆炸，
##   而且极易出现"两个状态同时为真"的非法态。枚举保证任意时刻只有一个主状态。

signal state_changed(from: State, to: State)

enum State {
	NORMAL,     ## 常规：走、跳、落
	DASHING,    ## 冲刺中
	GLIDING,    ## 滑翔中
	ATTACKING,  ## 攻击中（可能仍在移动）
	HITSTUN,    ## 受击硬直，不可操作
	DEAD,       ## 死亡
}

@export var profile: MovementProfile

## 玩家生成时的能力阶段。留空则读 GameState.stage。
## 调试时可以在场景里直接改这个值跳到任意阶段。
@export var override_stage: bool = false
@export var debug_stage: Abilities.Stage = Abilities.Stage.YOUNG

@onready var health: Health = $Health
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var attack_hitbox: Hitbox = $AttackPivot/AttackHitbox
@onready var attack_pivot: Node2D = $AttackPivot
@onready var sprite: PlayerVisual = $Visual
@onready var interactor: Node = $Interactor

var abilities: AbilitySet

var state: State = State.NORMAL
var facing: int = 1                    ## 1 = 右, -1 = 左

# --- 跳跃状态 ---
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _air_jumps_used: int = 0
var _was_on_floor: bool = false

# --- 冲刺状态 ---
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_available: bool = true
var _dash_direction: int = 1

# --- 滑翔状态 ---
var _fall_time: float = 0.0

# --- 攻击状态 ---
var _attack_timer: float = 0.0
var _attack_phase: int = 0             ## 0=前摇 1=判定 2=后摇

# --- 受击状态 ---
var _hitstun_timer: float = 0.0

# --- 输入缓存（每帧采集一次，避免同一帧多次读取产生不一致）---
var _in_x: float = 0.0
var _in_jump_pressed: bool = false
var _in_dash_pressed: bool = false
var _in_attack_pressed: bool = false


func _ready() -> void:
	add_to_group(&"player")

	if profile == null:
		profile = MovementProfile.new()

	_apply_body_size()

	var stage: Abilities.Stage = debug_stage if override_stage else GameState.stage
	abilities = AbilitySet.new(stage)
	abilities.changed.connect(_on_abilities_changed)

	GameState.stage_changed.connect(_on_game_stage_changed)

	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)
	_sync_health_to_stage()

	attack_hitbox.deactivate()

	collision_layer = GameConfig.mask([GameConfig.Layer.PLAYER])
	collision_mask = GameConfig.mask([GameConfig.Layer.WORLD])


## 按 GameConfig 的主角尺寸重建碰撞体、受击框、攻击框和外观。
##
## 为什么在代码里算而不是在 Player.tscn 里填死像素值：
## 主角尺寸是世界尺度基准，调一次要同步改 4 个 shape + 2 个 ColorRect + 攻击框位置，
## 手改必漏。这里一处定义，全部派生。
##
## 各部件的比例关系（相对身体尺寸）：
##   受击框  比身体略窄一圈，避免"看起来没碰到却掉血"
##   攻击框  宽 0.8 身高、高 0.75 身高，向前伸出半个身位
##   交互圈  0.8 身高，够到脚边的长凳即可
##
## 外观不在这里派生：它由 PlayerVisual 按 visual_height_tiles 自己算，
## 因为美术素材的高度跟碰撞体从来不是 1:1（头发和武器总要溢出）。
func _apply_body_size() -> void:
	var w := GameConfig.tiles(GameConfig.PLAYER_TILE_WIDTH)
	var h := GameConfig.tiles(GameConfig.PLAYER_TILE_HEIGHT)

	_set_rect_shape($CollisionShape2D, Vector2(w, h))
	_set_rect_shape($Hurtbox/CollisionShape2D, Vector2(w * 0.88, h * 0.94))
	_set_rect_shape($AttackPivot/AttackHitbox/CollisionShape2D, Vector2(h * 0.8, h * 0.75))

	# 攻击框贴在身体前方：身体半宽 + 攻击框半宽，略有重叠好打中贴脸的敌人。
	attack_hitbox.position = Vector2(w * 0.5 + h * 0.34, -h * 0.06)


## shape 必须 duplicate 再改。Player.tscn 里的 SubResource 在
## 多实例场景下是共享的，直接改会波及所有实例（自检里同屏多个玩家就会中招）。
func _set_rect_shape(node: CollisionShape2D, size: Vector2) -> void:
	var rect := node.shape as RectangleShape2D
	if rect == null:
		rect = RectangleShape2D.new()
	else:
		rect = rect.duplicate() as RectangleShape2D
	rect.size = size
	node.shape = rect


func _physics_process(delta: float) -> void:
	_collect_input()
	_tick_timers(delta)

	match state:
		State.NORMAL:
			_process_normal(delta)
		State.DASHING:
			_process_dashing(delta)
		State.GLIDING:
			_process_gliding(delta)
		State.ATTACKING:
			_process_attacking(delta)
		State.HITSTUN:
			_process_hitstun(delta)
		State.DEAD:
			_process_dead(delta)

	move_and_slide()
	_post_move()


# ---------------------------------------------------------------------------
# 输入
# ---------------------------------------------------------------------------

func _collect_input() -> void:
	_in_x = Input.get_axis(&"move_left", &"move_right")
	_in_jump_pressed = Input.is_action_just_pressed(&"jump")
	_in_dash_pressed = Input.is_action_just_pressed(&"dash")
	_in_attack_pressed = Input.is_action_just_pressed(&"attack")

	if _in_jump_pressed:
		_jump_buffer_timer = profile.jump_buffer_time


func _tick_timers(delta: float) -> void:
	_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)
	_dash_cooldown_timer = maxf(0.0, _dash_cooldown_timer - delta)

	if is_on_floor():
		_coyote_timer = profile.coyote_time
		_fall_time = 0.0
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
		if velocity.y > 0.0:
			_fall_time += delta
		else:
			_fall_time = 0.0


# ---------------------------------------------------------------------------
# 状态：常规
# ---------------------------------------------------------------------------

func _process_normal(delta: float) -> void:
	# 优先级：攻击 > 冲刺 > 滑翔 > 跳跃 > 移动
	# 这个顺序决定了同帧多个输入时谁生效，改动会直接影响手感。
	if _in_attack_pressed and _can_attack():
		_enter_attack()
		return

	if _in_dash_pressed and _can_dash():
		_enter_dash()
		return

	if _should_start_glide():
		_change_state(State.GLIDING)
		return

	_try_jump()
	_apply_horizontal(delta, 1.0)
	_apply_gravity(delta)


func _try_jump() -> void:
	if _jump_buffer_timer <= 0.0:
		return

	# 地面跳 / 土狼跳
	if _coyote_timer > 0.0:
		velocity.y = profile.jump_velocity()
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		return

	# 二段跳 —— 只有拥有该能力时才存在
	if abilities.has(Abilities.DOUBLE_JUMP) and _air_jumps_used < 1:
		velocity.y = profile.double_jump_velocity()
		_air_jumps_used += 1
		_jump_buffer_timer = 0.0
		# 二段跳刷新冲刺额度：第二段滞空仍可用 shift 突进。
		# 否则"空中冲刺过沟 → 二段跳续力 → 再冲刺"的连招走不通，
		# 一次滞空只有一段冲刺可用，二段跳的后半程手感是断的。
		_dash_available = true
		# 视觉：让外观播一遍二段跳动画（播完/落地自动恢复常规外观）。
		if sprite != null:
			sprite.trigger_double_jump()
		EventBus.ability_used.emit(Abilities.DOUBLE_JUMP)


func _apply_horizontal(delta: float, speed_scale: float) -> void:
	var target := _in_x * profile.run_speed() * speed_scale
	var rate := profile.accel() if absf(target) > 0.01 else profile.decel()
	if not is_on_floor():
		rate *= profile.air_control
	velocity.x = move_toward(velocity.x, target, rate * delta)

	if absf(_in_x) > 0.01:
		_set_facing(1 if _in_x > 0.0 else -1)


func _apply_gravity(delta: float) -> void:
	var g := profile.gravity()

	# 下落时加重重力，让落地更利落。
	# 注意：上升段不做任何"松开按键削减速度"的处理——
	# 起跳初速度恒定，每次跳跃高度固定（由 jump_height_tiles 决定）。
	if velocity.y > 0.0:
		g *= profile.fall_gravity_multiplier

	velocity.y = minf(velocity.y + g * delta, profile.max_fall_speed())


# ---------------------------------------------------------------------------
# 状态：冲刺
# ---------------------------------------------------------------------------

func _can_dash() -> bool:
	return abilities.has(Abilities.DASH) \
		and _dash_available \
		and _dash_cooldown_timer <= 0.0


func _enter_dash() -> void:
	_dash_direction = int(signf(_in_x)) if absf(_in_x) > 0.01 else facing
	_set_facing(_dash_direction)
	_dash_timer = profile.dash_duration
	_dash_available = false
	_dash_cooldown_timer = profile.dash_duration + profile.dash_cooldown
	velocity.x = _dash_direction * profile.dash_speed()
	if profile.dash_ignore_gravity:
		velocity.y = 0.0
	_change_state(State.DASHING)
	EventBus.ability_used.emit(Abilities.DASH)


func _process_dashing(delta: float) -> void:
	_dash_timer -= delta
	velocity.x = _dash_direction * profile.dash_speed()
	if not profile.dash_ignore_gravity:
		_apply_gravity(delta)
	else:
		velocity.y = 0.0

	if _dash_timer <= 0.0:
		# 冲刺结束保留一部分速度，避免突兀急停。
		velocity.x *= 0.55
		_change_state(State.NORMAL)


# ---------------------------------------------------------------------------
# 状态：滑翔
# ---------------------------------------------------------------------------

func _should_start_glide() -> bool:
	return abilities.has(Abilities.GLIDE) \
		and not is_on_floor() \
		and velocity.y > 0.0 \
		and _fall_time >= profile.glide_min_fall_time \
		and Input.is_action_pressed(&"glide")


func _process_gliding(delta: float) -> void:
	# 滑翔中依然允许攻击和冲刺打断（如果拥有这些能力）。
	if _in_attack_pressed and _can_attack():
		_enter_attack()
		return
	if _in_dash_pressed and _can_dash():
		_enter_dash()
		return

	# 松手或落地即退出。
	if is_on_floor() or not Input.is_action_pressed(&"glide"):
		_change_state(State.NORMAL)
		return

	var target := _in_x * profile.glide_horizontal_speed()
	velocity.x = move_toward(velocity.x, target, profile.accel() * profile.air_control * delta)
	velocity.y = move_toward(velocity.y, profile.glide_fall_speed(), profile.gravity() * 0.5 * delta)

	if absf(_in_x) > 0.01:
		_set_facing(1 if _in_x > 0.0 else -1)


# ---------------------------------------------------------------------------
# 状态：攻击
# ---------------------------------------------------------------------------

func _can_attack() -> bool:
	# 锋锐切割是唯一的攻击手段。失去它之后，攻击输入完全无响应，
	# Hitbox 永远不会被激活，战斗系统干净地失效。
	return abilities.has(Abilities.CLEAVE)


func _enter_attack() -> void:
	_attack_phase = 0
	_attack_timer = profile.attack_windup
	attack_pivot.scale.x = facing
	_change_state(State.ATTACKING)
	# 视觉：攻击动画强制播完整条（逻辑状态 0.36s 就结束，演出不跟着被掐断）。
	if sprite != null:
		sprite.trigger_attack()
	EventBus.ability_used.emit(Abilities.CLEAVE)


func _process_attacking(delta: float) -> void:
	_attack_timer -= delta

	var move_scale := 0.0 if profile.attack_locks_movement else profile.attack_move_multiplier
	_apply_horizontal(delta, move_scale)
	_apply_gravity(delta)

	if _attack_timer > 0.0:
		return

	match _attack_phase:
		0:  # 前摇结束 -> 开判定
			_attack_phase = 1
			_attack_timer = profile.attack_active
			attack_hitbox.activate()
		1:  # 判定结束 -> 后摇
			_attack_phase = 2
			_attack_timer = profile.attack_recovery
			attack_hitbox.deactivate()
		_:  # 后摇结束
			attack_hitbox.deactivate()
			_change_state(State.NORMAL)


# ---------------------------------------------------------------------------
# 状态：受击硬直
# ---------------------------------------------------------------------------

func _process_hitstun(delta: float) -> void:
	_hitstun_timer -= delta
	# 硬直期间不接受方向输入，但保留摩擦和重力，让击退自然衰减。
	velocity.x = move_toward(velocity.x, 0.0, profile.decel() * 0.4 * delta)
	_apply_gravity(delta)
	if _hitstun_timer <= 0.0:
		_change_state(State.NORMAL)


func _process_dead(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, profile.decel() * delta)
	_apply_gravity(delta)


# ---------------------------------------------------------------------------
# 移动后处理
# ---------------------------------------------------------------------------

func _post_move() -> void:
	var on_floor := is_on_floor()

	# 落地瞬间：重置空中资源
	if on_floor and not _was_on_floor:
		_air_jumps_used = 0
		if profile.dash_refresh_on_land:
			_dash_available = true

	# 离地瞬间（非跳跃导致）：不消耗二段跳，交给土狼时间处理
	_was_on_floor = on_floor

	# 顶到天花板时清除上升速度，避免"贴着天花板飘"
	if is_on_ceiling() and velocity.y < 0.0:
		velocity.y = 0.0

	# 外观放在移动之后更新：此时 velocity 和 is_on_floor 都是本帧的最终结果。
	# 若放在 move_and_slide 之前，落地那一帧 on_floor 还是 false，
	# 角色会闪一帧下落姿势，快速起跳落地时看得很明显。
	if sprite != null:
		sprite.update_look(state, velocity, on_floor, _in_x)


# ---------------------------------------------------------------------------
# 能力与状态同步
# ---------------------------------------------------------------------------

func _on_abilities_changed(_current: Array, _gained: Array, lost: Array) -> void:
	_sync_health_to_stage()

	# 失去某能力时，如果正处于该能力的状态中，立刻退出，避免卡死。
	if lost.has(Abilities.DASH) and state == State.DASHING:
		_change_state(State.NORMAL)
	if lost.has(Abilities.GLIDE) and state == State.GLIDING:
		_change_state(State.NORMAL)
	if lost.has(Abilities.CLEAVE) and state == State.ATTACKING:
		attack_hitbox.deactivate()
		_change_state(State.NORMAL)


func _on_game_stage_changed(stage: Abilities.Stage) -> void:
	if override_stage:
		return
	abilities.set_stage(stage)


func _sync_health_to_stage() -> void:
	health.set_max_hp_penalty(abilities.hp_penalty())
	health.auto_regen = abilities.auto_regen()


# ---------------------------------------------------------------------------
# 受击与死亡
# ---------------------------------------------------------------------------

func _on_damaged(info: DamageInfo) -> void:
	if state == State.DEAD:
		return

	var kb := info.resolve_knockback(global_position)
	if kb != Vector2.ZERO:
		if profile.knockback_overrides_velocity:
			velocity = kb
		else:
			velocity += kb

	if state == State.DASHING:
		attack_hitbox.deactivate()
	if state == State.ATTACKING:
		attack_hitbox.deactivate()

	# 攻击动画被打断：受击硬直的 HURT 外观要立即可见，解除攻击强制。
	if sprite != null:
		sprite.cancel_attack_forced()

	_hitstun_timer = profile.hitstun_duration
	_change_state(State.HITSTUN)


func _on_died() -> void:
	attack_hitbox.deactivate()
	if sprite != null:
		sprite.cancel_attack_forced()
	_change_state(State.DEAD)
	EventBus.player_died.emit()


## 由复活流程调用：传送 + 回满血 + 保护性无敌。
func respawn_at(pos: Vector2) -> void:
	teleport_to(pos)
	health.revive()
	health.grant_invulnerability(1.0)
	EventBus.player_respawned.emit(pos)


## 只传送并清空运动状态，不碰血量。
##
## 坠落出界时用这个：掉一次坑该扣的血要真扣掉，
## 走 respawn_at 的话会顺手回满，惩罚就消失了。
func teleport_to(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	_air_jumps_used = 0
	_dash_available = true
	_dash_cooldown_timer = 0.0
	_hitstun_timer = 0.0
	_attack_timer = 0.0
	attack_hitbox.deactivate()
	_change_state(State.NORMAL)


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _change_state(next: State) -> void:
	if state == next:
		return
	var prev := state
	state = next
	state_changed.emit(prev, next)


func _set_facing(dir: int) -> void:
	if dir == 0 or facing == dir:
		return
	facing = dir
	if sprite != null:
		sprite.scale.x = dir
	if attack_pivot != null:
		attack_pivot.scale.x = dir


func state_name() -> String:
	return State.keys()[state]
