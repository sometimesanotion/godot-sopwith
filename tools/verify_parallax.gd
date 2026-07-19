extends SceneTree
## Run: godot --headless --path . --script res://tools/verify_parallax.gd
func _initialize() -> void:
	var BG := load("res://scripts/background.gd")
	var b = BG.new()
	root.add_child(b)
	b.generate(424242)

	var ok := true
	ok = _expect(b.parallax != null, "parallax created") and ok
	ok = _expect(b.parallax.get_child_count() == 3, "3 parallax layers") and ok
	for i in range(3):
		var layer = b.parallax.get_child(i)
		var has_poly := false
		var has_line := false
		var trim_line: Line2D = null
		for c in layer.get_children():
			if c is Polygon2D:
				has_poly = true
			if c is Line2D:
				has_line = true
				trim_line = c
		ok = _expect(has_poly and has_line, "layer %d has ridge polygon + trim" % i) and ok
		var spec_scale: float = [0.1, 0.3, 0.6][i]
		ok = _expect(is_equal_approx(layer.motion_mirroring.x, 16384.0 * spec_scale),
			"layer %d mirroring = TERRAIN_LENGTH*scale" % i) and ok
		# Seam-Δy assertion: the ridge's first and last points must match in y
		# (D3 periodic sampling) and the last x must equal the mirror period
		# exactly.  Without this, motion_mirroring produces a vertical jump
		# between tiles.
		if trim_line and trim_line.points.size() >= 2:
			var first_pt: Vector2 = trim_line.points[0]
			var last_pt: Vector2 = trim_line.points[trim_line.points.size() - 1]
			var seam_dy: float = absf(first_pt.y - last_pt.y)
			var period: float = 16384.0 * spec_scale
			ok = _expect(seam_dy < 1e-3,
				"layer %d ridge seam Δy=%.6f (< 1e-3)" % [i, seam_dy]) and ok
			ok = _expect(is_equal_approx(last_pt.x, period),
				"layer %d last ridge x=%.4f == period=%.4f" % [i, last_pt.x, period]) and ok

	# M5.1 clouds: layer 3 (index 2) hosts CLOUD_COUNT clusters × 3-7 puffs,
	# each puff is a 12-vert Polygon2D with translucent white color.
	var cloud_layer = b.parallax.get_child(2)
	var cloud_polys: Array[Polygon2D] = []
	for c in cloud_layer.get_children():
		if c is Polygon2D and c.color.a < 1.0:
			cloud_polys.append(c)
	ok = _expect(cloud_polys.size() >= 3 * 14 and cloud_polys.size() <= 7 * 14,
		"cloud puff count in [42, 98] (got %d)" % cloud_polys.size()) and ok
	# All puffs must be inside the layer-3 mirror period and the design y range.
	var in_range := true
	var layer3_period := 16384.0 * 0.6
	for p in cloud_polys:
		if p.polygon.size() != 12:
			in_range = false
			break
		for v in p.polygon:
			if v.x < 0.0 or v.x > layer3_period or v.y < 0.0 or v.y > 720.0:
				in_range = false
				break
		if not in_range:
			break
	ok = _expect(in_range, "all cloud puffs: 12 verts, inside [0, period) × [0, 720]") and ok
	# Translucency range [0.35, 0.55] (D9).
	var alpha_ok := true
	for p in cloud_polys:
		if p.color.a < 0.30 or p.color.a > 0.60:
			alpha_ok = false
			break
	ok = _expect(alpha_ok, "cloud alpha in [0.30, 0.60]") and ok

	# Idempotency: a second generate() must be a no-op (no extra layers, no
	# extra cloud puffs).
	var prev_cloud_count := cloud_polys.size()
	b.generate(999)
	ok = _expect(b.parallax.get_child_count() == 3, "generate() idempotent (layers)") and ok
	var cloud_layer2 = b.parallax.get_child(2)
	var after_count := 0
	for c in cloud_layer2.get_children():
		if c is Polygon2D and c.color.a < 1.0:
			after_count += 1
	ok = _expect(after_count == prev_cloud_count,
		"generate() idempotent (clouds)") and ok

	# Determinism: a fresh Background built with the same seed produces the
	# same first-puff polygon center.
	var b2 = BG.new()
	root.add_child(b2)
	b2.generate(424242)
	var cl2 = b2.parallax.get_child(2)
	var first_puff: Polygon2D = null
	for c in cl2.get_children():
		if c is Polygon2D and c.color.a < 1.0:
			first_puff = c
			break
	var first_puff_orig: Polygon2D = null
	for c in cloud_layer.get_children():
		if c is Polygon2D and c.color.a < 1.0:
			first_puff_orig = c
			break
	ok = _expect(first_puff != null and first_puff_orig != null
			and first_puff.polygon[0] == first_puff_orig.polygon[0],
		"clouds deterministic (same seed → same first puff)") and ok

	print("VERIFY PARALLAX: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _expect(cond: bool, label: String) -> bool:
	print(("  OK   " if cond else "  FAIL ") + label)
	return cond
