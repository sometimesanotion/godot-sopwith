extends State

func enter() -> void:
	pass

func exit() -> void:
	pass

func update(delta: float) -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if not ai or not ai.target or not ai.biplane:
		return
	var avatar = ai._get_avatar()
	if not avatar:
		return
	# Compute-only: writes pilot outputs. The controller applies them once per
	# physics frame (single application path, D4).
	ai._decision_takeoff(avatar)

	var alt = ai._get_altitude_above_ground()
	var dist_to_tgt = ai._get_wrapped_distance(ai.biplane.global_position.x, ai.target.global_position.x)
	if alt > ai.PATROL_ALTITUDE:
		finished.emit(&"patrolling")
	elif dist_to_tgt < ai.ENGAGEMENT_RANGE and alt > ai.MIN_ALTITUDE_ABOVE_GROUND:
		finished.emit(&"engaging")
