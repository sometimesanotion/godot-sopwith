extends Node2D

var velocity: Vector2 = Vector2(100, 0)
var wing_flap: float = 0.0

func _ready() -> void:
	add_to_group("obstacle")
	velocity = Vector2(80 + randf() * 40, randf() * 20 - 10)

func _process(delta: float) -> void:
	global_position += velocity * delta
	wing_flap += delta * 15
	queue_redraw()
	
	if global_position.x > 4500:
		queue_free()
	elif global_position.x < -500:
		queue_free()

func _draw() -> void:
	var flap_angle = sin(wing_flap) * 0.5
	draw_line(Vector2(-8, 0), Vector2(-12, -8 * flap_angle - 4), Color(0.2, 0.2, 0.2), 2)
	draw_line(Vector2(-8, 0), Vector2(-12, 8 * flap_angle + 4), Color(0.2, 0.2, 0.2), 2)
	draw_circle(Vector2(0, 0), 4, Color(0.15, 0.15, 0.15))
	draw_line(Vector2(4, 0), Vector2(10, -2), Color(0.2, 0.2, 0.2), 2)
	draw_line(Vector2(4, 0), Vector2(10, 2), Color(0.2, 0.2, 0.2), 2)

func _on_area_entered(_area: Area2D) -> void:
	queue_free()