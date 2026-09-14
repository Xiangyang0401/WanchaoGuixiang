@tool
class_name LevelBackground
extends Parallax2D
## 关卡背景图。摆进关卡，Inspector 里填一张图，就成了这张图的底图。
##
## 设定用法（策划向）：
##   1. 把图片文件拖进 res://assets/backgrounds/（没有就新建这个文件夹）
##   2. 把 scenes/world/LevelBackground.tscn 拖进关卡，放在关卡根节点下
##   3. Inspector 里把图片拖进 texture 字段 —— 编辑器里立刻能看到效果
##   4. 想要纵深感就调 parallax（比 1 小 = 背景滚得比地形慢）
##
## 一张图铺不满整关时不用手动拉缩放：fill 模式会自动按关卡边界缩放，
## 主角改尺寸、关卡改大小都不用回来重调。
##
## 想做多层背景（远山 + 近树），拖多个进来、给不同的 parallax 和 sort_order 即可，
## 不需要改代码。

## 铺法。
##   LEVEL  —— 贴合整个关卡（最常见的"关卡底图"）。图随世界一起滚，parallax 被忽略。
##   SCREEN —— 按屏幕尺寸铺，随相机以 parallax 速度滚，横向自动重复。远景天空用这个。
enum Fill {
	LEVEL,
	SCREEN,
}

## 背景图。留空则本节点不显示任何东西（不会报错，方便先占位后补图）。
@export var texture: Texture2D:
	set(v):
		texture = v
		_rebuild()

## 铺法，见 Fill 枚举说明。
@export var fill: Fill = Fill.LEVEL:
	set(v):
		fill = v
		_rebuild()

## 视差系数，仅 SCREEN 模式生效。
## 1 = 和地形同速（等于贴在世界上）；0 = 完全钉在屏幕上不动；
## 0.3 左右是典型的远景天空。
@export_range(0.0, 1.0, 0.05) var parallax: float = 0.5:
	set(v):
		parallax = v
		_rebuild()

## 绘制层级。默认 -100，保证压在地形（z_index=0）下面。
## 多层背景时用它排前后：数值越小越靠后。
@export var sort_order: int = -100:
	set(v):
		sort_order = v
		z_index = v

## 整体染色，可用来把同一张图调成不同关卡的色调（省一张图的美术量）。
@export var tint: Color = Color.WHITE:
	set(v):
		tint = v
		if _sprite != null:
			_sprite.modulate = v

## LEVEL 模式下额外放大的比例。
##
## 留一点余量：相机做平滑跟随时会略微越过关卡边界，正好贴边的背景
## 会在边缘露出底色缝。5% 足够盖住，又不会让构图明显偏移。
@export_range(0.0, 0.5, 0.01) var overscan: float = 0.05:
	set(v):
		overscan = v
		_rebuild()

var _sprite: Sprite2D = null


func _ready() -> void:
	z_index = sort_order
	# 背景永远不参与碰撞/交互，也不该被 Level._auto_bounds 之外的逻辑当地形。
	_ensure_sprite()
	# 关卡边界要等 TileMapLayer 都进树才准，延后一帧再算。
	_rebuild.call_deferred()


func _ensure_sprite() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return
	# 找已有的（编辑器里 @tool 重复 _ready 时不要越建越多）。
	for c in get_children():
		if c is Sprite2D:
			_sprite = c as Sprite2D
			return
	_sprite = Sprite2D.new()
	_sprite.name = "BackgroundImage"
	_sprite.centered = true
	add_child(_sprite)
	# 不设 owner：这是运行时的内部节点，不写进 .tscn，避免污染场景文件。


func _rebuild() -> void:
	_ensure_sprite()
	if _sprite == null:
		return

	_sprite.texture = texture
	_sprite.modulate = tint
	_sprite.visible = texture != null
	if texture == null:
		return

	var tex_size := Vector2(texture.get_size())
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return

	match fill:
		Fill.LEVEL:
			_fit_to_level(tex_size)
		Fill.SCREEN:
			_fit_to_screen(tex_size)


## 贴合关卡边界：等比放大到能盖住整个关卡（cover，不是拉伸变形）。
##
## 用 cover 而不是 stretch：拉伸会让美术给的图变形，
## 而策划摆图时几乎不可能让图的宽高比正好等于关卡宽高比。
func _fit_to_level(tex_size: Vector2) -> void:
	# 本节点跟世界同速——它就是"贴在关卡上的一张图"。
	scroll_scale = Vector2.ONE
	repeat_size = Vector2.ZERO

	var bounds := _level_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	var s: float = maxf(bounds.size.x / tex_size.x, bounds.size.y / tex_size.y)
	s *= 1.0 + overscan
	_sprite.scale = Vector2(s, s)
	# 转到本节点的局部坐标：关卡里 LevelBackground 可能被摆在任意位置，
	# 直接写全局中心会在节点被拖动后错位。
	_sprite.position = to_local(bounds.get_center())


## 按屏幕铺：图高度撑满一屏，横向自动重复，随相机以 parallax 速度滚。
func _fit_to_screen(tex_size: Vector2) -> void:
	scroll_scale = Vector2(parallax, parallax)

	var view := Vector2(GameConfig.VIEWPORT_WIDTH, GameConfig.VIEWPORT_HEIGHT)
	var s: float = maxf(view.x / tex_size.x, view.y / tex_size.y)
	_sprite.scale = Vector2(s, s)
	_sprite.position = Vector2.ZERO

	# 横向无限重复，避免相机走远后背景断片露底。
	# 只重复横向：竖向重复会让天空/地面上下颠倒地叠出来，反而更假。
	repeat_size = Vector2(tex_size.x * s, 0.0)
	repeat_times = 3


## 取所在关卡的世界边界；不在关卡下（比如单独 F6 跑本组件）时退化成一屏大小。
##
## 为什么不直接调 Level.get_world_bounds()：
##   本组件是 @tool（要在编辑器里所见即所得），而 Level.gd 不是。编辑器里
##   非 tool 脚本的节点只是 placeholder 实例，方法根本没加载，一调就报
##   "Attempt to call a method on a placeholder instance"。
##   所以编辑器分支自己扫 TileMapLayer 算边界——导出属性 placeholder 能读，
##   方法不能调，这是 Godot 的既定行为，别指望绕过去。
func _level_bounds() -> Rect2:
	var level := _find_level()
	if level == null:
		return Rect2(Vector2.ZERO, Vector2(GameConfig.VIEWPORT_WIDTH, GameConfig.VIEWPORT_HEIGHT))

	if not Engine.is_editor_hint():
		return level.get_world_bounds()

	# --- 编辑器分支：不调方法，只读导出属性 + 自己扫地形 ---
	var manual: Variant = level.get("manual_bounds_tiles")
	if manual is Rect2 and (manual as Rect2).size != Vector2.ZERO:
		var m: Rect2 = manual
		return Rect2(m.position * GameConfig.TILE_SIZE, m.size * GameConfig.TILE_SIZE)

	var rect := _scan_tilemap_bounds(level)
	if rect.size == Vector2.ZERO:
		return Rect2(Vector2.ZERO, Vector2(GameConfig.VIEWPORT_WIDTH, GameConfig.VIEWPORT_HEIGHT))

	var padding: Variant = level.get("bounds_padding_tiles")
	if padding is float:
		var p: float = padding
		rect = rect.grow(GameConfig.tiles(p))
	return rect


## 往上找关卡根节点。
##
## 编辑器里 placeholder 实例不一定能通过 `is Level` 判定（脚本没真正加载），
## 所以退而求其次：认"挂着 Level.gd 且是本节点祖先"的那个 Node2D。
func _find_level() -> Node:
	var n := get_parent()
	while n != null:
		if n is Level:
			return n
		var s: Script = n.get_script() as Script
		if s != null and s.resource_path == "res://src/world/Level.gd":
			return n
		n = n.get_parent()
	return null


## 合并关卡下所有 TileMapLayer 的已用区域（编辑器分支用）。
func _scan_tilemap_bounds(root: Node) -> Rect2:
	var result := Rect2()
	var found := false
	for node in _all_tilemaps(root):
		var layer := node as TileMapLayer
		var used := layer.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		var cell: Vector2i = layer.tile_set.tile_size if layer.tile_set != null \
			else Vector2i(GameConfig.TILE_SIZE, GameConfig.TILE_SIZE)
		var r := Rect2(Vector2(used.position * cell), Vector2(used.size * cell))
		r.position = layer.to_global(r.position)
		r.size *= layer.global_scale
		if not found:
			result = r
			found = true
		else:
			result = result.merge(r)
	return result


func _all_tilemaps(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is TileMapLayer:
			out.append(c)
		out.append_array(_all_tilemaps(c))
	return out
