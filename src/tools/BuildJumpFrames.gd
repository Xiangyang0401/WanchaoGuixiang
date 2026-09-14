extends SceneTree
## 一次性工具：从 60 帧 player_jump 素材重建「一段跳 / 二段跳」，并重建下落帧。
##
## 四个统一处理（对齐 idle/run 等现有动画的规格）：
##   1. 去白底转透明：白底源按亮度把背景转成 alpha=0（边缘平滑，rgb 压黑去白晕）；
##      已经是透明底的源（player_jump_fall）保持原 alpha 不受影响（取 min 原则）
##   2. 去烟雾残影：AI 抽帧素材角色周围常带灰色烟雾/拖影，靠亮度阈值抠不掉
##      （烟雾是灰色的，和剑刃高光、衣服灰细节亮度重叠）。
##      用形态学处理：开运算去掉细碎烟雾纹理 → 取最大连通域当角色主体 →
##      主体向外膨胀一个保留区（拉回头发丝/剑刃等细结构）→ 边缘羽化。
##      离角色较远的大块烟雾全被切掉，贴体的一小圈残留作为氛围可接受。
##   3. 组内统一裁剪窗口：取该组所有帧角色包围盒的并集，一组一个窗口，
##      保证帧间角色大小、位置稳定（逐帧独立裁会让角色忽大忽小）
##   4. 统一规格 514x672、角色脚底对齐画布底：与现有 _crop 版一致
##
## 用法：Godot --headless --path . --script res://src/tools/BuildJumpFrames.gd
## 输出保持源帧号命名（030.png 等），SpriteFrames 里的引用路径不变，重导入即生效。

const TARGET_W := 514
const TARGET_H := 672
const PAD_SIDE := 8    ## 左右留白
const PAD_TOP := 10    ## 顶部留白
const PAD_FOOT := 2    ## 脚底离画布底的间距
const FG_LUMA := 0.70  ## 亮度低于此 = 角色主体（完全不透明）
const BG_LUMA := 0.92  ## 亮度高于此 = 背景（完全透明）

const ERODE_R := 4     ## 开运算腐蚀半径：宽度 <= 2*ERODE_R 的烟雾纹理被去掉
const KEEP_R := 20     ## 角色主体向外保留的半径（拉回头发/剑刃/贴体细节）
const FEATHER := 8.0   ## 保留区边缘的羽化宽度（px），硬切会有可见截断边

## 三组：一段跳（曲腿起跳）、二段跳（身躯舒展）、下落。
## 帧号 1-based；输出目录与 SpriteFrames 现有引用一致。
const GROUPS := [
	{
		"label": "一段跳",
		"src": "res://assets/animation/player_jump",
		"out": "res://assets/animation/player_jump_start_crop",
		"frames": [30, 31, 32, 33, 34, 46, 47, 48, 49, 50, 51, 52],
	},
	{
		"label": "二段跳",
		"src": "res://assets/animation/player_jump",
		"out": "res://assets/animation/player_jump_air_crop",
		"frames": [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29],
	},
	{
		"label": "下落",
		"src": "res://assets/animation/player_jump_fall",
		"out": "res://assets/animation/player_jump_fall_crop",
		"frames": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
	},
]


func _initialize() -> void:
	for g in GROUPS:
		_process_group(g)
	quit(0)


func _process_group(g: Dictionary) -> void:
	var src_dir: String = g["src"]
	var out_dir: String = g["out"]
	var nums: Array = g["frames"]

	# 1. 读全部源帧，并把白底烤成 alpha（透明底源不受影响）
	var imgs: Array = []
	for n in nums:
		var path := ProjectSettings.globalize_path(src_dir.path_join("%03d.png" % int(n)))
		var img := Image.load_from_file(path)
		if img == null:
			push_warning("[%s] 读取失败 %03d" % [g["label"], int(n)])
			continue
		img.convert(Image.FORMAT_RGBA8)
		img = _bake_alpha(img)
		imgs.append([int(n), img])
	if imgs.is_empty():
		print("[%s] 没有可用源帧，跳过" % g["label"])
		return

	# 2. 所有帧角色包围盒求并集（统一窗口，帧间稳定）
	var ux0 := 999999
	var uy0 := 999999
	var ux1 := -1
	var uy1 := -1
	for item in imgs:
		var b: Rect2i = _bbox(item[1])
		ux0 = mini(ux0, b.position.x)
		uy0 = mini(uy0, b.position.y)
		ux1 = maxi(ux1, b.end.x - 1)
		uy1 = maxi(uy1, b.end.y - 1)
	var src_w: int = (imgs[0][1] as Image).get_width()
	var src_h: int = (imgs[0][1] as Image).get_height()
	ux0 = maxi(0, ux0 - 2)
	uy0 = maxi(0, uy0 - 2)
	ux1 = mini(src_w - 1, ux1 + 2)
	uy1 = mini(src_h - 1, uy1 + 2)
	var uw := ux1 - ux0 + 1
	var uh := uy1 - uy0 + 1

	# 3. 统一缩放：窗口适配进目标画布可用区
	var avail_w := TARGET_W - PAD_SIDE * 2
	var avail_h := TARGET_H - PAD_TOP - PAD_FOOT
	var s: float = minf(float(avail_w) / float(uw), float(avail_h) / float(uh))
	var dw := maxi(1, int(round(uw * s)))
	var dh := maxi(1, int(round(uh * s)))

	# 4. 逐帧：裁统一窗口 → 缩放 → 透明画布上水平居中、脚底对齐底边 → 去烟雾
	var out_abs := ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(out_abs)
	for f in DirAccess.get_files_at(out_abs):
		if f.get_extension().to_lower() == "png":
			DirAccess.remove_absolute(out_abs.path_join(f))

	for item in imgs:
		var n: int = item[0]
		var img: Image = item[1]
		var win := img.get_region(Rect2i(ux0, uy0, uw, uh))
		win.resize(dw, dh, Image.INTERPOLATE_LANCZOS)

		var canvas := Image.create_empty(TARGET_W, TARGET_H, false, Image.FORMAT_RGBA8)
		canvas.fill(Color(0, 0, 0, 0))
		var ox := (TARGET_W - dw) / 2
		var oy := TARGET_H - PAD_FOOT - dh
		canvas.blit_rect(win, Rect2i(0, 0, dw, dh), Vector2i(ox, oy))
		canvas = _remove_smoke(canvas)

		canvas.save_png(out_abs.path_join("%03d.png" % n))

	print("[%s] %d 帧 → %s（窗口 %dx%d → 显示 %dx%d）" % [g["label"], imgs.size(), out_dir, uw, uh, dw, dh])


## 白底转透明：按亮度生成 alpha，rgb 同乘 alpha 压黑（去白晕）。
## 用 min(原alpha, 亮度alpha)：白底源（alpha=255）按亮度算；
## 透明底源背景（alpha=0）保持 0；烟雾等半透明像素按亮度进一步收紧。
func _bake_alpha(img: Image) -> Image:
	var data := img.get_data()
	var i := 0
	for y in img.get_height():
		for x in img.get_width():
			var a := data[i + 3]
			if a == 0:
				i += 4
				continue
			var luma := (data[i] + data[i + 1] + data[i + 2]) / 765.0
			var la := clampf((BG_LUMA - luma) / (BG_LUMA - FG_LUMA), 0.0, 1.0)
			var na := mini(a, int(la * 255.0))
			data[i] = data[i] * na / 255
			data[i + 1] = data[i + 1] * na / 255
			data[i + 2] = data[i + 2] * na / 255
			data[i + 3] = na
			i += 4
	return Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


## 去烟雾残影：
##   mask（alpha>12）→ 开运算去细碎纹理 → 最大连通域=角色主体 →
##   主体膨胀 KEEP_R 得保留区 → 边缘 FEATHER 羽化 → 区外 alpha 清零。
func _remove_smoke(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var n := w * h
	var data := img.get_data()

	var mask := PackedByteArray()
	mask.resize(n)
	for i in n:
		mask[i] = 1 if data[i * 4 + 3] > 12 else 0

	# 开运算：腐蚀去细烟雾纹理，再膨胀回来恢复角色主体轮廓
	var d_bg := _dist_to_zero(mask, w, h)
	var eroded := PackedByteArray()
	eroded.resize(n)
	for i in n:
		eroded[i] = 1 if d_bg[i] > ERODE_R else 0
	var opened := _dilate_mask(eroded, w, h, ERODE_R)

	# 最大连通域 = 角色主体（烟雾即使没被开运算除尽，也与主体分离）
	var core := _largest_component(opened, w, h)
	if core.is_empty():
		return img  # 兜底：开运算后什么都没剩（不该发生），保留原图

	# 保留区：主体向外 KEEP_R 像素，边缘羽化
	var d_core := _dist_to_one(core, w, h)
	for i in n:
		var k := clampf((KEEP_R + FEATHER - float(d_core[i])) / FEATHER, 0.0, 1.0)
		if k >= 1.0:
			continue
		data[i * 4 + 3] = int(data[i * 4 + 3] * k)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)


## 切比雪夫距离变换：每个像素到最近「值为 0 的像素」的距离（两遍扫描）。
func _dist_to_zero(mask: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var INF := 1 << 28
	var d := PackedInt32Array()
	d.resize(w * h)
	for i in w * h:
		d[i] = INF if mask[i] == 1 else 0
	for y in h:
		var row := y * w
		for x in w:
			var i := row + x
			if d[i] == 0:
				continue
			var m := d[i]
			if x > 0:
				m = mini(m, d[i - 1] + 1)
			if y > 0:
				m = mini(m, d[i - w] + 1)
				if x > 0:
					m = mini(m, d[i - w - 1] + 1)
				if x < w - 1:
					m = mini(m, d[i - w + 1] + 1)
			d[i] = m
	for y in range(h - 1, -1, -1):
		var row := y * w
		for x in range(w - 1, -1, -1):
			var i := row + x
			if d[i] == 0:
				continue
			var m := d[i]
			if x < w - 1:
				m = mini(m, d[i + 1] + 1)
			if y < h - 1:
				m = mini(m, d[i + w] + 1)
				if x < w - 1:
					m = mini(m, d[i + w + 1] + 1)
				if x > 0:
					m = mini(m, d[i + w - 1] + 1)
			d[i] = m
	return d


## 每个像素到最近「值为 1 的像素」的距离 = 对取反 mask 求 dist_to_zero。
func _dist_to_one(mask: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var inv := PackedByteArray()
	inv.resize(w * h)
	for i in w * h:
		inv[i] = 0 if mask[i] == 1 else 1
	return _dist_to_zero(inv, w, h)


## 二值膨胀（切比雪夫结构元，半径 r）。
func _dilate_mask(mask: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var d := _dist_to_one(mask, w, h)
	var out := PackedByteArray()
	out.resize(w * h)
	for i in w * h:
		out[i] = 1 if d[i] <= r else 0
	return out


## 最大连通域（4 邻接 BFS）。全空返回空数组。
func _largest_component(mask: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var n := w * h
	var visited := PackedByteArray()
	visited.resize(n)
	var stack := PackedInt32Array()
	var best_seed := -1
	var best_size := 0
	for start in n:
		if mask[start] == 0 or visited[start] == 1:
			continue
		var size := 0
		stack.clear()
		stack.append(start)
		visited[start] = 1
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			size += 1
			var x := i % w
			var y := i / w
			if x > 0 and mask[i - 1] == 1 and visited[i - 1] == 0:
				visited[i - 1] = 1
				stack.append(i - 1)
			if x < w - 1 and mask[i + 1] == 1 and visited[i + 1] == 0:
				visited[i + 1] = 1
				stack.append(i + 1)
			if y > 0 and mask[i - w] == 1 and visited[i - w] == 0:
				visited[i - w] = 1
				stack.append(i - w)
			if y < h - 1 and mask[i + w] == 1 and visited[i + w] == 0:
				visited[i + w] = 1
				stack.append(i + w)
		if size > best_size:
			best_size = size
			best_seed = start
	if best_seed < 0:
		return PackedByteArray()

	var out := PackedByteArray()
	out.resize(n)
	stack.clear()
	stack.append(best_seed)
	out[best_seed] = 1
	while not stack.is_empty():
		var i := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var x := i % w
		var y := i / w
		if x > 0 and mask[i - 1] == 1 and out[i - 1] == 0:
			out[i - 1] = 1
			stack.append(i - 1)
		if x < w - 1 and mask[i + 1] == 1 and out[i + 1] == 0:
			out[i + 1] = 1
			stack.append(i + 1)
		if y > 0 and mask[i - w] == 1 and out[i - w] == 0:
			out[i - w] = 1
			stack.append(i - w)
		if y < h - 1 and mask[i + w] == 1 and out[i + w] == 0:
			out[i + w] = 1
			stack.append(i + w)
	return out


## 扫描非背景像素（alpha>2）的包围盒
func _bbox(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	var data := img.get_data()
	var i := 3
	for y in h:
		for x in w:
			if data[i] > 2:
				if x < min_x: min_x = x
				if x > max_x: max_x = x
				if y < min_y: min_y = y
				if y > max_y: max_y = y
			i += 4
	if max_x < 0:
		return Rect2i(0, 0, 1, 1)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
