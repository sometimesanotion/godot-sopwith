## parallax_scenery.gd — static builders for vector parallax content.
## Pure functions only — no node references (same pattern as aerodynamics.gd).
class_name ParallaxScenery

## One-sided ridge silhouette: values mapped [0,1] so the ridge only rises
## above `baseline`.  The silhouette is periodic with `period`, so the first
## point (x=0) and the point at every multiple of `period` share the same y —
## required so a ParallaxLayer's motion_mirroring wraps without a vertical jump
## (D3 periodic sampling).  `repeat` tiles the silhouette that many periods
## wide so a single layer tile always covers the whole viewport, even at the
## title-screen zoom-out (camera.zoom = 0.3) where Godot's parallax mirroring
## under-counts copies because it computes the repeat from the *screen* width
## and ignores the camera zoom (T-parallax bug).  The seam duplicate at each
## period boundary is skipped so the tiled polygon has no degenerate vertices.
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
				continue            # duplicate of previous period's last point
			var x := k * period + j * step
			var v := TerrainNoise.sample_periodic(noise, x, period)
			pts.append(Vector2(x, baseline - (v * 0.5 + 0.5) * amplitude))
	return pts

static func make_ridge_polygon(ridge: PackedVector2Array, period: float,
		floor_y: float, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	var pts := ridge.duplicate()
	# `ridge` may span several periods (see build_ridge_points `repeat`); close
	# the silhouette at its actual right edge rather than assuming a single
	# `period` width.
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

## Puffy cumulus clusters: overlapping rounded ellipse puffs.  `alpha` is the
## base opacity and `puff_scale` scales puff size.  Used on the nearer parallax
## layers, where clouds should read as soft, voluminous and very translucent
## (T-clouds: "more translucent and puffy in nearer layers").
## `seed` is deterministic (caller derives a per-layer salt); `period` is the
## layer's mirror period.  Clusters span x ∈ [0, period), y ∈ [120, 460].
static func build_cumulus_clouds(seed: int, period: float, count: int,
		alpha: float, puff_scale: float) -> Array[Polygon2D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var clouds: Array[Polygon2D] = []
	# Inset the cluster center so puffs never cross the period seam (keeps the
	# whole cloud inside one tile; reach ~ rx*1.6 + rx with max rx ≈ 121*puff_scale).
	var reach := 121.0 * puff_scale * 1.6 + 121.0 * puff_scale
	for i in range(count):
		var cx := reach + rng.randf() * (period - 2.0 * reach)
		var cy := rng.randf_range(120.0, 460.0)
		var puffs := rng.randi_range(3, 7)
		for j in range(puffs):
			var puff := Polygon2D.new()
			var rx := rng.randf_range(40.0, 110.0) * puff_scale
			var ry := rx * rng.randf_range(0.45, 0.65)        # rounder = puffier
			var center := Vector2(cx + rng.randf_range(-rx, rx) * 1.6,
								  cy + rng.randf_range(-18.0, 18.0))
			var verts := PackedVector2Array()
			for k in range(14):
				var a := TAU * k / 14.0
				verts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
			puff.polygon = verts
			puff.color = Color(1.0, 1.0, 1.0, alpha * rng.randf_range(0.8, 1.0))
			clouds.append(puff)
	return clouds

## Minimalist cirrus streaks: a few thin, layered horizontal wisps.  Used on the
## distant parallax layers, where clouds should read as faint, high, layered
## haze rather than puffy volume (T-clouds: "more minimalist and layered cirrus
## in distant layers").  `alpha` is the base opacity.
static func build_cirrus_clouds(seed: int, period: float, count: int,
		alpha: float) -> Array[Polygon2D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var clouds: Array[Polygon2D] = []
	# Inset the cluster center so streaks never cross the period seam (reach
	# ~ rx*1.3 + rx with max rx ≈ 260).
	var reach := 260.0 * 1.3 + 260.0
	for i in range(count):
		var cx := reach + rng.randf() * (period - 2.0 * reach)
		var cy := rng.randf_range(60.0, 320.0)
		var streaks := rng.randi_range(2, 4)
		for s in range(streaks):
			var streak := Polygon2D.new()
			var rx := rng.randf_range(120.0, 260.0)
			var ry := rng.randf_range(5.0, 12.0)             # thin wisp
			var sx := cx + rng.randf_range(-rx * 0.3, rx * 0.3)
			var sy := cy + float(s) * rng.randf_range(10.0, 22.0)   # layered
			var verts := PackedVector2Array()
			for k in range(16):
				var a := TAU * k / 16.0
				verts.append(Vector2(sx + cos(a) * rx, sy + sin(a) * ry))
			streak.polygon = verts
			streak.color = Color(1.0, 1.0, 1.0, alpha * rng.randf_range(0.7, 1.0))
			clouds.append(streak)
	return clouds
