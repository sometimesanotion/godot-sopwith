extends CharacterBody2D

class_name Biplane

## Biplane flight controller with SI-based aerodynamics
## Sopwith Camel baseline: 659 kg MTOW, 130hp rotary, 21.46 m2 wing
## Arcade feel achieved via gravity multiplier and tuned propeller curve

@export_group("Flight Parameters (SI Units)")
@export var mass: float = 659.0
@export var engine_power_watts: float = 96941.0
@export var wing_area: float = 21.46
@export var gravity: float = 9.81

@export_group("Scale & Arcade Tuning")
@export var pixels_per_meter: float = 10.0
@export var arcade_gravity_multiplier: float = 3.0

@export_group("Aerodynamics")
@export var zero_lift_drag_area: float = 0.811
@export var ar_efficiency: float = 11.0
@export var max_lift_coeff: float = 1.4
@export var air_density: float = 1.225
@export var stall_aoa: float = 0.244
@export var stall_speed_ms: float = 21.4

@export_group("Throttle")
@export var min_throttle: float = 0.0
@export var max_throttle: float = 1.0
@export var max_speed: float = 50.5

const THROTTLE_STEP := 0.2
const THROTTLE_REPEAT_DELAY := 0.1
const THROTTLE_RAMP_SPEED := 4.0

@export_group("Weapons")
@export var gun_cooldown: float = 0.1
@export var bomb_cooldown: float = 0.5
@export var bullet_speed: float = 800.0
@export var max_ammo: int = 100
@export var max_bombs: int = 5

@export_group("Roll")
@export var roll_speed: float = 4.0
@export var max_roll_angle: float = PI

@export_group("Handling")
@export var rotation_speed: float = 6.0
@export var rotation_inertia: float = 2.0

var throttle: float = 0.0
var throttle_target: float = 0.0
var throttle_repeat_timer: float = 0.0
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

var bank_angle: float = 0.0
var pitch_yaw_angle: float = 0.0
var visual_roll: float = 0.0
var heading_angle: float = 0.0

var max_bullet_range: float = 600.0
var last_shot_range: float = 0.0

var hit_count: int = 0
var reliability: float = 1.0
var smoke_particles: GPUParticles2D = null
var is_losing_control: bool = false
var game_active: bool = false

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
	PhysicsServer2D.body_set_param(get_rid(), PhysicsServer2D.BODY_PARAM_MASS, mass)

func _physics_process(delta: float) -> void:
	if not game_active:
		return

	if flight_state == FlightState.CRASHED:
		_apply_crash_physics(delta)
		return

	if is_losing_control:
		rotation += delta * 4.0
		_check_crash_on_spin()

	_handle_input(delta)
	_handle_weapons(delta)
	_apply_aerodynamics(delta)
	_apply_ground_forces(delta)
	_handle_roll(delta)

	global_position += velocity * delta
	_check_ground_collision()
	_check_obstacle_collision()
	_check_fuel_consumption(delta)

func _check_crash_on_spin() -> void:
	var ground_y: float = 650.0
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(global_position.x)

	if global_position.y >= ground_y - 5:
		flight_state = FlightState.CRASHED
		crashed.emit()
		if is_player and GameManager:
			GameManager.take_damage()

func _handle_input(delta: float) -> void:
	var pitch_authority: float = 1.0
	if flight_state == FlightState.STALLED:
		pitch_authority = 0.4

	var pitch_input: float
	var new_throttle: float

	if is_ai_controlled:
		pitch_input = ai_pitch_input
		throttle_target = ai_throttle
	else:
		pitch_input = Input.get_axis("pull_up", "pull_down") * pitch_authority
		var throttle_changed := false
		if Input.is_action_pressed("throttle_up"):
			throttle_repeat_timer -= delta
			if throttle_repeat_timer <= 0:
				throttle_target = min(max_throttle, throttle_target + THROTTLE_STEP)
				throttle_repeat_timer = THROTTLE_REPEAT_DELAY
				throttle_changed = true
		elif Input.is_action_pressed("throttle_down"):
			throttle_repeat_timer -= delta
			if throttle_repeat_timer <= 0:
				throttle_target = max(min_throttle, throttle_target - THROTTLE_STEP)
				throttle_repeat_timer = THROTTLE_REPEAT_DELAY
				throttle_changed = true
		else:
			throttle_repeat_timer = 0.0
		if not throttle_changed and throttle_target < min_throttle:
			throttle_target = min_throttle

		if Input.is_action_just_pressed("roll") and not is_rolling:
			_start_roll()
		elif Input.is_action_just_released("roll") and is_rolling:
			_end_roll()

	throttle = move_toward(throttle, throttle_target, THROTTLE_RAMP_SPEED * delta)

	if is_rolling:
		rotation = pitch_yaw_angle + bank_angle
	else:
		var target_angular_velocity := pitch_input * rotation_speed
		angular_velocity = move_toward(angular_velocity, target_angular_velocity, rotation_inertia * delta)
		pitch_yaw_angle += angular_velocity * delta
		rotation = pitch_yaw_angle + bank_angle

func _start_roll() -> void:
	is_rolling = true
	var normalized_rot := fmod(visual_roll, TAU)
	if normalized_rot < 0:
		normalized_rot += TAU

	if normalized_rot < PI:
		roll_direction = 1
	else:
		roll_direction = -1

func _handle_roll(delta: float) -> void:
	if is_rolling:
		bank_angle += roll_speed * delta * roll_direction
		var normalized_bank := fmod(bank_angle, TAU)
		if normalized_bank < 0:
			normalized_bank += TAU
		if normalized_bank > PI:
			visual_roll = normalized_bank - TAU
		else:
			visual_roll = normalized_bank
	else:
		var target_bank: float = 0.0
		var normalized_bank: float = fmod(bank_angle, TAU)
		if normalized_bank < 0:
			normalized_bank += TAU
		var dist_to_upright: float = abs(normalized_bank)
		var dist_to_inverted: float = abs(normalized_bank - PI)
		if dist_to_inverted < dist_to_upright:
			target_bank = PI
		else:
			target_bank = 0.0
		var remaining: float = target_bank - bank_angle
		while remaining > PI:
			remaining -= TAU
		while remaining < -PI:
			remaining += TAU
		bank_angle += remaining * 5.0 * delta
		visual_roll = bank_angle

func _end_roll() -> void:
	is_rolling = false

func is_dodging() -> bool:
	return is_rolling

func get_dodge_chance() -> float:
	if not is_rolling:
		return 0.0
	return last_shot_range / max_bullet_range

func _is_on_ground() -> bool:
	var ground_y: float = 650.0
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(global_position.x)
	var speed = get_speed()
	return global_position.y >= ground_y - 15 and speed < 80

func _apply_aerodynamics(delta: float) -> void:
	heading_angle = pitch_yaw_angle
	var forward := Vector2(cos(heading_angle), sin(heading_angle))

	var vel_si := velocity / pixels_per_meter
	var speed_si := vel_si.length()

	var on_ground := _is_on_ground()

	if on_ground and speed_si < 0.5:
		var thrust_si := _calc_thrust(0.0, throttle)
		velocity.x += thrust_si * throttle * 0.85 * delta * pixels_per_meter / mass
		var drag_si := speed_si * 0.5 * 0.05
		if speed_si > 0.01:
			velocity += (-vel_si.normalized()) * drag_si * delta * pixels_per_meter / mass
		return

	var thrust_si := _calc_thrust(speed_si, throttle)
	var thrust_vec := forward * thrust_si

	var angle_of_attack: float = 0.0
	if speed_si > 0.5:
		var vel_dir := vel_si.normalized()
		angle_of_attack = forward.angle_to(vel_dir)
	else:
		angle_of_attack = 0.0

	if on_ground:
		is_stalled = false
		flight_state = FlightState.FLYING
	elif abs(angle_of_attack) > stall_aoa or speed_si < stall_speed_ms:
		is_stalled = true
		if flight_state == FlightState.FLYING:
			flight_state = FlightState.STALLED
	else:
		is_stalled = false
		if flight_state == FlightState.STALLED:
			flight_state = FlightState.FLYING

	var cl: float = angle_of_attack * 2.0 * PI
	cl = clampf(cl, -max_lift_coeff, max_lift_coeff)
	if is_stalled:
		cl *= 0.3

	var lift_si: float = 0.5 * air_density * speed_si * speed_si * wing_area * cl
	var lift_vec: Vector2 = Vector2.ZERO
	if speed_si > 0.5:
		var lift_dir: Vector2 = Vector2(forward.y, -forward.x)
		var is_inverted: bool = abs(visual_roll) > PI * 0.5
		if is_inverted:
			lift_dir = -lift_dir
		lift_vec = lift_dir * lift_si

	var parasitic_drag_si := 0.5 * air_density * speed_si * speed_si * zero_lift_drag_area
	var induced_drag_si := 0.5 * air_density * speed_si * speed_si * wing_area * (cl * cl) / ar_efficiency

	var speed_px := velocity.length()
	var speed_limit_drag: float = 0.0
	if speed_px > max_speed:
		var overspeed := speed_px - max_speed
		speed_limit_drag = overspeed * overspeed * 0.5

	var total_drag_si := parasitic_drag_si + induced_drag_si + speed_limit_drag / pixels_per_meter
	var drag_vec := Vector2.ZERO
	if speed_si > 0.01:
		drag_vec = -vel_si.normalized() * total_drag_si

	var weight_vec := Vector2(0, mass * gravity)

	var net_force_si := thrust_vec + lift_vec + drag_vec + weight_vec

	var accel_si := net_force_si / mass
	var accel_px := accel_si * pixels_per_meter

	velocity += accel_px * delta

func _apply_ground_forces(delta: float) -> void:
	var ground_y: float = 650.0
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(global_position.x)

	if global_position.y >= ground_y - 12:
		global_position.y = ground_y - 12
		velocity.y = 0
	elif global_position.y > ground_y - 12:
		global_position.y = ground_y - 12
		velocity.y = 0

func _calc_thrust(speed_si: float, thr: float) -> float:
	if speed_si < 0.5:
		return 2000.0 * thr

	var eta := 0.8 * (1.0 - pow((speed_si - 40.0) / 40.0, 2))
	eta = maxf(eta, 0.0)

	var thrust_from_power := engine_power_watts * eta / speed_si

	var gm_thrust_mult := 1.5
	if GameManager:
		gm_thrust_mult = GameManager.thrust_multiplier

	return thrust_from_power * thr * gm_thrust_mult

func _check_ground_collision() -> void:
	var ground_y: float = 650.0
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(global_position.x)

	if global_position.y >= ground_y - 8:
		var speed = get_speed()
		var normalized_rot: float = fmod(rotation, TAU)
		if normalized_rot < 0:
			normalized_rot += TAU

		var slope_angle: float = 0.0
		if terrain and terrain.has_method("get_ground_height_at"):
			var ground_ahead: float = terrain.get_ground_height_at(global_position.x + 10)
			var ground_behind: float = terrain.get_ground_height_at(global_position.x - 10)
			slope_angle = atan2(ground_ahead - ground_behind, 20.0)

		var relative_angle: float = normalized_rot - slope_angle
		while relative_angle > PI:
			relative_angle -= TAU
		while relative_angle < -PI:
			relative_angle += TAU

		var tilt_angle: float = abs(relative_angle)
		var is_excessive_tilt: bool = tilt_angle > deg_to_rad(20)

		if speed < 30 and not is_excessive_tilt:
			global_position.y = ground_y - 10
			velocity.x = 0
			velocity.y = 0
			flight_state = FlightState.FLYING
		elif is_excessive_tilt:
			flight_state = FlightState.CRASHED
			crashed.emit()
			if is_player and GameManager:
				GameManager.take_damage()

func _check_obstacle_collision() -> void:
	if flight_state == FlightState.CRASHED:
		return

	var speed := get_speed()
	if speed < 5:
		return

	var parent := get_parent()
	if not parent:
		return

	for child in parent.get_children():
		if child == self:
			continue
		if child is StaticBody2D and (child.is_in_group("ground_target") or child.is_in_group("wreck") or child.is_in_group("obstacle")):
			var dist := global_position.distance_to(child.global_position)
			var hit_radius: float = 25.0
			if child.is_in_group("ground_target") or child.is_in_group("wreck"):
				hit_radius = 35.0
			if dist < hit_radius:
				flight_state = FlightState.CRASHED
				crashed.emit()
				if is_player and GameManager:
					GameManager.take_damage()
				return

func _apply_crash_physics(delta: float) -> void:
	velocity.y += gravity * pixels_per_meter * arcade_gravity_multiplier * delta
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

	var heading_dir := Vector2(cos(pitch_yaw_angle), sin(pitch_yaw_angle))
	var spawn_pos := global_position + heading_dir * 30
	var direction := heading_dir

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
	bullet.rotation = pitch_yaw_angle
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

	var forward := Vector2(cos(pitch_yaw_angle), sin(pitch_yaw_angle))
	var perpendicular := Vector2(-forward.y, forward.x).normalized()

	var spawn_offset := perpendicular * 15.0

	var spawn_pos := global_position + spawn_offset
	bomb.global_position = spawn_pos
	bomb.rotation = pitch_yaw_angle
	bomb.initialize(self, velocity)

	get_parent().add_child(bomb)
	dropped_bomb.emit(spawn_pos, velocity, self)

func _check_fuel_consumption(delta: float) -> void:
	if is_player and GameManager and throttle > 0:
		var fuel_loss = throttle * delta * 2.0
		if hit_count >= 2:
			fuel_loss *= 2.0
		GameManager.use_fuel(fuel_loss)

	if is_player and SoundManager:
		SoundManager.play_engine(throttle)

func set_player(p: bool) -> void:
	is_player = p

func set_game_active(active: bool) -> void:
	game_active = active

func get_ammo() -> int:
	return current_ammo

func get_bombs() -> int:
	return current_bombs

func reset_flight_state() -> void:
	flight_state = FlightState.FLYING
	throttle = 0.0
	throttle_target = 0.0
	throttle_repeat_timer = 0.0
	angular_velocity = 0.0
	rotation = 0.0
	pitch_yaw_angle = 0.0
	bank_angle = 0.0
	visual_roll = 0.0
	is_stalled = false
	velocity = Vector2.ZERO
	is_rolling = false
	is_losing_control = false
	hit_count = 0
	reliability = 1.0
	autopilot_enabled = false
	is_autopilot_landing = false
	if has_node("SmokeParticles"):
		var sp: GPUParticles2D = get_node("SmokeParticles")
		sp.emitting = false
		sp.queue_free()
		smoke_particles = null

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

	var heading_dir := Vector2(cos(pitch_yaw_angle), sin(pitch_yaw_angle))
	var spawn_pos := global_position + heading_dir * 30
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
	bullet.rotation = pitch_yaw_angle
	bullet.assign_owner(self, range_percent)

	get_parent().add_child(bullet)
	fired_bullet.emit(spawn_pos, heading_dir, bullet_speed, self, range_percent)

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

func take_damage(amount: float, attacker: Node) -> void:
	if flight_state == FlightState.CRASHED:
		return

	hit_count += 1

	if hit_count == 1:
		reliability = 0.75
		_add_smoke_stream(Color(0.9, 0.9, 0.9, 0.6), 15)
	elif hit_count == 2:
		reliability = 0.5
		_add_smoke_stream(Color(0.3, 0.3, 0.3, 0.8), 25)
	elif hit_count >= 3:
		reliability = 0.0
		_start_spinning_out()

func _add_smoke_stream(color: Color, amount: int) -> void:
	if has_node("SmokeParticles"):
		smoke_particles = get_node("SmokeParticles")
	else:
		smoke_particles = GPUParticles2D.new()
		smoke_particles.name = "SmokeParticles"
		smoke_particles.emitting = true
		smoke_particles.amount = amount
		smoke_particles.lifetime = 0.5
		smoke_particles.speed_scale = 1.0

		var material = ParticleProcessMaterial.new()
		material.emission_shape = 1
		material.emission_sphere_radius = 5.0
		material.gravity = Vector3(0, 50, 0)
		material.spread = 20.0
		material.initial_velocity_min = 20.0
		material.initial_velocity_max = 50.0
		material.scale_min = 3.0
		material.scale_max = 8.0
		material.color = color
		smoke_particles.process_material = material

		add_child(smoke_particles)

func _start_spinning_out() -> void:
	is_losing_control = true
	throttle = 0.0
	_start_roll()

func get_reliability() -> float:
	return reliability
