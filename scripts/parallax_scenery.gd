## parallax_scenery.gd — static builders for vector parallax content.
## Pure functions only — no node references (same pattern as aerodynamics.gd).
class_name ParallaxScenery

# =============================================================================
# Layer styling constants — Final Atmospheric Depth Palette
# =============================================================================

## Layer 1 (Farthest): Monolithic Alps. Deep regal cobalt blues.
const COBALT_ALPS_CREST := Color(0.18, 0.32, 0.58)
const COBALT_ALPS_BASE  := Color(0.24, 0.38, 0.65)

## Layer 2 (Mid): Misty transition hills. Fades from a slightly blue-green peak
## down to a slightly paler, atmospheric green at the base (simulating horizon mist).
const MID_MOUNTAIN_CREST := Color(0.22, 0.44, 0.42)
const MID_MOUNTAIN_BASE  := Color(0.32, 0.52, 0.46)

## Layer 3 (Nearest): Foreground backdrop hills. Deep cobalt blue shades echoing
## the classic game's primary background depth before blending into the real terrain.
const FOREGROUND_HILL_CREST := Color(0.15, 0.28, 0.52)
const FOREGROUND_HILL_BASE  := Color(0.20, 0.35, 0.60)

## Snow line threshold (y) for the cobalt mountain layer.  Ridge vertices
## above this (smaller y) receive a white snow-cap polygon.  Tuned so the
## tallest ~25% of the macro/micro peaks breach it; lower-frequency ridges
## below stay cobalt.
const DEFAULT_SNOW_LINE_Y := 530.0

## Game max altitude in pixels (matches Aerodynamics.ENGINE_CUTOFF_ALTITUDE
## and sky_gradient.gdshader's `max_altitude`).  Used to position the
## flight-ceiling cloud band.
const FLIGHT_CEILING_PX := 2000.0

## World-space pixels per meter (matches Biplane.pixels_per_meter).  Used to
## convert the Layer 3 cloud band's lower altitude bound to world Y.
const METERS_TO_PX := 13.0

## Lower altitude bound of the Layer 3 cumulus band, in meters above ground.
## Clouds stratify seamlessly from this altitude up to the flight-ceiling cap.
const CLOUD_BAND_MIN_ALTITUDE_M := 600.0

## World Y of the Layer 3 cloud band's top edge (600 m above ground).
## World Y grows downward, so the *higher* altitude is the *smaller* y:
##   650 - 600 * 13 = -7150.
const LAYER3_CLOUD_TOP_Y := DEFAULT_GROUND_Y - CLOUD_BAND_MIN_ALTITUDE_M * METERS_TO_PX

## Default ground Y for converting ceiling altitude → world Y.  Mirrors
## Terrain.BASE_Y (650.0); kept local so this module stays node-free.
const DEFAULT_GROUND_Y := 650.0

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

# =============================================================================
# Gradient-filled mountain layer (shared by Layers 2 & 3)
# =============================================================================

## Build a gradient-filled mountain polygon: ridge silhouette closed at
## `floor_y`, filled with a TRUE vertical gradient on per-vertex COLORS
## (not a texture).  Each ridge vertex is tinted by its normalized height in
## the silhouette — the highest peak (smallest y) takes `peak_color` and the
## lowest baseline vertex (largest y) takes `base_color`, with every vertex
## between linearly interpolated.  Godot then blends per fragment, so the
## visible body ranges smoothly from the crest hue down to the haze foot: a
## real bottom→top gradient, no flat crest band, no UV math, no AABB mapping
## pitfalls, and no risk of out-of-range texture sampling bleaching to white.
## `polygon.color` is left at the default (1,1,1,1) so the vertex colors
## render unmodified (the per-vertex color is multiplied by `polygon.color`,
## and white is the identity multiplier).
static func build_gradient_mountain_polygon(ridge: PackedVector2Array, period: float,
		floor_y: float, peak_color: Color, base_color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	var pts := ridge.duplicate()
	# Close the silhouette at its actual right edge (ridge may span several
	# mirror periods; see `build_ridge_points` `repeat` param).
	var end_x := 0.0
	if ridge.size() > 0:
		end_x = ridge[ridge.size() - 1].x
	pts.append(Vector2(end_x, floor_y))
	pts.append(Vector2(0.0, floor_y))
	poly.polygon = pts
	poly.color = Color(1.0, 1.0, 1.0, 1.0)   # identity multiplier for vertex colors
	# Height-based per-vertex coloring.  Find the silhouette's vertical span
	# (peak_y = smallest y, base_y = largest y) and lerp each ridge vertex
	# from peak_color (top) down to base_color (foot) by its normalized y.
	# Both floor-closure vertices are base_color so the below-baseline skirt
	# reads as continuous haze foot — no seam, no white stops.
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
	vcols.append(base_color)   # right floor closure
	vcols.append(base_color)   # left floor closure
	poly.vertex_colors = vcols
	return poly

## Build the snow-cap overlay polygons for the cobalt mountain layer.
## Walks the ridge, groups consecutive vertices above `snow_line_y` (smaller
## y = higher), and emits one white Polygon2D per group: the ridge arc +
## a horizontal closure at the snow line.  Vertices below the line stay
## cobalt.  Returns [] if nothing breaches the alpine threshold.
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
	# Trailing run that ran off the right edge of the ridge.
	if in_run and run.size() >= 2:
		caps.append(_close_snow_run(run, snow_line_y, cap_color))
	return caps

static func _close_snow_run(run: PackedVector2Array, snow_line_y: float,
		cap_color: Color) -> Polygon2D:
	var pts := run.duplicate()
	# Drop down to the snow line on both sides to close the cap into a
	# proper filled polygon.  The two extra points are *below* the ridge arc
	# so the cap reads as a band of white between the snow line and the peaks.
	var last := run[run.size() - 1]
	var first := run[0]
	pts.append(Vector2(last.x, snow_line_y))
	pts.append(Vector2(first.x, snow_line_y))
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = cap_color
	return poly

# =============================================================================
# Cloud geometry helpers (M7 cumulus profile)
# =============================================================================

## Stylized cumulus puff outline: the TOP half (sin(a) < 0 — smaller y is up
## in world space) keeps the full round arc so overlapping puffs stack into
## heavy, billowing crowns, while the BOTTOM half is compressed by
## `bottom_flatten` (0.0 = perfectly flat base, 1.0 = full ellipse).  The
## result is the classic flat-bottomed / dome-topped cumulus silhouette.
static func _cumulus_puff_verts(center: Vector2, rx: float, ry: float,
		vert_count: int, bottom_flatten: float) -> PackedVector2Array:
	var verts := PackedVector2Array()
	for k in range(vert_count):
		var a := TAU * k / float(vert_count)
		var sy := sin(a)
		var vert_scale := 1.0 if sy < 0.0 else bottom_flatten
		verts.append(center + Vector2(cos(a) * rx, sy * ry * vert_scale))
	return verts

# =============================================================================
# Flight-band cumulus (Layer 3 — nearest parallax)
# =============================================================================

## Build massive, translucent cumulus distributed seamlessly through the
## whole flight band: vertically from `band_top_y` (600 m above ground,
## LAYER3_CLOUD_TOP_Y) down to `band_bottom_y` (the flight-ceiling cap,
## DEFAULT_GROUND_Y - FLIGHT_CEILING_PX).  Distribution is uniform — no
## thin ceiling strip.  Each cluster is 4–8 overlapping flat-bottomed
## cumulus puffs at doubled baseline radii (rx 110–260) so they read as
## distinct, massive air masses; per-puff alpha stays in the delicate
## [alpha_min, alpha_max] ≈ [0.1, 0.2] band so the layer reads as light,
## translucent vector air.  All clusters are inset from the period seam so
## mirroring wraps without artifacts.
static func build_ceiling_clouds(seed: int, period: float, band_top_y: float,
		band_bottom_y: float, count: int, alpha_min: float,
		alpha_max: float) -> Array[Polygon2D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var clouds: Array[Polygon2D] = []
	# Seam reach with the doubled radii: max rx (260) × cluster spread (1.4)
	# + one max rx — clusters never cross the mirror-period boundary.
	var reach := 260.0 * 1.4 + 260.0
	for i in range(count):
		var cx := reach + rng.randf() * (period - 2.0 * reach)
		# Uniform stratification across the whole flight band.
		var cy := rng.randf_range(band_top_y, band_bottom_y)
		var puffs := rng.randi_range(4, 8)
		for j in range(puffs):
			var puff := Polygon2D.new()
			var rx := rng.randf_range(110.0, 260.0)       # 2× the old 55–130
			var ry := rx * rng.randf_range(0.5, 0.7)      # rounder crowns
			var center := Vector2(cx + rng.randf_range(-rx, rx) * 1.4,
								  cy + rng.randf_range(-0.35, 0.35) * ry)
			puff.polygon = _cumulus_puff_verts(center, rx, ry, 16, 0.3)
			puff.color = Color(1.0, 1.0, 1.0, rng.randf_range(alpha_min, alpha_max))
			clouds.append(puff)
	return clouds

# =============================================================================
# Stratum clouds (Layer 2 — mid parallax)
# =============================================================================

## Mid-tier stratum: a crisp midpoint between Layer 1's ultra-thin cirrus
## streaks and Layer 3's massive cumulus hills.  Medium vertical thickness
## (ry ≈ 0.35–0.5 · rx), gently rounded tops over flat bases (same cumulus
## profile, less extreme), sprinkled through the middle air corridors
## (cy_min–cy_max) at a low alpha (≈ 0.15).  Seam-safe reach inset as usual.
static func build_stratum_clouds(seed: int, period: float, count: int,
		alpha: float, cy_min: float, cy_max: float) -> Array[Polygon2D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var clouds: Array[Polygon2D] = []
	# Reach: max rx (200) × spread (1.2) + one max rx.
	var reach := 200.0 * 1.2 + 200.0
	for i in range(count):
		var cx := reach + rng.randf() * (period - 2.0 * reach)
		var cy := rng.randf_range(cy_min, cy_max)
		var puffs := rng.randi_range(2, 4)
		for j in range(puffs):
			var puff := Polygon2D.new()
			var rx := rng.randf_range(120.0, 200.0)
			var ry := rx * rng.randf_range(0.35, 0.5)      # medium thickness
			var center := Vector2(cx + rng.randf_range(-rx, rx) * 1.2,
								  cy + rng.randf_range(-0.25, 0.25) * ry)
			puff.polygon = _cumulus_puff_verts(center, rx, ry, 14, 0.4)
			puff.color = Color(1.0, 1.0, 1.0, alpha * rng.randf_range(0.8, 1.0))
			clouds.append(puff)
	return clouds

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
			puff.polygon = _cumulus_puff_verts(center, rx, ry, 14, 0.35)
			puff.color = Color(1.0, 1.0, 1.0, alpha * rng.randf_range(0.8, 1.0))
			clouds.append(puff)
	return clouds

## Minimalist cirrus streaks: a few thin, layered horizontal wisps.  Used on the
## distant parallax layers, where clouds should read as faint, high, layered
## haze rather than puffy volume (T-clouds: "more minimalist and layered cirrus
## in distant layers").  `alpha` is the base opacity; `cy_min`/`cy_max` bound
## the streak center vertically so callers can pin a layer's cirrus to a
## narrow horizon band (M7: Layer 1 horizon hugging, alpha 0.05–0.1).
static func build_cirrus_clouds(seed: int, period: float, count: int,
		alpha: float, cy_min: float = 60.0, cy_max: float = 320.0) -> Array[Polygon2D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var clouds: Array[Polygon2D] = []
	# Inset the cluster center so streaks never cross the period seam (reach
	# ~ rx*1.3 + rx with max rx ≈ 260).
	var reach := 260.0 * 1.3 + 260.0
	for i in range(count):
		var cx := reach + rng.randf() * (period - 2.0 * reach)
		var cy := rng.randf_range(cy_min, cy_max)
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
