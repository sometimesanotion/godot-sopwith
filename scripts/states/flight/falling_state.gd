extends State

func enter() -> void:
	var plane: RigidBody2D = (state_machine as FlightStateMachine).biplane
	if not plane:
		return
	var avatar = plane.get_avatar_data(0)
	if avatar:
		avatar.angular_velocity = 1.0

func exit() -> void:
	pass

func physics_update(delta: float) -> void:
	var plane: RigidBody2D = (state_machine as FlightStateMachine).biplane
	if not plane or not plane.game_active:
		return
	var avatar = plane.get_avatar_data(0)
	if not avatar:
		return
	plane._check_obstacle_collision(avatar)
