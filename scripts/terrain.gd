extends Node2D

const TERRAIN_LENGTH := 4096.0
const SEGMENT_WIDTH := 32.0
const RUNWAY_START := 200.0
const RUNWAY_END := 600.0

var noise: FastNoiseLite
var ground_points: PackedVector2Array = []
var visual_line: Line2D
var collision_polygon: CollisionPolygon2D

@export var ground_color: Color = Color(0.2, 0.5, 0.2)
@export var runway_color: Color = Color(0.4, 0.4, 0.45)

var camera: Camera2D

func _ready() -> void:
	_initialize_noise()
	_generate_terrain()
	_create_visual_line()
	_create_collision()

func _process(_delta: float) -> void:
	_update_position()

func _update_position() -> void:
	var main := get_parent()
	if main and main.has_method("get_biplane_position"):
		var player_x: float = main.get_biplane_position()
		var viewport_width: float = 1280.0
		position.x = wrapf(player_x - viewport_width / 2, 0, TERRAIN_LENGTH)

func _initialize_noise() -> void:
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.008
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5

func _generate_terrain() -> void:
	ground_points.clear()

	var num_segments := int(TERRAIN_LENGTH / SEGMENT_WIDTH)
	var base_y := 650.0

	for i in range(num_segments + 1):
		var x := i * SEGMENT_WIDTH
		var y: float

		if x >= RUNWAY_START and x <= RUNWAY_END:
			y = base_y
		else:
			var noise_val := noise.get_noise_2d(x, 0)
			y = base_y + noise_val * 100

		ground_points.append(Vector2(x, y))

	ground_points.append(Vector2(TERRAIN_LENGTH, 750.0))
	ground_points.append(Vector2(0, 750.0))

func _create_visual_line() -> void:
	visual_line = Line2D.new()
	visual_line.antialiased = true
	visual_line.width = 3.0
	visual_line.closed = false

	_update_visual_line()
	add_child(visual_line)

func _update_visual_line() -> void:
	if visual_line:
		visual_line.clear_points()
		for point in ground_points:
			if point.x < TERRAIN_LENGTH - SEGMENT_WIDTH:
				visual_line.add_point(point)

		var gradient := Gradient.new()
		gradient.set_color(0, ground_color)
		gradient.set_color(1, ground_color.darkened(0.3))

		var gradient_texture := GradientTexture1D.new()
		gradient_texture.gradient = gradient
		gradient_texture.width = 64

		visual_line.texture = gradient_texture

func _process(_delta: float) -> void:
	if camera:
		position.x = -camera.position.x + 640

func _create_collision() -> void:
	collision_polygon = CollisionPolygon2D.new()
	collision_polygon.polygon = ground_points
	add_child(collision_polygon)

func get_ground_height_at(x: float) -> float:
	var index := int(x / SEGMENT_WIDTH)
	index = clamp(index, 0, ground_points.size() - 2)

	var p1 := ground_points[index]
	var p2 := ground_points[index + 1]

	var t := (x - p1.x) / (p2.x - p1.x) if p2.x != p1.x else 0.0
	return lerp(p1.y, p2.y, t)

func is_on_runway(x: float) -> bool:
	return x >= RUNWAY_START and x <= RUNWAY_END

func wrap_position(pos: Vector2) -> Vector2:
	var wrapped_x := wrapf(pos.x, 0, TERRAIN_LENGTH)
	return Vector2(wrapped_x, pos.y)

func get_visual_line() -> Line2D:
	return visual_line