extends CharacterBody2D

class_name Biplane

## Biplane flight controller using vector-force aerodynamics
## Based on the Sopwith flight model with continuous rotation

@export_group("Flight Parameters")
@export var thrust_power: float = 200.0
@export var drag_coefficient: float = 0.02
@export var gravity: float = 400.0
@export var rotation_speed: float = 4.0
@export var rotation_inertia: float = 2.0

@export_group("Aerodynamics")
@export var lift_coefficient: float = 0.8
@export var stall_threshold: float = 80.0

@export_group("Throttle")
@export var min_throttle: float = 0.0
@export var max_throttle: float = 1.0

@export_group("Weapons")
@export var gun_cooldown: float = 0.1
@export var bomb_cooldown: float = 0.5
@export var bullet_speed: float = 800.0
@export var max_ammo: int = 100
@export var max_bombs: int = 5

@export_group("Roll")
@export var roll_speed: float = 4.0
@export var max_roll_angle: float = PI

var throttle: float = 0.5
var angular_velocity: float = 0.0
var is_stalled: bool = false

var current_ammo: int = 100
var current_bombs: int = 5
var gun_timer: float = 0.0
var bomb_timer: float = 0.0
var is_player: bool = true

var is_rolling: bool = false
var roll_direction: int = 1
var roll_start_angle: float = 0.0
var target_roll_angle: float = 0.0

var visual_roll: float = 0.0
var heading_angle: float = 0.0

var max_bullet_range: float = 600.0
var last_shot_range: float = 0.0

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const BOMB_SCENE := preload("res://scenes/bomb.tscn")

signal fired_bullet(position: Vector2, direction: Vector2, speed: float, owner: Node, range_percent: float)
signal dropped_bomb(position: Vector2, velocity: Vector2, owner: Node)
signal crashed()

enum FlightState {
	FLYING,
	STALLED,
	FALLING,
	CRASHED
}

var flight_state: FlightState = FlightState.FLYING

func _ready() -> void:
	motion_mode = MotionMode.MOTION_MODE_FLOATING

func _physics_process(delta: float) -> void:
	if flight_state == FlightState.CRASHED:
		_apply_crash_physics(delta)
		return

	_handle_input(delta)
	_handle_weapons(delta)
	_apply_aerodynamics(delta)
	_apply_forces(delta)
	_handle_roll(delta)
	
	global_position += velocity * delta
	_check_ground_collision()
	_check_fuel_consumption(delta)

func _handle_input(delta: float) -> void:
	if flight_state == FlightState.STALLED or flight_state == FlightState.FALLING:
		return

	var pitch_input: float
	var new_throttle: float

	if is_ai_controlled:
		pitch_input = ai_pitch_input
		new_throttle = ai_throttle
	else:
		pitch_input = Input.get_axis("pull_down", "pull_up")
		if Input.is_action_pressed("throttle_up"):
			new_throttle = min(throttle + delta * 0.5, max_throttle)
		elif Input.is_action_pressed("throttle_down"):
			new_throttle = max(throttle - delta * 0.5, min_throttle)
		else:
			new_throttle = throttle

		if Input.is_action_just_pressed("roll") and not is_rolling:
			_start_roll()
		elif Input.is_action_just_released("roll") and is_rolling:
			_end_roll()

	throttle = new_throttle

	if not is_rolling:
		var target_angular_velocity := pitch_input * rotation_speed
		angular_velocity = move_toward(angular_velocity, target_angular_velocity, rotation_inertia * delta)
		rotation += angular_velocity * delta

func _start_roll() -> void:
	is_rolling = true
	var normalized_rot := fmod(rotation, TAU)
	if normalized_rot < 0:
		normalized_rot += TAU
	
	if normalized_rot < PI:
		roll_direction = 1
		roll_start_angle = normalized_rot
		target_roll_angle = normalized_rot + PI
	else:
		roll_direction = -1
		roll_start_angle = normalized_rot
		target_roll_angle = normalized_rot - PI

func _handle_roll(delta: float) -> void:
	if not is_rolling:
		return

	visual_roll += roll_speed * delta * roll_direction
	
	if visual_roll >= PI:
		visual_roll -= TAU
		is_rolling = false
	elif visual_roll <= -PI:
		visual_roll += TAU
		is_rolling = false
	
	if not is_rolling:
		if visual_roll > 0:
			visual_roll = PI
		else:
			visual_roll = -PI

func _end_roll() -> void:
	is_rolling = false
	if abs(visual_roll) > PI / 2:
		visual_roll = PI if visual_roll > 0 else -PI
	else:
		visual_roll = 0.0

func is_dodging() -> bool:
	return is_rolling

func get_dodge_chance() -> float:
	if not is_rolling:
		return 0.0
	return last_shot_range / max_bullet_range

func _apply_aerodynamics(delta: float) -> void:
	heading_angle = rotation
	var forward := Vector2(cos(heading_angle), sin(heading_angle))
	var speed := velocity.length()

	if speed < stall_threshold:
		is_stalled = true
		if flight_state == FlightState.FLYING:
			flight_state = FlightState.STALLED
	else:
		is_stalled = false
		if flight_state == FlightState.STALLED:
			flight_state = FlightState.FLYING

	var dot_product := forward.dot(velocity.normalized()) if speed > 0 else 0.0
	var lift_factor := clampf(dot_product, -1.0, 1.0)
	lift_factor = lift_factor * lift_factor * sign(dot_product)

	var lift_magnitude := lift_coefficient * speed * speed * 0.001
	if is_stalled:
		lift_magnitude *= 0.2

	var lift_direction := Vector2(-forward.y, forward.x)
	velocity += lift_direction * lift_magnitude * delta

	var thrust_direction := forward * throttle * thrust_power
	if is_stalled and flight_state == FlightState.STALLED:
		thrust_direction *= 0.0

	velocity += thrust_direction * delta

	var drag_magnitude := drag_coefficient * speed * speed
	var drag_direction := -velocity.normalized() if speed > 0 else Vector2.ZERO
	velocity += drag_direction * drag_magnitude * delta

func _apply_forces(delta: float) -> void:
	if is_stalled and flight_state == FlightState.STALLED:
		velocity.y += gravity * 2.5 * delta
	else:
		velocity.y += gravity * delta

func _check_ground_collision() -> void:
	var ground_y: float = 650.0
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(global_position.x)
	
	if global_position.y >= ground_y - 8:
		var speed = get_speed()
		if speed < 40:
			global_position.y = ground_y - 10
			velocity = Vector2.ZERO
			flight_state = FlightState.FLYING
		else:
			flight_state = FlightState.CRASHED
			crashed.emit()
			if is_player and GameManager:
				GameManager.take_damage()

func _apply_crash_physics(delta: float) -> void:
	velocity.y += gravity * delta
	rotation += velocity.x * 0.01 * delta
	move_and_slide()
	var ground_ray: RayCast2D = $GroundRay if has_node("GroundRay") else null
	if ground_ray and ground_ray.is_colliding():
		velocity = Vector2.ZERO

func get_speed() -> float:
	return velocity.length()

func get_vertical_speed() -> float:
	return velocity.y

func is_stalling() -> bool:
	return is_stalled

func _handle_weapons(delta: float) -> void:
	gun_timer = max(0, gun_timer - delta)
	bomb_timer = max(0, bomb_timer - delta)

	if is_player and GameManager:
		current_ammo = GameManager.ammo
		current_bombs = GameManager.bombs

	if Input.is_action_pressed("fire") and gun_timer <= 0:
		_fire_gun()

	if Input.is_action_just_pressed("bomb") and bomb_timer <= 0:
		_drop_bomb()

func _fire_gun() -> void:
	if current_ammo <= 0:
		return

	gun_timer = gun_cooldown

	if is_player and GameManager:
		if not GameManager.use_ammo():
			return

	var spawn_pos := global_position + transform.x * 20
	var direction := transform.x
	
	var target_enemy: Node = _find_nearest_enemy()
	var range_percent: float = 0.0
	if target_enemy:
		var dist := spawn_pos.distance_to(target_enemy.global_position)
		last_shot_range = min(dist, max_bullet_range)
		range_percent = last_shot_range / max_bullet_range
	else:
		last_shot_range = max_bullet_range * 0.5
		range_percent = 0.5

	var bullet := BULLET_SCENE.instantiate()
	bullet.speed = bullet_speed

	bullet.global_position = spawn_pos
	bullet.rotation = rotation
	bullet.assign_owner(self, range_percent)

	get_parent().add_child(bullet)
	fired_bullet.emit(spawn_pos, direction, bullet_speed, self, range_percent)
	
	if SoundManager:
		SoundManager.play_machine_gun()

func _find_nearest_enemy() -> Node:
	var nearest: Node = null
	var min_dist := INF
	
	var parent := get_parent()
	for child in parent.get_children():
		if child == self:
			continue
		if is_player and child.has_method("is_enemy") and child.is_enemy():
			var dist := global_position.distance_to(child.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = child
		elif not is_player and child == GameManager.player:
			var dist := global_position.distance_to(child.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = child
	
	return nearest

func _drop_bomb() -> void:
	if current_bombs <= 0:
		return

	bomb_timer = bomb_cooldown

	if is_player and GameManager:
		if not GameManager.use_bomb():
			return

	var bomb := BOMB_SCENE.instantiate()
	
	var forward := Vector2(cos(rotation), sin(rotation))
	var perpendicular := Vector2(-forward.y, forward.x).normalized()
	
	var spawn_offset := perpendicular * 15.0
	
	var spawn_pos := global_position + spawn_offset
	bomb.global_position = spawn_pos
	bomb.rotation = rotation
	bomb.initialize(self, velocity)

	get_parent().add_child(bomb)
	dropped_bomb.emit(spawn_pos, velocity, self)

func _check_fuel_consumption(delta: float) -> void:
	if is_player and GameManager and throttle > 0:
		GameManager.use_fuel(throttle * delta * 2.0)
	
	if is_player and SoundManager:
		SoundManager.play_engine(throttle)

func set_player(p: bool) -> void:
	is_player = p

func get_ammo() -> int:
	return current_ammo

func get_bombs() -> int:
	return current_bombs

func reset_flight_state() -> void:
	flight_state = FlightState.FLYING
	throttle = 0.0
	angular_velocity = 0.0
	is_stalled = false
	velocity = Vector2.ZERO

var ai_pitch_input: float = 0.0
var ai_throttle: float = 0.5
var is_ai_controlled: bool = false

func set_ai_input(pitch: float, throttle_val: float) -> void:
	ai_pitch_input = pitch
	ai_throttle = throttle_val
	is_ai_controlled = true

func fire_gun() -> void:
	if current_ammo <= 0:
		return

	gun_timer = gun_cooldown

	var spawn_pos := global_position + transform.x * 20
	var target_enemy: Node = _find_nearest_enemy()
	var range_percent: float = 0.5
	if target_enemy:
		var dist := spawn_pos.distance_to(target_enemy.global_position)
		last_shot_range = min(dist, max_bullet_range)
		range_percent = last_shot_range / max_bullet_range
	else:
		last_shot_range = max_bullet_range * 0.5

	var bullet := BULLET_SCENE.instantiate()
	bullet.speed = bullet_speed

	bullet.global_position = spawn_pos
	bullet.rotation = rotation
	bullet.assign_owner(self, range_percent)

	get_parent().add_child(bullet)
	fired_bullet.emit(spawn_pos, transform.x, bullet_speed, self, range_percent)

var autopilot_enabled: bool = false

func enable_autopilot() -> void:
	autopilot_enabled = true

func disable_autopilot() -> void:
	autopilot_enabled = false
	is_ai_controlled = false

var is_autopilot_landing: bool = false

func update_autopilot(target_pos: Vector2) -> void:
	if not autopilot_enabled:
		return

	var to_target := target_pos - global_position
	var distance := to_target.length()
	
	if distance < 150:
		_handle_autopilot_landing(to_target)
		return

	var target_angle := to_target.angle()

	var angle_diff := target_angle - rotation
	while angle_diff > PI:
		angle_diff -= TAU
	while angle_diff < -PI:
		angle_diff += TAU

	var pitch_input := 0.0
	if angle_diff > 0.1:
		pitch_input = -1.0
	elif angle_diff < -0.1:
		pitch_input = 1.0

	var throttle_val := 0.8
	if distance < 300:
		throttle_val = 0.5

	set_ai_input(pitch_input, throttle_val)

func _handle_autopilot_landing(to_home: Vector2) -> void:
	if is_grounded():
		is_autopilot_landing = false
		autopilot_enabled = false
		throttle = 0.0
		return
	
	is_autopilot_landing = true
	
	var home_angle := to_home.angle()
	var angle_diff := home_angle - rotation
	while angle_diff > PI:
		angle_diff -= TAU
	while angle_diff < -PI:
		angle_diff += TAU
	
	var pitch_input: float = 0.0
	if angle_diff > 0.2:
		pitch_input = -1.0
	elif angle_diff < -0.2:
		pitch_input = 1.0
	
	if to_home.x > 0 and rotation > -0.3 and rotation < 0.3:
		pitch_input = 0.3
	
	var speed_val := get_speed()
	if speed_val > 60:
		pitch_input = max(pitch_input, 0.3)
	
	set_ai_input(pitch_input, 0.3)

func is_player_plane() -> bool:
	return is_player

func is_enemy_plane() -> bool:
	return not is_player

func is_grounded() -> bool:
	var ground_ray: RayCast2D = $GroundRay if has_node("GroundRay") else null
	if ground_ray:
		return ground_ray.is_colliding()
	return false

func get_visual_roll() -> float:
	return visual_roll