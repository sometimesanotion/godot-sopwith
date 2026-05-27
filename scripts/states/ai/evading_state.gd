extends State

var evade_timer: float = 0.0

func enter() -> void:
	evade_timer = randf_range(0.5, 2.0)
	var ai = (state_machine as AIStateMachine).ai_controller
	if ai:
		ai.pilots[0].previous_state = 3  # AIState.ENGAGING

func exit() -> void:
	pass

func update(delta: float) -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if not ai or not ai.target or not ai.biplane:
		return
	var avatar = ai._get_avatar()
	if not avatar:
		return

	evade_timer -= ai.decision_interval
	var pitch = ai._compute_evade_pitch()
	var throttle = ai._compute_evade_throttle()
	var reflexed = ai._apply_reflexes(pitch, throttle)
	ai.pilots[0].last_pitch_input = reflexed[0]
	ai.pilots[0].last_throttle = reflexed[1]
	ai._apply_input(ai.pilots[0].last_pitch_input, ai.pilots[0].last_throttle)
	ai._check_flip_needed()

	var alt = ai._get_altitude_above_ground()
	var is_stalled = avatar and avatar.flight_state == 1
	if not is_stalled and evade_timer <= 0.0 \
			and alt > ai.MIN_ALTITUDE_ABOVE_GROUND \
			and ai.pilots[0].incoming_bullet_timer <= 0.0:
		var prev = ai.pilots[0].previous_state
		match prev:
			2: finished.emit(&"patrolling")
			3: finished.emit(&"engaging")
			5: finished.emit(&"returning")
			_: finished.emit(&"patrolling")
