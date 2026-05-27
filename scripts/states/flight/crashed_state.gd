extends State

func enter() -> void:
	var plane: RigidBody2D = (state_machine as FlightStateMachine).biplane
	if not plane:
		return
	var avatar = plane.get_avatar_data(0)
	if avatar:
		avatar.flight_state = plane.FlightState.CRASHED
		avatar.damage.damage_state = DamageData.DamageState.DESTROYED

func exit() -> void:
	pass

func physics_update(delta: float) -> void:
	pass
