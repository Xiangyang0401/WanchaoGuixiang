class_name MovementProfile
extends Resource
## 主角手感参数集。
##
## 独立成 Resource 而不是写在控制器里，有三个好处：
##   1. 你可以在编辑器里边跑边拖，改动立刻生效
##   2. 可以存多份做对比（比如"年轻手感"和"迟缓手感"，后期区域可能需要）
##   3. 参数和逻辑分离，调参不会误改代码
##
## 单位说明：
##   距离用「格」（1 格 = 32px），因为你摆地图时是按格思考的。
##   时间用秒。内部会自动换算成像素。

@export_group("水平移动")
## 最大跑速（格/秒）。
@export var run_speed_tiles: float = 8.0
## 从静止到全速所需时间（秒）。越小越跟手，越大越"重"。
@export var accel_time: float = 0.08
## 从全速到停止所需时间（秒）。
@export var decel_time: float = 0.10
## 空中的加减速倍率。<1 表示空中操控更迟钝。
@export_range(0.0, 1.0) var air_control: float = 0.75

@export_group("跳跃")
## 跳跃最高点（格）。这是设计地图的核心依据。
## 跳跃高度固定：无论按键按多久，每次起跳都到同一高度（初速度恒定）。
@export var jump_height_tiles: float = 3.2
## 上升到最高点所需时间（秒）。它和高度共同决定了重力大小。
@export var jump_rise_time: float = 0.45
## 下落时的重力倍率。>1 让下落更快，手感更利落（几乎所有平台游戏都这么做）。
@export var fall_gravity_multiplier: float = 1.3
## 最大下落速度（格/秒），防止掉太久变得不可控。
@export var max_fall_speed_tiles: float = 15.0

@export_group("跳跃宽容度")
## 土狼时间：离开平台边缘后仍可起跳的宽容窗口（秒）。
## 这个参数玩家感觉不到，但没有它会觉得"明明按了却没跳"。
@export var coyote_time: float = 0.12
## 跳跃缓冲：落地前提前按跳，落地瞬间自动执行（秒）。
@export var jump_buffer_time: float = 0.14

@export_group("二段跳")
## 二段跳高度（格）。通常略低于一段跳。
@export var double_jump_height_tiles: float = 2.6

@export_group("疾风冲刺")
## 冲刺速度（格/秒）。
@export var dash_speed_tiles: float = 22.0
## 冲刺持续时间（秒）。
@export var dash_duration: float = 0.16
## 冲刺冷却（秒）。
@export var dash_cooldown: float = 0.45
## 冲刺期间是否免疫重力（悬空直线冲）。
@export var dash_ignore_gravity: bool = true
## 落地是否重置冲刺次数。
@export var dash_refresh_on_land: bool = true

@export_group("滑翔")
## 滑翔时的下落速度（格/秒）。远小于正常下落。
@export var glide_fall_speed_tiles: float = 3.0
## 滑翔时的水平移动速度（格/秒）。
@export var glide_horizontal_speed_tiles: float = 6.5
## 需要下落多久才能开始滑翔（秒），避免刚跳起就飘。
@export var glide_min_fall_time: float = 0.12

@export_group("攻击")
## 一次挥砍从按下到判定生效的前摇（秒）。
## 与攻击动画（BuildAnimations.gd 的 ATTACK_DURATIONS）对齐：
## 0.35s 是蓄势段播完、剑开始刺出的时刻——判定跟着视觉走，
## 否则剑还没伸出去伤害就结算了，打击感是错的。
@export var attack_windup: float = 0.35
## 判定持续时间（秒）。对齐动画刺出段（0.25s）。
@export var attack_active: float = 0.25
## 判定结束到可以再次攻击的后摇（秒）。对齐动画收招段（0.33s）。
@export var attack_recovery: float = 0.33
## 攻击时是否锁住水平移动。出招全程锁死：提膝蓄势是单腿站姿，
## 移动会破坏姿态演出，也符合"出招硬直"的常规手感。
@export var attack_locks_movement: bool = true
## 攻击时的移动速度倍率（未锁死时生效）。
@export_range(0.0, 1.0) var attack_move_multiplier: float = 0.5

@export_group("受击")
## 受击硬直时长（秒），期间玩家无法操作。
@export var hitstun_duration: float = 0.22
## 受击击退是否覆盖当前速度（true）还是叠加（false）。
@export var knockback_overrides_velocity: bool = true


# ---------------------------------------------------------------------------
# 换算成引擎用的像素单位
# ---------------------------------------------------------------------------

func run_speed() -> float:
	return GameConfig.tiles(run_speed_tiles)

func max_fall_speed() -> float:
	return GameConfig.tiles(max_fall_speed_tiles)

func dash_speed() -> float:
	return GameConfig.tiles(dash_speed_tiles)

func glide_fall_speed() -> float:
	return GameConfig.tiles(glide_fall_speed_tiles)

func glide_horizontal_speed() -> float:
	return GameConfig.tiles(glide_horizontal_speed_tiles)

## 由「跳跃高度 + 上升时间」反推重力。
## 公式来源：h = g*t²/2  =>  g = 2h/t²
func gravity() -> float:
	var h := GameConfig.tiles(jump_height_tiles)
	var t := maxf(0.01, jump_rise_time)
	return 2.0 * h / (t * t)

## 起跳初速度：v = g*t
func jump_velocity() -> float:
	return -gravity() * jump_rise_time

## 二段跳初速度，按高度比例缩放。
func double_jump_velocity() -> float:
	var g := gravity()
	var h := GameConfig.tiles(double_jump_height_tiles)
	return -sqrt(2.0 * g * maxf(0.0, h))

## 加速度（像素/秒²）。
func accel() -> float:
	return run_speed() / maxf(0.01, accel_time)

func decel() -> float:
	return run_speed() / maxf(0.01, decel_time)
