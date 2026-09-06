extends State

## Take-off roll and initial climb.  Uses DIRECT PITCH MODE
## (current_pitch_override) because the takeoff curve is a function of
## speed and altitude — not an aim-at-point.  The controller applies
## the override and never reads current_aim_point while it's set.
##
## Pitch is computed in the GRAVITY FRAME via enemy_ai._takeoff_pitch()
## which in turn uses AvatarData helpers (gravity_pitch, etc.) so a
## leftward/inverted plane still commands "nose up" the same way as a
## rightward upright one.
##
## min_state_time commits the plane to a brief roll-and-climb before
## allowing a transition out (otherwise a fast plane that reaches
## PATROL_ALTITUDE on a single decision tick would flap back to
## grounded or jump straight to engaging).

func enter() -> void:
	var fsm: AIStateMachine = state_machine
	# Direct pitch mode: leave aim at INF, write the pitch override.
	fsm.current_pitch_override = 0.0
	fsm.current_throttle = 1.0
	fsm.min_state_time = 0.5

func update(_delta: float) -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if not ai or not ai.target or not ai.biplane:
		return
	var avatar = ai._get_avatar()
	if not avatar:
		return
	var fsm: AIStateMachine = state_machine

	# Re-evaluate the takeoff pitch every tick — the curve is
	# speed-dependent and a freshly-spawned plane hasn't reached its
	# first rotate speed yet.
	fsm.current_pitch_override = ai._takeoff_pitch(avatar)
	fsm.current_throttle = 1.0

	# Once we've climbed to the patrol altitude (and the stickiness
	# floor is met) commit to the patrol.  From patrolling the engage
	# transition takes over if a target is in range — keeping the
	# takeoff state's job narrow (just get airborne) avoids a
	# mid-takeoff engage decision that flaps back to patrolling when
	# the target drifts.
	#
	# Early interrupt: a safely airborne plane (above the tallest runway
	# structures) with a live target inside detection range answers the
	# cue at once instead of climbing blind to patrol altitude first.
	# Engaging owns low-altitude safety itself (evades below danger
	# altitude), and its 0.4 s stickiness prevents flap-back, so this
	# cannot oscillate.
	if fsm.can_transition() and ai._get_altitude_above_ground() > ai.TAKEOFF_ENGAGE_MIN_ALT \
			and ai._is_target_alive() \
			and ai._get_wrapped_distance(ai.biplane.global_position.x, ai.target.global_position.x) < ai.DETECTION_RANGE:
		finished.emit(&"engaging")
		return
	if fsm.can_transition() and ai._get_altitude_above_ground() > ai.PATROL_ALTITUDE:
		finished.emit(&"patrolling")
