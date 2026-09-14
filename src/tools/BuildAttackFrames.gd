extends SceneTree
## 一次性工具：从 player_attack 绿幕素材生成攻击动画帧（player_attack_crop）。
##
## 源素材：AI 视频抽帧 39 帧，1112x834，墨绿纯色底（RGB 约 56,136,104），
## 角色为纯黑平涂剪影。与 BuildJumpFrames.gd（白底亮度法）不同，这里走
## 色度抠像：按与背景基准色的距离算 alpha（ChromaKeyFrames.gd 的思路），
## 但修正了两点——
##   1. 死区：背景有色偏噪声（±8），距离小于死区的像素直接归零，
##      否则整幅背景会留一层 10% 左右的半透明鬼影；
##   2. 边缘去污染：半透明边缘像素 rgb 乘 alpha 压向黑，
##      剪影角色的绿边（spill）会被一起压掉。
##
## 【缩放基准】不按"窗口适配画布"缩放，而是读 idle 第一帧
## （player_idle_crop/001.png）的角色实际像素高，让攻击帧的角色显示高度
## 与 idle 一致——源视频里角色占画幅的比例和 idle 素材不同，若按窗口
## 适配缩放，游戏里攻击时角色会忽大忽小（PlayerVisual 以 idle 为缩放基准）。
##
## 用法：Godot --headless --path . --script res://src/tools/BuildAttackFrames.gd

## 画布按需加宽，只留高度约束（PlayerVisual._align_foot 只看高度，
## 宽度没有代码假设；idle 702 / run 645 / jump 672 本来就各不相同）。
## MAX_W 只是防失控的上限保护。
const MAX_W := 1200
const PAD_SIDE := 8
const PAD_TOP := 10
const PAD_FOOT := 2

## 色度抠像灵敏度：与背景色距离小于 DEAD_ZONE 完全透明，
## 大于 TOLERANCE 完全不透明，中间线性过渡。
const TOLERANCE := 0.30
const DEAD_ZONE_RATIO := 0.3

const ERODE_R := 4     ## 开运算腐蚀半径（去残影/噪点，与跳跃工具一致）
const KEEP_R := 20     ## 角色主体向外保留半径
const FEATHER := 8.0

## 缩放基准：idle 第一帧的角色像素高在运行时读取，不写死。
const REF_IDLE := "res://assets/animation/player_idle_crop/001.png"

const SRC_DIR := "res://assets/animation/player_attack"
const OUT_DIR := "res://assets/animation/player_attack_crop"
## 挑帧（1-based 源帧号）：待机起手 → 提剑提膝 → 蓄势 → 落步发力 →
## 刺出极点 → 收招 → 回待机。跳过 17/18（AI 误加的剑尖白光）。
const FRAMES := [1, 6, 7, 8, 10, 14, 15, 16, 19, 20, 22, 25, 27, 29, 31, 33]


func _initialize() -> void:
	var ref_h := _measure_idle_char_height()
	if ref_h <= 0:
		push_error("读不到 idle 基准帧，缩放基准失效")
		quit(1)
		return
	_process_group(ref_h)
	quit(0)


func _process_group(ref_h: int) -> void:
	var imgs: Array = []
	for n in FRAMES:
		var path := ProjectSettings.globalize_path(SRC_DIR.path_join("%03d.png" % int(n)))
		var img := Image.load_from_file(path)
		if img == null:
			push_warning("读取失败 %03d" % int(n))
			continue
		img.convert(Image.FORMAT_RGBA8)
		_chroma_key(img)
		imgs.append([int(n), img])
	if imgs.is_empty():
		print("没有可用源帧")
		return

	# 所有帧角色包围盒求并集（统一窗口，帧间稳定）
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

	# 缩放：对齐 idle 基准高度是硬要求（否则游戏里出招瞬间角色缩小一圈），
	# 画布宽度按缩放结果反向加宽。仅留 MAX_W 上限保护。
	var s: float = float(ref_h) / float(uh)
	var max_s := float(MAX_W - PAD_SIDE * 2) / float(uw)
	if s > max_s:
		push_warning("窗口宽度过大，缩放被上限压低：%.3f → %.3f" % [s, max_s])
		s = max_s
	var dw := maxi(1, int(round(uw * s)))
	var dh := maxi(1, int(round(uh * s)))
	var cw := dw + PAD_SIDE * 2
	var ch := dh + PAD_TOP + PAD_FOOT

	var out_abs := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_abs)
	for f in DirAccess.get_files_at(out_abs):
		if f.get_extension().to_lower() == "png":
			DirAccess.remove_absolute(out_abs.path_join(f))

	for item in imgs:
		var n: int = item[0]
		var img: Image = item[1]
		var win := img.get_region(Rect2i(ux0, uy0, uw, uh))
		win.resize(dw, dh, Image.INTERPOLATE_LANCZOS)

		var canvas := Image.create_empty(cw, ch, false, Image.FORMAT_RGBA8)
		canvas.fill(Color(0, 0, 0, 0))
		var ox := (cw - dw) / 2
		var oy := ch - PAD_FOOT - dh
		canvas.blit_rect(win, Rect2i(0, 0, dw, dh), Vector2i(ox, oy))
		canvas = _remove_smoke(canvas)

		canvas.save_png(out_abs.path_join("%03d.png" % n))

	print("[attack] %d 帧 → %s（窗口 %dx%d → 显示 %dx%d，画布 %dx%d，idle 基准高 %d）" % [imgs.size(), OUT_DIR, uw, uh, dw, dh, cw, ch, ref_h])


## 读 idle 第一帧的角色包围盒高度当缩放基准。
func _measure_idle_char_height() -> int:
	var img := Image.load_from_file(ProjectSettings.globalize_path(REF_IDLE))
	if img == null:
		return -1
	return _bbox(img).size.y


## 色度抠像：四角均值当背景基准色。
## alpha：距离 < 死区 → 0；死区 ~ TOLERANCE 线性过渡；> TOLERANCE → 原值。
## 过渡区像素 rgb 乘 alpha（压向黑，去掉绿色 spill）。
func _chroma_key(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var ref := _corner_avg(img)
	var dead := TOLERANCE * DEAD_ZONE_RATIO
	var data := img.get_data()
	var i := 0
	for y in h:
		for x in w:
			var a := data[i + 3]
			if a == 0:
				i += 4
				continue
			var c := Color(data[i] / 255.0, data[i + 1] / 255.0, data[i + 2] / 255.0)
			var dr := c.r - ref.r
			var dg := c.g - ref.g
			var db := c.b - ref.b
			var d := sqrt(dr * dr + dg * dg + db * db)
			if d >= TOLERANCE:
				i += 4
				continue
			var na := 0 if d <= dead else int(clampf((d - dead) / (TOLERANCE - dead), 0.0, 1.0) * 255.0)
			data[i] = data[i] * na / 255
			data[i + 1] = data[i + 1] * na / 255
			data[i + 2] = data[i + 2] * na / 255
			data[i + 3] = mini(a, na)
			i += 4
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)


## 四角 8x8 区域均值：比取"最绿像素"稳，不受角色误入角落影响。
func _corner_avg(img: Image) -> Color:
	var acc := Color(0, 0, 0)
	var count := 0
	for corner in [Vector2i(0, 0), Vector2i(img.get_width() - 8, 0), Vector2i(0, img.get_height() - 8), Vector2i(img.get_width() - 8, img.get_height() - 8)]:
		for y in 8:
			for x in 8:
				acc += img.get_pixel(corner.x + x, corner.y + y)
				count += 1
	return acc / float(count)


## 去残影（与 BuildJumpFrames.gd 相同：开运算 → 最大连通域 → 保留区羽化）。
func _remove_smoke(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var n := w * h
	var data := img.get_data()

	var mask := PackedByteArray()
	mask.resize(n)
	for i in n:
		mask[i] = 1 if data[i * 4 + 3] > 12 else 0

	var d_bg := _dist_to_zero(mask, w, h)
	var eroded := PackedByteArray()
	eroded.resize(n)
	for i in n:
		eroded[i] = 1 if d_bg[i] > ERODE_R else 0
	var opened := _dilate_mask(eroded, w, h, ERODE_R)

	var core := _largest_component(opened, w, h)
	if core.is_empty():
		return img

	var d_core := _dist_to_one(core, w, h)
	for i in n:
		var k := clampf((KEEP_R + FEATHER - float(d_core[i])) / FEATHER, 0.0, 1.0)
		if k >= 1.0:
			continue
		data[i * 4 + 3] = int(data[i * 4 + 3] * k)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)


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


func _dist_to_one(mask: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var inv := PackedByteArray()
	inv.resize(w * h)
	for i in w * h:
		inv[i] = 0 if mask[i] == 1 else 1
	return _dist_to_zero(inv, w, h)


func _dilate_mask(mask: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var d := _dist_to_one(mask, w, h)
	var out := PackedByteArray()
	out.resize(w * h)
	for i in w * h:
		out[i] = 1 if d[i] <= r else 0
	return out


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
