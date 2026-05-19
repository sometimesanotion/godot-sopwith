class_name Biplane
extends CharacterBody2D

## Biplane flight controller with SI-based aerodynamics
## Sopwith Camel baseline: 659 kg MTOW, 130hp rotary, 21.46 m2 wing
## Arcade feel achieved via gravity multiplier and tuned propeller curve

@export_group("Flight Parameters (SI Units)")
@export var arcade_multiplier: float = 1.8

@export var camel_mass_kg: float = 447.0
@export var engine_power_watts: float = 96941.0 * arcade_multiplier
@export var wing_area: float = 21.46
@export var gravity: float = 9.81 * 0.6

@export_group("Scale & Arcade Tuning")
@export var pixels_per_meter: float = 10.0

@export_group("Aerodynamics")
@export var zero_lift_drag_area: float = 0.811
@export var ar_efficiency: float = 11.0
@export var max_lift_coeff: float = 1.4
@export var air_density: float = 1.225 * arcade_multiplier
@export var ground_drag_coeff = 200.0
@export var stall_aoa: float = 0.244
@export var stall_speed_ms: float = 21.4 / 2.2

@export_group("Throttle")
@export var min_throttle: float = 0.0
@export var max_throttle: float = 1.0
@export var max_speed: float = 400.0

const THROTTLE_STEP := 0.1
const THROTTLE_REPEAT_DELAY := 0.1
const THROTTLE_RAMP_SPEED := 4.0

const MAX_AMMO := 250
const MAX_BOMBS := 5

@export_group("Weapons")
@export var gun_cooldown: float = 0.1
@export var bomb_cooldown: float = 0.5
@export var bullet_speed: float = 1600.0

const FLIP_DURATION := 0.35
const FLIP_ARC_HEIGHT := 15.0

@export_group("Handling")
@export var rotation_speed: float = 9.0
@export var rotation_inertia: float = 3.0

@export_group("Impact Physics (Sopwith Camel)")
@export var bungee_compression_time: float = 0.15
@export var soft_landing_vperp: float = 40.0
@export var hard_landing_vperp: float = 100.0
@export var max_landing_tilt_deg: float = 34.0

enum FlightState {
	FLYING,
	STALLED,
	FALLING,
	DAMAGED,
	CRASHED
}

const ENGINE_EFFICIENCY_START_ALTITUDE := 700.0
const ENGINE_CUTOFF_ALTITUDE := 2000.0

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const BOMB_SCENE := preload("res://scenes/bomb.tscn")

static var _white_smoke_material: ParticleProcessMaterial
static var _black_smoke_material: ParticleProcessMaterial
static var _fire_material: ParticleProcessMaterial

static func _init_particle_materials() -> void:
	if _white_smoke_material:
		return
	_white_smoke_material = ParticleProcessMaterial.new()
	_white_smoke_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_white_smoke_material.emission_sphere_radius = 8.0
	_white_smoke_material.gravity = Vector3(0, 30, 0)
	_white_smoke_material.spread = 30.0
	_white_smoke_material.initial_velocity_min = 30.0
	_white_smoke_material.initial_velocity_max = 60.0
	_white_smoke_material.scale_min = 4.0
	_white_smoke_material.scale_max = 10.0
	_white_smoke_material.color = Color(0.8, 0.8, 0.8, 0.5)

	_black_smoke_material = ParticleProcessMaterial.new()
	_black_smoke_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_black_smoke_material.emission_sphere_radius = 8.0
	_black_smoke_material.gravity = Vector3(0, 30, 0)
	_black_smoke_material.spread = 30.0
	_black_smoke_material.initial_velocity_min = 30.0
	_black_smoke_material.initial_velocity_max = 60.0
	_black_smoke_material.scale_min = 4.0
	_black_smoke_material.scale_max = 10.0
	_black_smoke_material.color = Color(0.05, 0.05, 0.05, 0.5)

	_fire_material = ParticleProcessMaterial.new()
	_fire_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_fire_material.emission_sphere_radius = 5.0
	_fire_material.gravity = Vector3(0, 30, 0)
	_fire_material.spread = 30.0
	_fire_material.initial_velocity_min = 60.0
	_fire_material.initial_velocity_max = 90.0
	_fire_material.scale_min = 3.0
	_fire_material.scale_max = 6.0
	_fire_material.color = Color(0.95, 0.5, 0.2, 0.9)

signal fired_bullet(position: Vector2, direction: Vector2, speed: float, owner: Node, range_percent: float)
signal dropped_bomb(position: Vector2, velocity: Vector2, owner: Node)
signal crashed()
signal damaged(impact_force: float, v_perp: float)

var game_active: bool = false
var _crash_processed: Dictionary = {}

# var _smoke_material = ParticleProcessMaterial.new()
# _smoke_material.emission_shape = 1
# _smoke_material.emission_sphere_radius = 5.0
# _smoke_material.gravity = Vector3(0, 50, 0)
# _smoke_material.spread = 20.0
# _smoke_material.initial_velocity_min = 20.0
# _smoke_material.initial_velocity_max = 50.0
# _smoke_material.scale_min = 3.0
# _smoke_material.scale_max = 8.0
# _smoke_material.color = color

class HomebaseData:
	var id: int = 0
	var home_base_x: float = 6554.0
	var home_base_width: float = 200.0
	var landing_threshold: float = 1000.0
	var spawn_position: Vector2 = Vector2(7000, 500)
	var spawn_rotation: float = 0.0

var _homebases: Dictionary[int, HomebaseData] = {}

class AvatarData:
	var id: int = 0
	var unlimited_fuel_ammo: bool = false
	var bombs_disabled: bool = false
	var is_ai_controlled: bool = true
	var is_player: bool = false
	var homebase_id: int = 0

	var ammo: int = 100
	var bombs: int = 5
	var fuel: float = 100.0
	var damage_percent: float = 0.0
	var reliability: float = 1.0
	var refuel_timer: float = 0.0

	var throttle: float = 0.0
	var throttle_target: float = 0.0
	var throttle_repeat_timer: float = 0.0
	var angular_velocity: float = 0.0
	var is_stalled: bool = false

	var gun_timer: float = 0.0
	var bomb_timer: float = 0.0

	var is_flipping: bool = false
	var flip_progress: float = 0.0
	var flip_direction: int = 0 # 0=none, 1=forward (upright→inverted), -1=reverse (inverted→upright)
	var is_inverted: bool = false

	var pitch_angle: float = 0.0
	var visual_roll: float = 0.0
	var heading_angle: float = 0.0

	var max_bullet_range: float = 600.0
	var last_shot_range: float = 0.0

	var smoke_particles: GPUParticles2D = null
	var fire_particles: GPUParticles2D = null
	var current_smoke_type: int = 0 # 0=none, 1=white, 2=black
	var is_losing_control: bool = false

	var engine_cutoff: bool = false
	var engine_restart_hold_time: float = 0.0
	var engine_restart_required_time: float = 0.0
	var flight_state: FlightState = FlightState.FLYING

	func reset() -> void:
		flight_state = FlightState.FLYING
		ammo = 100
		bombs = 5
		fuel = 100.0
		damage_percent = 0.0
		reliability = 1.0
		refuel_timer = 0.0
		is_losing_control = false

		throttle = 0.0
		throttle_target = 0.0
		throttle_repeat_timer = 0.0
		angular_velocity = 0.0
		is_stalled = false

		gun_timer = 0.0
		bomb_timer = 0.0

		is_flipping = false
		flip_progress = 0.0
		flip_direction = 0
		is_inverted = false

		pitch_angle = 0.0
		visual_roll = 0.0
		heading_angle = 0.0

		max_bullet_range = 600.0
		last_shot_range = 0.0

		is_losing_control = false

		engine_cutoff = false
		engine_restart_hold_time = 0.0
		engine_restart_required_time = 0.0
		flight_state = FlightState.FLYING

		if smoke_particles:
			smoke_particles.emitting = false
			smoke_particles.queue_free()
			smoke_particles = null
		if fire_particles:
			fire_particles.emitting = false
			fire_particles.queue_free()
			fire_particles = null
		current_smoke_type = 0

var _avatars: Dictionary[int, AvatarData] = {}

static func get_avatar(player_id: int) -> AvatarData:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	var root := tree.root
	var biplane := root.get_node_or_null("Main/Biplane")
	if not biplane:
		biplane = root.get_node_or_null("Biplane")
	if biplane and biplane.has_method("get_avatar_data"):
		return biplane.get_avatar_data(player_id)
	return null

func get_avatar_data(player_id: int) -> AvatarData:
	if not _avatars.has(player_id):
		var avatar := AvatarData.new()
		avatar.id = player_id
		_avatars[player_id] = avatar
	return _avatars.get(player_id)

func setup_homebase(id: int, x: float, width: float, spawn_pos: Vector2, spawn_rot: float) -> void:
	var homebase := HomebaseData.new()
	homebase.id = id
	homebase.home_base_x = x
	homebase.home_base_width = width
	homebase.spawn_position = spawn_pos
	homebase.spawn_rotation = spawn_rot
	_homebases[id] = homebase

func get_homebase_x(avatar: AvatarData) -> float:
	var homebase: HomebaseData = _homebases.get(avatar.homebase_id)
	if homebase:
		return homebase.home_base_x
	return 6554.0

func get_homebase_width(avatar: AvatarData) -> float:
	var homebase: HomebaseData = _homebases.get(avatar.homebase_id)
	if homebase:
		return homebase.home_base_width
	return 200.0

func _ready() -> void:
	motion_mode = MotionMode.MOTION_MODE_FLOATING
	PhysicsServer2D.body_set_param(get_rid(), PhysicsServer2D.BODY_PARAM_MASS, camel_mass_kg)
	_init_particle_materials()
	reset_visual_transform()

func _physics_process(delta: float) -> void:
	if not game_active:
		return

	var avatar: AvatarData = null

	for avatar_id in _avatars:
		avatar = _avatars[avatar_id]
		if avatar.flight_state == FlightState.CRASHED:
			_apply_crash_physics(avatar, delta)
			_check_obstacle_collision(avatar)
			continue

		if avatar.is_losing_control:
			rotation += delta * 4.0
			_check_crash_on_spin(avatar)

		_handle_input(avatar, delta)
		_handle_weapons(avatar, delta)
		_check_altitude_engine_cutoff(avatar, delta)
		_apply_aerodynamics(avatar, delta)
		_check_ground_collision(avatar)
		_apply_ground_forces(avatar, delta)

		global_position += velocity * delta
		_check_obstacle_collision(avatar)
		_check_fuel_consumption(avatar, delta)
		_check_home_refuel(avatar.id, delta)

func _check_crash_on_spin(avatar: AvatarData) -> void:
	var ground_y: float = 650.0
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(global_position.x)

	if global_position.y >= ground_y - 5:
		avatar.flight_state = FlightState.CRASHED
		_on_avatar_crashed(avatar)

func _check_altitude_engine_cutoff(avatar: AvatarData, delta: float) -> void:
	if avatar.unlimited_fuel_ammo:
		return

	var ground_y: float = 650.0
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(global_position.x)

	var altitude: float = ground_y - global_position.y

	if not avatar.engine_cutoff:
		if altitude >= ENGINE_CUTOFF_ALTITUDE:
			avatar.engine_cutoff = true
			avatar.throttle = 0.0
			avatar.throttle_target = 0.0
			avatar.engine_restart_hold_time = 0.0
			avatar.engine_restart_required_time = 4.0 + randf() * 4.0
	else:
		if avatar.is_player and Input.is_action_pressed("throttle_up"):
			avatar.engine_restart_hold_time += delta
			if avatar.engine_restart_hold_time >= avatar.engine_restart_required_time:
				avatar.engine_cutoff = false
				avatar.engine_restart_hold_time = 0.0

func _handle_input(avatar: AvatarData, delta: float) -> void:
	if not avatar.is_player:
		return

	var pitch_authority: float = 1.0
	if avatar.flight_state == FlightState.STALLED:
		pitch_authority = 0.4

	var pitch_input := 0.0
	if Input.is_action_pressed("pull_up"):
		pitch_input = -1.0
	elif Input.is_action_pressed("pull_down"):
		pitch_input = 1.0
	pitch_input *= pitch_authority

	var new_throttle: float

	var throttle_changed := false
	if avatar.engine_cutoff:
		pass
	elif Input.is_action_pressed("throttle_up"):
		avatar.throttle_repeat_timer -= delta
		if avatar.throttle_repeat_timer <= 0:
			avatar.throttle_target = min(max_throttle, avatar.throttle_target + THROTTLE_STEP)
			avatar.throttle_repeat_timer = THROTTLE_REPEAT_DELAY
			throttle_changed = true
	elif Input.is_action_pressed("throttle_down"):
		avatar.throttle_repeat_timer -= delta
		if avatar.throttle_repeat_timer <= 0:
			avatar.throttle_target = max(min_throttle, avatar.throttle_target - THROTTLE_STEP)
			avatar.throttle_repeat_timer = THROTTLE_REPEAT_DELAY
			throttle_changed = true
	else:
		avatar.throttle_repeat_timer = 0.0
	if not throttle_changed and avatar.throttle_target < min_throttle and not avatar.engine_cutoff:
		avatar.throttle_target = min_throttle

	if Input.is_action_just_pressed("roll") and not avatar.is_flipping:
		_start_flip(avatar)
	elif Input.is_action_just_released("roll") and avatar.is_flipping:
		_release_flip(avatar)

	avatar.throttle = move_toward(avatar.throttle, avatar.throttle_target, THROTTLE_RAMP_SPEED * delta)

	if not avatar.is_flipping:
		var effective_rotation_speed: float = rotation_speed * (1.0 - avatar.damage_percent * 0.4)
		var target_angular_velocity := pitch_input * effective_rotation_speed
		avatar.angular_velocity = move_toward(avatar.angular_velocity, target_angular_velocity, rotation_inertia * delta)
		avatar.pitch_angle += avatar.angular_velocity * delta
	rotation = avatar.pitch_angle

func set_ai_input(pitch: float, throttle_amount: float) -> void:
	for avatar_id in _avatars:
		var avatar = _avatars[avatar_id]
		if avatar.flight_state == FlightState.CRASHED:
			continue
		avatar.throttle_target = clampf(throttle_amount, min_throttle, max_throttle)
		avatar.throttle = move_toward(avatar.throttle, avatar.throttle_target, THROTTLE_RAMP_SPEED * 0.016)

		var pitch_authority: float = 1.0
		if avatar.flight_state == FlightState.STALLED:
			pitch_authority = 0.4

		var effective_rotation_speed: float = rotation_speed * (1.0 - avatar.damage_percent * 0.4)
		var target_angular_velocity := pitch * pitch_authority * effective_rotation_speed
		avatar.angular_velocity = move_toward(avatar.angular_velocity, target_angular_velocity, rotation_inertia * 0.016)
		avatar.pitch_angle += avatar.angular_velocity * 0.016
		rotation = avatar.pitch_angle

var _flip_tween: Tween = null

func _start_flip(avatar: AvatarData) -> void:
	if _flip_tween and _flip_tween.is_valid():
		_flip_tween.kill()

	avatar.is_flipping = true
	avatar.flip_progress = 0.0
	avatar.flip_direction = 1 if not avatar.is_inverted else -1

	_flip_tween = create_tween()
	_flip_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_flip_tween.tween_method(_update_flip.bind(avatar), 0.0, 1.0, FLIP_DURATION)
	_flip_tween.finished.connect(_on_flip_completed.bind(avatar))

func _release_flip(avatar: AvatarData) -> void:
	if avatar.flip_progress < 0.5:
		if _flip_tween and _flip_tween.is_valid():
			var current_progress = avatar.flip_progress
			_flip_tween.kill()
			_flip_tween = create_tween()
			_flip_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			_flip_tween.tween_method(_update_flip.bind(avatar), current_progress, 0.0, FLIP_DURATION * current_progress)
			_flip_tween.finished.connect(_on_flip_completed.bind(avatar))
		avatar.flip_direction = -avatar.flip_direction
	else:
		_flip_tween.kill()
		avatar.flip_progress = 1.0
		_apply_flip_transform(avatar, 1.0)
		_on_flip_completed(avatar)

func _update_flip(progress: float, avatar: AvatarData) -> void:
	avatar.flip_progress = progress
	_apply_flip_transform(avatar, progress)

func _apply_flip_transform(avatar: AvatarData, t: float) -> void:
	var visual = $Visual
	var start_scale := 1.0 if avatar.flip_direction == 1 else -1.0
	var end_scale := -1.0 if avatar.flip_direction == 1 else 1.0
	visual.scale.y = lerp(start_scale, end_scale, t)
	visual.position.y = -sin(t * PI) * FLIP_ARC_HEIGHT

func _on_flip_completed(avatar: AvatarData) -> void:
	avatar.is_flipping = false
	avatar.flip_progress = 0.0
	avatar.is_inverted = (avatar.flip_direction == 1)
	avatar.visual_roll = PI if avatar.is_inverted else 0.0
	_flip_tween = null

func reset_visual_transform() -> void:
	var visual = $Visual
	visual.scale = Vector2.ONE
	visual.rotation = 0.0
	visual.position = Vector2.ZERO

func do_flip(avatar: AvatarData) -> void:
	if avatar and not avatar.is_flipping:
		_start_flip(avatar)

func is_inverted(avatar: AvatarData) -> bool:
	return avatar.is_inverted if avatar else false

func _is_on_ground(avatar: AvatarData) -> bool:
	var ground_y: float = 650.0
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(global_position.x)
	var speed = get_avatar_speed(avatar)
	return global_position.y >= ground_y - 15 and speed < stall_speed_ms

func _apply_aerodynamics(avatar: AvatarData, delta: float) -> void:
	avatar.heading_angle = avatar.pitch_angle
	var forward := Vector2(cos(avatar.heading_angle), sin(avatar.heading_angle))

	var vel_si := velocity / pixels_per_meter
	var speed_si := vel_si.length()

	var on_ground := _is_on_ground(avatar)

	if on_ground and speed_si < 0.5:
		var thrust_si := _calc_thrust(avatar, 0.0, avatar.throttle)
		velocity.x += thrust_si * avatar.throttle * 0.85 * delta * pixels_per_meter / camel_mass_kg
		var drag_si: float = speed_si * 0.5 * 0.05

		var tilt_angle: float = 0.0
		var terrain = get_parent().get_node_or_null("Terrain")
		if terrain and terrain.has_method("get_ground_height_at"):
			var ground_ahead: float = terrain.get_ground_height_at(global_position.x + 10)
			var ground_behind: float = terrain.get_ground_height_at(global_position.x - 10)
			var slope_angle: float = atan2(ground_ahead - ground_behind, 30.0)
			var relative_angle: float = avatar.pitch_angle - slope_angle
			while relative_angle > PI:
				relative_angle -= TAU
			while relative_angle < -PI:
				relative_angle += TAU
			tilt_angle = abs(relative_angle)

		if tilt_angle >= deg_to_rad(max_landing_tilt_deg):
			avatar.flight_state = FlightState.CRASHED
			_on_avatar_crashed(avatar)
			return

		var can_lift_off: bool = tilt_angle < deg_to_rad(max_landing_tilt_deg) and avatar.throttle >= THROTTLE_STEP and speed_si >= stall_speed_ms

		var effective_ground_drag: float = ground_drag_coeff
		var terrain_node = get_parent()
		if terrain_node:
			terrain_node = terrain_node.get_node_or_null("Terrain")
		else:
			terrain_node = null
		if terrain_node and terrain_node.has_method("is_on_runway") and terrain_node.is_on_runway(global_position.x):
			effective_ground_drag *= 40.0
		if tilt_angle >= deg_to_rad(max_landing_tilt_deg) or avatar.throttle < THROTTLE_STEP:
			drag_si += effective_ground_drag

		if speed_si > 0.01:
			velocity += (-vel_si.normalized()) * drag_si * delta * pixels_per_meter / camel_mass_kg

		if not can_lift_off:
			return

	var thrust_si := _calc_thrust(avatar, speed_si, avatar.throttle)
	var thrust_vec := forward * thrust_si

	var angle_of_attack: float = 0.0
	if speed_si > 0.5:
		var vel_dir := vel_si.normalized()
		angle_of_attack = forward.angle_to(vel_dir)
	else:
		angle_of_attack = 0.0

	if on_ground:
		avatar.is_stalled = false
		if avatar.flight_state == FlightState.DAMAGED:
			pass
		else:
			avatar.flight_state = FlightState.FLYING
	elif abs(angle_of_attack) > stall_aoa or speed_si < stall_speed_ms:
		avatar.is_stalled = true
		if avatar.flight_state == FlightState.FLYING:
			avatar.flight_state = FlightState.STALLED
	else:
		avatar.is_stalled = false
		if avatar.flight_state == FlightState.STALLED:
			avatar.flight_state = FlightState.FLYING

	var cl: float = angle_of_attack * 2.0 * PI
	cl = clampf(cl, -max_lift_coeff, max_lift_coeff)
	if avatar.is_stalled:
		cl *= 0.3

	var lift_si: float = 0.5 * air_density * speed_si * speed_si * wing_area * cl
	var lift_vec: Vector2 = Vector2.ZERO
	if speed_si > 0.5:
		var lift_dir: Vector2 = Vector2(forward.y, -forward.x)
		var is_inverted: bool = abs(avatar.visual_roll) > PI * 0.5
		if is_inverted:
			lift_dir = -lift_dir
		lift_vec = lift_dir * lift_si

	var parasitic_drag_si := 0.5 * air_density * speed_si * speed_si * zero_lift_drag_area
	var induced_drag_si := 0.5 * air_density * speed_si * speed_si * wing_area * (cl * cl) / ar_efficiency

	var effective_max_speed: float = max_speed
	if avatar.damage_percent > 0:
		effective_max_speed *= (1.0 - avatar.damage_percent * 0.5)

	var speed_px := velocity.length()
	var speed_limit_drag: float = 0.0
	if speed_px > effective_max_speed:
		var overspeed := speed_px - effective_max_speed
		speed_limit_drag = overspeed * overspeed * 0.5

	var total_drag_si := parasitic_drag_si + induced_drag_si + speed_limit_drag / pixels_per_meter

	if avatar.damage_percent > 0:
		total_drag_si *= (1.0 + avatar.damage_percent * 0.4)

	var drag_vec := Vector2.ZERO
	if speed_si > 0.01:
		drag_vec = -vel_si.normalized() * total_drag_si

	var weight_vec := Vector2(0, camel_mass_kg * gravity)

	var net_force_si := thrust_vec + lift_vec + drag_vec + weight_vec

	var accel_si := net_force_si / camel_mass_kg
	var accel_px := accel_si * pixels_per_meter

	velocity += accel_px * delta

func _apply_ground_forces(avatar: AvatarData, delta: float) -> void:
	var ground_y: float = 650.0
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(global_position.x)

	var speed_si: float = velocity.length() / pixels_per_meter
	var tilt_angle: float = 0.0
	if terrain and terrain.has_method("get_ground_height_at"):
		var ground_ahead: float = terrain.get_ground_height_at(global_position.x + 10)
		var ground_behind: float = terrain.get_ground_height_at(global_position.x - 10)
		var slope_angle: float = atan2(ground_ahead - ground_behind, 30.0)
		var relative_angle: float = avatar.pitch_angle - slope_angle
		while relative_angle > PI:
			relative_angle -= TAU
		while relative_angle < -PI:
			relative_angle += TAU
		tilt_angle = abs(relative_angle)

	var can_lift_off: bool = tilt_angle < deg_to_rad(max_landing_tilt_deg) and avatar.throttle >= THROTTLE_STEP and speed_si >= stall_speed_ms

	if global_position.y >= ground_y - 12:
		if tilt_angle >= deg_to_rad(max_landing_tilt_deg):
			avatar.flight_state = FlightState.CRASHED
			_on_avatar_crashed(avatar)
			return
		if can_lift_off:
			global_position.y -= 1
		else:
			global_position.y = ground_y - 12
			velocity.y = 0
	elif global_position.y > ground_y - 12:
		if tilt_angle >= deg_to_rad(max_landing_tilt_deg):
			avatar.flight_state = FlightState.CRASHED
			_on_avatar_crashed(avatar)
			return
		if not can_lift_off:
			global_position.y = ground_y - 12

func _calc_thrust(avatar: AvatarData, speed_si: float, thr: float) -> float:
	var ground_y: float = 650.0
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(global_position.x)

	var altitude: float = ground_y - global_position.y
	var altitude_efficiency: float = 1.0
	if altitude > ENGINE_EFFICIENCY_START_ALTITUDE:
		altitude_efficiency = 1.0 - clampf((altitude - ENGINE_EFFICIENCY_START_ALTITUDE) / (ENGINE_CUTOFF_ALTITUDE - ENGINE_EFFICIENCY_START_ALTITUDE), 0.0, 1.0)

	if avatar.engine_cutoff:
		return 0.0

	if speed_si < 0.5:
		var base_thrust := 2000.0 * thr
		var damage_reduction := 1.0 - (avatar.damage_percent * 0.5)
		return base_thrust * damage_reduction * altitude_efficiency

	var eta := 0.8 * (1.0 - pow((speed_si - 40.0) / 40.0, 2))
	eta = maxf(eta, 0.0)

	var thrust_from_power := engine_power_watts * eta / speed_si

	var damage_reduction := 1.0 - (avatar.damage_percent * 0.5)
	return thrust_from_power * thr * damage_reduction * altitude_efficiency

func _check_ground_collision(avatar: AvatarData) -> void:
	var ground_y: float = 650.0
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(global_position.x)

	if global_position.y >= ground_y - 14 and velocity.y > 20:
		# print_rich("[color=yellow]  _check_gc: CALLED pos_y=", global_position.y, "[/color]")
		var speed = get_avatar_speed(avatar)
		var v_perp: float = abs(velocity.y)
		# print_rich("[color=magenta]  _check_gc: IN RANGE pos_y=", global_position.y, " gy=", ground_y, " speed=", speed, " v_perp=", v_perp, "[/color]")
		var normalized_rot: float = fmod(avatar.pitch_angle, TAU)
		if normalized_rot < 0:
			normalized_rot += TAU

		var slope_angle: float = 0.0
		if terrain and terrain.has_method("get_ground_height_at"):
			var ground_ahead: float = terrain.get_ground_height_at(global_position.x + 10)
			var ground_behind: float = terrain.get_ground_height_at(global_position.x - 10)
			slope_angle = atan2(ground_ahead - ground_behind, 30.0)

		var relative_angle: float = normalized_rot - slope_angle
		while relative_angle > PI:
			relative_angle -= TAU
		while relative_angle < -PI:
			relative_angle += TAU

		var tilt_angle: float = abs(relative_angle)
		# print_rich("[color=cyan]  _check_gc: tilt_angle=", rad_to_deg(tilt_angle), " deg, speed=", speed, "[/color]")

		if tilt_angle >= deg_to_rad(max_landing_tilt_deg) and velocity.y > 40.0:
			# print_rich("[color=red]  _check_gc: CRASH condition met![/color]")
			avatar.flight_state = FlightState.CRASHED
			_on_avatar_crashed(avatar)
			return

		var impact_force: float = (camel_mass_kg * v_perp) / bungee_compression_time
		# print_rich("[color=green]  _check_gc: impact_force=", impact_force, " N, v_perp=", v_perp, "[/color]")

		if v_perp <= soft_landing_vperp:
			# print_rich("[color=green]  _check_gc: SOFT LANDING[/color]")
			global_position.y = ground_y - 10
			velocity.y = 0
			avatar.flight_state = FlightState.FLYING
		elif v_perp <= hard_landing_vperp:
			# print_rich("[color=orange]  _check_gc: HARD LANDING (damaged)[/color]")
			global_position.y = ground_y - 10
			velocity.y = 0
			velocity.x *= 0.5
			avatar.flight_state = FlightState.DAMAGED
			avatar.damage_percent += 0.2 # * impact_force / hard_landing_vperp
			# print_rich("[color=orange]  _check_gc: HARD LANDING damage: avatar.damage_percent=", avatar.damage_percent, " avatar.damage_percent=", avatar.damage_percent, "[/color]")
			avatar.reliability = 0.75
			_ensure_smoke(avatar, 2, 15)
			if avatar.damage_percent > 0.5:
				_ensure_smoke(avatar, 2, 30)
			damaged.emit(impact_force, v_perp)
		else:
			# print_rich("[color=red]  _check_gc: DESTROYED (v_perp too high)[/color]")
			avatar.flight_state = FlightState.CRASHED
			_on_avatar_crashed(avatar)

func _check_obstacle_collision(avatar: AvatarData) -> void:
	if avatar.flight_state == FlightState.DAMAGED:
		return

	var speed := get_avatar_speed(avatar)
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
				if child.is_in_group("ground_target") and child.has_method("take_damage") and not child.is_destroyed:
					child.take_damage(100.0, self)
				elif child.has_method("take_damage"):
					child.take_damage(100.0, self)
				if avatar.flight_state != FlightState.CRASHED:
					avatar.flight_state = FlightState.CRASHED
					_on_avatar_crashed(avatar)
				return
		elif child is CharacterBody2D and child.has_method("is_enemy") and speed > 30:
			var hit_radius: float = 20.0
			var dist := global_position.distance_to(child.global_position)
			if dist < hit_radius:
				if avatar.flight_state != FlightState.CRASHED:
					avatar.flight_state = FlightState.CRASHED
					_on_avatar_crashed(avatar)
				if child.has_method("get_avatar_data") and child.has_method("force_crash"):
					child.force_crash()
				elif child.has_method("take_damage"):
					child.take_damage(100.0, self)
				return

func _apply_crash_physics(avatar: AvatarData, delta: float) -> void:
	if avatar.flight_state != FlightState.CRASHED:
		return

	if velocity == Vector2.ZERO:
		return

	velocity.y += gravity * pixels_per_meter * delta
	rotation += velocity.x * 0.01 * delta
	move_and_slide()
	var ground_ray: RayCast2D = $GroundRay if has_node("GroundRay") else null
	if ground_ray and ground_ray.is_colliding():
		velocity = Vector2.ZERO
		damaged.emit(1.0, 0.0)
		_on_avatar_crashed(avatar)

func get_avatar_speed(avatar: AvatarData) -> float:
	return velocity.length()

func get_vertical_speed(avatar: AvatarData) -> float:
	return velocity.y

func is_stalling(avatar: AvatarData) -> bool:
	return avatar.is_stalled

func _handle_weapons(avatar: AvatarData, delta: float) -> void:
	avatar.gun_timer = max(0, avatar.gun_timer - delta)
	avatar.bomb_timer = max(0, avatar.bomb_timer - delta)

	if avatar.is_player and GameManager:
		avatar.ammo = avatar.ammo
		avatar.bombs = avatar.bombs

	if avatar.is_player and Input.is_action_pressed("fire") and avatar.gun_timer <= 0:
		_fire_gun(avatar)

	if avatar.is_player and Input.is_action_just_pressed("bomb") and avatar.bomb_timer <= 0:
		_drop_bomb(avatar)

func _fire_gun(avatar: AvatarData) -> void:
	if avatar.ammo <= 0:
		return

	avatar.gun_timer = gun_cooldown

	if avatar.is_player:
		if avatar.ammo <= 0:
			return
		avatar.ammo -= 1
		if GameManager:
			GameManager.ammo_changed.emit(avatar.id, avatar.ammo)

	var heading_dir := Vector2(cos(avatar.pitch_angle), sin(avatar.pitch_angle))
	var spawn_offset := Vector2(34, -15).rotated(avatar.pitch_angle)
	if avatar.is_inverted:
		spawn_offset = Vector2(34, 15).rotated(avatar.pitch_angle)
	var spawn_pos := global_position + spawn_offset
	var direction := heading_dir

	var target_enemy: Node = _find_nearest_enemy(avatar)
	var range_percent: float = 0.0
	if target_enemy:
		var dist := spawn_pos.distance_to(target_enemy.global_position)
		avatar.last_shot_range = min(dist, avatar.max_bullet_range)
		range_percent = avatar.last_shot_range / avatar.max_bullet_range
	else:
		avatar.last_shot_range = avatar.max_bullet_range * 0.5
		range_percent = 0.5

	var bullet := BULLET_SCENE.instantiate()
	bullet.speed = bullet_speed

	bullet.global_position = spawn_pos
	bullet.rotation = avatar.pitch_angle
	bullet.assign_owner(self, range_percent)

	get_parent().add_child(bullet)
	fired_bullet.emit(spawn_pos, direction, bullet_speed, self, range_percent)

	if SoundManager:
		SoundManager.play_machine_gun()

func _find_nearest_enemy(avatar: AvatarData) -> Node:
	var nearest: Node = null
	var min_dist := INF

	var parent := get_parent()
	for child in parent.get_children():
		if child == self:
			continue
		if avatar.is_player and child.has_method("is_enemy") and child.is_enemy():
			var dist := global_position.distance_to(child.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = child
		elif not avatar.is_player and child.is_in_group("player"):
			var dist := global_position.distance_to(child.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = child

	return nearest

func _drop_bomb(avatar: AvatarData) -> void:
	if avatar.bombs_disabled:
		return

	if avatar.bombs <= 0:
		return

	avatar.bomb_timer = bomb_cooldown

	if avatar.is_player:
		avatar.bombs -= 1
		if GameManager:
			GameManager.bombs_changed.emit(avatar.id, avatar.bombs)

	var bomb := BOMB_SCENE.instantiate()

	var spawn_offset := Vector2(0, 26).rotated(avatar.pitch_angle)
	if avatar.is_inverted:
		spawn_offset = Vector2(0, -26).rotated(avatar.pitch_angle)

	var spawn_pos := global_position + spawn_offset
	bomb.global_position = spawn_pos
	bomb.rotation = avatar.pitch_angle
	bomb.initialize(self, velocity)

	get_parent().add_child(bomb)
	dropped_bomb.emit(spawn_pos, velocity, self)

func get_reliability(avatar: AvatarData) -> float:
	return avatar.reliability

func set_unlimited_fuel_ammo(avatar: AvatarData, val: bool) -> void:
	avatar.unlimited_fuel_ammo = val

func disable_bombs(avatar: AvatarData) -> void:
	avatar.bombs_disabled = true

func drop_bomb(avatar: AvatarData) -> void:
	_drop_bomb(avatar)

func _check_fuel_consumption(avatar: AvatarData, delta: float) -> void:
	if avatar.unlimited_fuel_ammo:
		return

	if avatar.is_player:
		if avatar.fuel <= 0:
			avatar.throttle = 0
			avatar.throttle_target = 0
			_ensure_smoke(avatar, 1, 10) # white smoke

		elif avatar.throttle > 0 or avatar.damage_percent >= 0.8:
			var fuel_loss = avatar.throttle * delta * 0.7
			if avatar.damage_percent >= 0.8:
				fuel_loss *= 8.0
			elif avatar.damage_percent >= 0.5:
				fuel_loss *= 2.0
			avatar.fuel = maxf(0.0, avatar.fuel - fuel_loss)
			if GameManager:
				GameManager.fuel_changed.emit(avatar.id, avatar.fuel)
	else:
		if avatar.fuel <= 0 and is_grounded(avatar):
			var home_x := get_homebase_x(avatar)
			var home_width := get_homebase_width(avatar)
			var dist_to_home: float = abs(global_position.x - home_x)
			if dist_to_home > home_width:
				avatar.flight_state = FlightState.CRASHED
				_on_avatar_crashed(avatar)

	if avatar.is_player and SoundManager:
		SoundManager.play_engine(avatar.throttle)

func _check_home_refuel(player_id: int, delta: float) -> void:
	var avatar: AvatarData = _avatars.get(player_id)
	if not avatar:
		return
	if not is_grounded(avatar):
		return

	var home_x := get_homebase_x(avatar)
	var home_width := get_homebase_width(avatar)

	var dist_to_home: float = abs(global_position.x - home_x)
	if dist_to_home > home_width:
		return

	if avatar.damage_percent > 0:
		avatar.damage_percent = 0.0
		avatar.reliability = 1.0
		avatar.flight_state = FlightState.FLYING
		if avatar.smoke_particles:
			avatar.smoke_particles.emitting = false
			avatar.smoke_particles.queue_free()
			avatar.smoke_particles = null
		if avatar.fire_particles:
			avatar.fire_particles.emitting = false
			avatar.fire_particles.queue_free()
			avatar.fire_particles = null

	var old_ammo: int = avatar.ammo
	var old_bombs: int = avatar.bombs
	var old_fuel: float = avatar.fuel

	avatar.ammo = min(MAX_AMMO, avatar.ammo + int(5.0 * delta))
	avatar.fuel = minf(100.0, avatar.fuel + delta * 10.0)

	avatar.refuel_timer += delta
	if avatar.refuel_timer >= 1.5:
		avatar.refuel_timer = 0.0
		avatar.bombs = min(MAX_BOMBS, avatar.bombs + 1)

	if avatar.ammo != old_ammo:
		GameManager.ammo_changed.emit(avatar.id, avatar.ammo)
	if avatar.bombs != old_bombs:
		GameManager.bombs_changed.emit(avatar.id, avatar.bombs)
	if avatar.fuel != old_fuel:
		GameManager.fuel_changed.emit(avatar.id, avatar.fuel)

func set_player(avatar: AvatarData, p: bool) -> void:
	avatar.is_player = p

func set_game_active(active: bool) -> void:
	game_active = active

func get_ammo(avatar: AvatarData) -> int:
	return avatar.ammo

func get_bombs(avatar: AvatarData) -> int:
	return avatar.bombs

func fire_gun(avatar: AvatarData) -> void:
	if avatar.ammo <= 0:
		return
	if avatar.gun_timer > 0:
		return

	avatar.gun_timer = gun_cooldown

	var heading_dir := Vector2(cos(avatar.pitch_angle), sin(avatar.pitch_angle))
	var spawn_offset := Vector2(34, -15).rotated(avatar.pitch_angle)
	if avatar.is_inverted:
		spawn_offset = Vector2(34, 15).rotated(avatar.pitch_angle)
	var spawn_pos := global_position + spawn_offset
	var target_enemy: Node = _find_nearest_enemy(avatar)
	var range_percent: float = 0.5
	if target_enemy:
		var dist := spawn_pos.distance_to(target_enemy.global_position)
		avatar.last_shot_range = min(dist, avatar.max_bullet_range)
		range_percent = avatar.last_shot_range / avatar.max_bullet_range
	else:
		avatar.last_shot_range = avatar.max_bullet_range * 0.5

	var bullet := BULLET_SCENE.instantiate()
	bullet.speed = bullet_speed

	bullet.global_position = spawn_pos
	bullet.rotation = avatar.pitch_angle
	bullet.assign_owner(self, range_percent)

	get_parent().add_child(bullet)
	fired_bullet.emit(spawn_pos, heading_dir, bullet_speed, self, range_percent)

func set_home_base(avatar: AvatarData, id: int) -> void:
	avatar.homebase_id = id

func get_homebase_spawn_position(avatar: AvatarData) -> Vector2:
	var homebase: HomebaseData = _homebases.get(avatar.homebase_id)
	if homebase:
		return homebase.spawn_position
	return Vector2(7000.0, 500.0)

func get_homebase_spawn_rotation(avatar: AvatarData) -> float:
	var homebase: HomebaseData = _homebases.get(avatar.homebase_id)
	if homebase:
		return homebase.spawn_rotation
	return 0.0

func _perform_teleport_landing(avatar: AvatarData) -> void:
	var spawn_pos := get_homebase_spawn_position(avatar)
	var spawn_rot := get_homebase_spawn_rotation(avatar)

	var terrain = get_parent().get_node_or_null("Terrain")
	var ground_y: float = 650.0
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(spawn_pos.x)

	avatar.reset()
	global_position = Vector2(spawn_pos.x, ground_y - 12)
	rotation = spawn_rot
	avatar.pitch_angle = spawn_rot

	if avatar.is_player and GameManager:
		GameManager.fuel_changed.emit(avatar.id, avatar.fuel)
		GameManager.ammo_changed.emit(avatar.id, avatar.ammo)
		GameManager.bombs_changed.emit(avatar.id, avatar.bombs)

	avatar.reliability = 1.0
	if has_node("SmokeParticles"):
		var sp: GPUParticles2D = get_node("SmokeParticles")
		sp.emitting = false
		sp.queue_free()
		avatar.smoke_particles = null

func is_player_plane(avatar: AvatarData) -> bool:
	return avatar.is_player

func is_enemy_plane(avatar: AvatarData) -> bool:
	return not avatar.is_player

func is_grounded(avatar: AvatarData) -> bool:
	var ground_ray: RayCast2D = $GroundRay if has_node("GroundRay") else null
	if ground_ray:
		return ground_ray.is_colliding()
	return false

func get_visual_roll(avatar: AvatarData) -> float:
	return avatar.visual_roll

func _start_spinning_out(avatar: AvatarData) -> void:
	avatar.is_losing_control = true
	avatar.throttle = 0.0

func take_damage(avatar: AvatarData, amount: float, attacker: Node) -> void:
	if avatar.flight_state == FlightState.CRASHED:
		return

	_init_particle_materials()
	avatar.damage_percent = min(1.0, avatar.damage_percent + amount / 100.0)

	if avatar.damage_percent >= 0.8:
		avatar.reliability = 0.0
		_ensure_fire(avatar, int(30.0 * avatar.damage_percent))
		_ensure_smoke(avatar, 2, int(30.0 * avatar.damage_percent)) # black smoke
	elif avatar.damage_percent >= 0.5:
		avatar.reliability = 0.5
		_disable_fire(avatar)
		_ensure_smoke(avatar, 2, int(60.0 * avatar.damage_percent)) # black smoke
	elif avatar.damage_percent >= 0.25:
		avatar.reliability = 0.75
		_disable_fire(avatar)
		_disable_smoke(avatar)
		_ensure_smoke(avatar, 1, int(20.0 * avatar.damage_percent)) # white smoke

	if avatar.damage_percent >= 1.0:
		avatar.flight_state = FlightState.CRASHED
		# Don't emit crashed yet - wait until hitting ground

func _ensure_smoke(avatar: AvatarData, smoke_type: int, amount: int) -> void:
	if not avatar.smoke_particles:
		avatar.smoke_particles = GPUParticles2D.new()
		avatar.smoke_particles.name = "SmokeParticles"
		avatar.smoke_particles.emitting = true
		avatar.smoke_particles.lifetime = 1.5
		avatar.smoke_particles.speed_scale = 1.0
		add_child(avatar.smoke_particles)

	if smoke_type == 1:
		avatar.smoke_particles.process_material = _white_smoke_material
	elif smoke_type == 2:
		avatar.smoke_particles.process_material = _black_smoke_material
	avatar.smoke_particles.amount = amount
	avatar.current_smoke_type = smoke_type

func create_explosion() -> void:
	var explosion_scene := load("res://scenes/explosion.tscn")
	if explosion_scene:
		var explosion: Node = explosion_scene.instantiate()
		explosion.global_position = global_position
		get_parent().add_child(explosion)

	var shatter_scene := load("res://scenes/shatter_effect.tscn")
	if shatter_scene and has_node("Visual"):
		var shatter: Node = shatter_scene.instantiate()
		shatter.setup(get_plane_polygon(), Color(0.5, 0.55, 0.5), global_position)
		get_parent().add_child(shatter)

func get_plane_polygon() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(20, 0),
		Vector2(10, -4),
		Vector2(-15, -4),
		Vector2(-20, 0),
		Vector2(-15, 4),
		Vector2(10, 4)
	])

func _disable_smoke(avatar: AvatarData) -> void:
	if avatar.smoke_particles:
		avatar.smoke_particles.emitting = false
		avatar.current_smoke_type = 0

func _ensure_fire(avatar: AvatarData, amount: int) -> void:
	if not avatar.fire_particles:
		avatar.fire_particles = GPUParticles2D.new()
		avatar.fire_particles.name = "FireParticles"
		avatar.fire_particles.emitting = true
		avatar.fire_particles.lifetime = 0.3
		avatar.fire_particles.speed_scale = 1.0
		avatar.fire_particles.process_material = _fire_material
		add_child(avatar.fire_particles)
	avatar.fire_particles.amount = amount
	avatar.fire_particles.emitting = true

func _disable_fire(avatar: AvatarData) -> void:
	if avatar.fire_particles:
		avatar.fire_particles.emitting = false

# Called once per crash transition (idempotent). Add any per-crash logic here.
func _on_avatar_crashed(avatar: AvatarData) -> void:
	if _crash_processed.has(avatar.id):
		return
	_crash_processed[avatar.id] = true
	crashed.emit()
	if avatar.is_player and GameManager:
		GameManager.destroy_player(avatar.id)

func reset_flight_state() -> void:
	var avatar = get_avatar_data(0)
	if avatar:
		avatar.reset()
		_crash_processed.erase(0)
	reset_visual_transform()

func force_crash() -> void:
	for avatar_id in _avatars:
		var avatar = _avatars[avatar_id]
		if avatar.flight_state != FlightState.CRASHED:
			avatar.flight_state = FlightState.CRASHED
			_on_avatar_crashed(avatar)
