extends State

## Defensive break turn.  Picks a direction AWAY from the attacker
## (or the velocity vector if no threat is in range) and aims at a
## waypoint that combines that direction with a vertical bias driven
## by energy — climb when the plane has speed to spend, dive when it
## has altitude to trade.
##
## The previous state's key is captured on enter (via the FSM's
## previous_key) so the evade can always return to where it came from
## (engaging or returning) once the break is done.
##
## min_state_time locks the plane into the break for at least
## EVADE_DURATION_MIN — a brief moment of "defensive" cannot pull
## the AI back into engaging one tick later (which is the canonical
## engage↔evade flap).

var _evade_duration: float = 0.0

func enter() -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	_evade_duration = ai.EVADE_DURATION_MIN if ai else 0.5
	if ai:
		_evade_duration = randf_range(ai.EVADE_DURATION_MIN, ai.EVADE_DURATION_MAX)
	var fsm: AIStateMachine = state_machine
	fsm.current_throttle = 1.0
	# Stickiness floor = full break duration: the plane cannot exit
	# the evade until the timer runs out, no matter what happens
	# to the defensive condition that triggered it.
	fsm.min_state_time = _evade_duration

func update(_delta: float) -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if not ai or not ai.target or not ai.biplane:
		return
	var avatar = ai._get_avatar()
	if not avatar:
		return
	var fsm: AIStateMachine = state_machine

	# Re-evaluate the evade waypoint every tick so an attacker that
	# keeps repositioning doesn't get a free pass.
	fsm.current_aim_point = ai._evade_aim_point()
	fsm.current_throttle = 1.0

	if not fsm.can_transition():
		return
	# Revert to whatever the FSM came from — the previous key is set
	# by AIStateMachine._change_state, so this works for engaging,
	# returning, or any other state that legitimately transitions in.
	# Fall back to patrolling if there is no prior state (e.g. the
	# FSM was just initialized).
	if ai._is_fuel_low():
		finished.emit(&"returning")
		return
	var prev = state_machine.previous_key
	if prev != &"" and prev != &"evading":
		finished.emit(prev)
	else:
		finished.emit(&"patrolling")
