extends Node2D
class_name Terrain

# --- World layout ---
const TERRAIN_LENGTH := 16384.0
const TERRAIN_LOW_BOUND := 3000.0
const SEGMENT_WIDTH := 32.0
const BASE_Y := 650.0

# --- Runway ---
const RUNWAY_START := 5300.0
const RUNWAY_LENGTH := 600.0
const RUNWAY_END := RUNWAY_START + RUNWAY_LENGTH
const RUNWAY_APRON := 64.0
const RUNWAY_BLEND_WIDTH := 192.0

# --- Terrain synthesis (D4 multi-frequency noise) ---
const MACRO_FREQUENCY  := 0.0012
const MICRO_FREQUENCY  := 0.003
const MACRO_AMPLITUDE  := 260.0
const MICRO_AMP_MIN    := 8.0
const MICRO_AMP_MAX    := 45.0

# --- Deterministic noise salts ---
const _SALT_MACRO := 101
const _SALT_MICRO := 102

var macro_noise: FastNoiseLite
var micro_noise: FastNoiseLite
var resolved_seed: int = 0
var ground_points: PackedVector2Array = []
var terrain_body: StaticBody2D
var terrain_polygon: Polygon2D
var terrain_polygons: Array[Polygon2D] = []
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
		_update_terrain_geometry()
	_create_runway_visual(runway_start, runway_end)

func _create_terrain() -> void:
	terrain_body = StaticBody2D.new()
	terrain_body.name = "Terrain"

	var collision_poly := CollisionPolygon2D.new()
	terrain_body.add_child(collision_poly)
	terrain_body.collision_layer = 1
	add_child(terrain_body)

	terrain_polygon = Polygon2D.new()
	terrain_polygon.color = ground_color
	add_child(terrain_polygon)

	# Three tiled copies for seamless world wrapping.
	terrain_polygons = [terrain_polygon]
	for offset in [-TERRAIN_LENGTH, TERRAIN_LENGTH]:
		var copy := Polygon2D.new()
		copy.color = ground_color
		copy.position.x = offset
		add_child(copy)
		terrain_polygons.append(copy)

	_update_terrain_geometry()

	# Diagnostic: verify terrain body and visual are aligned.
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

func _update_terrain_geometry() -> void:
	var poly_points := ground_points.duplicate()
	poly_points.append(Vector2(TERRAIN_LENGTH, TERRAIN_LOW_BOUND))
	poly_points.append(Vector2(0, TERRAIN_LOW_BOUND))
	if terrain_body:
		for child in terrain_body.get_children():
			if child is CollisionPolygon2D:
				child.polygon = poly_points
	for poly in terrain_polygons:
		poly.polygon = poly_points

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
	resolved_seed = seed_value
	if macro_noise:
		macro_noise.seed = TerrainNoise.derive_seed(resolved_seed, _SALT_MACRO)
	if micro_noise:
		micro_noise.seed = TerrainNoise.derive_seed(resolved_seed, _SALT_MICRO)

func _initialize_noise() -> void:
	if GameManager and GameManager.terrain_seed != 0:
		resolved_seed = GameManager.terrain_seed
	else:
		resolved_seed = randi()
	macro_noise = TerrainNoise.make_noise(
		TerrainNoise.derive_seed(resolved_seed, _SALT_MACRO), MACRO_FREQUENCY, 2, 0.5)
	micro_noise = TerrainNoise.make_noise(
		TerrainNoise.derive_seed(resolved_seed, _SALT_MICRO), MICRO_FREQUENCY, 4, 0.5)

# Signed height: macro sweeps ±MACRO_AMPLITUDE; micro amplitude scales with
# macro ruggedness so plains stay smooth and mountains get jagged.
func _sample_height(x: float) -> float:
	var macro := TerrainNoise.sample_periodic(macro_noise, x, TERRAIN_LENGTH)
	var rugged := TerrainNoise.smoothstep01(macro * 0.5 + 0.5)
	var micro_amp := lerpf(MICRO_AMP_MIN, MICRO_AMP_MAX, rugged)
	var micro := TerrainNoise.sample_periodic(micro_noise, x, TERRAIN_LENGTH)
	return BASE_Y - macro * MACRO_AMPLITUDE - micro * micro_amp

# 0.0 on any runway span + apron; smoothsteps to 1 over RUNWAY_BLEND_WIDTH.
func _runway_flatness(x: float) -> float:
	var f := 1.0
	for runway in runways:
		var a := runway.x - RUNWAY_APRON
		var b := runway.y + RUNWAY_APRON
		if x >= a and x <= b:
			return 0.0
		var d := minf(absf(x - a), absf(x - b))
		f = minf(f, d / RUNWAY_BLEND_WIDTH)
	return TerrainNoise.smoothstep01(f)

func _generate_terrain() -> void:
	ground_points.clear()
	var num_segments := int(TERRAIN_LENGTH / SEGMENT_WIDTH)
	for i in range(num_segments + 1):
		var x := i * SEGMENT_WIDTH
		var flatness := _runway_flatness(x)
		var y := BASE_Y if flatness == 0.0 \
			else BASE_Y + (_sample_height(x) - BASE_Y) * flatness
		ground_points.append(Vector2(x, y))

func get_ground_height_at(x: float) -> float:
	if ground_points.size() < 2:
		return BASE_Y
	# Runway surface is exactly BASE_Y regardless of sample-grid alignment.
	if is_on_runway(x):
		return BASE_Y
	x = fmod(x, TERRAIN_LENGTH)
	if x < 0.0:
		x += TERRAIN_LENGTH
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
