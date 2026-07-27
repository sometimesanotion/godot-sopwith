extends Node2D
class_name Terrain

# --- World layout ---
const TERRAIN_LENGTH := 16384.0
const TERRAIN_LOW_BOUND := 3000.0
const SEGMENT_WIDTH := 64.0
const BASE_Y := 650.0

# Vertical gradient crest (used at the highest terrain peaks).  Mirrors the
# layer-3 foreground-hill gradient in background.gd: the terrain fill blends
# from ground_crest_color at the highest points down to ground_base_color in the
# valleys / depths, giving the playfield the same depth cue as the parallax.
@export var ground_crest_color: Color = Color(0.10, 0.36, 0.22)
@export var ground_base_color: Color = Color(0.05, 0.17, 0.10)
@export var runway_color: Color = Color(0.35, 0.35, 0.4)

# --- Runway ---
const RUNWAY_START := 5300.0
const RUNWAY_LENGTH := 700.0
const RUNWAY_END := RUNWAY_START + RUNWAY_LENGTH
const RUNWAY_APRON := 320.0
# Flat mesa half-width on each side of a runway.  Every homebase sits on a flat
# strip (runway span + 2*apron) so planes take off and land without meeting a
# cliff.  Between mesas the terrain ramps smoothly (smoothstep, zero slope at
# both ends) from one base elevation to the next — this is what removes the
# mesa/ravine cliffs the old linear blend produced.
const RUNWAY_BLEND_WIDTH := 350.0
# Width over which the HILLS texture ramps from 0 (on the mesa) back to full
# amplitude out in the connecting terrain between bases.

# --- Terrain synthesis (D4 multi-frequency noise) ---
# Three independent layers shape the height:
#   * REGION — a very low-frequency noise.  Its samples at each homebase
#     become that base's elevation, and a smooth curve (straight/cosine slopes)
#     is interpolated THROUGH those per-homebase heights.  This makes the
#     terrain sweep continuously between bases with no cliffs, and every
#     runway sits exactly on the landscape.  Dominant term near homebases — it
#     is the ONLY knob controlling how far apart homebases sit on the Y axis,
#     so a wide amplitude is what gives the world its large-scale ruggedness.
#   * HILLS  — a medium-frequency noise adding the local valleys/hills texture
#     on top of the region sweep (flattened near runways by the blend).
#   * MICRO  — tiny bumps only.
const REGION_FREQUENCY := 0.00035
const REGION_AMPLITUDE := 400.0
# Keep seated runways inside a playable vertical band (well clear of the top
# edge and of TERRAIN_LOW_BOUND) while still allowing a wide Y spread.
const RUNWAY_MIN_Y := 200.0
const RUNWAY_MAX_Y := 1000.0
const HILLS_FREQUENCY  := 0.0012
const HILLS_AMPLITUDE  := 300.0
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

func _ready() -> void:
	runways.append(Runway.new(RUNWAY_START, RUNWAY_END))
	if SvgManager and SvgManager.has_sprite("runway"):
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func generate() -> void:
	_clear_terrain()
	_initialize_noise()
	_generate_terrain()
	_create_terrain()

## Remove all generated scenery, collision, and runways so generate() can
## produce a completely fresh terrain from scratch.  Re-adds the player
## runway (RUNWAY_START) as the sole remaining runway.
func _clear_terrain() -> void:
	for child in get_children():
		child.queue_free()
	runways.clear()
	runways.append(Runway.new(RUNWAY_START, RUNWAY_END))
	terrain_body = null
	terrain_polygon = null
	terrain_polygons.clear()
	ground_points.clear()

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
	# Vertex colors drive the fill (see _update_terrain_geometry), so the flat
	# color is left white and the gradient is supplied per-vertex.
	terrain_polygon.color = Color(1.0, 1.0, 1.0, 1.0)
	add_child(terrain_polygon)

	# Three tiled copies for seamless world wrapping.
	terrain_polygons = [terrain_polygon]
	for offset in [-TERRAIN_LENGTH, TERRAIN_LENGTH]:
		var copy := Polygon2D.new()
		copy.color = Color(1.0, 1.0, 1.0, 1.0)
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

	# Per-vertex vertical gradient (mirrors background.gd layer 3's
	# build_gradient_mountain_polygon): the highest terrain point takes
	# ground_crest_color, the lowest surface point takes ground_base_color, and every
	# other vertex is linearly interpolated by height.  The two floor-closing
	# points use the base color.  `poly.color` is left white so the vertex
	# colors render directly.
	var vcols := PackedColorArray()
	var has_surface := not ground_points.is_empty()
	var peak_y := INF
	var base_y := -INF
	if has_surface:
		for pt in ground_points:
			peak_y = minf(peak_y, pt.y)
			base_y = maxf(base_y, pt.y)
	var span := base_y - peak_y
	if span < 1.0:
		span = 1.0
	if has_surface:
		for pt in ground_points:
			var t := clampf((pt.y - peak_y) / span, 0.0, 1.0)
			vcols.append(ground_crest_color.lerp(ground_base_color, t))
	vcols.append(ground_base_color)   # floor-closing point (TERRAIN_LENGTH, LOW_BOUND)
	vcols.append(ground_base_color)   # floor-closing point (0, LOW_BOUND)

	if terrain_body:
		for child in terrain_body.get_children():
			if child is CollisionPolygon2D:
				child.polygon = poly_points
	for poly in terrain_polygons:
		poly.polygon = poly_points
		poly.vertex_colors = vcols

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

# Seat every runway on the region noise at its centre so each homebase sits at
# its own elevation.  Called from _generate_terrain so heights are always fresh,
# even if runways were registered after the initial noise setup or generate()
# is re-run.
func _seat_runways() -> void:
	if not region_noise:
		return
	for rw in runways:
		var center := (rw.start + rw.end) * 0.5
		var h := BASE_Y \
			- TerrainNoise.sample_periodic(region_noise, center, TERRAIN_LENGTH) * REGION_AMPLITUDE
		rw.height = clampf(h, RUNWAY_MIN_Y, RUNWAY_MAX_Y)

# --- Wrap-safe periodic interval helpers (all coordinates modulo the map) ---
func _in_forward_interval(x: float, start: float, end: float) -> bool:
	var l := fposmod(start, TERRAIN_LENGTH)
	var r := fposmod(end, TERRAIN_LENGTH)
	if l <= r:
		return x >= l and x <= r
	return x >= l or x <= r

func _forward_fraction(x: float, start: float, end: float) -> float:
	var l := fposmod(start, TERRAIN_LENGTH)
	var r := fposmod(end, TERRAIN_LENGTH)
	var span := r - l
	if span <= 0.0:
		span += TERRAIN_LENGTH
	var xx := fposmod(x, TERRAIN_LENGTH)
	if xx < l:
		xx += TERRAIN_LENGTH
	return (xx - l) / span

func _distance_to_interval(x: float, start: float, end: float) -> float:
	if _in_forward_interval(x, start, end):
		return 0.0
	var l := fposmod(start, TERRAIN_LENGTH)
	var r := fposmod(end, TERRAIN_LENGTH)
	var xx := fposmod(x, TERRAIN_LENGTH)
	var d_start := l - xx
	if d_start <= 0.0:
		d_start += TERRAIN_LENGTH
	var d_end := xx - r
	if d_end <= 0.0:
		d_end += TERRAIN_LENGTH
	return minf(d_start, d_end)

# Base elevation: a flat mesa at each runway's height across [start-apron,
# end+apron], joined to the neighbouring bases by a smoothstep ramp (zero slope
# at the mesa edges, so no cliffs).  Periodic: the last base ramps back to the
# first across the x = 0 wrap seam.  With a single runway the whole map is the
# base elevation (hills are layered on separately, see _generate_terrain).
func _base_elevation(x: float) -> float:
	var n := runways.size()
	if n == 0:
		return BASE_Y
	if n == 1:
		return runways[0].height
	var sorted := runways.duplicate()
	sorted.sort_custom(func(a: Runway, b: Runway) -> bool: return a.start < b.start)
	x = fposmod(x, TERRAIN_LENGTH)
	for rw in sorted:
		var l := fposmod(rw.start - RUNWAY_APRON, TERRAIN_LENGTH)
		var r := fposmod(rw.end + RUNWAY_APRON, TERRAIN_LENGTH)
		if _in_forward_interval(x, l, r):
			return rw.height
	for i in range(n):
		var a: Runway = sorted[i]
		var b: Runway = sorted[(i + 1) % n]
		var ar := fposmod(a.end + RUNWAY_APRON, TERRAIN_LENGTH)
		var bl := fposmod(b.start - RUNWAY_APRON, TERRAIN_LENGTH)
		if ar <= bl and _in_forward_interval(x, ar, bl):
			var t := _forward_fraction(x, ar, bl)
			t = t * t * (3.0 - 2.0 * t)   # smoothstep for C1 continuity
			return lerpf(a.height, b.height, t)
	return sorted[0].height

# 0 on any runway mesa, ramping to 1 over RUNWAY_BLEND_WIDTH out into the
# connecting terrain.  Suppresses the HILLS texture right at bases so mesa edges
# never drop into a ravine.
func _hills_factor(x: float) -> float:
	var n := runways.size()
	if n == 0:
		return 1.0
	var sorted := runways.duplicate()
	sorted.sort_custom(func(a: Runway, b: Runway) -> bool: return a.start < b.start)
	var best := 1.0
	for rw in sorted:
		var l := fposmod(rw.start - RUNWAY_APRON, TERRAIN_LENGTH)
		var r := fposmod(rw.end + RUNWAY_APRON, TERRAIN_LENGTH)
		var d := _distance_to_interval(x, l, r)
		best = minf(best, TerrainNoise.smoothstep01(d / RUNWAY_BLEND_WIDTH))
	return best

func _generate_terrain() -> void:
	# (Re)seat every runway on the region noise so heights are always correct
	# even if runways were added after the initial noise setup or generate()
	# is re-run.
	if region_noise:
		_seat_runways()
	ground_points.clear()
	var num_segments := int(TERRAIN_LENGTH / SEGMENT_WIDTH)
	for i in range(num_segments + 1):
		var x := i * SEGMENT_WIDTH
		# Flat mesa at each base: _base_elevation() is the constant runway
		# height across [start-apron, end+apron] (zero slope, exactly matching
		# the runway), and _hills_factor() is 0 there too — so BOTH the hills
		# and the micro texture are fully suppressed on the apron, giving it
		# strictly zero slope relative to the runway.  Both ramp back in
		# (smoothstep) over RUNWAY_BLEND_WIDTH beyond the apron edge.
		var hf := _hills_factor(x)
		var hills := TerrainNoise.sample_periodic(hills_noise, x, TERRAIN_LENGTH)
		var rugged := TerrainNoise.smoothstep01(hills * 0.5 + 0.5)
		var micro_amp := lerpf(MICRO_AMP_MIN, MICRO_AMP_MAX, rugged)
		var micro := TerrainNoise.sample_periodic(micro_noise, x, TERRAIN_LENGTH)
		var y := _base_elevation(x) + (hills * HILLS_AMPLITUDE - micro * micro_amp) * hf
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
