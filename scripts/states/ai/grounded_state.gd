extends State

## Parked on the runway.  Sits idle (no aim, no pitch, idle throttle)
## until a live target enters this plane's patrol territory, then
## immediately commits to a take-off.  The launch gate is the SAME
## territory bound that gates PATROL→ENGAGE, so a parked plane only
## scrambles when the player is actually inside its patrol_range — never
## when the player is elsewhere on the (wrapped) map.  No min_state_time
## floor: a parked plane should scramble the moment a target appears.
##
## The aim / pitch / throttle fields on the FSM stay at their reset
## defaults (Vector2.INF / INF / 1.0) — the controller treats that as
## "hold last heading, no pitch, idle throttle" (see
## enemy_ai._apply_state_output).

func enter() -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if ai:
		ai.pilots[0].last_pitch_input = 0.0
		ai.pilots[0].last_throttle = 0.0

func update(_delta: float) -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if not ai or not ai.target or not ai.biplane:
		return
	# A live player anywhere on the (wrapped) map is NOT automatically
	# worth scrambling for.  We only launch when the player is inside
	# this plane's patrol territory (the same bound that gates
	# PATROL→ENGAGE).  The engage layer still picks the right attack for
	# a grounded vs airborne target once we are airborne.
	if ai._is_target_alive() and ai._is_player_in_territory():
		finished.emit(&"taking_off")
