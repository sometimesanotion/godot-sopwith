extends Node2D

class_name SmokePuff
var lifetime: float = 2.0
var max_lifetime: float = 2.0
var base_color: Color = Color(0.2, 0.2, 0.2, 0.8)

func _ready() -> void:
	add_to_group("smoke_puff")

func setup(lifetime_seconds: float, color: Color) -> void:
	lifetime = lifetime_seconds
	max_lifetime = lifetime_seconds
	base_color = color

func _process(delta: float) -> void:
	lifetime -= delta
	queue_redraw()
	if lifetime <= 0:
		queue_free()

func _draw() -> void:
	var alpha := base_color.a * (lifetime / max_lifetime)
	var fade_color := Color(base_color.r, base_color.g, base_color.b, alpha)
	draw_circle(Vector2.ZERO, 10.0, fade_color)


class_name FireParticle
var lifetime: float = 2.0
var max_lifetime: float = 2.0
var base_color: Color = Color(1, 0.5, 0.1, 1)
var particle_size: float = 8.0

func _ready() -> void:
	add_to_group("fire_particle")

func setup(lifetime_seconds: float, color: Color, size: float) -> void:
	lifetime = lifetime_seconds
	max_lifetime = lifetime_seconds
	base_color = color
	particle_size = size

func _process(delta: float) -> void:
	lifetime -= delta
	global_position.y -= 30 * delta
	queue_redraw()
	if lifetime <= 0:
		queue_free()

func _draw() -> void:
	var alpha := base_color.a * (lifetime / max_lifetime)
	var fade_color := Color(base_color.r, base_color.g, base_color.b, alpha)
	draw_circle(Vector2.ZERO, particle_size * (lifetime / max_lifetime), fade_color)


class_name FirePlume
var lifetime: float = 10.0
var max_lifetime: float = 10.0
var particles: Array = []
var spawn_timer: float = 0.0

func _ready() -> void:
	add_to_group("fire_plume")

func setup(lifetime_seconds: float) -> void:
	lifetime = lifetime_seconds
	max_lifetime = lifetime_seconds

func _process(delta: float) -> void:
	lifetime -= delta
	spawn_timer -= delta

	if spawn_timer <= 0:
		_spawn_fire_particle()
		spawn_timer = 0.1

	if lifetime <= 0:
		queue_free()

func _spawn_fire_particle() -> void:
	var particle := Node2D.new()
	particle.global_position = global_position + Vector2(randf_range(-10, 10), randf_range(-5, 5))
	var size := randf_range(4, 10)
	particle.set_script(load("res://scripts/particles.gd"))
	particle.setup(lifetime, Color(1, 0.5, 0.1, 1), size)
	add_child(particle)


class_name DebrisEffect
extends Node2D

var fragments: Array[RigidBody2D] = []
var debris_lifetime: float = 3.0
var _lifetime: float = 0.0
var _debris_damage: float = 10.0

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= debris_lifetime:
		_cleanup()

func setup(pos: Vector2, color: Color = Color(0.5, 0.55, 0.5), count: int = 8, damage: float = 10.0, polygon: PackedVector2Array = PackedVector2Array()) -> void:
	global_position = pos
	_debris_damage = damage

	if EffectManager:
		EffectManager.spawn_fire(pos, 12)
		EffectManager.spawn_black_smoke(pos, 8)

	if polygon.size() >= 3:
		_create_shatter_from_polygon(polygon, color)
	else:
		_create_random_fragments(color, count)

func _create_shatter_from_polygon(poly: PackedVector2Array, color: Color) -> void:
	var center := _get_polygon_center(poly)
	var normalized := PackedVector2Array()
	for p in poly:
		normalized.append(p - center)

	var num_fragments: int = mini(poly.size() * 2, 12)
	for i in range(num_fragments):
		var fragment := _create_fragment(color)
		fragments.append(fragment)

func _create_random_fragments(base_color: Color, count: int) -> void:
	for i in range(count):
		var frag_color := base_color.darkened(randf() * 0.3)
		var fragment := _create_fragment(frag_color)
		fragments.append(fragment)

func _create_fragment(color: Color) -> RigidBody2D:
	var rb := RigidBody2D.new()
	rb.position = global_position
	rb.contact_monitor = true
	rb.max_contacts_reported = 2

	var points := PackedVector2Array()
	var num_points := randi_range(3, 5)
	var angle_step := TAU / num_points
	var start_angle := randf() * TAU
	for j in range(num_points):
		var angle := start_angle + j * angle_step
		var dist := randf_range(2, 8)
		points.append(Vector2(cos(angle), sin(angle)) * dist)

	var collision := CollisionPolygon2D.new()
	collision.polygon = points
	rb.add_child(collision)

	var sprite := Polygon2D.new()
	sprite.polygon = points
	sprite.color = color
	rb.add_child(sprite)

	rb.gravity_scale = 1.0
	rb.linear_damp = 0.5
	rb.angular_damp = 0.5

	var random_dir := Vector2(randf_range(-1, 1), randf_range(-1, -0.3)).normalized()
	var force := random_dir * randf_range(80, 200)
	rb.linear_velocity = force
	rb.angular_velocity = randf_range(-5, 5)

	rb.body_entered.connect(_on_fragment_hit.bind())
	call_deferred("add_child", rb)
	return rb

func _get_polygon_center(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / float(poly.size())

func _on_fragment_hit(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(_debris_damage, self)

func _cleanup() -> void:
	for f in fragments:
		if is_instance_valid(f):
			f.queue_free()
	fragments.clear()
	queue_free()


class_name BlackSmokeHeavyDamage
extends Node2D

@export var smoke_amount: int = 30
@export var smoke_lifetime: float = 2.0
@export var smoke_speed_min: float = 30.0
@export var smoke_speed_max: float = 60.0
@export var emission_radius: float = 8.0

var _particles: GPUParticles2D = null

func _ready() -> void:
	add_to_group("black_smoke")
	_particles = GPUParticles2D.new()
	_particles.name = "BlackSmokeParticles"
	_particles.emitting = true
	_particles.amount = smoke_amount
	_particles.lifetime = smoke_lifetime
	_particles.one_shot = false
	_particles.explosiveness = 0.0
	_particles.randomness = 0.5

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = emission_radius
	mat.gravity = Vector3(0, -30, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = smoke_speed_min
	mat.initial_velocity_max = smoke_speed_max
	mat.scale_min = 4.0
	mat.scale_max = 10.0
	mat.color = Color(0.05, 0.05, 0.05, 0.5)

	_particles.process_material = mat
	add_child(_particles)

func stop() -> void:
	if _particles:
		_particles.emitting = false

func set_intensity(amount: int) -> void:
	if _particles:
		_particles.amount = amount


class_name FireParticles
extends Node2D

@export var fire_amount: int = 30
@export var fire_lifetime: float = 0.3
@export var fire_speed_min: float = 60.0
@export var fire_speed_max: float = 90.0
@export var emission_radius: float = 5.0

@export var color_peak: Color = Color(1.0, 0.95, 0.7, 1.0)
@export var color_mid: Color = Color(1.0, 0.5, 0.1, 0.9)
@export var color_ash: Color = Color(0.4, 0.1, 0.05, 0.3)

var _particles: GPUParticles2D = null

func _ready() -> void:
	add_to_group("fire_particles")
	_particles = GPUParticles2D.new()
	_particles.name = "FireParticles"
	_particles.emitting = true
	_particles.amount = fire_amount
	_particles.lifetime = fire_lifetime
	_particles.one_shot = false
	_particles.explosiveness = 0.2
	_particles.randomness = 0.3

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = emission_radius
	mat.gravity = Vector3(0, -40, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = fire_speed_min
	mat.initial_velocity_max = fire_speed_max
	mat.scale_min = 3.0
	mat.scale_max = 6.0

	var gradient := Gradient.new()
	gradient.add_point(0.0, color_peak)
	gradient.add_point(0.3, color_mid)
	gradient.add_point(1.0, color_ash)
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	mat.color_ramp = tex

	_particles.process_material = mat
	add_child(_particles)

func stop() -> void:
	if _particles:
		_particles.emitting = false

func set_intensity(amount: int) -> void:
	if _particles:
		_particles.amount = amount


class_name ExplosionDebris
extends Node2D

@export var fragment_count: int = 8
@export var debris_damage: float = 10.0
@export var debris_lifetime: float = 3.0

const DEBRIS_COLORS := [
	Color(0.4, 0.45, 0.4),
	Color(0.5, 0.5, 0.5),
	Color(0.35, 0.4, 0.35),
	Color(0.3, 0.3, 0.3),
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

func setup(pos: Vector2, color: Color = Color(0.5, 0.55, 0.5), count: int = -1, damage: float = -1.0) -> void:
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
		var num_points := randi_range(3, 5)
		var angle_step := TAU / num_points
		var start_angle := randf() * TAU
		for j in range(num_points):
			var angle := start_angle + j * angle_step
			var dist := randf_range(2, 8)
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

		var random_dir := Vector2(randf_range(-1, 1), randf_range(-1, -0.3)).normalized()
		var force := random_dir * randf_range(80, 200)
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


class_name OpenFireWithSmoke
extends Node2D

@export var fire_amount: int = 40
@export var smoke_amount: int = 30
@export var duration: float = 8.0

@export var color_peak: Color = Color(1.0, 0.95, 0.7, 1.0)
@export var color_mid: Color = Color(1.0, 0.5, 0.1, 0.9)
@export var color_ash: Color = Color(0.4, 0.1, 0.05, 0.3)

var _fire: GPUParticles2D = null
var _smoke: GPUParticles2D = null
var _timer: float = 0.0
var _running: bool = false

func _ready() -> void:
	add_to_group("open_fire_with_smoke")

	_fire = GPUParticles2D.new()
	_fire.name = "Fire"
	_fire.emitting = true
	_fire.amount = fire_amount
	_fire.lifetime = 0.3
	_fire.one_shot = false
	_fire.explosiveness = 0.2

	var fire_mat := ParticleProcessMaterial.new()
	fire_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fire_mat.emission_sphere_radius = 5.0
	fire_mat.gravity = Vector3(0, -40, 0)
	fire_mat.spread = 30.0
	fire_mat.initial_velocity_min = 60.0
	fire_mat.initial_velocity_max = 90.0
	fire_mat.scale_min = 3.0
	fire_mat.scale_max = 6.0

	var fire_gradient := Gradient.new()
	fire_gradient.add_point(0.0, color_peak)
	fire_gradient.add_point(0.3, color_mid)
	fire_gradient.add_point(1.0, color_ash)
	var fire_tex := GradientTexture1D.new()
	fire_tex.gradient = fire_gradient
	fire_mat.color_ramp = fire_tex
	_fire.process_material = fire_mat
	add_child(_fire)

	_smoke = GPUParticles2D.new()
	_smoke.name = "Smoke"
	_smoke.emitting = true
	_smoke.amount = smoke_amount
	_smoke.lifetime = 2.0
	_smoke.one_shot = false
	_smoke.explosiveness = 0.0

	var smoke_mat := ParticleProcessMaterial.new()
	smoke_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke_mat.emission_sphere_radius = 10.0
	smoke_mat.gravity = Vector3(0, -30, 0)
	smoke_mat.spread = 30.0
	smoke_mat.initial_velocity_min = 30.0
	smoke_mat.initial_velocity_max = 60.0
	smoke_mat.scale_min = 4.0
	smoke_mat.scale_max = 10.0
	smoke_mat.color = Color(0.05, 0.05, 0.05, 0.5)
	_smoke.process_material = smoke_mat
	add_child(_smoke)

func start(lifetime: float = -1.0) -> void:
	_running = true
	_timer = 0.0
	if lifetime > 0.0:
		duration = lifetime
	if _fire:
		_fire.emitting = true
	if _smoke:
		_smoke.emitting = true

func stop() -> void:
	_running = false
	if _fire:
		_fire.emitting = false
	if _smoke:
		_smoke.emitting = false

func set_fire_intensity(amount: int) -> void:
	if _fire:
		_fire.amount = amount

func set_smoke_intensity(amount: int) -> void:
	if _smoke:
		_smoke.amount = amount

func _process(delta: float) -> void:
	if not _running:
		return
	_timer += delta
	if _timer >= duration:
		stop()
		queue_free()


class_name WhiteSmokeLightDamage
extends Node2D

@export var smoke_amount: int = 20
@export var smoke_lifetime: float = 1.5
@export var smoke_speed_min: float = 30.0
@export var smoke_speed_max: float = 60.0
@export var emission_radius: float = 8.0

var _particles: GPUParticles2D = null

func _ready() -> void:
	add_to_group("white_smoke")
	_particles = GPUParticles2D.new()
	_particles.name = "WhiteSmokeParticles"
	_particles.emitting = true
	_particles.amount = smoke_amount
	_particles.lifetime = smoke_lifetime
	_particles.one_shot = false
	_particles.explosiveness = 0.0
	_particles.randomness = 0.5

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = emission_radius
	mat.gravity = Vector3(0, -30, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = smoke_speed_min
	mat.initial_velocity_max = smoke_speed_max
	mat.scale_min = 4.0
	mat.scale_max = 10.0
	mat.color = Color(0.8, 0.8, 0.8, 0.5)

	_particles.process_material = mat
	add_child(_particles)

func stop() -> void:
	if _particles:
		_particles.emitting = false

func set_intensity(amount: int) -> void:
	if _particles:
		_particles.amount = amount
