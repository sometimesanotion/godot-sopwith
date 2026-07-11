extends Node2D
## Explosion debris with collision-enabled RigidBody2D fragments.
## Spawns on crash/destroy events. Debris fragments collide and can damage other objects.

@export var fragment_count: int = 4
@export var debris_damage: float = 5.0
@export var debris_lifetime: float = 4.0
## Mass (kg) of each debris fragment. Lighter fragments impart less kinetic force
## when they strike planes, reducing dramatic bouncing. Lower = gentler impacts.
@export var debris_mass: float = 0.05

const DEBRIS_COLORS := [
	Color(0.04, 0.015, 0.04),
	Color(0.05, 0.05, 0.05),
	Color(0.035, 0.04, 0.035),
	Color(0.03, 0.03, 0.03),
]

var _fire: GPUParticles2D = null
var _smoke: GPUParticles2D = null
var _fragments: Array[RigidBody2D] = []
var _lifetime: float = 0.0

func _ready() -> void:
	add_to_group("explosion_debris")
	_create_fire_effect()
	_create_smoke_effect()
	_create_fragments()
	_lifetime = 0.0
	set_process(true)

func _process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= debris_lifetime:
		_cleanup()

func setup(pos: Vector2, color: Color = Color(0.05, 0.055, 0.05), count: int = -1, damage: float = -1.0) -> void:
	global_position = pos
	if count > 0:
		fragment_count = count
	if damage >= 0.0:
		debris_damage = damage
	_create_fragments_with_color(color)

func _create_fire_effect() -> void:
	_fire = GPUParticles2D.new()
	_fire.emitting = true
	_fire.one_shot = true
	_fire.explosiveness = 0.9
	_fire.amount = 12
	_fire.lifetime = 0.4

	var fire_mat := ParticleProcessMaterial.new()
	fire_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fire_mat.emission_sphere_radius = 8.0
	fire_mat.gravity = Vector3(0, -50, 0)
	fire_mat.spread = 180.0
	fire_mat.initial_velocity_min = 80.0
	fire_mat.initial_velocity_max = 150.0
	fire_mat.scale_min = 2.0
	fire_mat.scale_max = 5.0
	fire_mat.color = Color(1, 0.5, 0, 1)
	_fire.process_material = fire_mat
	add_child(_fire)

func _create_smoke_effect() -> void:
	_smoke = GPUParticles2D.new()
	_smoke.emitting = true
	_smoke.one_shot = true
	_smoke.explosiveness = 0.7
	_smoke.amount = 15
	_smoke.lifetime = 0.8

	var smoke_mat := ParticleProcessMaterial.new()
	smoke_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke_mat.emission_sphere_radius = 12.0
	smoke_mat.gravity = Vector3(0, -30, 0)
	smoke_mat.spread = 180.0
	smoke_mat.initial_velocity_min = 40.0
	smoke_mat.initial_velocity_max = 80.0
	smoke_mat.scale_min = 3.0
	smoke_mat.scale_max = 8.0
	smoke_mat.color = Color(0.15, 0.15, 0.15, 0.8)
	_smoke.process_material = smoke_mat
	add_child(_smoke)

func _create_fragments() -> void:
	_create_fragments_with_color(Color(0.5, 0.55, 0.5))

func _create_fragments_with_color(base_color: Color) -> void:
	for i in range(fragment_count):
		var frag_color := base_color.darkened(randf() * 0.3)
		var rb := RigidBody2D.new()
		rb.contact_monitor = true
		rb.max_contacts_reported = 2

		var points := PackedVector2Array()
		var num_points := randi_range(3, 6)
		var angle_step := TAU / num_points
		var start_angle := randf() * TAU
		for j in range(num_points):
			var angle := start_angle + j * angle_step
			var dist := randf_range(1, 4)
			points.append(Vector2(cos(angle), sin(angle)) * dist)

		var collision := CollisionPolygon2D.new()
		collision.polygon = points
		rb.add_child(collision)

		var sprite := Polygon2D.new()
		sprite.polygon = points
		sprite.color = frag_color
		rb.add_child(sprite)

		rb.gravity_scale = 1.0
		rb.linear_damp = 0.5
		rb.angular_damp = 0.5
		rb.mass = debris_mass
		# rb.inertia = 0.5

		var random_dir := Vector2(randf_range(-1, 1), randf_range(-1, -0.3)).normalized()
		var force := random_dir * randf_range(200, 500)
		rb.linear_velocity = force
		rb.angular_velocity = randf_range(-5, 5)

		rb.body_entered.connect(_on_fragment_hit.bind())
		call_deferred("add_child", rb)
		_fragments.append(rb)

func _on_fragment_hit(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(debris_damage, self)

func _cleanup() -> void:
	for f in _fragments:
		if is_instance_valid(f):
			f.queue_free()
	_fragments.clear()
	queue_free()