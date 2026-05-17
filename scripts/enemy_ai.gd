extends Node

@export var target: Node2D
@export var biplane: CharacterBody2D

var decision_timer: float = 0.0
var decision_interval: float = 0.05

var target_position: Vector2 = Vector2.ZERO

var incoming_bullet_timer: float = 0.0
var roll_timer: float = 0.0
var is_rolling: bool = false

var home_base_x: float = 1400.0
var patrol_range: float = 2000.0
var enemy_state: String = "GROUNDED"
var landing_threshold: float = 800.0
var is_using_autopilot: bool = false
var unlimited_fuel_ammo: bool = false
var takeoff_delay: float = 0.0
var takeoff_timer: float = 0.0

var last_pitch_input: float = 0.0
var last_throttle: float = 0.0

const TERRAIN_LENGTH := 16384.0

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("destructible")
	if biplane and biplane.has_signal("crashed"):
		biplane.crashed.connect(_on_enemy_crashed)

func _is_grounded() -> bool:
	if biplane.has_method("is_grounded") and biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			return biplane.is_grounded(avatar)
	return false

func _physics_process(delta: float) -> void:
	if not target or not biplane:
		return

	if takeoff_delay > 0:
		takeoff_timer += delta
		if takeoff_timer < takeoff_delay:
			return

	_update_state(delta)

	incoming_bullet_timer = max(0, incoming_bullet_timer - delta)
	roll_timer = max(0, roll_timer - delta)
	if roll_timer <= 0 and is_rolling:
		is_rolling = false
		_end_roll()

	if is_rolling:
		_do_roll(delta)

	if last_pitch_input != 0.0 or last_throttle != 0.0:
		_apply_input(last_pitch_input, last_throttle)

	if not biplane.visible:
		_try_respawn()

	decision_timer -= delta
	if decision_timer <= 0:
		decision_timer = decision_interval
		_make_decision()

func _update_state(delta: float) -> void:
	if not biplane:
		return

	var dist_to_home := _get_wrapped_distance(biplane.global_position.x, home_base_x)
	var player_dist := 0.0
	var player_x := target.global_position.x if target else 0.0
	if target:
		player_dist = _get_wrapped_distance(target.global_position.x, home_base_x)

	match enemy_state:
		"GROUNDED":
			if player_dist < patrol_range:
				enemy_state = "TAKING_OFF"
		"TAKING_OFF":
			if dist_to_home > 100:
				enemy_state = "ENGAGING"
		"ENGAGING":
			if player_dist > patrol_range:
				enemy_state = "RETURNING"
			elif _is_grounded():
				enemy_state = "GROUNDED"
		"RETURNING":
			if dist_to_home < 50 and _is_grounded():
				enemy_state = "GROUNDED"
			elif dist_to_home > patrol_range * 0.5:
				enemy_state = "ENGAGING"

func _get_wrapped_distance(x1: float, x2: float) -> float:
	var d: float = abs(x1 - x2)
	if d > TERRAIN_LENGTH * 0.5:
		d = TERRAIN_LENGTH - d
	return d

func _make_decision() -> void:
	if not target:
		return

	match enemy_state:
		"GROUNDED", "TAKING_OFF":
			_decision_takeoff()
		"ENGAGING":
			_decision_engage()
		"RETURNING":
			_decision_return_home()

func _decision_takeoff() -> void:
	if _is_grounded():
		last_pitch_input = -0.7
	else:
		last_pitch_input = -0.5
	last_throttle = 1.0

func _decision_engage() -> void:
	var target_pos := target.global_position
	var my_pos := biplane.global_position
	var to_target := target_pos - my_pos
	var distance := to_target.length()

	var player_altitude := 650.0 - target_pos.y
	var my_altitude := 650.0 - my_pos.y
	var altitude_ratio := my_altitude / player_altitude if player_altitude > 0 else 0.0
	
	if distance > 400 and altitude_ratio < 1.3:
		last_pitch_input = -0.7
		last_throttle = 1.0
		if is_rolling:
			last_pitch_input = 0.0
		return
	
	var target_angle := to_target.angle()
	var current_angle := biplane.rotation
	var diff_angle := target_angle - current_angle
	while diff_angle > PI:
		diff_angle -= TAU
	while diff_angle < -PI:
		diff_angle += TAU
	
	last_pitch_input = 0.0
	if diff_angle > 0.1:
		last_pitch_input = 0.8
	elif diff_angle < -0.1:
		last_pitch_input = -0.8

	if is_rolling:
		last_pitch_input = 0.0

	if distance < 350:
		last_throttle = 0.5
		if abs(diff_angle) < 0.3:
			_fire_weapon()
	else:
		last_throttle = 1.0

	if incoming_bullet_timer > 0 and not is_rolling and randf() < 0.5:
		_start_roll()

func _decision_return_home() -> void:
	var home_pos := Vector2(home_base_x, 650.0)
	var to_home := home_pos - biplane.global_position
	var distance := to_home.length()

	if distance < landing_threshold and not is_using_autopilot:
		_enable_autopilot_for_landing()

	if is_using_autopilot:
		if biplane.has_method("update_autopilot"):
			biplane.update_autopilot(home_pos)
		if _is_grounded():
			is_using_autopilot = false
			enemy_state = "GROUNDED"
			if biplane.has_method("disable_autopilot"):
				biplane.disable_autopilot()
		return

	var target_angle := to_home.angle()
	var diff_angle := target_angle - biplane.rotation
	while diff_angle > PI:
		diff_angle -= TAU
	while diff_angle < -PI:
		diff_angle += TAU

	last_pitch_input = 0.0
	if diff_angle > 0.2:
		last_pitch_input = 1.0
	elif diff_angle < -0.2:
		last_pitch_input = -1.0

	last_throttle = 0.3
	if distance > 300:
		last_throttle = 0.5

	if is_rolling:
		last_pitch_input = 0.0

func _do_roll(delta: float) -> void:
	if not biplane:
		return

	biplane.rotation += delta * biplane.roll_speed * roll_direction

	var normalized_rot := fmod(biplane.rotation, TAU)
	if normalized_rot < 0:
		normalized_rot += TAU

	var dist_to_target: float
	if roll_direction > 0:
		dist_to_target = min(normalized_rot - roll_start_angle, TAU - (normalized_rot - roll_start_angle))
	else:
		dist_to_target = min(roll_start_angle - normalized_rot, normalized_rot + TAU - roll_start_angle)

	if dist_to_target >= PI - 0.1:
		_end_roll()

var roll_direction: int = 1
var roll_start_angle: float = 0.0

func _start_roll() -> void:
	if not biplane:
		return

	is_rolling = true
	roll_timer = 0.8

	var normalized_rot := fmod(biplane.rotation, TAU)
	if normalized_rot < 0:
		normalized_rot += TAU

	if normalized_rot < PI:
		roll_direction = 1
		roll_start_angle = normalized_rot
	else:
		roll_direction = -1
		roll_start_angle = normalized_rot

func _end_roll() -> void:
	is_rolling = false
	if not biplane:
		return

	var normalized_rot := fmod(biplane.rotation, TAU)
	if normalized_rot < 0:
		normalized_rot += TAU

	var dist_to_upright: float = min(normalized_rot, TAU - normalized_rot)
	var dist_to_inverted: float = abs(normalized_rot - PI)

	if dist_to_upright <= dist_to_inverted:
		biplane.rotation = round(normalized_rot / PI) * PI
	else:
		biplane.rotation = round((normalized_rot - PI) / PI) * PI + PI

func notify_incoming_fire() -> void:
	incoming_bullet_timer = 0.5

func is_doing_roll() -> bool:
	return is_rolling

func get_dodge_chance() -> float:
	if not is_rolling:
		return 0.0
	return 0.5

func _apply_input(pitch: float, throttle_amount: float) -> void:
	if biplane.has_method("set_ai_input"):
		biplane.set_ai_input(pitch, throttle_amount)

func _enable_autopilot_for_landing() -> void:
	is_using_autopilot = true
	if biplane.has_method("enable_autopilot"):
		biplane.enable_autopilot()

	var terrain = get_parent().get_node_or_null("Terrain")
	var ground_y := 650.0
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(home_base_x)

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
	_respawn_after_delay()

var crash_timer: float = 0.0
var crash_delay: float = 2.0

var respawn_timer: float = 0.0
var respawn_delay: float = 3.0

func _respawn_after_delay() -> void:
	crash_timer = crash_delay

func _try_respawn() -> void:
	if crash_timer > 0:
		crash_timer -= 0.016
		if crash_timer <= 0:
			_show_explosion_and_hide()
		return
	if respawn_timer > 0:
		respawn_timer -= 0.016
		return
	if not biplane:
		return
	var ground_y := 650.0
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(home_base_x)
	biplane.position = Vector2(home_base_x + 60, ground_y - 12)
	biplane.rotation = 0
	biplane.velocity = Vector2.ZERO
	biplane.visible = true
	if biplane.has_method("reset_flight_state"):
		biplane.reset_flight_state()
	if biplane.has_method("get_avatar_data"):
		biplane.get_avatar_data(0).is_player = false
	if biplane.has_method("set_game_active"):
		biplane.set_game_active(true)
	enemy_state = "GROUNDED"

func _show_explosion_and_hide() -> void:
	if not biplane:
		return
	var explosion: Node = load("res://scenes/explosion.tscn").instantiate()
	explosion.global_position = biplane.global_position
	get_parent().add_child(explosion)

	if GameManager:
		GameManager.request_screen_shake(20.0)

	if biplane.has_node("Visual"):
		var shatter: Node = load("res://scenes/shatter_effect.tscn").instantiate()
		shatter.setup(_get_plane_polygon(), Color(0.2, 0.3, 0.2), biplane.global_position)
		get_parent().add_child(shatter)
	
	biplane.visible = false
	if biplane.has_method("set_game_active"):
		biplane.set_game_active(false)
	respawn_timer = respawn_delay

func _get_plane_polygon() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(20, 0),
		Vector2(10, -4),
		Vector2(-15, -4),
		Vector2(-20, 0),
		Vector2(-15, 4),
		Vector2(10, 4)
	])

func get_biplane() -> CharacterBody2D:
	return biplane

func is_enemy() -> bool:
	return true