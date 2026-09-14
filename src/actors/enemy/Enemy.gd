class_name Enemy
extends CharacterBody2D
## 敌人基类。所有怪共用这一个类，差异全部由 EnemyData（数值）
## 和 EnemyBehavior（行为）两个资源决定。
##
## 这样设计的原因：
##   如果每种怪写一个继承类，加到二十种怪时会有二十个几乎相同的文件，
##   改一个通用逻辑（比如受击闪烁）要改二十遍。
##   现在通用逻辑只有这一份，怪的差异是数据。
##
## 后续 boss 如果需要复杂的多阶段逻辑，可以继承 Enemy 并重写，
## 但普通怪不应该需要写代码。

signal died_signal

@export var data: EnemyData
@export var behavior: EnemyBehavior

@onready var health: Health = $Health
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var contact_hitbox: Hitbox = $ContactHitbox
@onready var visual: Node2D = $Visual
## 占位色块。正式美术接入后换成 Sprite2D/AnimatedSprite2D，
## 这里置空即可，其余逻辑不受影响。
@onready var visual_rect: ColorRect = $Visual/Body
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var ledge_probe: RayCast2D = $LedgeProbe

var facing: int = 1
var spawn_position: Vector2
var _dead: bool = false
var _knockback: Vector2 = Vector2.ZERO
var _flash_timer: float = 0.0


func _ready() -> void:
	add_to_group(&"enemy")
	spawn_position = global_position

	if data == null:
		data = EnemyData.new()

	_apply_data()

	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)

	collision_layer = GameConfig.mask([GameConfig.Layer.ENEMY])
	collision_mask = GameConfig.mask([GameConfig.Layer.WORLD])

	if behavior != null:
		behavior.enter(self)


func _apply_data() -> void:
	health.base_max_hp = data.max_hp
	health.invulnerability_time = data.invulnerability_time
	health.auto_regen = false

	contact_hitbox.damage = data.contact_damage
	contact_hitbox.knockback_force = data.contact_knockback
	contact_hitbox.continuous = true
	contact_hitbox.tick_interval = data.contact_interval
	if data.contact_damage > 0:
		contact_hitbox.activate()
	else:
		contact_hitbox.deactivate()

	# 碰撞体与占位视觉按配置尺寸生成，策划改 size_tiles 即可，无需改场景。
	#
	# 注意必须 duplicate：Enemy.tscn 里 Hurtbox 和 ContactHitbox 引用的是
	# 同一个 SubResource，而 SubResource 在所有实例间共享。
	# 直接改 .size 会让场上每一只怪的判定框都跟着变成最后一只的尺寸。
	var size := data.size_px()
	_fit_shape(body_shape, size)
	_fit_shape($Hurtbox/CollisionShape2D as CollisionShape2D, size)
	_fit_shape($ContactHitbox/CollisionShape2D as CollisionShape2D, size)

	if visual_rect != null:
		visual_rect.size = size
		visual_rect.position = -size * 0.5
		visual_rect.color = data.placeholder_color

	if ledge_probe != null:
		ledge_probe.position = Vector2(size.x * 0.5, 0)
		ledge_probe.target_position = Vector2(0, size.y * 0.5 + GameConfig.tiles(0.5))
		ledge_probe.collision_mask = GameConfig.mask([GameConfig.Layer.WORLD])


func _fit_shape(node: CollisionShape2D, size: Vector2) -> void:
	if node == null:
		return
	var rect := node.shape as RectangleShape2D
	rect = rect.duplicate() as RectangleShape2D if rect != null else RectangleShape2D.new()
	rect.size = size
	node.shape = rect


func _physics_process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0 and visual != null:
			visual.modulate = Color.WHITE

	if _dead:
		velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		return

	# 击退期间行为暂不接管，让物理自然衰减。
	if _knockback.length_squared() > 1.0:
		velocity = _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, 1400.0 * delta)
		_apply_gravity(delta)
	else:
		_knockback = Vector2.ZERO
		if behavior != null:
			behavior.tick(self, delta)
		_apply_gravity(delta)

	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if data.gravity_scale <= 0.0:
		return
	# 用一个固定的世界重力值，敌人不需要玩家那套可变重力手感。
	# 数值以「格」为单位，主角尺寸变了要跟着变，否则怪会显得飘。
	var g := GameConfig.tiles(120.0) * data.gravity_scale
	if not is_on_floor():
		velocity.y = minf(velocity.y + g * delta, GameConfig.tiles(50.0))
	elif velocity.y > 0.0:
		velocity.y = 0.0


# ---------------------------------------------------------------------------
# 供行为脚本使用的辅助方法
# ---------------------------------------------------------------------------

func set_facing(dir: int) -> void:
	if dir == 0 or facing == dir:
		return
	facing = dir
	if visual != null:
		visual.scale.x = dir
	if ledge_probe != null:
		ledge_probe.position.x = absf(ledge_probe.position.x) * dir


## 前方是否有悬崖（用于巡逻怪在边缘转身）。
func is_at_ledge() -> bool:
	if ledge_probe == null or not is_on_floor():
		return false
	return not ledge_probe.is_colliding()


## 是否撞墙。
func is_at_wall() -> bool:
	return is_on_wall()


## 距离出生点的水平偏移。
func offset_from_spawn() -> float:
	return global_position.x - spawn_position.x


func is_dead() -> bool:
	return _dead


# ---------------------------------------------------------------------------
# 受击与死亡
# ---------------------------------------------------------------------------

func _on_damaged(info: DamageInfo) -> void:
	var kb := info.resolve_knockback(global_position)
	if kb != Vector2.ZERO:
		_knockback = kb * (1.0 - data.knockback_resistance)

	# 受击闪白。表现很轻，但没有它玩家会感觉不到自己打中了。
	if visual != null:
		visual.modulate = Color(3, 3, 3)
		_flash_timer = 0.08

	if behavior != null:
		behavior.on_damaged(self, info)


func _on_died() -> void:
	if _dead:
		return
	_dead = true

	contact_hitbox.deactivate()
	hurtbox.set_deferred(&"monitorable", false)
	set_collision_layer_value(GameConfig.Layer.ENEMY, false)

	if behavior != null:
		behavior.exit(self)

	if visual != null:
		visual.modulate = Color(0.4, 0.4, 0.4, 0.7)

	died_signal.emit()

	if data.corpse_duration > 0.0:
		await get_tree().create_timer(data.corpse_duration).timeout
	queue_free()
