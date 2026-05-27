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
	var dist_to_tgt = ai._get_wrapped_distance(ai.biplane.global_position.x, ai.target.global_position.x)
	if dist_to_tgt < ai.DETECTION_RANGE and ai._is_player_in_territory():
		finished.emit(&"taking_off")
