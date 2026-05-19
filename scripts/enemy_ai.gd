extends Node

## Enemy AI for Sopwith biplanes
## Layered architecture: State Machine -> Pursuit Calculator -> Reflex Layer

enum AIState {
	GROUNDED,
	TAKING_OFF,
	PATROLLING,
	ENGAGING,
	EVADING,
	RETURNING
}

const TERRAIN_LENGTH := 16384.0

# Constants tuned for Godot scale
const PATROL_ALTITUDE := 250.0
const MIN_ALTITUDE_ABOVE_GROUND := 60.0
const DANGER_ALTITUDE_ABOVE_GROUND := 40.0
const CRITICAL_ALTITUDE_ABOVE_GROUND := 20.0
const PULL_UP_ALTITUDE := 200.0
const DETECTION_RANGE := 2000.0
const ENGAGEMENT_RANGE := 1500.0
const MAX_FIRE_RANGE := 400.0
const MIN_FIRE_RANGE := 30.0
const FIRE_CONE_ANGLE := 0.3
const STALKING_THRESHOLD := 400.0
const ADVANTAGE_THRESHOLD := 50.0
const ALTITUDE_OSCILLATION_SPEED := 1.5
const ALTITUDE_OSCILLATION_AMP := 30.0
const HOME_PROXIMITY := 100.0
const PITCH_SENSITIVITY := 1.2
const PITCH_DAMPING := 0.8
const MAX_STEERING_ANGLE := 0.15
const EVADE_DURATION_MIN := 0.5
const EVADE_DURATION_MAX := 2.0
const TERRAIN_LOOK_DISTANCES := [50.0, 100.0, 200.0]
const TERRAIN_RISE_THRESHOLD := 0.3
const TAKEOFF_ROTATE_SPEED := 120.0
const TAKEOFF_BUILD_SPEED := 90.0
const TAKEOFF_PITCH := -0.05
const TAKEOFF_CLIMB_PITCH := -0.08
const RETURN_REENGAGE_RANGE := 300.0
const MAX_ALTITUDE := 1000.0
const GROUND_ATTACK_ALTITUDE := 300.0
const BOMB_DROP_ADVANCE := 400.0
const BOMB_OVERHEAD_X_THRESHOLD := 200.0
const BOMB_OVERHEAD_Y_MAX := 100.0
const BOMB_ANGLE_TOLERANCE := 0.175

@export var target: Node2D
@export var biplane: CharacterBody2D

var decision_timer: float = 0.0
var decision_interval: float = 0.05

var incoming_bullet_timer: float = 0.0
var flip_cooldown: float = 0.0

var home_base_x: float = 1400.0
var patrol_range: float = 2000.0
var ai_state: AIState = AIState.GROUNDED
var previous_state: AIState = AIState.PATROLLING
var evade_timer: float = 0.0
var is_using_autopilot: bool = false
var unlimited_fuel_ammo: bool = false
var takeoff_delay: float = 0.0
var takeoff_timer: float = 0.0

var last_pitch_input: float = 0.0
var last_throttle: float = 0.0
var desired_heading: float = 0.0
var bomb_cooldown_timer: float = 0.0

var patrol_time: float = 0.0
var territory_left: float = 0.0
var territory_right: float = 16384.0

var crash_timer: float = 0.0
var crash_delay: float = 2.0
var respawn_timer: float = 0.0
var respawn_delay: float = 3.0
var is_waiting_for_crash_land: bool = false

var terrain_cache: Node2D = null

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("destructible")
	if biplane and biplane.has_signal("crashed"):
		biplane.crashed.connect(_on_enemy_crashed)
	_setup_territory()

func _setup_territory() -> void:
	var half_range = patrol_range * 0.5
	territory_left = home_base_x - half_range
	territory_right = home_base_x + half_range

func _get_terrain() -> Node2D:
	if terrain_cache == null:
		terrain_cache = get_parent().get_node_or_null("Terrain")
	return terrain_cache

func _get_ground_height(x: float) -> float:
	var terrain = _get_terrain()
	if terrain and terrain.has_method("get_ground_height_at"):
		return terrain.get_ground_height_at(x)
	return 650.0

func _get_altitude_above_ground() -> float:
	if not biplane:
		return 0.0
	var ground_y = _get_ground_height(biplane.global_position.x)
	return ground_y - biplane.global_position.y

func _get_wrapped_distance(x1: float, x2: float) -> float:
	var d: float = abs(x1 - x2)
	if d > TERRAIN_LENGTH * 0.5:
		d = TERRAIN_LENGTH - d
	return d

func _is_grounded() -> bool:
	if biplane and biplane.has_method("is_grounded") and biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			return biplane.is_grounded(avatar)
	return false

func _get_avatar():
	if biplane and biplane.has_method("get_avatar_data"):
		return biplane.get_avatar_data(0)
	return null

func _physics_process(delta: float) -> void:
	if not target or not biplane:
		return

	if takeoff_delay > 0:
		takeoff_timer += delta
		if takeoff_timer < takeoff_delay:
			return

	incoming_bullet_timer = max(0.0, incoming_bullet_timer - delta)
	bomb_cooldown_timer = max(0.0, bomb_cooldown_timer - delta)
	flip_cooldown = max(0.0, flip_cooldown - delta)

	if crash_timer > 0:
		crash_timer -= delta
		return

	if is_waiting_for_crash_land:
		if biplane and biplane.has_method("get_avatar_data"):
			var avatar = biplane.get_avatar_data(0)
			if avatar and avatar.has_hit_ground:
				is_waiting_for_crash_land = false
				respawn_timer = respawn_delay

	_apply_input(last_pitch_input, last_throttle)

	if respawn_timer > 0:
		respawn_timer -= delta
		if respawn_timer <= 0:
			_do_respawn()
			return

	decision_timer -= delta
	if decision_timer <= 0.0:
		decision_timer = decision_interval
		_make_decision()

func _make_decision() -> void:
	if not target or not biplane:
		return

	var avatar = _get_avatar()
	if not avatar:
		return

	_update_state_machine()

	var pitch: float = 0.0
	var throttle: float = 0.0

	match ai_state:
		AIState.GROUNDED:
			pitch = 0.0
			throttle = 0.0
		AIState.TAKING_OFF:
			_decision_takeoff()
			return
		AIState.PATROLLING:
			pitch = _compute_patrol_pitch()
			throttle = _compute_patrol_throttle(avatar)
		AIState.ENGAGING:
			if _should_bomb_instead_of_strafe():
				pitch = _compute_bomb_pitch()
				throttle = _compute_engage_throttle(avatar)
				_try_drop_bomb()
			elif _is_target_on_ground() and not _is_overhead_target():
				pitch = _compute_bomb_pitch()
				throttle = _compute_patrol_throttle(avatar)
			else:
				pitch = _compute_engage_pitch()
				throttle = _compute_engage_throttle(avatar)
				_try_fire_weapon()
		AIState.EVADING:
			pitch = _compute_evade_pitch()
			throttle = _compute_evade_throttle()
		AIState.RETURNING:
			pitch = _compute_return_pitch()
			throttle = _compute_return_throttle(avatar)

	var reflex_result = _apply_reflexes(pitch, throttle)
	pitch = reflex_result[0]
	throttle = reflex_result[1]

	last_pitch_input = pitch
	last_throttle = throttle

func _update_state_machine() -> void:
	if not biplane or not target:
		return

	var player_dist_to_home = _get_wrapped_distance(target.global_position.x, home_base_x)
	var my_dist_to_home = _get_wrapped_distance(biplane.global_position.x, home_base_x)
	var avatar = _get_avatar()
	var damage = avatar.damage_percent if avatar else 0.0

	match ai_state:
		AIState.GROUNDED:
			if player_dist_to_home < DETECTION_RANGE and _is_player_in_territory():
				ai_state = AIState.TAKING_OFF

		AIState.TAKING_OFF:
			var alt = _get_altitude_above_ground()
			if alt > PATROL_ALTITUDE:
				ai_state = AIState.PATROLLING
				patrol_time = 0.0
			elif player_dist_to_home < ENGAGEMENT_RANGE and alt > MIN_ALTITUDE_ABOVE_GROUND:
				ai_state = AIState.ENGAGING

		AIState.PATROLLING:
			var dist_to_player = biplane.global_position.distance_to(target.global_position)
			var wrapped_dist = _get_wrapped_distance(biplane.global_position.x, target.global_position.x)
			if wrapped_dist < ENGAGEMENT_RANGE and _is_player_in_territory():
				ai_state = AIState.ENGAGING

		AIState.ENGAGING:
			var wrapped_dist = _get_wrapped_distance(biplane.global_position.x, target.global_position.x)
			var alt = _get_altitude_above_ground()

			if alt < DANGER_ALTITUDE_ABOVE_GROUND or incoming_bullet_timer > 0.0:
				previous_state = ai_state
				ai_state = AIState.EVADING
				evade_timer = randf_range(EVADE_DURATION_MIN, EVADE_DURATION_MAX)
			elif damage >= 0.5:
				ai_state = AIState.RETURNING
			elif wrapped_dist > ENGAGEMENT_RANGE * 1.2:
				ai_state = AIState.PATROLLING
				patrol_time = 0.0
			elif _is_target_on_ground() and alt > MIN_ALTITUDE_ABOVE_GROUND:
				previous_state = ai_state
				ai_state = AIState.RETURNING
				patrol_time = 0.0

		AIState.EVADING:
			evade_timer -= decision_interval
			var alt = _get_altitude_above_ground()
			var avatar_data = _get_avatar()
			var is_stalled = avatar_data and avatar_data.flight_state == 2

			if is_stalled:
				pass
			elif evade_timer <= 0.0 and alt > MIN_ALTITUDE_ABOVE_GROUND and incoming_bullet_timer <= 0.0:
				ai_state = previous_state

		AIState.RETURNING:
			var wrapped_dist = _get_wrapped_distance(biplane.global_position.x, target.global_position.x)
			if wrapped_dist < RETURN_REENGAGE_RANGE and damage < 0.5:
				ai_state = AIState.ENGAGING
			elif my_dist_to_home < HOME_PROXIMITY and _is_grounded():
				ai_state = AIState.GROUNDED
				if biplane.has_method("disable_autopilot"):
					biplane.disable_autopilot()
				is_using_autopilot = false

func _is_player_in_territory() -> bool:
	if not target:
		return false
	var px = target.global_position.x
	return px >= territory_left and px <= territory_right

func _is_target_on_ground() -> bool:
	if not target or not biplane:
		return false
	if target.has_method("is_grounded"):
		var avatar = target.get_avatar_data(0) if target.has_method("get_avatar_data") else null
		if avatar:
			return target.is_grounded(avatar)
	var target_alt = _get_altitude_above_ground_for(target)
	return target_alt < 30.0

func _is_overhead_target() -> bool:
	if not biplane or not target:
		return false
	var x_dist = _get_wrapped_distance(biplane.global_position.x, target.global_position.x)
	return x_dist < BOMB_OVERHEAD_X_THRESHOLD

func _can_bomb_ground_target() -> bool:
	if not target or not biplane:
		return false
	if bomb_cooldown_timer > 0.0:
		return false
	var avatar = _get_avatar()
	if not avatar or avatar.bombs <= 0:
		return false
	if not _is_target_on_ground():
		return false
	if not _is_overhead_target():
		return false
	var alt = _get_altitude_above_ground()
	if alt < 100.0:
		return false
	var my_pos = biplane.global_position
	var target_pos = target.global_position
	var to_target = target_pos - my_pos
	var angle_from_vertical = abs(atan2(to_target.x, -to_target.y))
	if angle_from_vertical > BOMB_ANGLE_TOLERANCE:
		return false
	return true

func _decision_takeoff() -> void:
	var speed = biplane.velocity.length()
	var stall_speed: float = 10.0
	if biplane and "stall_speed_ms" in biplane:
		stall_speed = biplane.stall_speed_ms

	var throttle = 1.0
	if not _is_grounded():
		if speed < stall_speed * 1.5:
			throttle = 0.3
		elif biplane.rotation < -0.3:
			throttle = 0.5
		elif biplane.rotation < 0.0:
			throttle = 0.7
	last_throttle = throttle

	if _is_grounded():
		if speed < TAKEOFF_BUILD_SPEED:
			last_pitch_input = 0.0
		elif speed < TAKEOFF_ROTATE_SPEED:
			last_pitch_input = 0.0
		elif speed < stall_speed * 2.0:
			last_pitch_input = 0.0
		else:
			last_pitch_input = TAKEOFF_PITCH
	else:
		var alt = _get_altitude_above_ground()
		if speed < stall_speed * 2.0:
			last_pitch_input = clampf(-0.03 * (speed / (stall_speed * 2.0)), -0.03, 0.0)
		elif alt < 100.0:
			last_pitch_input = -0.05
		elif alt < 200.0:
			last_pitch_input = -0.08
		else:
			last_pitch_input = -0.12

func _compute_patrol_pitch() -> float:
	if not biplane:
		return 0.0

	var patrol_x = clampf(home_base_x, TERRAIN_LENGTH * 0.33, TERRAIN_LENGTH * 0.67)
	var ground_y = _get_ground_height(patrol_x)
	patrol_time += decision_interval
	var oscillation = sin(patrol_time * ALTITUDE_OSCILLATION_SPEED) * ALTITUDE_OSCILLATION_AMP
	var patrol_y = ground_y - PATROL_ALTITUDE + oscillation

	var aim_point = Vector2(patrol_x, patrol_y)
	_steer_toward(aim_point)
	return _compute_pitch_from_heading()

func _compute_patrol_throttle(avatar) -> float:
	var alt = _get_altitude_above_ground()
	var target_alt = PATROL_ALTITUDE
	if alt < target_alt - 30.0:
		return 0.8
	elif alt > target_alt + 50.0:
		return 0.3
	return 0.5

func _compute_engage_pitch() -> float:
	if not biplane or not target:
		return 0.0

	var my_pos = biplane.global_position
	var target_pos = target.global_position
	var to_target = target_pos - my_pos
	var distance = to_target.length()

	var my_alt = _get_altitude_above_ground()
	var target_alt = _get_altitude_above_ground_for(target)
	var alt_diff = my_alt - target_alt

	var aim_point: Vector2

	if distance > STALKING_THRESHOLD:
		aim_point = _stalking_waypoint(target_pos)
	elif alt_diff > ADVANTAGE_THRESHOLD:
		aim_point = _lead_pursuit_point(target_pos, 0.6)
		aim_point.y += 20.0
	elif alt_diff < -ADVANTAGE_THRESHOLD:
		aim_point = _lead_pursuit_point(target_pos, 0.4)
		aim_point.y -= 40.0
	else:
		var dist_to_player = my_pos.distance_to(target_pos)
		if dist_to_player < 200.0 and distance > _get_wrapped_distance(my_pos.x, target_pos.x):
			aim_point = _lead_pursuit_point(target_pos, 0.5)
			aim_point.y -= 30.0
		else:
			aim_point = _lead_pursuit_point(target_pos, 0.7)

	_steer_toward(aim_point)
	return _compute_pitch_from_heading()

func _compute_engage_throttle(avatar) -> float:
	if not biplane or not target:
		return 0.5

	var my_pos = biplane.global_position
	var target_pos = target.global_position
	var distance = my_pos.distance_to(target_pos)
	var my_alt = _get_altitude_above_ground()
	var target_alt = _get_altitude_above_ground_for(target)
	var alt_diff = my_alt - target_alt

	var damage_mod = _damage_throttle_modifier(avatar.damage_percent if avatar else 0.0)

	if alt_diff > ADVANTAGE_THRESHOLD:
		return 0.7 * damage_mod
	elif alt_diff < -ADVANTAGE_THRESHOLD:
		return 1.0 * damage_mod
	elif distance < MAX_FIRE_RANGE:
		var my_heading = Vector2(cos(biplane.rotation), sin(biplane.rotation))
		var to_target_dir = (target_pos - my_pos).normalized()
		var alignment = my_heading.dot(to_target_dir)
		if alignment > 0.8:
			return 0.6 * damage_mod
		return 0.8 * damage_mod
	else:
		return 1.0 * damage_mod

func _should_bomb_instead_of_strafe() -> bool:
	return _can_bomb_ground_target()

func _compute_bomb_pitch() -> float:
	if not biplane or not target:
		return 0.0

	var my_pos = biplane.global_position
	var target_pos = target.global_position
	var x_dist = _get_wrapped_distance(my_pos.x, target_pos.x)

	var approach_dir = sign(target_pos.x - my_pos.x)

	if x_dist < BOMB_OVERHEAD_X_THRESHOLD * 0.5:
		var desired_y = my_pos.y - 20.0
		var aim_point = Vector2(my_pos.x + approach_dir * 100, desired_y)
		_steer_toward(aim_point)
		return _compute_pitch_from_heading()

	var overhead_x = target_pos.x - approach_dir * BOMB_OVERHEAD_X_THRESHOLD * 2.0
	var approach_y = my_pos.y
	var aim_point = Vector2(overhead_x, approach_y)

	_steer_toward(aim_point)
	return _compute_pitch_from_heading()

func _try_drop_bomb() -> void:
	if bomb_cooldown_timer > 0.0:
		return
	var avatar = _get_avatar()
	if not avatar or avatar.bombs <= 0:
		return
	if biplane.has_method("drop_bomb"):
		biplane.drop_bomb(avatar)
		bomb_cooldown_timer = 2.5

func _lead_pursuit_point(target_pos: Vector2, lead_factor: float) -> Vector2:
	if not biplane or not target:
		return target_pos

	var my_pos = biplane.global_position
	var to_target = target_pos - my_pos
	var distance = to_target.length()

	var target_vel: Vector2 = Vector2.ZERO
	if "velocity" in target:
		target_vel = target.velocity

	var my_speed = biplane.velocity.length()
	if my_speed < 1.0:
		my_speed = 1.0

	var lead_time = clampf(distance / my_speed * lead_factor, 0.2, 1.5)
	var predicted_pos = target_pos + target_vel * lead_time

	var my_alt = _get_altitude_above_ground()
	var target_alt = _get_altitude_above_ground_for(target)

	if my_alt < target_alt - ADVANTAGE_THRESHOLD:
		predicted_pos.y -= 30.0
	elif my_alt > target_alt + ADVANTAGE_THRESHOLD:
		predicted_pos.y += 15.0

	return predicted_pos

func _stalking_waypoint(target_pos: Vector2) -> Vector2:
	if not biplane:
		return target_pos

	var my_pos = biplane.global_position
	var dx = target_pos.x - my_pos.x
	var dist_x = abs(dx)

	if dist_x > STALKING_THRESHOLD:
		var waypoint_x = my_pos.x + sign(dx) * 150.0
		var safe_ceil = _get_ground_height(waypoint_x) - MIN_ALTITUDE_ABOVE_GROUND
		var waypoint_y = minf(my_pos.y - 100.0, safe_ceil)
		return Vector2(waypoint_x, waypoint_y)

	return target_pos

func _steer_toward(aim_point: Vector2) -> void:
	if not biplane:
		return

	var my_pos = biplane.global_position
	var to_aim = aim_point - my_pos
	desired_heading = to_aim.angle()

func _compute_pitch_from_heading() -> float:
	if not biplane:
		return 0.0

	var angle_diff = wrapf(desired_heading - biplane.rotation, -PI, PI)

	var avatar = _get_avatar()
	var angular_vel: float = 0.0
	if avatar:
		angular_vel = avatar.angular_velocity

	var abs_angle = abs(angle_diff)
	if abs_angle < 0.05:
		return 0.0

	var base_pitch = angle_diff * PITCH_SENSITIVITY

	var damping = angular_vel * PITCH_DAMPING * 0.5
	base_pitch -= damping

	base_pitch = clampf(base_pitch, -1.0, 1.0)

	return base_pitch

func _compute_evade_pitch() -> float:
	if not biplane:
		return 0.0

	var alt = _get_altitude_above_ground()

	if alt < CRITICAL_ALTITUDE_ABOVE_GROUND:
		return -1.0
	elif alt < DANGER_ALTITUDE_ABOVE_GROUND:
		return -0.8
	elif incoming_bullet_timer > 0.0:
		if flip_cooldown <= 0.0 and randf() < 0.6:
			var avatar = _get_avatar()
			if avatar:
				biplane.do_flip(avatar)
				flip_cooldown = 3.0
		return -0.3
	else:
		return -0.5

func _compute_evade_throttle() -> float:
	var alt = _get_altitude_above_ground()
	if alt < DANGER_ALTITUDE_ABOVE_GROUND:
		return 1.0
	return 0.8

func _compute_return_pitch() -> float:
	if not biplane:
		return 0.0

	var ground_y = _get_ground_height(home_base_x)
	var home_pos = Vector2(home_base_x, ground_y - PATROL_ALTITUDE)
	var to_home = home_pos - biplane.global_position
	var distance = to_home.length()

	if distance < HOME_PROXIMITY * 2.0:
		var landing_ground = _get_ground_height(home_base_x)
		var landing_pos = Vector2(home_base_x, landing_ground - 50.0)
		_steer_toward(landing_pos)

		if distance < HOME_PROXIMITY and not is_using_autopilot:
			_enable_autopilot_for_landing()

		return _compute_pitch_from_heading()

	var aim_point = _lead_pursuit_point(home_pos, 0.5)
	aim_point.y = minf(aim_point.y, ground_y - PATROL_ALTITUDE)
	_steer_toward(aim_point)
	return _compute_pitch_from_heading()

func _compute_return_throttle(avatar) -> float:
	if not biplane:
		return 0.3

	var my_dist_to_home = _get_wrapped_distance(biplane.global_position.x, home_base_x)
	var damage_mod = _damage_throttle_modifier(avatar.damage_percent if avatar else 0.0)

	if my_dist_to_home < HOME_PROXIMITY * 2.0:
		return 0.3 * damage_mod
	elif my_dist_to_home > 500.0:
		return 0.5 * damage_mod
	return 0.4 * damage_mod

func _damage_throttle_modifier(damage_percent: float) -> float:
	if damage_percent >= 0.8:
		return 0.3
	elif damage_percent >= 0.5:
		return 0.5
	elif damage_percent >= 0.25:
		return 0.75
	return 1.0

func _get_altitude_above_ground_for(node: Node2D) -> float:
	if not node:
		return 0.0
	var ground_y = _get_ground_height(node.global_position.x)
	return ground_y - node.global_position.y

func _try_fire_weapon() -> void:
	if not biplane or not target:
		return

	var my_pos = biplane.global_position
	var target_pos = target.global_position
	var to_target = target_pos - my_pos
	var distance = to_target.length()

	if distance > MAX_FIRE_RANGE or distance < MIN_FIRE_RANGE:
		return

	var target_vel: Vector2 = Vector2.ZERO
	if "velocity" in target:
		target_vel = target.velocity

	var bullet_speed = 1600.0
	var bullet_travel_time = distance / bullet_speed
	var predicted_pos = target_pos + target_vel * bullet_travel_time

	var bullet_dir = (predicted_pos - my_pos).normalized()
	var my_heading = Vector2(cos(biplane.rotation), sin(biplane.rotation))
	var angle_diff = bullet_dir.angle_to(my_heading)

	var shot_quality = 1.0 - (abs(angle_diff) / FIRE_CONE_ANGLE)
	var quality_threshold = 0.3 if distance < 200.0 else 0.6

	if shot_quality >= quality_threshold:
		_fire_weapon()

func _apply_reflexes(pitch: float, throttle: float) -> Array:
	if _stall_reflex():
		return [last_pitch_input, last_throttle]

	var alt_correction = _altitude_reflex()
	if alt_correction != 0.0:
		pitch = alt_correction
		throttle = maxf(throttle, 0.8)

	var ceiling_correction = _altitude_ceiling_reflex()
	if ceiling_correction != 0.0:
		pitch = maxf(pitch, ceiling_correction)

	var terrain_correction = _terrain_projection_reflex()
	if terrain_correction != 0.0:
		pitch = minf(pitch, terrain_correction)

	var pull_up_correction = _pull_up_reflex()
	if pull_up_correction != 0.0:
		pitch = pull_up_correction

	return [pitch, throttle]

func _pull_up_reflex() -> float:
	if not biplane:
		return 0.0

	var altitude = _get_altitude_above_ground()
	if altitude > PULL_UP_ALTITUDE:
		return 0.0

	if biplane.rotation > 0.1:
		return -0.5

	return 0.0

func _stall_reflex() -> bool:
	var avatar = _get_avatar()
	if avatar and avatar.flight_state == 1:
		last_pitch_input = -1.0
		last_throttle = 1.0
		return true
	return false

func _altitude_reflex() -> float:
	if not biplane:
		return 0.0

	var altitude = _get_altitude_above_ground()

	if altitude < CRITICAL_ALTITUDE_ABOVE_GROUND:
		return -1.0
	elif altitude < DANGER_ALTITUDE_ABOVE_GROUND:
		return -0.7
	elif altitude < MIN_ALTITUDE_ABOVE_GROUND:
		return -0.3
	return 0.0

func _altitude_ceiling_reflex() -> float:
	if not biplane:
		return 0.0

	var altitude = _get_altitude_above_ground()

	if altitude > MAX_ALTITUDE:
		return 0.5
	elif altitude > MAX_ALTITUDE - 50.0:
		return 0.2
	return 0.0

func _terrain_projection_reflex() -> float:
	if not biplane:
		return 0.0

	var current_ground = _get_ground_height(biplane.global_position.x)
	var vel_x = biplane.velocity.x

	for look_dist in TERRAIN_LOOK_DISTANCES:
		var future_x = biplane.global_position.x + sign(vel_x) * look_dist
		var ground_y = _get_ground_height(future_x)
		var terrain_rise = current_ground - ground_y

		if terrain_rise > look_dist * TERRAIN_RISE_THRESHOLD:
			return -0.5

	return 0.0

func notify_incoming_fire() -> void:
	incoming_bullet_timer = 0.5

func get_dodge_chance() -> float:
	var avatar = _get_avatar()
	if not avatar:
		return 0.0
	if avatar.is_flipping:
		return 0.5
	return 0.0

func _apply_input(pitch: float, throttle_amount: float) -> void:
	if biplane.has_method("set_ai_input"):
		biplane.set_ai_input(pitch, throttle_amount)

func _enable_autopilot_for_landing() -> void:
	is_using_autopilot = true
	if biplane.has_method("enable_autopilot"):
		biplane.enable_autopilot()

	var ground_y = _get_ground_height(home_base_x)

	if biplane.has_method("setup_homebase"):
		biplane.setup_homebase(1, home_base_x, 200.0, Vector2(home_base_x, ground_y - 12), 0.0)
	if biplane.has_method("set_home_base") and biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(1)
		if avatar:
			biplane.set_home_base(avatar, 1)

func _fire_weapon() -> void:
	if biplane.has_method("fire_gun") and biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			biplane.fire_gun(avatar)

func take_damage(amount: float, attacker: Node) -> void:
	var owner: Node = null
	if attacker.has_method("get_bullet_owner"):
		owner = attacker.get_bullet_owner()
	elif attacker.has_method("get_bomb_owner"):
		owner = attacker.get_bomb_owner()

	if owner and owner.has_method("is_player") and owner.is_player():
		notify_incoming_fire()
		if biplane.has_method("get_avatar_data"):
			var avatar = biplane.get_avatar_data(0)
			if avatar and biplane.has_method("take_damage"):
				biplane.take_damage(avatar, amount, attacker)

func _on_enemy_crashed() -> void:
	if crash_timer > 0:
		return
	crash_timer = crash_delay
	is_waiting_for_crash_land = true
	if biplane and biplane.has_method("create_explosion"):
		biplane.create_explosion()

func _respawn_after_delay() -> void:
	crash_timer = crash_delay

func _do_respawn() -> void:
	if not biplane:
		return
	var ground_y = _get_ground_height(home_base_x)
	biplane.position = Vector2(home_base_x + 50, ground_y - 12)
	biplane.rotation = 0
	biplane.velocity = Vector2.ZERO
	biplane.visible = true
	if biplane.has_method("reset_flight_state"):
		biplane.reset_flight_state()
	if biplane.has_method("get_avatar_data"):
		biplane.get_avatar_data(0).is_player = false
	if biplane.has_method("set_game_active"):
		biplane.set_game_active(true)
	ai_state = AIState.GROUNDED

func _show_explosion_and_hide() -> void:
	if not biplane:
		return
	var explosion: Node = load("res://scenes/explosion.tscn").instantiate()
	explosion.global_position = biplane.global_position
	get_parent().add_child(explosion)

	if biplane.has_node("Visual"):
		var plane_poly := PackedVector2Array([
			Vector2(20, 0),
			Vector2(10, -4),
			Vector2(-15, -4),
			Vector2(-20, 0),
			Vector2(-15, 4),
			Vector2(10, 4)
		])
		var shatter: Node = load("res://scenes/shatter_effect.tscn").instantiate()
		shatter.setup(plane_poly, Color(0.5, 0.55, 0.5), biplane.global_position)
		get_parent().add_child(shatter)

	if biplane.has_method("set_game_active"):
		biplane.set_game_active(false)
	respawn_timer = respawn_delay

func get_biplane() -> CharacterBody2D:
	return biplane

func is_enemy() -> bool:
	return true
