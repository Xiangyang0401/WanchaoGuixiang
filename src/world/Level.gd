class_name Level
extends Node2D
## 关卡基类。每张地图的根节点都用它。
##
## 职责：
##   - 声明自己的 id 和世界边界
##   - 提供入口点查询
##   - 提供默认复活点
##   - 收集本关的 TileMapLayer，供边界自动推算
##
## 关卡不负责加载/卸载自己，那是 LevelManager 的事。
## 这条边界很重要：关卡自己管自己的生命周期会导致切换逻辑散落各处。

## 关卡 id，必须与 LevelRegistry 中的键一致。
@export var level_id: StringName = &""

## 关卡显示名，调试面板和将来的地图 UI 用。
@export var display_name: String = ""

## 手动指定的世界边界（格）。留空（size 为 0）则从 TileMapLayer 自动推算。
@export var manual_bounds_tiles: Rect2 = Rect2()

## 相机边界向外扩展的余量（格）。给一点余量能避免主角贴边时视野太局促。
@export var bounds_padding_tiles: float = 0.0

## 教学提示（只在编辑器摆给玩家看的基础操作引导）。
##
## 每行一条，显示在屏幕底部。支持占位符 `{action:按键动作名}`，
## 会自动替换成玩家当前绑定到该动作的键名（改键后自动跟随）。
## 例如： "移动：{action:move_left} {action:move_right}"
##        "跳跃：{action:jump}     攻击：{action:attack}"
##
## 留空数组 = 本关不显示任何教学提示。
## 教学提示是否显示、显示什么，完全由本关决定，代码不写死内容。
@export var tutorial_hints: Array[String] = []

var _entries: Dictionary = {}          ## StringName -> LevelEntry


func _ready() -> void:
	add_to_group(&"level")
	if level_id == &"":
		push_warning("Level 未设置 level_id：%s" % name)
	_collect_entries()
	_ensure_standalone_runnable()


## 单独运行本关卡场景（编辑器里按 F6）时，自动补一个 LevelManager。
##
## 没有这个的话，F6 打开的关卡里没有玩家、没有相机、没有 HUD，
## 只能看到一张静态地图，改完地形想立刻试跑就必须回 Main 再改 start_level，
## 来回切非常烦。有了它，你在哪张图上按 F6 就直接从那张图开始玩。
##
## 判断依据是"头顶有没有 LevelManager"：
## 正常流程下关卡由 LevelManager 加载，条件不成立，这里什么都不做。
func _ensure_standalone_runnable() -> void:
	if get_tree() == null or Engine.is_editor_hint():
		return
	# 已经在 LevelManager 管辖下（正常流程），不介入。
	var n := get_parent()
	while n != null:
		if n is LevelManager:
			return
		n = n.get_parent()
	# 本关卡是场景树根（F6 直接运行），才接管。
	if get_tree().current_scene != self:
		return

	_boot_standalone.call_deferred()


func _boot_standalone() -> void:
	var main_scene := load("res://scenes/Main.tscn") as PackedScene
	if main_scene == null:
		push_error("找不到 Main.tscn，无法单关卡启动")
		return

	var mgr := main_scene.instantiate() as LevelManager
	if mgr == null:
		return
	# 让 LevelManager 直接加载本关，而不是它默认的 start_level。
	mgr.start_level = level_id

	var tree := get_tree()
	var root := tree.root
	# 把自己从根上摘下来，换成完整的 Main（它会重新实例化一份本关卡）。
	# 不复用当前实例是因为它已经 _ready 过了，状态不干净。
	root.remove_child(self)
	root.add_child(mgr)
	tree.current_scene = mgr
	queue_free()


func _collect_entries() -> void:
	_entries.clear()
	for node in _find_all_of_type(self, LevelEntry):
		var e := node as LevelEntry
		if _entries.has(e.entry_id):
			push_warning("关卡 %s 存在重复的入口 id：%s" % [level_id, e.entry_id])
		_entries[e.entry_id] = e


## 按 id 取入口点。找不到时回退到 default，再找不到返回 null。
func get_entry(entry_id: StringName) -> LevelEntry:
	if _entries.has(entry_id):
		return _entries[entry_id]
	if _entries.has(&"default"):
		return _entries[&"default"]
	return null


## 本关的默认复活点位置。
## 优先取标了 is_default_respawn 的入口，其次取 default 入口，最后兜底原点。
func get_default_respawn() -> Vector2:
	for e in _entries.values():
		if (e as LevelEntry).is_default_respawn:
			return (e as LevelEntry).global_position
	var d := get_entry(&"default")
	if d != null:
		return d.global_position
	return Vector2.ZERO


## 世界边界（像素）。相机用它做限位。
func get_world_bounds() -> Rect2:
	var rect: Rect2
	if manual_bounds_tiles.size != Vector2.ZERO:
		rect = Rect2(
			manual_bounds_tiles.position * GameConfig.TILE_SIZE,
			manual_bounds_tiles.size * GameConfig.TILE_SIZE
		)
	else:
		rect = _auto_bounds()

	var pad := GameConfig.tiles(bounds_padding_tiles)
	return rect.grow(pad)


## 从所有 TileMapLayer 的已用区域合并出边界。
func _auto_bounds() -> Rect2:
	var result := Rect2()
	var found := false

	for node in _find_all_of_type(self, TileMapLayer):
		var layer := node as TileMapLayer
		var used := layer.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		var cell := layer.tile_set.tile_size if layer.tile_set != null else Vector2i(GameConfig.TILE_SIZE, GameConfig.TILE_SIZE)
		var r := Rect2(
			Vector2(used.position * cell) ,
			Vector2(used.size * cell)
		)
		# 转到世界坐标（考虑 layer 自身的偏移与缩放）。
		r.position = layer.to_global(r.position)
		r.size *= layer.global_scale

		if not found:
			result = r
			found = true
		else:
			result = result.merge(r)

	if not found:
		# 没有任何瓦片时给一个屏幕大小的兜底，避免相机限位退化成一个点。
		result = Rect2(
			Vector2.ZERO,
			Vector2(GameConfig.VIEWPORT_WIDTH, GameConfig.VIEWPORT_HEIGHT)
		)
	return result


## 递归查找指定类型的所有节点。
func _find_all_of_type(root: Node, type) -> Array:
	var out: Array = []
	for child in root.get_children():
		if is_instance_of(child, type):
			out.append(child)
		out.append_array(_find_all_of_type(child, type))
	return out
