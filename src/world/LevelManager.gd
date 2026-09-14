class_name LevelManager
extends Node
## 游戏运行时根节点。负责关卡加载卸载、玩家生成、复活流程。
##
## 【关键架构决策】玩家节点跨关卡持久存在，不随关卡卸载。
##   原因：玩家身上挂着能力集、血量等运行时状态。如果每次切图都销毁重建，
##   这些状态就必须序列化到别处再读回来，多一道容易出错的环节。
##   现在玩家是 LevelManager 的子节点，切图只是换掉 _current_level 并挪一下位置。
##
## 场景树结构：
##   Main (LevelManager)
##     ├── LevelHolder     ← 关卡实例挂这里，切图时整个替换
##     ├── Player          ← 常驻
##     ├── PlayerCamera    ← 常驻
##     └── HUD             ← 常驻

signal level_changed(level_id: StringName)

@export var player_scene: PackedScene
@export var camera_scene: PackedScene

## 启动时加载的关卡。
@export var start_level: StringName = &"test"
@export var start_entry: StringName = &"default"

## 死亡到复活之间的停顿（秒）。
@export var respawn_delay: float = 1.2

## 玩家掉出关卡下边界多少格后判定坠落死亡。
##
## 没有这个兜底的话，只要地图有一处没封边（或者关卡还没画完），
## 玩家掉下去就会无限下坠，游戏彻底卡死且没有任何提示。
## 留一段余量是因为下边界外常常还有一截视觉延伸。
@export var fall_death_margin_tiles: float = 8.0

## 坠落造成的伤害。设为 0 表示直接复活不掉血。
@export var fall_damage: int = 1

var _current_level: Level
var _player: Player
var _camera: PlayerCamera
var _holder: Node2D
var _transitioning: bool = false


func _ready() -> void:
	_holder = Node2D.new()
	_holder.name = "LevelHolder"
	add_child(_holder)

	_spawn_player()
	_spawn_camera()

	EventBus.level_transition_requested.connect(_on_transition_requested)
	EventBus.player_died.connect(_on_player_died)

	load_level(start_level, start_entry)


# ---------------------------------------------------------------------------
# 关卡加载
# ---------------------------------------------------------------------------

func load_level(level_id: StringName, entry_id: StringName = &"default") -> void:
	var path := LevelRegistry.scene_path(level_id)
	if path == "":
		push_error("未注册的关卡 id：%s（检查 LevelRegistry）" % level_id)
		_transitioning = false
		return

	var packed := load(path) as PackedScene
	if packed == null:
		push_error("关卡场景加载失败：%s" % path)
		_transitioning = false
		return

	# 先卸旧的再装新的，避免同一时刻两个关卡的物理体互相干扰。
	# 顺序：先摘出场景树（立刻生效），再排队释放。
	# 反过来写的话 queue_free 已经标记了节点，remove_child 时机不确定，
	# 新旧关卡会在同一帧内共存并互相碰撞。
	if _current_level != null:
		_holder.remove_child(_current_level)
		_current_level.queue_free()
		_current_level = null

	var inst := packed.instantiate() as Level
	if inst == null:
		push_error("关卡根节点不是 Level 类型：%s" % path)
		_transitioning = false
		return

	_holder.add_child(inst)
	_current_level = inst

	# level_id 以注册表为准，避免场景里填错导致存档定位错乱。
	_current_level.level_id = level_id
	GameState.current_level_id = level_id
	GameState.mark_visited(level_id)

	_place_player_at_entry(entry_id)
	_camera.apply_limits(_current_level.get_world_bounds())
	_camera.set_target(_player)

	_transitioning = false
	level_changed.emit(level_id)
	EventBus.level_loaded.emit(level_id)


func _place_player_at_entry(entry_id: StringName) -> void:
	if _current_level == null or _player == null:
		return
	var entry := _current_level.get_entry(entry_id)
	if entry == null:
		push_warning("关卡 %s 找不到入口 %s，使用原点" % [_current_level.level_id, entry_id])
		_player.global_position = Vector2.ZERO
	else:
		_player.global_position = entry.global_position
		_player._set_facing(entry.facing)
	_player.velocity = Vector2.ZERO


func _on_transition_requested(level_id: StringName, entry_id: StringName) -> void:
	if _transitioning:
		return
	_transitioning = true
	# 延后一帧再切，避免在物理回调里销毁正在参与碰撞的节点。
	call_deferred(&"load_level", level_id, entry_id)


# ---------------------------------------------------------------------------
# 坠落兜底
# ---------------------------------------------------------------------------
# 只要地图有一处没封边，玩家掉下去就会无限下坠、游戏卡死且毫无提示。
# 与其指望每张图都不出错，不如在这里统一兜住。
# 放在 LevelManager 而不是 Player，是因为「掉出多远算出界」取决于关卡边界。

func _physics_process(_delta: float) -> void:
	_check_fall_out()


func _check_fall_out() -> void:
	if _player == null or _current_level == null or _transitioning:
		return
	if _player.health.is_dead():
		return

	var limit := _current_level.get_world_bounds().end.y + GameConfig.tiles(fall_death_margin_tiles)
	if _player.global_position.y < limit:
		return

	if fall_damage > 0:
		var info := DamageInfo.create(fall_damage, null, 0.0)
		info.ignore_invulnerability = true
		_player.health.take_damage(info)

	# 还活着就只做传送，不回血——掉一次坑该扣的血必须真扣。
	# 死了的话交给 _on_player_died 走正常复活流程。
	if not _player.health.is_dead():
		_player.teleport_to(get_respawn_position())
		_player.health.grant_invulnerability(0.6)
		EventBus.player_respawned.emit(_player.global_position)


# ---------------------------------------------------------------------------
# 玩家与相机
# ---------------------------------------------------------------------------

func _spawn_player() -> void:
	if player_scene == null:
		push_error("LevelManager 未设置 player_scene")
		return
	_player = player_scene.instantiate() as Player
	add_child(_player)


func _spawn_camera() -> void:
	if camera_scene != null:
		_camera = camera_scene.instantiate() as PlayerCamera
	else:
		_camera = PlayerCamera.new()
	add_child(_camera)
	_camera.set_target(_player)


func get_player() -> Player:
	return _player


func get_current_level() -> Level:
	return _current_level


# ---------------------------------------------------------------------------
# 复活
# ---------------------------------------------------------------------------
# 规则（按策划要求）：
#   检查点复活优先级 > 区域默认复活点。
#   若检查点在别的关卡，先切回那关再复活。

func _on_player_died() -> void:
	# 复活倒计时用 process_always：死亡后若撞上剧情暂停（如对话），计时不能被冻结，
	# 否则暂停结束玩家会被"迟到"的复活突然传送走（还可能在错误的关卡）。
	await get_tree().create_timer(respawn_delay, true).timeout
	respawn_player()


## 当前应该复活到哪。检查点优先于本关默认复活点。
##
## 注意：只算位置，不管跨关卡。检查点在别的关卡时由 respawn_player 负责先切图。
func get_respawn_position() -> Vector2:
	if GameState.has_checkpoint():
		return GameState.active_checkpoint_position
	if _current_level != null:
		return _current_level.get_default_respawn()
	return Vector2.ZERO


func respawn_player() -> void:
	if _player == null or not _player.health.is_dead():
		# 玩家还活着就什么也不做。死亡计时器可能迟到（见 _on_player_died），
		# 若玩家在等待期间已被其他路径复活，这里不能再补一次传送把人挪走。
		return

	if GameState.has_checkpoint():
		var cp_level := GameState.active_checkpoint_level
		if cp_level != &"" and cp_level != GameState.current_level_id:
			_transitioning = true
			load_level(cp_level, &"default")
		_player.respawn_at(GameState.active_checkpoint_position)
		return

	# 没有检查点：回到本关默认复活点。
	var pos := Vector2.ZERO
	if _current_level != null:
		pos = _current_level.get_default_respawn()
	_player.respawn_at(pos)
