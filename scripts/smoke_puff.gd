extends Node2D

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