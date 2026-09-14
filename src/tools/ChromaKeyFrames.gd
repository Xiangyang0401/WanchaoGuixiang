@tool
extends EditorScript
## 批量去除 AI 视频抽帧的绿幕背景（chroma key），输出带透明通道的 PNG。
##
## 工作流位置：视频 → 抽帧(带绿底) → 本工具 → 透明序列帧 → 拖进 SpriteFrames
##
## 用法：
##   1. 把抽好的绿底帧放进某个文件夹（例如 res://assets/anim/run_raw/）
##   2. 改下面 INPUT_DIR / OUTPUT_DIR
##   3. Godot 菜单 文件 → 运行(E) → 本脚本，或在终端：
##      Godot --headless --path . --script res://src/tools/ChromaKeyFrames.gd
##
## 原理：像素越接近纯绿，alpha 越低（线性衰减，不是生硬二值）。
## 边缘残留的半透明绿会一起被吃掉，出来的边缘更干净。
## 角色身上尽量不要有接近纯绿的颜色，否则会被一起抠掉。

const INPUT_DIR := "res://assets/anim/run_raw"
const OUTPUT_DIR := "res://assets/anim/run_clean"

## 抠像灵敏度。0.0 = 只抠纯绿；0.5 = 连偏绿也抠（更干净但可能伤到角色浅色边缘）。
const TOLERANCE := 0.30


func _run() -> void:
	# EditorScript 没有 autoload，用 ProjectSettings 转绝对路径。
	var in_abs := ProjectSettings.globalize_path(INPUT_DIR)
	var out_abs := ProjectSettings.globalize_path(OUTPUT_DIR)

	if not DirAccess.dir_exists_absolute(in_abs):
		push_error("输入目录不存在: %s" % INPUT_DIR)
		return
	DirAccess.make_dir_recursive_absolute(out_abs)

	var files := DirAccess.get_files_at(in_abs)
	files.sort()
	var cleaned := 0
	for f in files:
		if not f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			continue
		var img := Image.load_from_file(in_abs.path_join(f))
		if img == null:
			push_error("读取失败: %s" % f)
			continue
		_remove_green(img)
		var out_path := out_abs.path_join(f.get_basename() + ".png")
		img.save_png(out_path)
		cleaned += 1
		print("  已处理: %s" % f)

	if cleaned == 0:
		push_warning("输入目录里没有可处理的图片: %s" % INPUT_DIR)
	else:
		print("完成，共 %d 帧 → %s" % [cleaned, OUTPUT_DIR])


func _remove_green(img: Image) -> void:
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()

	# 纯绿参考点：绿色通道远高于红蓝。直接取图里"最像绿"的像素当基准色。
	# 这样即使你的"绿"偏青/偏草绿也能自适应，不用改代码。
	var ref := _find_green_ref(img)
	if ref == null:
		push_warning("没找到像绿色的像素，可能图里没有绿幕或颜色偏得厉害")
		return

	for y in h:
		for x in w:
			var c: Color = img.get_pixel(x, y)
			var d := c.distance_to(ref)
			if d < TOLERANCE:
				# 越绿越透明；边缘用 alpha 渐变过渡，避免硬边白圈。
				var a := clampf((d / TOLERANCE), 0.0, 1.0)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
			# 其余像素不动


## 扫一遍取最接近纯绿(0,1,0)的像素作为基准绿。
func _find_green_ref(img: Image) -> Color:
	var best := Color(0, 1, 0)
	var best_d := 1e9
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			# 跳过接近黑/白的像素（可能是角色）
			if c.r > 0.6 and c.g > 0.6 and c.b > 0.6:
				continue
			var d := c.distance_to(Color(0, 1, 0))
			if d < best_d:
				best_d = d
				best = c
	return best if best_d < 0.8 else null
