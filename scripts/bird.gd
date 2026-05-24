extends Node2D

var wing_flap: float = 0.0
var is_scattered: bool = false
var scatter_vel: Vector2 = Vector2.ZERO

var _svg_sprite_name: String = "bird"
var _svg_size: Vector2 = Vector2(20, 14)

signal bird_destroyed(pos: Vector2)

const TERRAIN_LENGTH := 16384.0
const EDGE_MARGIN := 500.0
const MAX_HEIGHT := 380.0

func _ready() -> void:
	add_to_group("bird")
	add_to_group("obstacle")
	add_to_group("destructible")
	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func _ground_y(x: float) -> float:
	var t = get_tree().current_scene.get_node_or_null("Terrain")
	if t and t.has_method("get_ground_height_at"):
		return t.get_ground_height_at(x)
	return 650.0

func _check_hazard() -> bool:
	var pos = global_position
	for child in get_parent().get_children():
		if child == self:
			continue
		if child.has_meta("bullet") and pos.distance_squared_to(child.global_position) < 400.0:
			_destroy()
			return true
	var bombs = get_tree().get_nodes_in_group("bomb")
	for b in bombs:
		if is_instance_valid(b) and pos.distance_squared_to(b.global_position) < 10000.0:
			_destroy()
			return true
	return false

func start_scatter() -> void:
	is_scattered = true
	var angle = randf() * TAU
	scatter_vel = Vector2(cos(angle), sin(angle)) * (80.0 + randf() * 80.0)

var _target: Vector2 = Vector2.ZERO

func _pick_target() -> Vector2:
	var g = _ground_y(global_position.x)
	return Vector2(global_position.x + randf() * 300 - 150, g - (20.0 + randf() * MAX_HEIGHT))

func _physics_process(delta: float) -> void:
	if not is_scattered:
		return
	if _check_hazard():
		return
	if _target == Vector2.ZERO or global_position.distance_squared_to(_target) < 1600.0:
		_target = _pick_target()
	var to_target = _target - global_position
	var desired = to_target.normalized() * (80.0 + randf() * 40.0)
	desired.y += sin(wing_flap * 0.5) * 15.0
	scatter_vel = scatter_vel.lerp(desired, delta * 1.5)
	global_position += scatter_vel * delta
	if global_position.x > TERRAIN_LENGTH - EDGE_MARGIN:
		global_position.x = TERRAIN_LENGTH - EDGE_MARGIN
		scatter_vel.x *= -0.5
		_target = Vector2.ZERO
	elif global_position.x < EDGE_MARGIN:
		global_position.x = EDGE_MARGIN
		scatter_vel.x *= -0.5
		_target = Vector2.ZERO
	var g = _ground_y(global_position.x)
	var too_low = g - 20.0
	if global_position.y > too_low:
		global_position.y = too_low
		scatter_vel.y = -absf(scatter_vel.y)
		_target = Vector2.ZERO
	wing_flap += delta * 20.0
	queue_redraw()

func _draw() -> void:
	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		var flip = false
		if is_scattered:
			flip = scatter_vel.x < 0
		SvgManager.draw_sprite_flipped(self, _svg_sprite_name, Vector2.ZERO, _svg_size, flip)
		return
	var flap = sin(wing_flap) * 0.5
	draw_line(Vector2(-8, 0), Vector2(-12, -8 * flap - 4), Color(0.2, 0.2, 0.2), 2)
	draw_line(Vector2(-8, 0), Vector2(-12, 8 * flap + 4), Color(0.2, 0.2, 0.2), 2)
	draw_circle(Vector2(0, 0), 4, Color(0.15, 0.15, 0.15))
	draw_line(Vector2(4, 0), Vector2(10, -2), Color(0.2, 0.2, 0.2), 2)
	draw_line(Vector2(4, 0), Vector2(10, 2), Color(0.2, 0.2, 0.2), 2)

func take_damage(amount: float, attacker: Node) -> void:
	_destroy()

func _destroy() -> void:
	bird_destroyed.emit(global_position)
	queue_free()
