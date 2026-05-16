extends Node2D

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
	particle.set_script(_get_fire_particle_script())
	particle.setup(lifetime, Color(1, 0.5, 0.1, 1), size)
	add_child(particle)

func _get_fire_particle_script() -> GDScript:
	return load("res://scripts/fire_particle.gd")