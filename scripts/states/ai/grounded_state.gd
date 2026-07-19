extends State

func enter() -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if ai:
		ai.pilots[0].last_pitch_input = 0.0
		ai.pilots[0].last_throttle = 0.0

func exit() -> void:
	pass

func update(delta: float) -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if not ai or not ai.target or not ai.biplane:
		return
	# A live player is always worth scrambling for, whether it is on the
	# ground (we will dive / bomb it once airborne) or in the air (we will
	# chase it).  No proximity or territory gate: the engage layer already
	# picks the right attack for a grounded target.
	var dist_to_tgt = ai._get_wrapped_distance(ai.biplane.global_position.x, ai.target.global_position.x)
	if ai._is_target_alive() and dist_to_tgt < ai.DETECTION_RANGE:
		finished.emit(&"taking_off")
