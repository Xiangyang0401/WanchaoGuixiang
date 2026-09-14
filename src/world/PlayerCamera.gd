class_name PlayerCamera
extends Camera2D
## 跟随主角的相机。
##
## 关卡边界由 Level 在加载时通过 apply_limits() 设置，
## 相机不会越过关卡边缘露出外面的空白。
##
## 所有观感参数都从 GameConfig 每帧读取，改了立刻生效，
## 方便你在 F1 面板里拖到满意再写回配置。

## 前瞻的跟随速度，越小越迟钝。纯手感参数，不需要关卡级差异，所以留在这里。
@export var lookahead_smoothing: float = 3.0

var _target: Node2D
var _lookahead: float = 0.0

## 关卡边界（像素），由 apply_limits 记下。
## 必须缓存原值，因为限位要不要生效取决于 zoom，而 zoom 是运行时可改的。
var _bounds: Rect2 = Rect2()
var _has_bounds: bool = false

## 放开限位时用的哨兵值。Camera2D 的 limit 是 int，给个远到不可能碰到的数。
const LIMIT_OFF: int = 100000000


func _ready() -> void:
	_apply_config()
	make_current()


func _apply_config() -> void:
	zoom = Vector2.ONE * GameConfig.camera_zoom
	# 不用引擎自带的 position_smoothing：它不分轴，水平/纵向共用同一速度。
	# 主角跳跃的纵向速度远超水平速度，统一平滑必然导致镜头纵向追不上、
	# 画面上下窜动（就是"镜头晃动"的观感）。分轴平滑在 _physics_process 手动做。
	position_smoothing_enabled = false
	_refresh_limits()


## 按当前 zoom 重新决定限位是否生效。
##
## 关键：Camera2D 在某个轴的限位框比视口还小时，会把相机**钉死在限位框中央**，
## 此时 global_position 写什么都没用——offset、lookahead、跟随全部失效。
##
## 【四向全放开：构图恒定】
##   相机 center 完全由 _physics_process 的跟随逻辑决定：
##   zoom = GameConfig.camera_zoom（全局常量）、
##   角色永远落在同一屏幕构图位（camera_offset_ratio + lookahead），
##   **不随关卡尺寸/边界变化**。策划画关卡时以实机构图为对齐依据：
##   地面画在同一行 → 实机地面永远在屏幕同一高度。
##
##   代价：玩家接近关卡边缘（或跳得极高）时视野会越出地形，露出关卡外空白。
##   这是"构图恒定"的必然取舍，防露白是关卡设计的责任：
##   出口摆进红线内侧（LevelBoundsGuide 绿线）、关外用背景/装饰延伸盖住。
##
##   apply_limits 仍保留接口（记录边界供将来锁镜头类玩法用），但不再钳制相机。
func _refresh_limits() -> void:
	limit_left = -LIMIT_OFF
	limit_right = LIMIT_OFF
	limit_top = -LIMIT_OFF
	limit_bottom = LIMIT_OFF


func _physics_process(delta: float) -> void:
	# 每帧同步配置，让 F1 面板的滑块能实时生效。
	_apply_config()

	if _target == null or not is_instance_valid(_target):
		_acquire_target()
		return

	var la_dist := _lookahead_distance()
	var desired := 0.0
	if _target is Player:
		var p := _target as Player
		if absf(p.velocity.x) > 10.0:
			desired = signf(p.velocity.x) * la_dist
	_lookahead = move_toward(_lookahead, desired, la_dist * lookahead_smoothing * delta)

	var target_pos := _target.global_position + _offset() + Vector2(_lookahead, 0)

	# 分轴指数平滑：
	#   x 用慢平滑（camera_smoothing），保留水平移动的余量感与前瞻；
	#   y 用快平滑（camera_smoothing_y），跳跃/下落时镜头几乎贴着主角，
	#   消除纵向追不上导致的上下窜动。
	# 指数逼近 k = 1 - e^(-speed*dt)；speed <= 0 视为硬跟随。
	global_position.x = _smooth(global_position.x, target_pos.x,
		GameConfig.camera_smoothing, delta)
	global_position.y = _smooth(global_position.y, target_pos.y,
		GameConfig.camera_smoothing_y, delta)


## 单轴指数平滑。speed <= 0 直接贴目标（硬跟随）。
static func _smooth(current: float, desired: float, speed: float, delta: float) -> float:
	if speed <= 0.0:
		return desired
	return lerpf(current, desired, 1.0 - exp(-speed * delta))


## 相机相对玩家的固定偏移（像素）。
##
## 按当前可见范围的比例算，不是固定格数——这样改 zoom 时构图自动保持。
## 除以 2 是因为比例定义的是"占半屏的多少"：
## -1.0 表示把角色顶到屏幕边缘，取值范围直观。
func _offset() -> Vector2:
	return GameConfig.camera_offset_ratio * GameConfig.visible_world_size() * 0.5


## 前瞻距离（像素）。同样按可见宽度的比例算，理由见 _offset。
func _lookahead_distance() -> float:
	return GameConfig.camera_lookahead_ratio * GameConfig.visible_world_size().x * 0.5


func set_target(t: Node2D) -> void:
	_target = t
	if t != null:
		# 首次绑定时直接瞬移到位（内置平滑已禁用，此处即最终位置），
		# 避免开局相机从原点飞过来。
		global_position = t.global_position + _offset()


## 由 Level 调用，设置相机不可越过的世界边界（像素）。
## 只记录，实际是否生效由 _refresh_limits 按当前 zoom 判断。
func apply_limits(rect: Rect2) -> void:
	_bounds = rect
	_has_bounds = true
	_refresh_limits()


func _acquire_target() -> void:
	var players := get_tree().get_nodes_in_group(&"player")
	if not players.is_empty():
		set_target(players[0] as Node2D)
