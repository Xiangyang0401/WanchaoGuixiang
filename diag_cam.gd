extends SceneTree
## 临时诊断：重算当前关卡（含墙后）的 bounds、相机 limit 计算结果，
## 说明「相机为何不跟玩家走」。用完即删。

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/levels/Battlefield01.tscn") as PackedScene
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame

	print("=== 各层 range（含墙） ===")
	for node in _find(inst, "TileMapLayer"):
		var layer := node as TileMapLayer
		var used := layer.get_used_rect()
		var cell := layer.tile_set.tile_size if layer.tile_set != null else Vector2i(32, 32)
		var r := Rect2(Vector2(used.position * cell), Vector2(used.size * cell))
		print("  %s: x[%.0f, %.0f] y[%.0f, %.0f]" % [layer.name, r.position.x, r.end.x, r.position.y, r.end.y])

	# 合并 bounds（与 Level._auto_bounds 同逻辑）
	var merged := _merge(inst)
	var pad := 32.0 * 1.0
	var bounds := merged.grow(pad)
	var view := Vector2(1920, 1080) / 0.8
	print("---")
	print("合并 bounds(x): [%.0f, %.0f]  宽=%.0f px = %.0f 格" % [bounds.position.x, bounds.end.x, bounds.size.x, bounds.size.x / 32.0])
	print("相机一屏 view.x = %.0f px = %.0f 格" % [view.x, view.x / 32.0])

	if bounds.size.x > view.x:
		var cl := int(bounds.position.x + view.x * 0.5)
		var cr := int(bounds.end.x - view.x * 0.5)
		print("=== 长关卡，limit 内收半屏 ===")
		print("  limit_left = %d   视野左缘 = %.0f" % [cl, cl - view.x * 0.5])
		print("  limit_right = %d  视野右缘 = %.0f" % [cr, cr + view.x * 0.5])
		print("  相机中心移动范围(被钳制) = [%d, %d]" % [cl, cr])
		print("  玩家能到 x range ≈ [%.0f, %.0f]" % [bounds.position.x, bounds.end.x])
		print("  => 玩家超出 [%d,%d] 后相机停住、玩家继续跑就出屏" % [cl, cr])
		print("  视野右缘当 clamp_right 时 = %.0f (等于地形右缘 %.0f? %s)" % [cr + view.x * 0.5, bounds.end.x, absf(cr + view.x*0.5 - bounds.end.x) < 1])
	else:
		print("=== 短关卡，limit 放开 ===")
		print("  limit_left/right = ±LIMIT_OFF，相机自由跟随玩家")
	quit(0)

func _merge(node: Node) -> Rect2:
	var result := Rect2()
	var found := false
	for ch in node.get_children():
		var layer := ch as TileMapLayer
		if layer != null:
			var used := layer.get_used_rect()
			if used.size != Vector2i.ZERO:
				var cell := layer.tile_set.tile_size if layer.tile_set != null else Vector2i(32, 32)
				var r := Rect2(Vector2(used.position * cell), Vector2(used.size * cell))
				r.position = layer.to_global(r.position)
				r.size *= layer.global_scale
				if not found:
					result = r
					found = true
				else:
					result = result.merge(r)
		var sub := _merge(ch)
		if sub.size != Vector2.ZERO:
			if not found:
				result = sub
				found = true
			else:
				result = result.merge(sub)
	return result

func _find(node: Node, cls: String) -> Array:
	var out := []
	for ch in node.get_children():
		if ch.get_class() == cls:
			out.append(ch)
		out.append_array(_find(ch, cls))
	return out
