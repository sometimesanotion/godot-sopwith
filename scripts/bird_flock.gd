extends Area2D

const BIRD_SCENE := preload("res://scenes/bird.tscn")
const TERRAIN_LENGTH := 16384.0
const EDGE_MARGIN := 500.0
const MAX_HEIGHT := 1200.0
const SWAY_X := 28.0
const SWAY_Y := 20.0


var flock_size: int = 8
var birds: Array[Node] = []
var move_direction: int = 1
var move_speed: float = 70.0
var target_y: float = 500.0
var altitude_timer: float = 0.0
var altitude_interval: float = 5.0
var scatter_triggered: bool = false
var elapsed: float = 0.0

func _ready() -> void:
	add_to_group("obstacle")
	add_to_group("destructible")
	add_to_group("flock")
	move_direction = 1 if randf() < 0.5 else -1
	target_y = _preferred_y()
	altitude_interval = 10.0 + randf() * 14.0
	for i in range(flock_size):
		var bird = BIRD_SCENE.instantiate()
		bird.position = Vector2.ZERO
		add_child(bird)
		birds.append(bird)

func _preferred_y() -> float:
	var g = _ground_y(global_position.x)
	return g - (200.0 + randf() * MAX_HEIGHT)

func _ground_y(x: float) -> float:
	var t = get_parent().get_node_or_null("Terrain")
	if t and t.has_method("get_ground_height_at"):
		return t.get_ground_height_at(x)
	return 650.0

func _check_disturbance() -> bool:
	var pos = global_position
	for body in get_overlapping_bodies():
		if body.has_method("get_avatar_data") or body.is_in_group("player"):
			return true
	for area in get_overlapping_areas():
		if area.has_method("get_avatar_data") or area.is_in_group("player") or area.is_in_group("destructible"):
			return true
	for child in get_parent().get_children():
		if child == self:
			continue
		if child.has_meta("bullet"):
			if pos.distance_squared_to(child.global_position) < 10000.0:
				return true
			continue
		if child.has_method("get_avatar_data") and pos.distance_squared_to(child.global_position) < 20000.0:
			return true
	return false

func _scatter_all() -> void:
	if scatter_triggered:
		return
	scatter_triggered = true
	for b in birds:
		if not is_instance_valid(b):
			continue
		var new_bird = BIRD_SCENE.instantiate()
		new_bird.global_position = b.global_position
		new_bird.start_scatter()
		get_parent().add_child(new_bird)
	queue_free()

func take_damage(amount: float, attacker: Node) -> void:
	_scatter_all()

func _physics_process(delta: float) -> void:
	if scatter_triggered:
		return
	elapsed += delta
	if _check_disturbance():
		_scatter_all()
		return
	global_position.x += move_direction * move_speed * delta
	if global_position.x > TERRAIN_LENGTH - EDGE_MARGIN:
		move_direction = -1
	elif global_position.x < EDGE_MARGIN:
		move_direction = 1
	altitude_timer += delta
	if altitude_timer >= altitude_interval:
		altitude_timer = 0.0
		target_y = _preferred_y()
		altitude_interval = 3.0 + randf() * 4.0
	var cur_ground = _ground_y(global_position.x)
	var clamped = minf(target_y, cur_ground - 200.0)
	global_position.y = move_toward(global_position.y, clamped, 40.0 * delta)
	for i in range(birds.size()):
		var b = birds[i]
		if not is_instance_valid(b):
			continue
		var sway = Vector2(cos(elapsed * 2.0 + i * 1.5) * SWAY_X, sin(elapsed * 3.0 + i * 2.0) * SWAY_Y)
		b.position = b.position.lerp(sway, delta * 4.0)
		b.wing_flap += delta * 15.0
		b.queue_redraw()
