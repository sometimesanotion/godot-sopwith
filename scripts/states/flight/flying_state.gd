extends State

func enter() -> void:
	pass

func exit() -> void:
	pass

func physics_update(delta: float) -> void:
	var plane: RigidBody2D = (state_machine as FlightStateMachine).biplane
	if not plane or not plane.game_active:
		return
	var avatar = plane.get_avatar_data(0)
	if not avatar:
		return
	plane._handle_input(avatar, delta)
	plane._handle_weapons(avatar, delta)
	plane._check_altitude_engine_cutoff(avatar, delta)
	plane._check_obstacle_collision(avatar)
	plane._check_fuel_consumption(avatar, delta)
	plane._check_home_refuel(avatar, delta)
