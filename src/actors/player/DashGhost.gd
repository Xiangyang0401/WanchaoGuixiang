class_name DashGhost
extends Node2D
## 冲刺残影拖尾。冲刺期间按固定间隔把角色当前帧"拍"成幽灵剪影，
## 幽灵留在原地快速淡出，形成忍者残影术的拖尾效果。
##
## 【设计意图】冲刺只有 0.16s，任何专属动画都来不及看清；
## 残影是横版游戏最经典的冲刺表达——它同时强化了"速度感"和"距离感"，
## 黑剪影风格下尤其合适（残影 = 同款剪影染色，视觉语言完全统一）。
##
## 【为什么由 PlayerVisual 驱动】残影是纯视觉表现，跟着外观状态走，
## 与移动逻辑零耦合：update_look 判定 DASHING 时 set_active(true) 即可。
## 本组件不引用 Player，丢进任何有 AnimatedSprite2D 的场景都能用。
##
## 【生成方式】不复制节点树，只取当前帧纹理 + 全局变换生成一个
## Sprite2D。挂在 current_scene 下（不挂玩家身上），玩家动/翻转都不影响
## 已生成的残影——残影本就该留在"冲刺经过的位置"。

## 残影生成间隔（秒）。0.03s ≈ 每 2 帧一张，0.16s 冲刺出 5 张左右。
@export var spawn_interval: float = 0.03

## 单张残影淡出时长（秒）。冲刺结束后拖尾还能延续一小会儿。
@export var fade_time: float = 0.22

## 残影起始透明度。
@export var start_alpha: float = 0.45

## 残影染色。黑剪影乘上这个颜色会变成冷色幽灵；
## 想要"原色残影"就改成 Color(1, 1, 1, 1)。
@export var ghost_tint: Color = Color(0.55, 0.8, 1.0, 1.0)

var _sprite: AnimatedSprite2D
var _active: bool = false
var _timer: float = 0.0


## 绑定要跟踪的动画精灵，由宿主在 _ready 时调用。
func setup(sprite: AnimatedSprite2D) -> void:
	_sprite = sprite


func set_active(active: bool) -> void:
	_active = active
	if not active:
		_timer = 0.0  # 归零，下次进入冲刺立刻出第一张残影


func _process(delta: float) -> void:
	if not _active or _sprite == null or not _sprite.visible:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = spawn_interval
	_spawn_ghost()


func _spawn_ghost() -> void:
	var tex := _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	if tex == null:
		return

	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.centered = true
	ghost.modulate = Color(ghost_tint.r, ghost_tint.g, ghost_tint.b, start_alpha)
	ghost.z_index = _sprite.z_index - 1  # 残影垫在角色身后

	var layer := get_tree().current_scene
	if layer == null:
		layer = get_parent()
	layer.add_child(ghost)
	# 进树后再拷贝全局变换，避免"未入树时 global_transform 语义不稳"的坑
	ghost.global_transform = _sprite.global_transform

	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, fade_time)
	tween.tween_callback(ghost.queue_free)
