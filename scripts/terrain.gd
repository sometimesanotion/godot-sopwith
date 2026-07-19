extends Node2D
class_name Terrain

# --- World layout ---
const TERRAIN_LENGTH := 16384.0
const TERRAIN_LOW_BOUND := 3000.0
const SEGMENT_WIDTH := 32.0
const BASE_Y := 650.0

# --- Runway ---
const RUNWAY_START := 5300.0
const RUNWAY_LENGTH := 700.0
const RUNWAY_END := RUNWAY_START + RUNWAY_LENGTH
const RUNWAY_APRON := 50.0
# Blend width: the off-runway transition ramps from the runway's own elevation
# to the surrounding terrain over this distance (D5).  Because every runway is
# seated exactly on the smooth base-elevation sweep (see _base_elevation), the
# step at the apron edge is only the HILLS/MICRO texture, so this width just
# controls how gradually local hills rise from each base — not cliff avoidance.
const RUNWAY_BLEND_WIDTH := 350.0

# --- Terrain synthesis (D4 multi-frequency noise) ---
# Three independent layers shape the height:
#   * REGION — a very low-frequency noise.  Its samples at each homebase
#     become that base's elevation, and a smooth curve (straight/cosine slopes)
#     is interpolated THROUGH those per-homebase heights.  This makes the
#     terrain sweep continuously between bases with no cliffs, and every
#     runway sits exactly on the landscape.  Dominant term near homebases.
#   * HILLS  — a medium-frequency noise adding the local valleys/hills texture
#     on top of the region sweep (flattened near runways by the blend).
#   * MICRO  — tiny bumps only.
const REGION_FREQUENCY := 0.00035
const REGION_AMPLITUDE := 300.0
const HILLS_FREQUENCY  := 0.0012
const HILLS_AMPLITUDE  := 240.0
const MICRO_FREQUENCY  := 0.003
const MICRO_AMP_MIN    := 4.0
const MICRO_AMP_MAX    := 22.0

# --- Deterministic noise salts ---
const _SALT_REGION := 100
const _SALT_HILLS  := 101
const _SALT_MICRO  := 102

var region_noise: FastNoiseLite
var hills_noise: FastNoiseLite
var micro_noise: FastNoiseLite
var resolved_seed: int = 0
# Per-homebase (x, height) control points the base-elevation sweep is built from.
var base_controls: Array[Vector2] = []
var ground_points: PackedVector2Array = []
var terrain_body: StaticBody2D
var terrain_polygon: Polygon2D
var terrain_polygons: Array[Polygon2D] = []

# A runway is a flat strip seated on the natural terrain elevation at its
# location (height), so each homebase sits at its own elevation instead of a
# global constant.  start/end are the world-x span; height is the flat
# surface y the plane lands/takes off from.
class Runway:
	var start: float
	var end: float
	var height: float = 0.0
	func _init(s: float, e: float, h: float = 0.0) -> void:
		start = s
		end = e
		height = h

var runways: Array[Runway] = []

@export var ground_color: Color = Color(0.05, 0.30, 0.10)
@export var runway_color: Color = Color(0.35, 0.35, 0.4)

func _ready() -> void:
	runways.append(Runway.new(RUNWAY_START, RUNWAY_END))
	if SvgManager and SvgManager.has_sprite("runway"):
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func generate() -> void:
	_initialize_noise()
	_generate_terrain()
	_create_terrain()

func add_runway(x: float) -> void:
	var runway_start := x
	var runway_end := x + RUNWAY_LENGTH
	var rw := Runway.new(runway_start, runway_end)
	runways.append(rw)
	# _generate_terrain re-seats every runway on the region noise and rebuilds
	# the base sweep, so the new base is folded into the smooth landscape.
	if ground_points.size() > 0:
		_generate_terrain()
		_update_terrain_geometry()
	_create_runway_visual(runway_start, runway_end, rw.height)

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
		_create_runway_visual(runway.start, runway.end, runway.height)

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

func _create_runway_visual(start: float, end: float, height: float = BASE_Y) -> void:
	if SvgManager and SvgManager.has_sprite("runway"):
		var runway_tex = SvgManager.get_sprite("runway")
		if runway_tex:
			var runway_sprite = Sprite2D.new()
			runway_sprite.texture = runway_tex
			runway_sprite.position = Vector2((start + end) * 0.5, height + 15)
			var tex_width = runway_tex.get_width()
			var tex_height = runway_tex.get_height()
			if tex_width > 0 and tex_height > 0:
				runway_sprite.scale = Vector2((end - start) / tex_width, 30.0 / tex_height)
			add_child(runway_sprite)
			return

	var runway := Polygon2D.new()
	runway.polygon = PackedVector2Array([
		Vector2(start, height),
		Vector2(end, height),
		Vector2(end, height + 30),
		Vector2(start, height + 30)
	])
	runway.color = runway_color
	add_child(runway)

func set_noise_seed(seed_value: int) -> void:
	resolved_seed = seed_value
	if region_noise:
		region_noise.seed = TerrainNoise.derive_seed(resolved_seed, _SALT_REGION)
	if hills_noise:
		hills_noise.seed = TerrainNoise.derive_seed(resolved_seed, _SALT_HILLS)
	if micro_noise:
		micro_noise.seed = TerrainNoise.derive_seed(resolved_seed, _SALT_MICRO)

func _initialize_noise() -> void:
	if GameManager and GameManager.terrain_seed != 0:
		resolved_seed = GameManager.terrain_seed
	else:
		resolved_seed = randi()
	region_noise = TerrainNoise.make_noise(
		TerrainNoise.derive_seed(resolved_seed, _SALT_REGION), REGION_FREQUENCY, 2, 0.5)
	hills_noise = TerrainNoise.make_noise(
		TerrainNoise.derive_seed(resolved_seed, _SALT_HILLS), HILLS_FREQUENCY, 3, 0.5)
	micro_noise = TerrainNoise.make_noise(
		TerrainNoise.derive_seed(resolved_seed, _SALT_MICRO), MICRO_FREQUENCY, 4, 0.5)

# Seat every runway on the smooth region noise at its centre and rebuild the
# base-elevation control points (one per runway, sorted by x).  Called from
# _generate_terrain so heights are always fresh, even if runways were
# registered after the initial noise setup or generate() is re-run.
func _seat_runways() -> void:
	base_controls.clear()
	var pts: Array[Vector2] = []
	for rw in runways:
		var center := (rw.start + rw.end) * 0.5
		rw.height = BASE_Y \
			- TerrainNoise.sample_periodic(region_noise, center, TERRAIN_LENGTH) * REGION_AMPLITUDE
		pts.append(Vector2(center, rw.height))
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	base_controls = pts

# Smooth (cosine) sweep THROUGH the per-homebase control points, periodic over
# the map (wraps between the last and first base).  This is what guarantees the
# terrain connects every homebase height with gentle, cliff-free slopes.
func _base_elevation(x: float) -> float:
	var n := base_controls.size()
	if n == 0:
		return BASE_Y
	if n == 1:
		return base_controls[0].y
	x = fposmod(x, TERRAIN_LENGTH)
	for i in range(n):
		var a := base_controls[i]
		var b := base_controls[(i + 1) % n]
		var bx := b.x
		if bx <= a.x:
			bx += TERRAIN_LENGTH
		var xx := x
		if xx < a.x:
			xx += TERRAIN_LENGTH
		if xx >= a.x and xx <= bx:
			var t := (xx - a.x) / (bx - a.x)
			t = t * t * (3.0 - 2.0 * t)   # smoothstep for C1 continuity
			return lerpf(a.y, b.y, t)
	return base_controls[0].y

# Signed height = smooth base sweep (homebase-aligned) + hills + micro bumps.
# The base sweep passes exactly through every runway's height, so the terrain
# is flat at each base and slopes smoothly between them.
func _sample_height(x: float) -> float:
	var hills := TerrainNoise.sample_periodic(hills_noise, x, TERRAIN_LENGTH)
	var rugged := TerrainNoise.smoothstep01(hills * 0.5 + 0.5)
	var micro_amp := lerpf(MICRO_AMP_MIN, MICRO_AMP_MAX, rugged)
	var micro := TerrainNoise.sample_periodic(micro_noise, x, TERRAIN_LENGTH)
	return _base_elevation(x) + hills * HILLS_AMPLITUDE - micro * micro_amp

# 0.0 on any runway span + apron; smoothsteps to 1 over RUNWAY_BLEND_WIDTH.
func _runway_flatness(x: float) -> float:
	var f := 1.0
	for runway in runways:
		var a := runway.start - RUNWAY_APRON
		var b := runway.end + RUNWAY_APRON
		if x >= a and x <= b:
			return 0.0
		var d := minf(absf(x - a), absf(x - b))
		f = minf(f, d / RUNWAY_BLEND_WIDTH)
	return TerrainNoise.smoothstep01(f)

# The flat elevation of the runway whose flat/blend region contains x, or
# BASE_Y when x is fully off-runway (only used while flatness == 0 anyway).
func _runway_height(x: float) -> float:
	for runway in runways:
		if x >= runway.start - RUNWAY_APRON and x <= runway.end + RUNWAY_APRON:
			return runway.height
	return BASE_Y

func _generate_terrain() -> void:
	# (Re)seat every runway on the region noise and rebuild the base sweep so
	# heights are always correct even if runways were added after the initial
	# noise setup or generate() is re-run.
	if region_noise:
		_seat_runways()
	ground_points.clear()
	var num_segments := int(TERRAIN_LENGTH / SEGMENT_WIDTH)
	for i in range(num_segments + 1):
		var x := i * SEGMENT_WIDTH
		var flatness := _runway_flatness(x)
		var rw_height := _runway_height(x)
		# On the runway the surface is flat at this base's specific elevation;
		# off it, blended toward the surrounding terrain (base sweep + hills).
		var y := rw_height if flatness == 0.0 \
			else lerpf(rw_height, _sample_height(x), flatness)
		ground_points.append(Vector2(x, y))

func get_ground_height_at(x: float) -> float:
	if ground_points.size() < 2:
		return BASE_Y
	# Runway surface is this base's specific flat elevation, regardless of
	# sample-grid alignment.
	if is_on_runway(x):
		for runway in runways:
			if x >= runway.start and x <= runway.end:
				return runway.height
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
		if x >= runway.start and x <= runway.end:
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
