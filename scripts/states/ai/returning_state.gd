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

	var pitch = ai._compute_return_pitch()
	var throttle = ai._compute_return_throttle(avatar)
	var reflexed = ai._apply_reflexes(pitch, throttle)
	ai.pilots[0].last_pitch_input = reflexed[0]
	ai.pilots[0].last_throttle = reflexed[1]

	var dist_to_tgt = ai._get_wrapped_distance(ai.biplane.global_position.x, ai.target.global_position.x)
	var my_dist_home = ai._get_wrapped_distance(ai.biplane.global_position.x, ai.home_base_x)
	var damage = avatar.damage.damage_percent

	if dist_to_tgt < ai.RETURN_REENGAGE_RANGE and damage < 0.5 and ai._is_target_alive():
		finished.emit(&"engaging")
	elif my_dist_home < ai.HOME_PROXIMITY * 3.0 and ai._is_grounded():
		finished.emit(&"grounded")
		if ai.biplane.has_method("disable_autopilot"):
			ai.biplane.disable_autopilot()
		ai.pilots[0].is_using_autopilot = false
