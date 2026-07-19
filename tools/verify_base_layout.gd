extends SceneTree
## Run: godot --headless --path . --script res://tools/verify_base_layout.gd
## Headless check for M6 base layout & orientation: distances (wrap-aware),
## runway fits, faces_left/spawn_rot, and that the new RUNWAY span is exactly
## BASE_Y after terrain.generate().
func _initialize() -> void:
	var MainScript := load("res://scripts/main.gd")
	var m = MainScript.new()
	var TerrainScript := load("res://scripts/terrain.gd")
	var t: Node2D = TerrainScript.new()
	root.add_child(t)
	t._ready()
	var gm = get_root().get_node_or_null("GameManager")
	if gm != null:
		gm.terrain_seed = 424242
	t.generate()

	var ok := true
	var bases: Array[float] = [2400.0, 8000.0, 10500.0, 13000.0, 15500.0]

	# 1. Every base clears MIN_ENEMY_DISTANCE from the player (wrap-aware).
	for bx in bases:
		var d: float = m._wrap_distance(bx, m.PLAYER_SPAWN_X)
		ok = _expect(d >= m.MIN_ENEMY_DISTANCE,
			"base x=%.0f clears MIN_ENEMY_DISTANCE (d=%.1f >= %.1f)" % [bx, d, m.MIN_ENEMY_DISTANCE]) and ok

	# 2. Every base's runway fits inside the map.  The runway sits on the
	# side of base_x that matches the takeoff direction: rightward bases
	# have it on the right ([base_x+50, base_x+550]), leftward bases on the
	# left ([base_x-550, base_x-50]).
	for bx in bases:
		var faces_left: bool = bx > m.PLAYER_SPAWN_X
		var rl: float = bx - 550.0 if faces_left else bx + 50.0
		var rr: float = rl + 500.0
		var in_map: bool = rl >= 0.0 and rr <= m.TERRAIN_LENGTH
		ok = _expect(in_map, "base x=%.0f runway fits in map [%.1f, %.1f] (faces_left=%s)" % [bx, rl, rr, faces_left]) and ok

	# 3. Pairwise distance (catches two adjacent east bases or wrap-arounds).
	for i in range(bases.size()):
		for j in range(i + 1, bases.size()):
			var d2: float = m._wrap_distance(bases[i], bases[j])
			ok = _expect(d2 >= m.MIN_ENEMY_DISTANCE,
				"bases x=%.0f & x=%.0f pairwise d=%.1f >= MIN_ENEMY_DISTANCE" % [bases[i], bases[j], d2]) and ok

	# 4. D10 faces_left/spawn_rot: only the leftmost base (x=2400, west of player
	# at 5330) faces right; all other bases are east of the player and must
	# spawn inverted.
	for bx in bases:
		var faces_left: bool = bx > m.PLAYER_SPAWN_X
		var spawn_rot: float = PI if faces_left else 0.0
		var ok_rot: bool = (faces_left and is_equal_approx(spawn_rot, PI)) \
						or (not faces_left and is_equal_approx(spawn_rot, 0.0))
		ok = _expect(ok_rot, "base x=%.0f faces_left=%s spawn_rot=%.2f" % [bx, faces_left, spawn_rot]) and ok

	# 5. Player spawn (5330) lies on the new runway span [5300, 5800] (D5 contract).
	ok = _expect(m.PLAYER_SPAWN_X >= t.RUNWAY_START and m.PLAYER_SPAWN_X <= t.RUNWAY_END,
		"PLAYER_SPAWN_X=%.0f inside new RUNWAY span [%.0f, %.0f]" % [m.PLAYER_SPAWN_X, t.RUNWAY_START, t.RUNWAY_END]) and ok
	ok = _expect(t.get_ground_height_at(m.PLAYER_SPAWN_X) == t.BASE_Y,
		"PLAYER_SPAWN_X ground = BASE_Y=%.0f" % t.BASE_Y) and ok

	# 6. New RUNWAY span is exactly BASE_Y (full sweep, not just player spawn).
	var runway_flat := true
	for x in range(int(t.RUNWAY_START), int(t.RUNWAY_END) + 1, 8):
		if t.get_ground_height_at(float(x)) != t.BASE_Y:
			runway_flat = false
			break
	ok = _expect(runway_flat, "new RUNWAY [%.0f, %.0f] exactly BASE_Y" % [t.RUNWAY_START, t.RUNWAY_END]) and ok

	# 7. HOME_BASE is anchored to the player runway (moved from 6500 to 5300).
	ok = _expect(m.HOME_BASE.x == t.RUNWAY_START,
		"HOME_BASE.x=%.0f == RUNWAY_START=%.0f (minimap marker follows runway)" % [m.HOME_BASE.x, t.RUNWAY_START]) and ok

	print("VERIFY BASE LAYOUT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _expect(cond: bool, label: String) -> bool:
	print(("  OK   " if cond else "  FAIL ") + label)
	return cond
