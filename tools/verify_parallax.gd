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
		# (D3 periodic sampling) and the last x must be an exact integer
		# multiple of the mirror period (so motion_mirroring wraps with no
		# vertical jump).  The ridge now spans several periods so it also
		# always covers the viewport, even at the title-screen zoom (T-parallax).
		if trim_line and trim_line.points.size() >= 2:
			var first_pt: Vector2 = trim_line.points[0]
			var last_pt: Vector2 = trim_line.points[trim_line.points.size() - 1]
			var seam_dy: float = absf(first_pt.y - last_pt.y)
			var period: float = 16384.0 * spec_scale
			ok = _expect(seam_dy < 1e-3,
				"layer %d ridge seam Δy=%.6f (< 1e-3)" % [i, seam_dy]) and ok
			var rem := fmod(last_pt.x, period)
			ok = _expect(rem < 1e-2 or absf(rem - period) < 1e-2,
				"layer %d last ridge x=%.2f is a multiple of period=%.2f" % [i, last_pt.x, period]) and ok
			# Coverage: the single tile must be wide enough to fill the screen
			# at the title-screen zoom (camera.zoom = 0.3 → ~8533 local units,
			# plus safety margin).
			var min_cover := 2560.0 / 0.3 * 1.3
			ok = _expect(last_pt.x >= min_cover,
				"layer %d ridge spans %.0f ≥ %.0f (covers title zoom)" % [i, last_pt.x, min_cover]) and ok

	# Clouds now appear on ALL three layers (T-clouds).  Distant layer (0) is
	# minimalist cirrus; near layers (1,2) are puffy cumulus and more
	# translucent.  Collect per-layer cloud polys.
	var layer_clouds: Array = []
	for i in range(3):
		var polys: Array[Polygon2D] = []
		for c in b.parallax.get_child(i).get_children():
			if c is Polygon2D and c.color.a < 1.0:
				polys.append(c)
		layer_clouds.append(polys)
		ok = _expect(polys.size() > 0, "layer %d has clouds" % i) and ok
		# All puffs inside the layer's spanned width and the design y range.
		var period_i: float = 16384.0 * [0.1, 0.3, 0.6][i]
		var in_range := true
		for p in polys:
			if p.polygon.size() < 10:
				in_range = false
				break
			for v in p.polygon:
				if v.x < -1.0 or v.x > period_i * 1.5 + 1.0 or v.y < -1.0 or v.y > 720.0:
					in_range = false
					break
			if not in_range:
				break
		ok = _expect(in_range, "layer %d clouds inside spanned width × [0,720]" % i) and ok

	# Translucency: nearer layers must be MORE translucent (lower alpha) than
	# the distant layer.  Per-layer max alpha bounds.
	var max_a0 := 0.0
	var max_a1 := 0.0
	var max_a2 := 0.0
	for p in layer_clouds[0]:
		max_a0 = maxf(max_a0, p.color.a)
	for p in layer_clouds[1]:
		max_a1 = maxf(max_a1, p.color.a)
	for p in layer_clouds[2]:
		max_a2 = maxf(max_a2, p.color.a)
	ok = _expect(max_a0 <= 0.45 and max_a0 >= 0.20,
		"distant(layer0) cirrus alpha max=%.3f in [0.20,0.45]" % max_a0) and ok
	ok = _expect(max_a1 <= 0.35 and max_a1 >= 0.12,
		"mid(layer1) cumulus alpha max=%.3f in [0.12,0.35]" % max_a1) and ok
	ok = _expect(max_a2 <= 0.28 and max_a2 >= 0.08,
		"near(layer2) cumulus alpha max=%.3f in [0.08,0.28]" % max_a2) and ok
	# Key requirement: nearer ⇒ more translucent (strictly lower max alpha).
	ok = _expect(max_a2 < max_a0,
		"nearer layer2 (%.3f) more translucent than distant layer0 (%.3f)" % [max_a2, max_a0]) and ok
	ok = _expect(max_a1 < max_a0,
		"mid layer1 (%.3f) more translucent than distant layer0 (%.3f)" % [max_a1, max_a0]) and ok

	# Idempotency: a second generate() must be a no-op (no extra layers, no
	# extra cloud puffs).
	var prev_cloud_count := 0
	for polys in layer_clouds:
		prev_cloud_count += polys.size()
	b.generate(999)
	ok = _expect(b.parallax.get_child_count() == 3, "generate() idempotent (layers)") and ok
	var after_count := 0
	for i in range(3):
		for c in b.parallax.get_child(i).get_children():
			if c is Polygon2D and c.color.a < 1.0:
				after_count += 1
	ok = _expect(after_count == prev_cloud_count,
		"generate() idempotent (clouds)") and ok

	# Determinism: a fresh Background built with the same seed produces the
	# same first-puff polygon on every layer.
	var b2 = BG.new()
	root.add_child(b2)
	b2.generate(424242)
	for i in range(3):
		var first_puff: Polygon2D = null
		for c in b2.parallax.get_child(i).get_children():
			if c is Polygon2D and c.color.a < 1.0:
				first_puff = c
				break
		var first_puff_orig: Polygon2D = null
		for c in b.parallax.get_child(i).get_children():
			if c is Polygon2D and c.color.a < 1.0:
				first_puff_orig = c
				break
		ok = _expect(first_puff != null and first_puff_orig != null
				and first_puff.polygon[0] == first_puff_orig.polygon[0],
			"layer %d clouds deterministic (same seed → same first puff)" % i) and ok

	print("VERIFY PARALLAX: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _expect(cond: bool, label: String) -> bool:
	print(("  OK   " if cond else "  FAIL ") + label)
	return cond
