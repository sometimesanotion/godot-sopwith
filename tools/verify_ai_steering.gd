extends SceneTree
## M7.x — Verify enemy AI _steer_to_aim wraps the X diff so the heading
## always reflects the short way around the wrapped world.  Without this
## the AI, when on the opposite side of the wrap boundary from its aim
## point (player, home base, bomb overhead, patrol centre), computes a
## heading that points the LONG way around the terrain — flying the
## "wrong" direction across thousands of pixels instead of the few-hundred-
## pixel short way, and never lining up for a shot.
##
## Run: godot --headless --path . --script res://tools/verify_ai_steering.gd
func _initialize() -> void:
	var ok := true

	# Instantiate the enemy AI script directly.  It is a Node; we add a
	# minimal RigidBody2D stub as its `biplane` so _steer_to_aim can read
	# global_position.  Only that field is touched by the path under test.
	# (The export is typed RigidBody2D; we use a real RigidBody2D to satisfy
	# the type check, but never integrate it.)
	var AI := load("res://scripts/enemy_ai.gd")
	var ai: Node = AI.new()
	ai.name = "TestAI"
	var biplane_stub := RigidBody2D.new()
	biplane_stub.name = "BiplaneStub"
	# Wire the export so _steer_to_aim sees it.  We also need the FSM
	# tick driver never to fire; we only call _steer_to_aim directly.
	ai.biplane = biplane_stub
	# pilots[0] is constructed in the script's var initializer.
	root.add_child(ai)

	const TERRAIN_HALF := 16384.0 * 0.5

	# Helper: place the stub at `x`, force a desired_heading, steer toward
	# `aim`, and return the resulting desired_heading.  We force
	# desired_heading to 0 before each call so the lerp starts from a
	# known value and the resulting heading is determined by the aim
	# alone (modulo the lerp factor bringing it partway).
	var steer := func(x: float, aim: Vector2) -> float:
		biplane_stub.global_position = Vector2(x, 0.0)
		ai.pilots[0].desired_heading = 0.0
		ai._steer_to_aim(aim)
		return ai.pilots[0].desired_heading

	# Case 1: short way is to the LEFT (aim at x=200, plane at x=16200).
	# Wrapped dx = 200 - 16200 = -15800 → wrapf to 284 (right, short way? no).
	# 16200 → 200 via left: 16200→0 (100) + 0→200 (200) = wait, the plane is
	# at 16200 and aim at 200.  Short way: 16200→16384 (184) + 0→200 (200)
	# = 384 going RIGHT (wrap).  Long way: 16200→200 directly = 16000 going
	# LEFT.  So the short way is RIGHT (heading 0).
	# The aim is on the opposite side of the wrap, but the short way is
	# the 384-px rightward arc.  desired_heading should end up near 0.
	var h1: float = steer.call(16200.0, Vector2(200.0, 0.0))
	# Heading lerps from 0 toward the target heading.  With default
	# HEADING_LERP_FACTOR (0.6), the result is partway.  We just check
	# the SIGN/quadrant: the short way is rightward, so target heading
	# is near 0 (within ±PI/2 of 0).  A naive (unwrapped) heading would
	# have been near PI (leftward, the long way).
	var short_h1 = wrapf(h1, -PI, PI)
	ok = _expect(absf(short_h1) < PI * 0.5,
		"wrap: plane at 16200, aim at 200 → heading is the short (right) way (got %.3f rad)" % short_h1) and ok

	# Case 2: plane at 200, aim at 16200.  Short way is LEFT (200 → 0 →
	# wrap → 16200 = 384 px).  Long way is RIGHT (16000 px).  Heading
	# should reflect LEFT (near PI).
	var h2: float = steer.call(200.0, Vector2(16200.0, 0.0))
	var short_h2 = wrapf(h2, -PI, PI)
	ok = _expect(absf(absf(short_h2) - PI) < PI * 0.5,
		"wrap: plane at 200, aim at 16200 → heading is the short (left) way (got %.3f rad)" % short_h2) and ok

	# Case 3: a non-wrap case to make sure the fix didn't break the
	# normal short-way computation.  Plane at 2000, aim at 4000
	# (rightward, 2000 px).  Heading near 0.
	var h3: float = steer.call(2000.0, Vector2(4000.0, 0.0))
	var short_h3 = wrapf(h3, -PI, PI)
	ok = _expect(absf(short_h3) < PI * 0.25,
		"normal: plane at 2000, aim at 4000 → heading rightward (got %.3f rad)" % short_h3) and ok

	# Case 4: a vertical aim.  Plane at (5000, 0), aim at (5000, -300).
	# Diff = (0, -300).  Heading = -PI/2 (up, since y-down: -y is up).
	var h4: float = steer.call(5000.0, Vector2(5000.0, -300.0))
	var short_h4 = wrapf(h4, -PI, PI)
	ok = _expect(absf(short_h4 - (-PI * 0.5)) < PI * 0.25,
		"vertical: heading up (got %.3f rad)" % short_h4) and ok

	# Case 5: Immelmann-style "near my_pos" aim must not be perturbed by
	# the new wrap.  Plane at 200, aim at 200 + 600 (right, 600 px).
	# Heading near 0.
	var h5: float = steer.call(200.0, Vector2(800.0, 0.0))
	var short_h5 = wrapf(h5, -PI, PI)
	ok = _expect(absf(short_h5) < PI * 0.25,
		"near-aim: heading rightward (got %.3f rad)" % short_h5) and ok

	# Case 6: the most important one — home-base return across the wrap.
	# Plane at 200, home at 16200 (16000 px rightward raw, 384 px leftward
	# wrapped).  Without the fix, heading is 0 (rightward, long way).
	# With the fix, heading is in the LEFT half (negative, near -PI),
	# i.e. the short way.  The Y offset of -200 means the exact heading
	# is left+up (atan2(-200, -384) ≈ -2.68), and the lerp from 0 with
	# factor 0.6 lands it around -1.6.  The key assertion is: the sign is
	# negative (leftward), proving the short way was chosen.
	var h6: float = steer.call(200.0, Vector2(16200.0, -200.0))
	var short_h6 = wrapf(h6, -PI, PI)
	ok = _expect(short_h6 < -PI * 0.25,
		"home return across wrap: heading is the short (left) way (got %.3f rad)" % short_h6) and ok

	ai.queue_free()
	biplane_stub.queue_free()

	print("VERIFY AI STEERING: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _expect(cond: bool, msg: String) -> bool:
	if cond:
		print("  OK   ", msg)
	else:
		print("  FAIL ", msg)
	return cond
