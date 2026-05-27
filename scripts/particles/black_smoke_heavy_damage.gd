extends Node2D
## Black smoke for heavy damage. GPUParticles2D scene.
## Attached to an entity; position and rotation track the parent.

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