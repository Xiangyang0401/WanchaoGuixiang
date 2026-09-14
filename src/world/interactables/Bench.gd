class_name Bench
extends Interactable
## 长凳 —— 检查点 + 恢复点。
##
## 设定来源：戍卫时代的遗产，古时哨兵换岗途中歇脚的地方。
## 年轻阶段长凳毫无用处（潮还在，伤会自己好，玩家跑过时看都不会看一眼）；
## 成熟阶段它变成唯一的恢复手段。
##
## 机制上这是同一个物件，行为差异完全由 AbilitySet.auto_regen() 决定，
## 不需要两套长凳。

## 检查点唯一 id。同一关卡内不可重复，用于存档定位。
@export var checkpoint_id: StringName = &""

## 是否作为复活点。某些长凳可能只用来回血不做复活点。
@export var is_checkpoint: bool = true

## 复活位置相对长凳的**额外**偏移（格）。
##
## 注意：脚底贴地所需的抬升由 GameConfig.player_center_offset_y() 自动算，
## 这里只填造型特殊时需要的额外微调。
## 早期这里硬编码过 -0.5 格，主角一改高就全错位了——尺寸相关的值不要写死。
@export var respawn_offset_tiles: Vector2 = Vector2.ZERO

## 已激活过的长凳再交互时的提示。
@export var rest_prompt: String = "休息"

## 长凳尺寸（格）。造型按这个尺寸自动生成，主角改尺寸时跟着改这里即可。
@export var size_tiles: Vector2 = Vector2(3.0, 2.0)


func _ready() -> void:
	super._ready()
	# 长凳可以反复使用。
	one_shot = false
	if prompt_text == "交互":
		prompt_text = rest_prompt
	if checkpoint_id == &"":
		# 没填 id 时用节点名兜底，避免策划漏填导致存档定位失败。
		checkpoint_id = StringName(name)
	add_to_group(&"bench")
	_apply_size()


## 按 size_tiles 重建交互框和占位造型。
## 场景里写死像素值的话，主角一改尺寸长凳就变成小板凳了。
func _apply_size() -> void:
	var s := size_tiles * GameConfig.TILE_SIZE

	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null:
		var rect := cs.shape as RectangleShape2D
		rect = rect.duplicate() as RectangleShape2D if rect != null else RectangleShape2D.new()
		# 交互框比造型大一圈，让玩家不用站得分毫不差。
		rect.size = s * 1.15
		cs.shape = rect

	# 造型：座面贴地上方，两条腿撑到地面，靠背在座面之上。
	var seat_h := s.y * 0.16
	var leg_w := s.x * 0.1
	var leg_h := s.y * 0.34
	_fit("Visual/Seat", Vector2(-s.x * 0.5, -seat_h), Vector2(s.x, seat_h))
	_fit("Visual/LegL", Vector2(-s.x * 0.42, 0), Vector2(leg_w, leg_h))
	_fit("Visual/LegR", Vector2(s.x * 0.42 - leg_w, 0), Vector2(leg_w, leg_h))
	_fit("Visual/Back", Vector2(-s.x * 0.5, -s.y * 0.5), Vector2(s.x, s.y * 0.12))


func _fit(path: String, pos: Vector2, size: Vector2) -> void:
	var r := get_node_or_null(path) as ColorRect
	if r == null:
		return
	r.offset_left = pos.x
	r.offset_top = pos.y
	r.offset_right = pos.x + size.x
	r.offset_bottom = pos.y + size.y


func _on_interact(by: Node) -> void:
	var player := by as Player
	if player == null:
		return

	if is_checkpoint:
		# 基础抬升按主角身高算，额外微调走 respawn_offset_tiles。
		var base := Vector2(0, GameConfig.player_center_offset_y())
		GameState.activate_checkpoint(
			checkpoint_id,
			GameState.current_level_id,
			global_position + base + GameConfig.tiles(1.0) * respawn_offset_tiles
		)

	player.health.heal_full()
	EventBus.rested_at_bench.emit(checkpoint_id)
