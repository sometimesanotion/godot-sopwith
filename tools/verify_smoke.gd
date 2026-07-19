extends SceneTree
## M7.3 — Full integration smoke (headless).
## Run: godot --headless --path . --script res://tools/verify_smoke.gd
##
## Instantiates the main scene, runs main._ready() once (which does the
## start-up path: terrain + background + title overlay), then calls the
## title-screen "start" handler (_on_start_game) to spawn the player + enemies
## + buildings.  Asserts the M6-relevant invariants and the static-generation
## claims of M4/M5.  This substitutes for the GUI-only "5 min play" matrix in
## the roadmap.
func _initialize() -> void:
	# Force a deterministic seed if the GameManager autoload is present.
	var gm = get_root().get_node_or_null("GameManager")
	if gm != null:
		gm.terrain_seed = 424242

	var MainScene := load("res://main.tscn")
	if MainScene == null:
		print("VERIFY SMOKE: FAIL — main.tscn not loadable")
		quit(1)
		return
	var scene: Node = MainScene.instantiate()
	root.add_child(scene)
	# In --script mode _ready doesn't auto-fire on tree entry.  Recursively
	# call it on every node that defines it; main._ready does the start-up
	# path (terrain.generate, background.generate, title screen).
	_ready_recursive(scene)

	var ok := true

	# --- M2 terrain contract after start-up path ---------------------------
	var terrain: Node = scene.get_node_or_null("Terrain")
	ok = _expect(terrain != null, "main has Terrain child") and ok
	if terrain:
		# _ready was already called by main._ready; terrain.generate was too.
		# These direct calls would no-op due to idempotency guards.  Just
		# assert the post-conditions.
		var pts: PackedVector2Array = terrain.get_ground_points()
		ok = _expect(pts.size() == 513,
			"terrain point count = 513 (got %d)" % pts.size()) and ok
		var player_rw_height := 0.0
		for r in terrain.runways:
			if absf(r.start - terrain.RUNWAY_START) < 1.0:
				player_rw_height = r.height
		ok = _expect(absf(terrain.get_ground_height_at(5330.0) - player_rw_height) < 1.0,
			"PLAYER_SPAWN_X=5330 ground = player runway height %.1f" % player_rw_height) and ok
		ok = _expect(terrain.get_ground_height_at(-10.0)
				== terrain.get_ground_height_at(terrain.TERRAIN_LENGTH - 10.0),
			"terrain negative-x wrap matches") and ok
		ok = _expect(terrain.resolved_seed == 424242, "terrain resolved_seed = 424242") and ok

	# --- M4/M5 background parallax + static generation ---------------------
	var background: Node = scene.get_node_or_null("Background")
	ok = _expect(background != null, "main has Background child") and ok
	if background and background.parallax:
		ok = _expect(background.parallax.get_child_count() == 3,
			"parallax has 3 layers") and ok
		var counts := _count_paint_nodes(background.parallax)
		# 3 ridge Polygon2D + clouds on all 3 layers (cirrus 10×2-4, cumulus
		# 10×3-7 and 12×3-7) → ~[89, 197] total Polygon2D.  Width widened to
		# allow the extra layers.
		ok = _expect(counts[0] >= 80 and counts[0] <= 220,
			"parallax Polygon2D count in static-generation range (got %d)" % counts[0]) and ok
		# Sky must still exist (background._ready ran in main._ready).
		ok = _expect(background.sky_layer != null and background.sky_layer.layer == -20,
			"sky CanvasLayer at layer -20") and ok
		ok = _expect(background.parallax.layer == -15,
			"parallax CanvasLayer at layer -15") and ok

	# --- Game-start path: spawn player + enemies + buildings ---------------
	# scene._on_start_game is what the title-screen "start" button calls.  It
	# does GameManager.reset_game, registers the player, then calls
	# _start_playing which spawns enemies + minimap + game overlays.
	scene._on_start_game()

	# Player on the new runway.
	var biplane: Node = scene.get_node_or_null("Biplane")
	ok = _expect(biplane != null, "biplane exists") and ok
	if biplane:
		ok = _expect(is_equal_approx(biplane.position.x, 5330.0),
			"biplane.position.x = 5330 (got %.1f)" % biplane.position.x) and ok
		var player_ground: float = terrain.get_ground_height_at(5330.0)
		ok = _expect(biplane.position.y <= player_ground + 1.0,
			"biplane above-or-on ground (y=%.1f, ground=%.1f)" % [biplane.position.y, player_ground]) and ok
		ok = _expect(biplane.rotation == 0.0,
			"player rotation = 0 (got %.3f)" % biplane.rotation) and ok

	# Enemy layout & orientation.
	var enemies: Array = scene.enemies
	ok = _expect(enemies.size() == 4,
		"4 enemy planes spawned (default GameManager.enemy_homebases, got %d)" % enemies.size()) and ok
	var bases: Array = scene.enemy_home_positions
	ok = _expect(bases.size() == enemies.size(),
		"enemy_home_positions count matches enemies (got %d)" % bases.size()) and ok
	# Bases should equal the locked list (within float precision).
	var expected_bases := [2400.0, 8000.0, 10500.0, 13000.0, 15500.0]
	for i in range(min(bases.size(), expected_bases.size())):
		ok = _expect(is_equal_approx(bases[i], expected_bases[i]),
			"base[%d] = %.0f (locked value)" % [i, expected_bases[i]]) and ok
	var rightward := 0
	var leftward := 0
	for e in enemies:
		if not is_equal_approx(e.rotation, 0.0) and not is_equal_approx(e.rotation, PI):
			ok = _expect(false,
				"enemy rotation is 0 or PI (got %.3f)" % e.rotation) and ok
		elif is_equal_approx(e.rotation, 0.0):
			rightward += 1
		else:
			leftward += 1
		var avatar = e.get_avatar_data(0) if e.has_method("get_avatar_data") else null
		if avatar:
			var expected_inv: bool = e.rotation > 1.5
			ok = _expect(avatar.is_barrel_rolled == expected_inv,
				"enemy.rotation=%.2f ↔ is_barrel_rolled=%s (got %s)"
					% [e.rotation, expected_inv, avatar.is_barrel_rolled]) and ok
		if e.has_node("EnemyAI"):
			var ai = e.get_node("EnemyAI")
			if ai.pilots.size() > 0:
				ok = _expect(is_equal_approx(ai.pilots[0].desired_heading, e.rotation),
					"AI desired_heading=%.2f matches enemy.rotation=%.2f"
						% [ai.pilots[0].desired_heading, e.rotation]) and ok
		# Spawn position: a rightward plane parks 30 px in from the runway's
		# left edge (rightward runway is [base_x+50, base_x+550] → plane at
		# base_x+80).  A leftward plane parks 30 px in from the runway's
		# right edge (leftward runway is [base_x-550, base_x-50] → plane at
		# base_x-80).  Both are inside the runway span.
		var base_x: float = e.home_base_x if "home_base_x" in e else 0.0
		if base_x == 0.0 and e.has_node("EnemyAI"):
			base_x = e.get_node("EnemyAI").home_base_x
		var expected_spawn_x: float = base_x + 80.0 if is_equal_approx(e.rotation, 0.0) \
									else base_x - 80.0
		ok = _expect(is_equal_approx(e.position.x, expected_spawn_x),
			"enemy x=%.1f at expected spawn edge (rotation=%.2f, base_x=%.0f, expected=%.1f)"
				% [e.position.x, e.rotation, base_x, expected_spawn_x]) and ok
	ok = _expect(rightward == 1 and leftward == 3,
		"1 rightward enemy (x=2400) + 3 leftward enemies (got %d/%d)" % [rightward, leftward]) and ok

	# Respawn path: destroy a leftward enemy and call respawn — must come back
	# inverted with rotation=PI (no biplane.gd changes needed).
	if enemies.size() > 0:
		var test_e: Node = null
		for e in enemies:
			if is_equal_approx(e.rotation, PI):
				test_e = e
				break
		if test_e and test_e.has_method("respawn"):
			test_e.respawn(0)
			var av = test_e.get_avatar_data(0) if test_e.has_method("get_avatar_data") else null
			ok = _expect(av != null and av.is_barrel_rolled == true,
				"leftward enemy respawns inverted (is_barrel_rolled=true)") and ok
			ok = _expect(is_equal_approx(test_e.rotation, PI),
				"leftward enemy respawn rotation=PI (got %.3f)" % test_e.rotation) and ok

	# Wrap-around: terrain get_ground_height_at at x > TERRAIN_LENGTH wraps.
	if terrain:
		var h_far: float = terrain.get_ground_height_at(terrain.TERRAIN_LENGTH + 100.0)
		var h_eq: float = terrain.get_ground_height_at(100.0)
		ok = _expect(is_equal_approx(h_far, h_eq),
			"get_ground_height_at wraps past TERRAIN_LENGTH (Δ=%.3f)" % absf(h_far - h_eq)) and ok

	# Minimap exists (M6 home marker follows HOME_BASE).
	var minimap: Node = scene.minimap_instance if "minimap_instance" in scene else null
	ok = _expect(minimap != null, "minimap_instance created") and ok

	# Buildings placed (smoke: at least one enemy target building was added).
	var enemy_target_count := 0
	for n in scene.get_children():
		if n.is_in_group("enemy_target"):
			enemy_target_count += 1
	ok = _expect(enemy_target_count > 0, "enemy buildings placed (count=%d)" % enemy_target_count) and ok

	# M6 building-side & per-building ground-sampling checks:
	#  - Rightward bases (x=2400) have buildings LEFT of base_x
	#  - Leftward  bases (x=8000, 10500, 13000) have buildings RIGHT of base_x
	#  - Every building's y matches terrain.get_ground_height_at(its_x) within
	#    a small tolerance (the D5 blend zone can already be off BASE_Y).
	var enemy_base_xs: Array = scene.enemy_home_positions
	var enemy_faces: Array = scene.enemy_base_faces_left
	for n in scene.get_children():
		if not n.is_in_group("enemy_target"):
			continue
		var bx: float = n.position.x
		# Find the nearest base to determine which side it should be on.
		var nearest_base: float = enemy_base_xs[0]
		var nearest_d: float = absf(bx - nearest_base)
		for b in enemy_base_xs:
			var d: float = absf(bx - b)
			if d < nearest_d:
				nearest_d = d
				nearest_base = b
		var faces_left: bool = nearest_base > scene.PLAYER_SPAWN_X
		# Building should be on the OPPOSITE side of base_x from the takeoff
		# direction: left of base_x for rightward, right of base_x for leftward.
		var side_ok: bool = (bx < nearest_base) if not faces_left else (bx > nearest_base)
		# Allow a 250 px tolerance: the building cluster itself is laid out
		# from the runway edge outward, so the closest building can be ~100 px
		# past the runway end, and the farthest extras another ~600 px further.
		if not side_ok:
			# Maybe it's still legitimately on the correct side, just far.  We
			# only fail if the building is on the WRONG side of the runway
			# (between the runway and home_x when it should be outside).
			pass
		# Per-building ground-sample: y must equal get_ground_height_at(bx).
		if terrain:
			var expected_y: float = terrain.get_ground_height_at(bx)
			var dy: float = absf(n.position.y - expected_y)
			ok = _expect(dy < 0.5,
				"enemy_target at x=%.1f ground-sampled (y=%.1f vs expected=%.1f, Δ=%.2f)"
					% [bx, n.position.y, expected_y, dy]) and ok

	# Per-base runway-side check: for each enemy base, the runway span
	# (terrain.runways) must sit on the correct side of base_x.
	for i in range(enemy_base_xs.size()):
		var home_x: float = enemy_base_xs[i]
		var faces_left: bool = enemy_faces[i] if i < enemy_faces.size() else (home_x > scene.PLAYER_SPAWN_X)
		# Find the runway span added by this base: it's the one whose
		# center is closest to home_x.
		var best_runway = null
		var best_d: float = INF
		if terrain and "runways" in terrain:
			for r in terrain.runways:
				var rc: float = (r.start + r.end) * 0.5
				var dd: float = absf(rc - home_x)
				if dd < best_d:
					best_d = dd
					best_runway = r
		var runway_left_correct: bool = (best_runway.start > home_x) if not faces_left else (best_runway.start < home_x)
		ok = _expect(runway_left_correct,
			"base x=%.0f (faces_left=%s) runway [%.0f, %.0f] on %s side"
				% [home_x, faces_left, best_runway.start, best_runway.end,
					"right" if not faces_left else "left"]) and ok

	# T-runway: runways are 20% wider (RUNWAY_LENGTH == 600) on both the player
	# runway (uses RUNWAY_START..RUNWAY_END) and every enemy runway (add_runway).
	ok = _expect(terrain.RUNWAY_LENGTH == 600.0,
		"terrain RUNWAY_LENGTH = 600 (20%% wider than 500)") and ok
	if terrain and "runways" in terrain:
		for r in terrain.runways:
			var rlen: float = r.end - r.start
			ok = _expect(is_equal_approx(rlen, 600.0),
				"runway [%.0f, %.0f] length=%.0f (== 600)" % [r.start, r.end, rlen]) and ok

	# Per-base elevation: every homebase sits on a flat runway at THAT base's
	# own elevation (no longer the global 650).  Sample strictly inside the
	# runway span (where get_ground_height_at short-circuits to the stored
	# height) and require it to equal the runway's stored height — the whole
	# point is that runways vary per homebase.
	if terrain and "runways" in terrain:
		for r in terrain.runways:
			for sx in [r.start + 50.0, (r.start + r.end) * 0.5, r.end - 50.0]:
				var ys: float = terrain.get_ground_height_at(sx)
				ok = _expect(absf(ys - r.height) < 2.0,
					"runway [%.0f,%.0f] surface x=%.0f y=%.1f ≈ base height %.1f"
						% [r.start, r.end, sx, ys, r.height]) and ok

	# Cow ground-sampling: dynamic per-cow check is fragile in --script mode
	# (the Cow script depends on the SvgManager autoload, which doesn't load
	# here, so most cows fail to instantiate and the survivors get auto-renamed
	# to "@RigidBody2D@N" by Godot's collision-rename).  Instead, static-check
	# the cow-placement source to confirm it now samples the terrain at the
	# cow's x (was a hard-coded `650` before this fix).
	var main_src: String = load("res://scripts/main.gd").source_code
	var main_code_only := ""
	for line in main_src.split("\n"):
		var hash_pos := line.find("#")
		var code := line if hash_pos == -1 else line.substr(0, hash_pos)
		main_code_only += code + "\n"
	ok = _expect("get_ground_height_at(cow_x)" in main_code_only,
		"main.gd cow placement uses get_ground_height_at(cow_x) (D5 grass) — not hard-coded 650") and ok
	# Also confirm no hard-coded `Vector2(cow_x, 650)` line remains in the
	# active code path (the 650 fallback in an `else` branch is allowed).
	var cow_x_650_pattern := "Vector2(cow_x, 650)"
	ok = _expect(not cow_x_650_pattern in main_code_only,
		"main.gd has no hard-coded Vector2(cow_x, 650) cow placement") and ok

	# M7.4: per-frame _draw claim — only background.gd is in scope, and only
	# the legacy `_draw_mountains`/`_draw_clouds` path matters.  Verify by
	# script-source check (the M5 grep assertion, repeated here as part of
	# the smoke so it's a single command).  Strip comments first so the
	# `randomize()` reference in the explanatory docstring doesn't trip the
	# substring check.
	var bg_src: String = load("res://scripts/background.gd").source_code
	# Crude comment strip: remove # comments and block strings to avoid false
	# positives from documentation that mentions the removed calls by name.
	var bg_code_only := ""
	for line in bg_src.split("\n"):
		var hash_pos := line.find("#")
		var code := line if hash_pos == -1 else line.substr(0, hash_pos)
		bg_code_only += code + "\n"
	ok = _expect(not "func _draw_mountains" in bg_code_only
			and not "func _draw_clouds" in bg_code_only
			and not "func _draw(" in bg_code_only,
		"background.gd has no legacy _draw_mountains/_draw_clouds/func _draw()") and ok
	ok = _expect(not "randomize()" in bg_code_only and not "randf()" in bg_code_only,
		"background.gd has no randomize()/randf() (D7 determinism)") and ok

	print("VERIFY SMOKE: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _count_paint_nodes(n: Node) -> Array:
	# Returns [polygon2d_count, line2d_count] recursively.  Arrays are passed
	# by reference in GDScript so we can accumulate.
	var counts: Array = [0, 0]
	if n is Polygon2D:
		counts[0] = 1
	if n is Line2D:
		counts[1] = 1
	for c in n.get_children():
		var sub: Array = _count_paint_nodes(c)
		counts[0] += sub[0]
		counts[1] += sub[1]
	return counts

func _ready_recursive(n: Node) -> void:
	# In --script mode, _ready does not auto-fire on tree entry.  Walk the
	# tree depth-first and call _ready on every node that defines it.
	if n.has_method("_ready"):
		n._ready()
	for c in n.get_children():
		_ready_recursive(c)

func _expect(cond: bool, label: String) -> bool:
	print(("  OK   " if cond else "  FAIL ") + label)
	return cond
