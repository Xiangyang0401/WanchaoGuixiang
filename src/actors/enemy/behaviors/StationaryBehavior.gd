class_name StationaryBehavior
extends EnemyBehavior
## 静止行为：原地不动。
##
## 用途：障碍型的怪（尖刺生物、固定炮台的基础形态）。
## 虽然逻辑几乎为空，但仍然独立成一个策略，
## 这样 Enemy 不需要处理"behavior 为 null"的特例分支。

## 是否面朝玩家。开启后会随玩家位置翻转朝向（纯表现，不影响行为）。
@export var face_player: bool = false


func tick(enemy: Enemy, delta: float) -> void:
	enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.data.move_speed() * 6.0 * delta + 200.0 * delta)

	if not face_player:
		return

	var players := enemy.get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return
	var p := players[0] as Node2D
	if p == null:
		return
	enemy.set_facing(1 if p.global_position.x >= enemy.global_position.x else -1)
