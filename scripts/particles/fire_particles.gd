extends Node2D
## Fire particles for engine/plane fire. GPUParticles2D scene.

@export var fire_amount: int = 30
@export var fire_lifetime: float = 0.3
@export var fire_speed_min: float = 60.0
@export var fire_speed_max: float = 90.0
@export var emission_radius: float = 5.0

@export var color_peak: Color = Color(1.0, 0.95, 0.7, 1.0)      ## Yellow-white core
@export var color_mid: Color = Color(1.0, 0.5, 0.1, 0.9)       ## Orange mid
@export var color_ash: Color = Color(0.4, 0.1, 0.05, 0.3)      ## Reddish translucent ash

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