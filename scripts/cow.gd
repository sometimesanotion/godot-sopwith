extends StaticBody2D

func _ready() -> void:
	add_to_group("obstacle")

func _draw() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-15, 0), Vector2(-15, -20), Vector2(-10, -28),
		Vector2(10, -28), Vector2(15, -20), Vector2(15, 0)
	]), Color(0.9, 0.9, 0.9))

	draw_rect(Rect2(-12, -18, 8, 8), Color(0.1, 0.1, 0.1))
	draw_circle(Vector2(12, -22), 4, Color(0.1, 0.1, 0.1))

	draw_line(Vector2(-8, -28), Vector2(-10, -32), Color(0.3, 0.3, 0.3), 2)
	draw_line(Vector2(0, -28), Vector2(0, -33), Color(0.3, 0.3, 0.3), 2)
	draw_line(Vector2(8, -28), Vector2(10, -32), Color(0.3, 0.3, 0.3), 2)

	draw_circle(Vector2(10, -8), 3, Color(0.2, 0.2, 0.2))

func take_damage(amount: float, attacker: Node) -> void:
	if GameManager:
		GameManager.add_score(-50)
	queue_free()
