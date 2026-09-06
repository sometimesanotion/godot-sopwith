extends Node2D
## Explosion debris: lightweight sensor fragments, no physics bodies.
## Spawns on crash/destroy events. Fragments damage on overlap (Area2D
## sensor only — they never push, bounce, or block anything) and vanish
## individually once they slow down; nothing solid is left behind.

@export var fragment_count: int = 6
@export var debris_damage: float = 5.0
@export var debris_lifetime: float = 2.0

## Fragment vanish speed: 2 m/s, converted with the project's pixels-per-meter
## (Biplane.pixels_per_meter default). Fragments are visual shrapnel + a
## damage sensor — a slow fragment is spent, so it is removed.
const VANISH_SPEED_MS := 1.0
const PIXELS_PER_METER := 13.0
const VANISH_SPEED_PX := VANISH_SPEED_MS * PIXELS_PER_METER
## Gravity for manual fragment integration (px/s^2).
const GRAVITY_PX := 9.81 * PIXELS_PER_METER
## Air drag, same model as the old RigidBody linear_damp (vel /= 1 + damp*dt).
const AIR_DAMP := 0.5

const DEBRIS_COLORS := [
	Color(0.04, 0.015, 0.04),
	Color(0.05, 0.05, 0.05),
	Color(0.035, 0.04, 0.035),
	Color(0.03, 0.03, 0.03),
]

## One sensor fragment: an Area2D that detects physics bodies for damage but
## takes part in no collision response. Motion is integrated manually.
class DebrisFragment extends Area2D:
	var vel: Vector2 = Vector2.ZERO
	var spin: float = 0.0

var _fire: GPUParticles2D = null
var _smoke: GPUParticles2D = null
var _fragments: Array[DebrisFragment] = []
var _fragments_created: bool = false
var _lifetime: float = 0.0
var _terrain: Node = null

func _ready() -> void:
	add_to_group("explosion_debris")
	_create_fire_effect()
	_create_smoke_effect()
	# Fragments are created once in setup(), not here: _ready runs at add_child
	# (before setup), so creating them here as well would double-spawn.
	_lifetime = 0.0
	var parent := get_parent()
	if parent:
		_terrain = parent.get_node_or_null("Terrain")

func _physics_process(delta: float) -> void:
	_integrate_fragments(delta)
	_lifetime += delta
	if _lifetime >= debris_lifetime or _fragments.is_empty():
		_cleanup()

func setup(pos: Vector2, color: Color = Color(0.05, 0.055, 0.05), count: int = -1, damage: float = -1.0) -> void:
	global_position = pos
	if count > 0:
		fragment_count = count
	if damage >= 0.0:
		debris_damage = damage
	if not _fragments_created:
		_fragments_created = true
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

func _create_fragments_with_color(base_color: Color) -> void:
	for i in range(fragment_count):
		var frag_color := base_color.darkened(randf() * 0.3)

		var points := PackedVector2Array()
		var num_points := randi_range(3, 6)
		var angle_step := TAU / num_points
		var start_angle := randf() * TAU
		for j in range(num_points):
			var angle := start_angle + j * angle_step
			var dist := randf_range(1, 4)
			points.append(Vector2(cos(angle), sin(angle)) * dist)

		# Sensor only: detects bodies for damage, resolves nothing. Speeds
		# are small vs. body sizes at 60 Hz physics, so no CCD is needed.
		var frag := DebrisFragment.new()
		frag.collision_layer = 0
		frag.collision_mask = 1
		frag.monitorable = false

		var sensor := CollisionPolygon2D.new()
		sensor.polygon = points
		frag.add_child(sensor)

		var sprite := Polygon2D.new()
		sprite.polygon = points
		sprite.color = frag_color
		frag.add_child(sprite)

		var random_dir := Vector2(randf_range(-1, 1), randf_range(-1, -0.3)).normalized()
		frag.vel = random_dir * randf_range(100, 300)
		frag.spin = randf_range(-5, 5)

		frag.body_entered.connect(_on_fragment_hit)
		_fragments.append(frag)
		add_child(frag)

func _integrate_fragments(delta: float) -> void:
	var drag := 1.0 / (1.0 + AIR_DAMP * delta)
	for i in range(_fragments.size() - 1, -1, -1):
		var frag := _fragments[i]
		if not is_instance_valid(frag):
			_fragments.remove_at(i)
			continue
		frag.vel.y += GRAVITY_PX * delta
		frag.vel *= drag
		frag.position += frag.vel * delta
		frag.rotation += frag.spin * delta
		# Spent fragments vanish: too slow to matter, or buried in terrain.
		if frag.vel.length() < VANISH_SPEED_PX or _is_buried(frag):
			frag.queue_free()
			_fragments.remove_at(i)

func _is_buried(frag: DebrisFragment) -> bool:
	if _terrain and _terrain.has_method("get_ground_height_at"):
		return frag.global_position.y >= _terrain.get_ground_height_at(frag.global_position.x)
	return false

func _on_fragment_hit(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(debris_damage, self)

func _cleanup() -> void:
	for f in _fragments:
		if is_instance_valid(f):
			f.queue_free()
	_fragments.clear()
	queue_free()
