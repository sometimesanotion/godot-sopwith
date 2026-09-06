extends Node2D

func _draw() -> void:
	var color := get_meta("wreck_color", Color(0.7, 0.7, 0.7))
	# Fallen cow body (side-turned oval)
	draw_colored_polygon(PackedVector2Array([
		Vector2(20, 0), Vector2(10, -10), Vector2(-10, -10), Vector2(-20, 0),
		Vector2(-10, 10), Vector2(10, 10),
	]), color.darkened(0.3))
	# Head (tipped over)
	draw_colored_polygon(PackedVector2Array([
		Vector2(22, -6), Vector2(30, -12), Vector2(32, -4), Vector2(24, 4),
	]), color.darkened(0.1))
