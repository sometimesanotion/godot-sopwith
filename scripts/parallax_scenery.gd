## Static builders for vector parallax content. Pure functions only.
class_name ParallaxScenery

# =============================================================================
# Layer styling constants — Final Atmospheric Depth Palette
# =============================================================================

## Layer 1 (Farthest): Monolithic Alps. Deep regal cobalt blues.
const COBALT_ALPS_CREST := Color(0.08, 0.15, 0.50)
const COBALT_ALPS_BASE  := Color(0.12, 0.20, 0.55)

## Layer 2 (Mid): Misty transition hills.
const MID_MOUNTAIN_CREST := Color(0.10, 0.24, 0.36)
const MID_MOUNTAIN_BASE  := Color(0.15, 0.35, 0.40)

## Layer 3 (Nearest): Foreground backdrop hills.
const FOREGROUND_HILL_CREST := Color(0.08, 0.26, 0.14)
const FOREGROUND_HILL_BASE  := Color(0.10, 0.32, 0.22)

const DEFAULT_SNOW_LINE_Y := 530.0
const FLIGHT_CEILING_PX := 2000.0
const METERS_TO_PX := 13.0
const CLOUD_BAND_MIN_ALTITUDE_M := 600.0
const LAYER3_CLOUD_TOP_Y := DEFAULT_GROUND_Y - CLOUD_BAND_MIN_ALTITUDE_M * METERS_TO_PX
const DEFAULT_GROUND_Y := 650.0

# =============================================================================
# Ridge / polygon builders
# =============================================================================

## One-sided ridge silhouette. Periodic with `period` so motion_mirroring wraps
## without a vertical jump. `repeat` tiles the silhouette for viewport coverage.
static func build_ridge_points(seed: int, period: float, baseline: float,
		amplitude: float, frequency: float, segment_width: float,
		repeat: int = 1) -> PackedVector2Array:
	var noise := TerrainNoise.make_noise(seed, frequency, 3, 0.5)
	var pts := PackedVector2Array()
	var n := maxi(1, int(round(period / segment_width)))
	var step := period / float(n)
	for k in range(repeat):
		for j in range(0, n + 1):
			if k > 0 and j == 0:
				continue
			var x := k * period + j * step
			var v := TerrainNoise.sample_periodic(noise, x, period)
			pts.append(Vector2(x, baseline - (v * 0.5 + 0.5) * amplitude))
	return pts

static func make_ridge_polygon(ridge: PackedVector2Array, period: float,
		floor_y: float, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	var pts := ridge.duplicate()
	var end_x := 0.0
	if ridge.size() > 0:
		end_x = ridge[ridge.size() - 1].x
	pts.append(Vector2(end_x, floor_y))
	pts.append(Vector2(0.0, floor_y))
	poly.polygon = pts
	poly.color = color
	return poly

static func make_trim_line(ridge: PackedVector2Array, color: Color,
		width := 2.5) -> Line2D:
	var line := Line2D.new()
	line.points = ridge
	line.default_color = color.lightened(0.15)
	line.width = width
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	return line

# =============================================================================
# Gradient-filled mountain layer
# =============================================================================

## Ridge silhouette with per-vertex vertical gradient. Highest peak takes
## `peak_color`, lowest baseline takes `base_color`, all others linearly
## interpolated. `polygon.color` left at white so vertex colors render directly.
static func build_gradient_mountain_polygon(ridge: PackedVector2Array, period: float,
		floor_y: float, peak_color: Color, base_color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	var pts := ridge.duplicate()
	var end_x := 0.0
	if ridge.size() > 0:
		end_x = ridge[ridge.size() - 1].x
	pts.append(Vector2(end_x, floor_y))
	pts.append(Vector2(0.0, floor_y))
	poly.polygon = pts
	poly.color = Color(1.0, 1.0, 1.0, 1.0)
	var vcols := PackedColorArray()
	if ridge.is_empty():
		poly.vertex_colors = vcols
		return poly
	var peak_y := INF
	var base_y := -INF
	for pt in ridge:
		peak_y = minf(peak_y, pt.y)
		base_y = maxf(base_y, pt.y)
	var span := base_y - peak_y
	if span < 1.0:
		span = 1.0
	for pt in ridge:
		var t := clampf((pt.y - peak_y) / span, 0.0, 1.0)
		vcols.append(peak_color.lerp(base_color, t))
	vcols.append(base_color)
	vcols.append(base_color)
	poly.vertex_colors = vcols
	return poly

# =============================================================================
# Snow caps
# =============================================================================

## White snow-cap polygons for vertices above `snow_line_y`.
static func build_snow_caps(ridge: PackedVector2Array, snow_line_y: float,
		cap_color: Color = Color(1.0, 1.0, 1.0, 1.0)) -> Array[Polygon2D]:
	var caps: Array[Polygon2D] = []
	var run: PackedVector2Array = PackedVector2Array()
	var in_run := false
	for pt in ridge:
		if pt.y < snow_line_y:
			run.append(pt)
			in_run = true
		else:
			if in_run and run.size() >= 2:
				caps.append(_close_snow_run(run, snow_line_y, cap_color))
			run = PackedVector2Array()
			in_run = false
	if in_run and run.size() >= 2:
		caps.append(_close_snow_run(run, snow_line_y, cap_color))
	return caps

static func _close_snow_run(run: PackedVector2Array, snow_line_y: float,
		cap_color: Color) -> Polygon2D:
	var pts := run.duplicate()
	var last := run[run.size() - 1]
	var first := run[0]
	pts.append(Vector2(last.x, snow_line_y))
	pts.append(Vector2(first.x, snow_line_y))
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = cap_color
	return poly

# =============================================================================
# Cloud geometry
# =============================================================================

## Flat-bottomed / dome-topped cumulus silhouette.
static func _cumulus_puff_verts(center: Vector2, rx: float, ry: float,
		vert_count: int, bottom_flatten: float) -> PackedVector2Array:
	var verts := PackedVector2Array()
	for k in range(vert_count):
		var a := TAU * k / float(vert_count)
		var sy := sin(a)
		var vert_scale := 1.0 if sy < 0.0 else bottom_flatten
		verts.append(center + Vector2(cos(a) * rx, sy * ry * vert_scale))
	return verts

## Massive translucent cumulus stratified through the flight band.
static func build_ceiling_clouds(seed: int, period: float, band_top_y: float,
		band_bottom_y: float, count: int, alpha_min: float,
		alpha_max: float) -> Array[Polygon2D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var clouds: Array[Polygon2D] = []
	var reach := 260.0 * 1.4 + 260.0
	for i in range(count):
		var cx := reach + rng.randf() * (period - 2.0 * reach)
		var cy := rng.randf_range(band_top_y, band_bottom_y)
		var puffs := rng.randi_range(4, 8)
		for j in range(puffs):
			var puff := Polygon2D.new()
			var rx := rng.randf_range(110.0, 260.0)
			var ry := rx * rng.randf_range(0.5, 0.7)
			var center := Vector2(cx + rng.randf_range(-rx, rx) * 1.4,
								  cy + rng.randf_range(-0.35, 0.35) * ry)
			puff.polygon = _cumulus_puff_verts(center, rx, ry, 16, 0.3)
			puff.color = Color(1.0, 1.0, 1.0, rng.randf_range(alpha_min, alpha_max))
			clouds.append(puff)
	return clouds

## Mid-tier stratum clouds for the middle parallax layer.
static func build_stratum_clouds(seed: int, period: float, count: int,
		alpha: float, cy_min: float, cy_max: float) -> Array[Polygon2D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var clouds: Array[Polygon2D] = []
	var reach := 200.0 * 1.2 + 200.0
	for i in range(count):
		var cx := reach + rng.randf() * (period - 2.0 * reach)
		var cy := rng.randf_range(cy_min, cy_max)
		var puffs := rng.randi_range(2, 4)
		for j in range(puffs):
			var puff := Polygon2D.new()
			var rx := rng.randf_range(120.0, 200.0)
			var ry := rx * rng.randf_range(0.35, 0.5)
			var center := Vector2(cx + rng.randf_range(-rx, rx) * 1.2,
								  cy + rng.randf_range(-0.25, 0.25) * ry)
			puff.polygon = _cumulus_puff_verts(center, rx, ry, 14, 0.4)
			puff.color = Color(1.0, 1.0, 1.0, alpha * rng.randf_range(0.8, 1.0))
			clouds.append(puff)
	return clouds

## Puffy cumulus clusters for nearer parallax layers.
static func build_cumulus_clouds(seed: int, period: float, count: int,
		alpha: float, puff_scale: float) -> Array[Polygon2D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var clouds: Array[Polygon2D] = []
	var reach := 121.0 * puff_scale * 1.6 + 121.0 * puff_scale
	for i in range(count):
		var cx := reach + rng.randf() * (period - 2.0 * reach)
		var cy := rng.randf_range(120.0, 460.0)
		var puffs := rng.randi_range(3, 7)
		for j in range(puffs):
			var puff := Polygon2D.new()
			var rx := rng.randf_range(40.0, 110.0) * puff_scale
			var ry := rx * rng.randf_range(0.45, 0.65)
			var center := Vector2(cx + rng.randf_range(-rx, rx) * 1.6,
								  cy + rng.randf_range(-18.0, 18.0))
			puff.polygon = _cumulus_puff_verts(center, rx, ry, 14, 0.35)
			puff.color = Color(1.0, 1.0, 1.0, alpha * rng.randf_range(0.8, 1.0))
			clouds.append(puff)
	return clouds

## Minimalist cirrus streaks for distant parallax layers.
static func build_cirrus_clouds(seed: int, period: float, count: int,
		alpha: float, cy_min: float = 60.0, cy_max: float = 320.0) -> Array[Polygon2D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var clouds: Array[Polygon2D] = []
	var reach := 260.0 * 1.3 + 260.0
	for i in range(count):
		var cx := reach + rng.randf() * (period - 2.0 * reach)
		var cy := rng.randf_range(cy_min, cy_max)
		var streaks := rng.randi_range(2, 4)
		for s in range(streaks):
			var streak := Polygon2D.new()
			var rx := rng.randf_range(120.0, 260.0)
			var ry := rng.randf_range(5.0, 12.0)
			var sx := cx + rng.randf_range(-rx * 0.3, rx * 0.3)
			var sy := cy + float(s) * rng.randf_range(10.0, 22.0)
			var verts := PackedVector2Array()
			for k in range(16):
				var a := TAU * k / 16.0
				verts.append(Vector2(sx + cos(a) * rx, sy + sin(a) * ry))
			streak.polygon = verts
			streak.color = Color(1.0, 1.0, 1.0, alpha * rng.randf_range(0.7, 1.0))
			clouds.append(streak)
	return clouds
