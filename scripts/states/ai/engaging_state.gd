extends State

## The default air-combat state: point at the target and fire.
##
## The state's job is just: WHERE do I want to fly, and at what
## throttle?  enemy_ai._engaging_aim_and_throttle() handles all the
## aim-throttling details — lead pursuit for a healthy plane, a
## recovery waypoint for a low-energy one, ground-attack dive for a
## grounded target, and a bomb run if we still have bombs.
##
## RECOVERY MODES (RECOVER_DIVE / RECOVER_CLIMB) are an internal
## sub-state managed by the controller, not a separate FSM state.
## They change the aim and turn rate but never the high-level FSM
## state — entering recovering as its own state would just give the
## recovery helper another wrapper to maintain.
##
## min_state_time commits the plane to a brief engagement before it
## can break off.  This is the primary flapping-prevention: a plane
## that is briefly on the AI's tail (defensive condition toggles)
## cannot immediately force an evade transition.

func enter() -> void:
	var fsm: AIStateMachine = state_machine
	fsm.current_throttle = 1.0
	fsm.min_state_time = 0.4

func update(_delta: float) -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if not ai or not ai.target or not ai.biplane:
		return
	var avatar = ai._get_avatar()
	if not avatar:
		return
	var fsm: AIStateMachine = state_machine

	# Target lost → bail out to patrolling (no engage aim is possible).
	if not ai._is_target_alive():
		if fsm.can_transition():
			finished.emit(&"patrolling")
		return

	# Aim + throttle.  Aim covers all attack types (air / ground / bomb);
	# the helper returns Vector2.INF if it can't decide so the controller
	# just holds heading.
	var pack: Array = ai._engaging_aim_and_throttle()
	fsm.current_aim_point   = pack[0]
	fsm.current_throttle    = pack[1]

	# Open fire every tick (the helper checks range / cone internally).
	ai._try_fire_weapon()

	# Exit gates (only after the stickiness floor has been met).
	if not fsm.can_transition():
		return
	var alt = ai._get_altitude_above_ground()
	var damage = avatar.damage.damage_percent
	var dist_to_tgt = ai._get_wrapped_distance(ai.biplane.global_position.x, ai.target.global_position.x)

	# Defensive reactions: always break when the player has our six, and
	# break under fire only when too slow or too hurt to fight back.  A
	# healthy, fast plane PRESSES a head-on attack instead of flinching
	# at every incoming round — that's what makes it aggressive.
	var defensive: bool = ai._should_evade_defensively()
	var under_fire: bool = ai.pilots[0].incoming_bullet_timer > 0.0
	if alt < ai.DANGER_ALTITUDE_ABOVE_GROUND or defensive \
			or (under_fire and (ai._is_low_energy() or damage >= 0.3)):
		finished.emit(&"evading")
	elif damage >= 0.5:
		finished.emit(&"returning")
	elif dist_to_tgt > ai.ENGAGEMENT_RANGE * 1.2:
		finished.emit(&"patrolling")
