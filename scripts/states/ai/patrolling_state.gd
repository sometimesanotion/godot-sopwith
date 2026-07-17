extends State

func enter() -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if ai:
		ai.pilots[0].patrol_time = 0.0

func exit() -> void:
	pass

func update(delta: float) -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if not ai or not ai.target or not ai.biplane:
		return
	var avatar = ai._get_avatar()
	if not avatar:
		return
	var pitch = ai._compute_patrol_pitch()
	var throttle = ai._compute_patrol_throttle(avatar)
	var reflexed = ai._apply_reflexes(pitch, throttle)
	ai.pilots[0].last_pitch_input = reflexed[0]
	ai.pilots[0].last_throttle = reflexed[1]

	var dist_to_tgt = ai._get_wrapped_distance(ai.biplane.global_position.x, ai.target.global_position.x)
	if ai._is_fuel_low():
		finished.emit(&"returning")
	# Engage any live target within range, wherever it is — a challenging enemy
	# hunts the player across the map rather than only when the player wanders
	# into its own territory.  Distance is wrapped, so ENGAGEMENT_RANGE (9000)
	# already spans the whole field.
	elif ai._is_target_alive() and dist_to_tgt < ai.ENGAGEMENT_RANGE:
		finished.emit(&"engaging")
