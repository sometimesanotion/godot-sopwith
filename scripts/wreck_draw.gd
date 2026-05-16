extends Node2D

func _ready():
	queue_redraw()

func _draw():
	var color = get_meta("wreck_color", Color(0.15, 0.15, 0.18))
	var points = get_meta("wreck_points", PackedVector2Array())
	if points.size() >= 3:
		draw_colored_polygon(points, color)