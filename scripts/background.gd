extends Node2D

const TERRAIN_LENGTH := 4096.0

var camera: Camera2D
var mountain_positions: Array[Vector2] = []
var cloud_positions: Array[Vector2] = []

func _ready() -> void:
	_generate_background()

func _generate_background() -> void:
	randomize()
	for i in range(8):
		mountain_positions.append(Vector2(randf() * TERRAIN_LENGTH, 500 + randf() * 150))
	for i in range(6):
		cloud_positions.append(Vector2(randf() * TERRAIN_LENGTH, 100 + randf() * 200))

func _process(_delta: float) -> void:
	pass

func _draw() -> void:
	_draw_sky()
	_draw_mountains()
	_draw_clouds()

func _draw_sky() -> void:
	draw_rect(Rect2(-1000, -1000, 5000, 2000), Color(0.15, 0.2, 0.35))

func _draw_mountains() -> void:
	for pos in mountain_positions:
		var screen_pos = pos
		var height = 80 + randf() * 60
		var points = PackedVector2Array([
			Vector2(screen_pos.x - 100, 750),
			Vector2(screen_pos.x - 30, 750 - height),
			Vector2(screen_pos.x + 40, 750 - height - 30),
			Vector2(screen_pos.x + 100, 750)
		])
		draw_colored_polygon(points, Color(0.15, 0.18, 0.22))

func _draw_clouds() -> void:
	for pos in cloud_positions:
		var shade = 0.5 + randf() * 0.2
		draw_circle(pos, 25, Color(shade, shade, shade, 0.7))
		draw_circle(pos + Vector2(20, -5), 20, Color(shade, shade, shade, 0.7))
		draw_circle(pos + Vector2(-18, -3), 18, Color(shade, shade, shade, 0.7))