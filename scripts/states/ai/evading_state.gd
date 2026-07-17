extends State

var evade_timer: float = 0.0

func enter() -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if ai:
		evade_timer = randf_range(ai.EVADE_DURATION_MIN, ai.EVADE_DURATION_MAX)

func exit() -> void:
	pass

func update(delta: float) -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if not ai or not ai.target or not ai.biplane:
		return
	var avatar = ai._get_avatar()
	if not avatar:
		return

	# Wall-time timer: decremented by the real delta accumulated by the
	# controller and passed through tick() (D8).
	evade_timer -= delta
	var pitch = ai._compute_evade_pitch()
	var throttle = ai._compute_evade_throttle()
	var reflexed = ai._apply_reflexes(pitch, throttle)
	ai.pilots[0].last_pitch_input = reflexed[0]
	ai.pilots[0].last_throttle = reflexed[1]

	var alt = ai._get_altitude_above_ground()
	var is_stalled = avatar and avatar.flight_state == ai.biplane.FlightState.STALLED
	if ai._is_fuel_low():
		finished.emit(&"returning")
	elif not is_stalled and evade_timer <= 0.0 \
			and alt > ai.MIN_ALTITUDE_ABOVE_GROUND \
			and ai.pilots[0].incoming_bullet_timer <= 0.0:
		# Return to the actual previous state (tracked by the base class),
		# replacing the old hardcoded previous_state=3 / magic match (D4).
		var prev = state_machine.previous_key
		if prev != &"":
			finished.emit(prev)
		else:
			finished.emit(&"patrolling")
