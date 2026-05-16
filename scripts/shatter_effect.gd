extends Node2D

var fragments: Array[RigidBody2D] = []
var lifetime: float = 2.0
var _damage_amount: float = 10.0

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0:
		for f in fragments:
			if is_instance_valid(f):
				f.queue_free()
		queue_free()

func setup(poly: PackedVector2Array, color: Color, position: Vector2, damage: float = 10.0) -> void:
	global_position = position
	_damage_amount = damage

	if poly.size() < 3:
		queue_free()
		return

	var center := _get_polygon_center(poly)
	var normalized := PackedVector2Array()
	for p in poly:
		normalized.append(p - center)

	_spawn_fire_and_smoke()

	var num_fragments: int = mini(poly.size() * 2, 12)

	for i in range(num_fragments):
		var fragment: RigidBody2D = _create_fragment(normalized, color, center)
		fragments.append(fragment)

func _spawn_fire_and_smoke() -> void:
	var fire := GPUParticles2D.new()
	fire.emitting = true
	fire.one_shot = true
	fire.explosiveness = 0.9
	fire.amount = 20
	fire.lifetime = 0.6
	fire.position = Vector2.ZERO

	var fire_mat := ParticleProcessMaterial.new()
	fire_mat.emission_shape = 1
	fire_mat.emission_sphere_radius = 8.0
	fire_mat.gravity = Vector3(0, -40, 0)
	fire_mat.spread = 180.0
	fire_mat.initial_velocity_min = 60.0
	fire_mat.initial_velocity_max = 140.0
	fire_mat.scale_min = 2.0
	fire_mat.scale_max = 5.0
	fire_mat.color = Color(1, 0.4, 0, 1)
	fire.process_material = fire_mat
	add_child(fire)

	var smoke := GPUParticles2D.new()
	smoke.emitting = true
	smoke.one_shot = true
	smoke.explosiveness = 0.6
	smoke.amount = 15
	smoke.lifetime = 1.2
	smoke.position = Vector2.ZERO

	var smoke_mat := ParticleProcessMaterial.new()
	smoke_mat.emission_shape = 1
	smoke_mat.emission_sphere_radius = 12.0
	smoke_mat.gravity = Vector3(0, -15, 0)
	smoke_mat.spread = 180.0
	smoke_mat.initial_velocity_min = 30.0
	smoke_mat.initial_velocity_max = 70.0
	smoke_mat.scale_min = 3.0
	smoke_mat.scale_max = 7.0
	smoke_mat.color = Color(0.15, 0.15, 0.15, 1)
	smoke.process_material = smoke_mat
	add_child(smoke)

func _get_polygon_center(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / float(poly.size())

func _create_fragment(poly: PackedVector2Array, color: Color, center: Vector2) -> RigidBody2D:
	var rb := RigidBody2D.new()
	rb.position = global_position

	var fragment_poly := PackedVector2Array()
	var num_points: int = randi_range(3, 5)
	var angle_step := TAU / num_points
	var start_angle := randf() * TAU
	for i in range(num_points):
		var angle := start_angle + i * angle_step
		var dist := randf_range(5, 15)
		fragment_poly.append(Vector2(cos(angle), sin(angle)) * dist)

	var collision := CollisionPolygon2D.new()
	collision.polygon = fragment_poly
	rb.add_child(collision)

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

	rb.body_entered.connect(_on_fragment_hit)

	add_child(rb)
	return rb

func _on_fragment_hit(body: Node) -> void:
	if body.has_method("take_damage"):
		if "is_player" in body and body.is_player:
			body.take_damage(_damage_amount, self)
