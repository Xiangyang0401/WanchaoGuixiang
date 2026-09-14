class_name EnemyBehavior
extends Resource
## 敌人行为策略基类。
##
## 为什么把行为独立成 Resource 而不是给每种怪写一个继承类：
##   继承会导致"巡逻怪 + 会飞" "巡逻怪 + 会喷火"这类组合产生类爆炸。
##   策略对象可以自由组合替换，加一种新行为只写一个小文件，
##   而且策划能在编辑器里直接给同一种怪换行为试效果。
##
## 生命周期：enter() -> 每物理帧 tick() -> exit()

## 敌人生成时调用一次。
func enter(_enemy: Enemy) -> void:
	pass

## 每物理帧调用。在这里设置 enemy.velocity，不要直接改 position。
func tick(_enemy: Enemy, _delta: float) -> void:
	pass

## 被替换或敌人死亡时调用。
func exit(_enemy: Enemy) -> void:
	pass

## 敌人受击时调用，行为可以据此做出反应（比如被打断、转身面向攻击者）。
func on_damaged(_enemy: Enemy, _info: DamageInfo) -> void:
	pass
