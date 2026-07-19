extends State

## Cruises above the home base, ready to pounce on a target that comes
## in range.  The state's job is just: where do I want to fly?  The
## controller converts that into a heading and a pitch command.
##
## min_state_time keeps the plane from immediately snapping into an
## engagement on the first decision tick after a state change (e.g. a
## freshly-climbed plane is briefly inside engagement range and would
## otherwise flap engaging ↔ patrolling as the target orbits).

var _patrol_time: float = 0.0

func enter() -> void:
	_patrol_time = 0.0
	var fsm: AIStateMachine = state_machine
	fsm.current_throttle = 1.0
	fsm.min_state_time = 0.5
	# current_aim_point is set every update; reset on enter so the
	# controller holds the last heading for the first frame.

func update(delta: float) -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if not ai or not ai.target or not ai.biplane:
		return
	var avatar = ai._get_avatar()
	if not avatar:
		return
	var fsm: AIStateMachine = state_machine

	_patrol_time += delta
	var aim: Vector2 = ai._patrol_aim_point(_patrol_time)
	fsm.current_aim_point = aim
	fsm.current_throttle = 1.0

	# Exit gates (only after the stickiness floor has been met).
	if not fsm.can_transition():
		return
	if ai._is_fuel_low():
		finished.emit(&"returning")
		return
	# Engage a live target only when it is inside this plane's patrol
	# territory — the SAME bound that gates launch.  A challenging enemy
	# still hunts the player across its own patrol_range, but it does not
	# abandon its territory and chase the player across the whole (wrapped)
	# map.  Distance is wrapped, so ENGAGEMENT_RANGE already spans the
	# field; the territory check is the controlling gate.
	var dist_to_tgt = ai._get_wrapped_distance(ai.biplane.global_position.x, ai.target.global_position.x)
	if ai._is_target_alive() and ai._is_player_in_territory() and dist_to_tgt < ai.ENGAGEMENT_RANGE:
		finished.emit(&"engaging")
