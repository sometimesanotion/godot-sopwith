extends Node2D

const TERRAIN_LENGTH := 4096.0
const SEGMENT_WIDTH := 32.0
const RUNWAY_START := 200.0
const RUNWAY_END := 600.0
const BASE_Y := 650.0

var noise: FastNoiseLite
var ground_points: PackedVector2Array = []
var visual_polygon: Polygon2D
var collision_polygon: CollisionPolygon2D

@export var ground_color: Color = Color(0.15, 0.35, 0.15)
@export var runway_color: Color = Color(0.35, 0.35, 0.4)

func _ready() -> void:
	_initialize_noise()
	_generate_terrain()
	_create_visuals()
	_create_collision()

func _process(_delta: float) -> void:
	_update_position()

func _update_position() -> void:
	var main = get_parent()
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

	for i in range(num_segments + 1):
		var x := i * SEGMENT_WIDTH
		var y: float

		if x >= RUNWAY_START and x <= RUNWAY_END:
			y = BASE_Y
		else:
			var noise_val := noise.get_noise_2d(float(x), 0.0)
			y = BASE_Y + noise_val * 80.0

		ground_points.append(Vector2(x, y))

func _create_visuals() -> void:
	visual_polygon = Polygon2D.new()
	
	var poly_points := ground_points.duplicate()
	poly_points.append(Vector2(TERRAIN_LENGTH, 800.0))
	poly_points.append(Vector2(0, 800.0))
	
	visual_polygon.polygon = poly_points
	
	var gradient := Gradient.new()
	gradient.set_color(0, ground_color)
	gradient.set_color(1, ground_color.darkened(0.2))
	
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.width = 64
	gradient_texture.height = 128
	
	visual_polygon.texture = gradient_texture
	add_child(visual_polygon)

	var runway_polygon := Polygon2D.new()
	var runway_points := PackedVector2Array([
		Vector2(RUNWAY_START, BASE_Y),
		Vector2(RUNWAY_END, BASE_Y),
		Vector2(RUNWAY_END, BASE_Y + 25),
		Vector2(RUNWAY_START, BASE_Y + 25)
	])
	runway_polygon.polygon = runway_points
	runway_polygon.color = runway_color
	add_child(runway_polygon)

func _create_collision() -> void:
	var static_body := StaticBody2D.new()
	static_body.name = "TerrainBody"
	
	collision_polygon = CollisionPolygon2D.new()
	
	var poly_points := ground_points.duplicate()
	poly_points.append(Vector2(TERRAIN_LENGTH, 800.0))
	poly_points.append(Vector2(0, 800.0))
	
	collision_polygon.polygon = poly_points
	static_body.add_child(collision_polygon)
	
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	
	add_child(static_body)

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
	return null

func get_ground_points() -> PackedVector2Array:
	return ground_points