extends Node2D
## Combined fire + black smoke for total destruction.
## GPUParticles2D scene with fire and smoke emitters.

@export var fire_amount: int = 40
@export var smoke_amount: int = 30
@export var duration: float = 8.0

## Fire color gradient parameters
@export var color_peak: Color = Color(1.0, 0.95, 0.7, 1.0)      ## Yellow-white core
@export var color_mid: Color = Color(1.0, 0.5, 0.1, 0.9)       ## Orange mid
@export var color_ash: Color = Color(0.4, 0.1, 0.05, 0.3)      ## Reddish translucent ash

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