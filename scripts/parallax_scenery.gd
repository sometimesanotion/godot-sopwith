## parallax_scenery.gd — static builders for vector parallax content.
## Pure functions only — no node references (same pattern as aerodynamics.gd).
class_name ParallaxScenery

## One-sided ridge silhouette: values mapped [0,1] so the ridge only rises
## above `baseline`.  The first point is at x=0 and the last is at x=`period`
## exactly — required so a ParallaxLayer's motion_mirroring wraps without a
## vertical jump (D3 periodic sampling guarantees the y values match).  The
## segment count is rounded, then the actual step is `period/n` so the loop
## ends precisely on the period even when it isn't a clean multiple of
## `segment_width` (e.g. parallax layer 1: period 1638.4 / seg 32 = 51.2).
static func build_ridge_points(seed: int, period: float, baseline: float,
		amplitude: float, frequency: float, segment_width: float) -> PackedVector2Array:
	var noise := TerrainNoise.make_noise(seed, frequency, 3, 0.5)
	var pts := PackedVector2Array()
	var n := maxi(1, int(round(period / segment_width)))
	var step := period / float(n)
	for i in range(n + 1):
		var x := i * step
		var v := TerrainNoise.sample_periodic(noise, x, period)
		pts.append(Vector2(x, baseline - (v * 0.5 + 0.5) * amplitude))
	return pts

static func make_ridge_polygon(ridge: PackedVector2Array, period: float,
		floor_y: float, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	var pts := ridge.duplicate()
	pts.append(Vector2(period, floor_y))
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

## Translucent ellipse-puff cloud clusters for the fastest parallax layer (D9).
## `seed` is deterministic so the cloud layout matches the world seed; `period`
## is the layer's mirror period (caller passes TERRAIN_LENGTH * scale for the
## target layer).  Clusters span x ∈ [0, period), y ∈ [100, 420] in parallax
## space.  Returns ~3–7 puffs per cluster as Polygon2D children ready to add.
static func build_clouds(seed: int, period: float, count: int) -> Array[Polygon2D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var clouds: Array[Polygon2D] = []
	for i in range(count):
		var cx := rng.randf() * period
		var cy := rng.randf_range(100.0, 420.0)
		var puffs := rng.randi_range(3, 7)
		for j in range(puffs):
			var puff := Polygon2D.new()
			var rx := rng.randf_range(40.0, 110.0)
			var ry := rx * rng.randf_range(0.35, 0.55)
			var center := Vector2(cx + rng.randf_range(-rx, rx) * 1.6,
								  cy + rng.randf_range(-18.0, 18.0))
			var verts := PackedVector2Array()
			for k in range(12):
				var a := TAU * k / 12.0
				verts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
			puff.polygon = verts
			puff.color = Color(1.0, 1.0, 1.0, rng.randf_range(0.35, 0.55))
			clouds.append(puff)
	return clouds
