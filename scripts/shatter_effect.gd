extends Node2D

var fragments: Array[RigidBody2D] = []
var lifetime: float = 2.0

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0:
		for f in fragments:
			if is_instance_valid(f):
				f.queue_free()
		queue_free()

func setup(poly: PackedVector2Array, color: Color, position: Vector2) -> void:
	global_position = position

	if poly.size() < 3:
		queue_free()
		return

	var center := _get_polygon_center(poly)
	var normalized := PackedVector2Array()
	for p in poly:
		normalized.append(p - center)

	var num_fragments: int = mini(poly.size() * 2, 12)

	for i in range(num_fragments):
		var fragment: RigidBody2D = _create_fragment(normalized, color, center)
		fragments.append(fragment)

func _get_polygon_center(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / float(poly.size())

func _create_fragment(poly: PackedVector2Array, color: Color, center: Vector2) -> RigidBody2D:
	var rb := RigidBody2D.new()
	rb.position = global_position

	var shape := CollisionPolygon2D.new()
	var fragment_poly := PackedVector2Array()
	var num_points: int = randi_range(3, 6)
	for i in range(num_points):
		var angle := randf() * TAU
		var dist := randf_range(5, 15)
		fragment_poly.append(Vector2(cos(angle), sin(angle)) * dist)

	shape.polygon = fragment_poly
	rb.add_child(shape)

	var sprite := Polygon2D.new()
	sprite.polygon = fragment_poly
	sprite.color = color.darkened(randf() * 0.3)
	rb.add_child(sprite)

	rb.gravity_scale = 1.0
	rb.linear_damp = 0.5
	rb.angular_damp = 0.5

	var random_dir := Vector2(randf_range(-1, 1), randf_range(-1, -0.5)).normalized()
	var force := random_dir * randf_range(100, 300)
	rb.linear_velocity = force
	rb.angular_velocity = randf_range(-5, 5)

	add_child(rb)
	return rb