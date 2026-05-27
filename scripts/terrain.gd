extends Node2D

const TERRAIN_LENGTH := 16384.0
const TERRAIN_LOW_BOUND := 3000.0
const SEGMENT_WIDTH := 32.0
const RUNWAY_START := 6500.0
const RUNWAY_END := 7100.0
const RUNWAY_LENGTH := 500.0
const BASE_Y := 650.0

var noise: FastNoiseLite
var ground_points: PackedVector2Array = []
var terrain_body: StaticBody2D
var terrain_polygon: Polygon2D
var runways: Array[Vector2] = []

@export var ground_color: Color = Color(0.12, 0.35, 0.12)
@export var runway_color: Color = Color(0.35, 0.35, 0.4)

func _ready() -> void:
	runways.append(Vector2(RUNWAY_START, RUNWAY_END))
	if SvgManager and SvgManager.has_sprite("runway"):
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func generate() -> void:
	_initialize_noise()
	_generate_terrain()
	_create_terrain()

func add_runway(x: float) -> void:
	var runway_start := x
	var runway_end := x + RUNWAY_LENGTH
	runways.append(Vector2(runway_start, runway_end))
	if ground_points.size() > 0:
		_generate_terrain()
	_create_runway_visual(runway_start, runway_end)

func _create_terrain() -> void:
	terrain_body = StaticBody2D.new()
	terrain_body.name = "Terrain"

	var collision_poly := CollisionPolygon2D.new()
	var poly_points := ground_points.duplicate()
	poly_points.append(Vector2(TERRAIN_LENGTH, TERRAIN_LOW_BOUND))
	poly_points.append(Vector2(0, TERRAIN_LOW_BOUND))
	collision_poly.polygon = poly_points
	terrain_body.add_child(collision_poly)
	terrain_body.collision_layer = 1
	add_child(terrain_body)

	terrain_polygon = Polygon2D.new()
	terrain_polygon.polygon = poly_points
	terrain_polygon.color = ground_color
	add_child(terrain_polygon)

	# Diagnostic: verify terrain body and visual are aligned
	var terrain_min_y := INF
	var terrain_max_y := -INF
	for pt in ground_points:
		terrain_min_y = min(terrain_min_y, pt.y)
		terrain_max_y = max(terrain_max_y, pt.y)
	var collision_poly_count := 0
	for ch in terrain_body.get_children():
		if ch is CollisionPolygon2D:
			collision_poly_count += 1
			var cpoly_min_y := INF
			var cpoly_max_y := -INF
			for pt in ch.polygon:
				cpoly_min_y = min(cpoly_min_y, pt.y)
				cpoly_max_y = max(cpoly_max_y, pt.y)
			DLog.info("terrain_collision_poly", {
				"poly_index": collision_poly_count - 1,
				"poly_local_min_y": snapped(cpoly_min_y, 0.1),
				"poly_local_max_y": snapped(cpoly_max_y, 0.1),
				"poly_point_count": ch.polygon.size(),
				"body_pos_y": snapped(terrain_body.global_position.y, 0.1),
			})
	DLog.info("terrain_created", {
		"body_pos_y": snapped(terrain_body.global_position.y, 0.1),
		"poly_pos_y": snapped(terrain_polygon.global_position.y, 0.1),
		"node_pos_y": snapped(global_position.y, 0.1),
		"ground_min_y": snapped(terrain_min_y, 0.1),
		"ground_max_y": snapped(terrain_max_y, 0.1),
		"collision_poly_count": collision_poly_count,
	})

	for runway in runways:
		_create_runway_visual(runway.x, runway.y)

func _create_runway_visual(start: float, end: float) -> void:
	if SvgManager and SvgManager.has_sprite("runway"):
		var runway_tex = SvgManager.get_sprite("runway")
		if runway_tex:
			var runway_sprite = Sprite2D.new()
			runway_sprite.texture = runway_tex
			runway_sprite.position = Vector2((start + end) * 0.5, BASE_Y + 15)
			var tex_width = runway_tex.get_width()
			var tex_height = runway_tex.get_height()
			if tex_width > 0 and tex_height > 0:
				runway_sprite.scale = Vector2((end - start) / tex_width, 30.0 / tex_height)
			add_child(runway_sprite)
			return

	var runway := Polygon2D.new()
	runway.polygon = PackedVector2Array([
		Vector2(start, BASE_Y),
		Vector2(end, BASE_Y),
		Vector2(end, BASE_Y + 30),
		Vector2(start, BASE_Y + 30)
	])
	runway.color = runway_color
	add_child(runway)

func set_noise_seed(seed_value: int) -> void:
	if noise:
		noise.seed = seed_value

func _initialize_noise() -> void:
	noise = FastNoiseLite.new()
	if GameManager and GameManager.terrain_seed != 0:
		noise.seed = GameManager.terrain_seed
	else:
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
		var on_runway := false
		for runway in runways:
			if x >= runway.x and x <= runway.y:
				on_runway = true
				break
		if on_runway:
			y = BASE_Y
		else:
			var noise_val := noise.get_noise_2d(float(x), 0.0)
			y = BASE_Y + noise_val * 60.0
		ground_points.append(Vector2(x, y))

func get_ground_height_at(x: float) -> float:
	if ground_points.size() < 2:
		return BASE_Y
	var index := int(x / SEGMENT_WIDTH)
	index = clampi(index, 0, ground_points.size() - 2)
	var p1 := ground_points[index]
	var p2 := ground_points[index + 1]
	var t := (x - p1.x) / (p2.x - p1.x) if p2.x != p1.x else 0.0
	return lerp(p1.y, p2.y, t)

func is_on_runway(x: float) -> bool:
	for runway in runways:
		if x >= runway.x and x <= runway.y:
			return true
	return false

func get_ground_points() -> PackedVector2Array:
	return ground_points

func get_terrain_info_at(x: float) -> Dictionary:
	var surface_y := get_ground_height_at(x)
	var idx := int(x / SEGMENT_WIDTH)
	idx = clamp(idx, 0, ground_points.size() - 1)
	var body_pos_y := terrain_body.global_position.y if terrain_body else 0.0
	var poly_pos_y := terrain_polygon.global_position.y if terrain_polygon else 0.0
	return {
		"surface_y": surface_y,
		"terrain_body_pos_y": body_pos_y,
		"terrain_poly_pos_y": poly_pos_y,
		"terrain_node_pos_y": global_position.y,
		"x": x,
	}

func get_visual_line() -> Line2D:
	return null