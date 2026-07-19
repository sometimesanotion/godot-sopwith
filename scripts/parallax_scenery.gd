## Static builders for vector parallax content. Pure functions only.
class_name ParallaxScenery

# =============================================================================
# Layer styling constants — Final Atmospheric Depth Palette
# =============================================================================

## Layer 1 (Farthest): Monolithic Alps. Deep regal cobalt blues.
const COBALT_ALPS_CREST := Color(0.08, 0.15, 0.50)
const COBALT_ALPS_BASE  := Color(0.12, 0.20, 0.55)

## Layer 2 (Mid): Misty transition hills.
const MID_MOUNTAIN_CREST := Color(0.12, 0.24, 0.36)
const MID_MOUNTAIN_BASE  := Color(0.16, 0.35, 0.40)

## Layer 3 (Nearest): Foreground backdrop hills.
const FOREGROUND_HILL_CREST := Color(0.10, 0.28, 0.20)
const FOREGROUND_HILL_BASE  := Color(0.12, 0.32, 0.24)

const DEFAULT_SNOW_LINE_Y := 530.0

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

## Minimalist cirrus streaks for distant parallax layers.
## `scale` is an independent per-layer coefficient that expands the streak
## radii/extent (layers tile via motion_mirroring, so oversized streaks simply
## wrap the period). Default 6.0 keeps the design-brief cloud growth.
static func build_cirrus_clouds(seed: int, period: float, count: int,
		alpha: float, cy_min: float, cy_max: float, scale: float = 6.0) -> Array[Polygon2D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var clouds: Array[Polygon2D] = []
	var max_rx := 260.0 * scale
	var reach := max_rx * 1.3 + max_rx
	for i in range(count):
		var cx := reach + rng.randf() * (period - 2.0 * reach)
		var cy := rng.randf_range(cy_min, cy_max)
		var streaks := rng.randi_range(2, 4)
		for s in range(streaks):
			var streak := Polygon2D.new()
			var rx := rng.randf_range(120.0, 260.0) * scale
			var ry := rng.randf_range(5.0, 12.0) * scale
			var sx := cx + rng.randf_range(-rx * 0.3, rx * 0.3)
			var sy := cy + float(s) * rng.randf_range(10.0, 22.0) * scale
			var verts := PackedVector2Array()
			for k in range(16):
				var a := TAU * k / 16.0
				verts.append(Vector2(sx + cos(a) * rx, sy + sin(a) * ry))
			streak.polygon = verts
			streak.color = Color(1.0, 1.0, 1.0, alpha * rng.randf_range(0.7, 1.0))
			clouds.append(streak)
	return clouds
