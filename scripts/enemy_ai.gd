extends Node

@export var target: Node2D
@export var biplane: CharacterBody2D

var decision_timer: float = 0.0
var decision_interval: float = 0.5

var target_position: Vector2 = Vector2.ZERO

var incoming_bullet_timer: float = 0.0
var roll_timer: float = 0.0
var is_rolling: bool = false

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("destructible")

func _physics_process(delta: float) -> void:
	if not target or not biplane:
		return

	incoming_bullet_timer = max(0, incoming_bullet_timer - delta)
	roll_timer = max(0, roll_timer - delta)
	if roll_timer <= 0 and is_rolling:
		is_rolling = false
		_end_roll()
	
	if is_rolling:
		_do_roll(delta)

	decision_timer -= delta
	if decision_timer <= 0:
		decision_timer = decision_interval
		_make_decision()

func _make_decision() -> void:
	if not target:
		return

	var target_pos := target.global_position
	var my_pos := biplane.global_position

	var to_target := target_pos - my_pos
	var distance := to_target.length()

	var diff_angle := to_target.angle() - biplane.rotation

	while diff_angle > PI:
		diff_angle -= TAU
	while diff_angle < -PI:
		diff_angle += TAU

	var pitch_input := 0.0
	if diff_angle > 0.2:
		pitch_input = -1.0
	elif diff_angle < -0.2:
		pitch_input = 1.0

	var throttle := 0.7
	if distance < 200:
		throttle = 0.4
	elif distance > 500:
		throttle = 1.0

	if is_rolling:
		pitch_input = 0.0

	_apply_input(pitch_input, throttle)

	if distance < 300 and randf() < 0.3:
		_fire_weapon()

	if incoming_bullet_timer > 0 and not is_rolling and randf() < 0.5:
		_start_roll()

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

func _fire_weapon() -> void:
	if biplane.has_method("fire_gun"):
		biplane.fire_gun()

func take_damage(amount: float, attacker: Node) -> void:
	var owner: Node = null
	if attacker.has_method("get_bullet_owner"):
		owner = attacker.get_bullet_owner()
	elif attacker.has_method("get_bomb_owner"):
		owner = attacker.get_bomb_owner()
	
	if owner and owner.has_method("is_enemy") and owner.is_enemy():
		pass
	elif owner and owner.has_method("add_score"):
		owner.add_score(int(amount))
	
	if owner and owner.has_method("is_player") and owner.is_player():
		notify_incoming_fire()
	
	die()

func die() -> void:
	if biplane:
		var explosion: Node = load("res://scenes/explosion.tscn").instantiate()
		explosion.global_position = biplane.global_position
		get_parent().add_child(explosion)
		
		if GameManager:
			GameManager.request_screen_shake(20.0)
		
		if biplane.has_node("Visual"):
			var shatter: Node = load("res://scenes/shatter_effect.tscn").instantiate()
			shatter.setup(_get_plane_polygon(), Color(0.2, 0.3, 0.2), biplane.global_position)
			get_parent().add_child(shatter)
		biplane.queue_free()
	queue_free()

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