extends Node2D

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