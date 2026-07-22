extends State

## Heading home for fuel / damage.  The state's job is just: point
## the plane at the glide-slope waypoint and let the helper pick the
## throttle.  The helper encapsulates the entire approach: en-route
## glide, committed final, and the flare-on-touchdown idle.
##
## The home-base proximity check is gated by min_state_time so a plane
## that takes off, enters returning, then immediately lands in the
## same tick (because the home base was already under it) cannot
## flap returning → grounded → taking_off on the next frame.

func enter() -> void:
	var fsm: AIStateMachine = state_machine
	fsm.min_state_time = 0.5

func update(_delta: float) -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if not ai or not ai.target or not ai.biplane:
		return
	var avatar = ai._get_avatar()
	if not avatar:
		return
	var fsm: AIStateMachine = state_machine

	var pack: Array = ai._return_aim_and_throttle()
	fsm.current_aim_point = pack[0]
	fsm.current_throttle  = pack[1]

	if not fsm.can_transition():
		return
	var damage = avatar.damage.damage_percent
	var dist_to_tgt  = ai._get_wrapped_distance(ai.biplane.global_position.x, ai.target.global_position.x)
	var my_dist_runway = ai._dist_to_runway() if ai.has_method("_dist_to_runway") else ai._get_wrapped_distance(ai.biplane.global_position.x, ai.home_base_x)

	# Re-engage a healthy target that came back into range.
	if dist_to_tgt < ai.RETURN_REENGAGE_RANGE and damage < 0.5 and ai._is_target_alive():
		finished.emit(&"engaging")
	elif my_dist_runway < ai.HOME_PROXIMITY * 3.0 and ai._is_grounded():
		finished.emit(&"grounded")
