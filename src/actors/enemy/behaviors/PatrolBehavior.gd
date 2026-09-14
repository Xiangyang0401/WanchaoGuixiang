class_name PatrolBehavior
extends EnemyBehavior
## 巡逻行为：在出生点左右来回走。
##
## 转身条件（任一满足即转）：
##   1. 走到巡逻范围边界
##   2. 撞墙（data.turn_at_wall）
##   3. 走到悬崖边（data.turn_at_ledge）
##
## 第 3 条很重要：没有它，巡逻怪会自己走下平台掉进坑里，
## 策划摆一次图就会遇到，然后开始怀疑是不是 bug。

## 起始朝向。1 = 右，-1 = 左。
@export var initial_facing: int = 1

var _pause_timer: float = 0.0


func enter(enemy: Enemy) -> void:
	enemy.set_facing(initial_facing)
	_pause_timer = 0.0


func tick(enemy: Enemy, delta: float) -> void:
	var d := enemy.data

	if _pause_timer > 0.0:
		_pause_timer -= delta
		enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, d.move_speed() * 4.0 * delta)
		if _pause_timer <= 0.0:
			enemy.set_facing(-enemy.facing)
		return

	var should_turn := false

	# 边界检查：用当前朝向判断，避免刚转身又被判定越界导致抖动。
	var offset := enemy.offset_from_spawn()
	if d.patrol_range_tiles > 0.0:
		if enemy.facing > 0 and offset >= d.patrol_range():
			should_turn = true
		elif enemy.facing < 0 and offset <= -d.patrol_range():
			should_turn = true

	if not should_turn and d.turn_at_wall and enemy.is_at_wall():
		should_turn = true

	if not should_turn and d.turn_at_ledge and enemy.is_at_ledge():
		should_turn = true

	if should_turn:
		if d.patrol_pause > 0.0:
			_pause_timer = d.patrol_pause
			enemy.velocity.x = 0.0
			return
		enemy.set_facing(-enemy.facing)

	enemy.velocity.x = enemy.facing * d.move_speed()
