extends SceneTree
## Run: godot --headless --path . --script res://tools/verify_terrain.gd
func _initialize() -> void:
	var ok := true
	var TerrainScript := load("res://scripts/terrain.gd")
	var t: Node2D = TerrainScript.new()
	root.add_child(t)   # registers the node in the tree
	t._ready()          # in --script mode _ready() does not auto-fire; the real
	                    # game calls it on tree-entry and main.gd then calls generate()

	# Force a deterministic seed if the autoload is present; otherwise generate()
	# resolves a random seed — all structural assertions still hold.
	var gm = get_root().get_node_or_null("GameManager")
	if gm != null:
		gm.terrain_seed = 424242
	t.generate()

	var pts: PackedVector2Array = t.get_ground_points()
	ok = _expect(pts.size() == int(t.TERRAIN_LENGTH / t.SEGMENT_WIDTH) + 1,
		"point count (%d)" % pts.size()) and ok
	ok = _expect(is_equal_approx(pts[0].y, pts[pts.size() - 1].y),
		"seam height match") and ok
	var kink: float = absf((pts[pts.size()-1].y - pts[pts.size()-2].y)
						 - (pts[1].y - pts[0].y))
	ok = _expect(kink < 6.0, "seam slope continuity (kink=%.3f)" % kink) and ok
	var runway_flat := true
	for x in range(int(t.RUNWAY_START), int(t.RUNWAY_END) + 1, 8):
		if t.get_ground_height_at(float(x)) != t.BASE_Y:
			runway_flat = false
	ok = _expect(runway_flat, "runway exactly BASE_Y") and ok
	ok = _expect(t.get_ground_height_at(-10.0) == t.get_ground_height_at(t.TERRAIN_LENGTH - 10.0),
		"negative-x wrap") and ok

	# Determinism: force a fixed seed and regenerate twice.
	t.set_noise_seed(424242)
	t._generate_terrain()
	var a: PackedVector2Array = t.get_ground_points().duplicate()
	t._generate_terrain()
	var b: PackedVector2Array = t.get_ground_points().duplicate()
	var det := a.size() == b.size()
	for i in range(a.size()):
		if not is_equal_approx(a[i].y, b[i].y):
			det = false
			break
	ok = _expect(det, "determinism (same seed -> identical points)") and ok

	print("VERIFY TERRAIN: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _expect(cond: bool, label: String) -> bool:
	print(("  OK   " if cond else "  FAIL ") + label)
	return cond
