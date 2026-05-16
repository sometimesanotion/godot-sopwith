extends Node2D

const NUM_MOUNTAINS := 8
const NUM_CLOUDS := 6

var mountains: Array[Vector2] = []
var clouds: Array[Vector2] = []
var mountain_colors: Array[Color] = []
var cloud_colors: Array[Color] = []

func _ready() -> void:
	_initialize_background_elements()

func _initialize_background_elements() -> void:
	var screen_width := 1280.0
	var screen_height := 720.0

	for i in range(NUM_MOUNTAINS):
		var x := randf() * screen_width
		var y := screen_height * 0.6 + randf() * screen_height * 0.2
		mountains.append(Vector2(x, y))
		var shade := 0.15 + randf() * 0.15
		mountain_colors.append(Color(shade, shade, shade * 1.1))

	for i in range(NUM_CLOUDS):
		var x := randf() * screen_width
		var y := randf() * screen_height * 0.5
		clouds.append(Vector2(x, y))
		var shade := 0.6 + randf() * 0.2
		cloud_colors.append(Color(shade, shade, shade))

func _draw() -> void:
	_draw_gradient_sky()
	_draw_mountains()
	_draw_clouds()

func _draw_gradient_sky() -> void:
	var screen_width := 1280.0
	var screen_height := 720.0

	var top_color := Color(0.1, 0.15, 0.3)
	var bottom_color := Color(0.4, 0.5, 0.6)

	var gradient := Gradient.new()
	gradient.set_color(0, top_color)
	gradient.set_color(1, bottom_color)

	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 2
	gradient_texture.height = int(screen_height)

	draw_texture(gradient_texture, Vector2(0, 0))

func _draw_mountains() -> void:
	var screen_height := 720.0
	var base_y := screen_height * 0.75

	for i in range(mountains.size()):
		var pos := mountains[i]
		var peak_y := pos.y

		if peak_y > base_y:
			peak_y = base_y - 10

		var left_x := pos.x - 150
		var right_x := pos.x + 150

		var points: PackedVector2Array = []
		points.append(Vector2(left_x, base_y))
		points.append(Vector2(pos.x - 50, peak_y))
		points.append(Vector2(pos.x + 30, peak_y - 30))
		points.append(Vector2(pos.x + 100, peak_y + 10))
		points.append(Vector2(right_x, base_y))

		if points.size() >= 3:
			draw_colored_polygon(points, mountain_colors[i])

func _draw_clouds() -> void:
	for i in range(clouds.size()):
		var pos := clouds[i]
		var cloud_color := cloud_colors[i]

		var center := pos
		var radius := 30.0 + randf() * 20.0

		draw_circle(center, radius, cloud_color)
		draw_circle(center + Vector2(radius * 0.8, -radius * 0.2), radius * 0.7, cloud_color)
		draw_circle(center + Vector2(-radius * 0.7, -radius * 0.1), radius * 0.6, cloud_color)
		draw_circle(center + Vector2(radius * 0.3, radius * 0.4), radius * 0.5, cloud_color)