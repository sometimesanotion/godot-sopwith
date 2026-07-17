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

	if not ai._is_target_alive():
		finished.emit(&"patrolling")
		return

	var result = ai._compute_engage(avatar)
	var reflexed = ai._apply_reflexes(result[0], result[1])
	ai.pilots[0].last_pitch_input = reflexed[0]
	ai.pilots[0].last_throttle = reflexed[1]

	var alt = ai._get_altitude_above_ground()
	var damage = avatar.damage.damage_percent
	var dist_to_tgt = ai._get_wrapped_distance(ai.biplane.global_position.x, ai.target.global_position.x)

	# Defensive reactions: always break when the player has our six, and break
	# under fire only when too slow or too hurt to fight back.  A healthy,
	# fast plane PRESSES a head-on attack instead of flinching at every
	# incoming round — this is what makes it an aggressive opponent.
	var defensive: bool = ai._should_evade_defensively()
	var under_fire: bool = ai.pilots[0].incoming_bullet_timer > 0.0
	if alt < ai.DANGER_ALTITUDE_ABOVE_GROUND or defensive \
			or (under_fire and (ai._is_low_energy() or damage >= 0.3)):
		finished.emit(&"evading")
	elif damage >= 0.5:
		finished.emit(&"returning")
	elif dist_to_tgt > ai.ENGAGEMENT_RANGE * 1.2:
		finished.emit(&"patrolling")
