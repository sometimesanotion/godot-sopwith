## parallax_scenery.gd — static builders for vector parallax content.
## Pure functions only — no node references (same pattern as aerodynamics.gd).
class_name ParallaxScenery

# =============================================================================
# Layer styling constants (M7 atmospheric perspective)
# =============================================================================

## Cobalt peak color — used for the mid-background mountain layer's
## GradientTexture2D top stop and snow-cap trim.  Spec: Color(0.2, 0.3, 0.55).
const COBALT_PEAK_COLOR := Color(0.2, 0.3, 0.55)

## Lighter, hazier blue-grey base stop — fades the mountain's lower polygon
## edge into the sky gradient (atmospheric perspective).
const COBALT_BASE_COLOR := Color(0.55, 0.62, 0.72)

## Snow line threshold (y) for the cobalt mountain layer.  Ridge vertices
## above this (smaller y) receive a white snow-cap polygon.  Tuned so the
## tallest ~25% of the macro/micro peaks breach it; lower-frequency ridges
## below stay cobalt.
const DEFAULT_SNOW_LINE_Y := 530.0

## Game max altitude in pixels (matches Aerodynamics.ENGINE_CUTOFF_ALTITUDE
## and sky_gradient.gdshader's `max_altitude`).  Used to position the
## flight-ceiling cloud band.
const FLIGHT_CEILING_PX := 2000.0

## Vertical band height for the flight-ceiling clouds on the nearest
## parallax layer.  200 m at 13 px/m = 2 600 px would extend below ground
## in this coordinate system, so the band is clamped to a 400 px (~31 m)
## strip that still gives a strong "ceiling" cue when the camera climbs.
## The "200 m below ceiling" intent is preserved as the band's anchor at
## FLIGHT_CEILING_PX (the band is positioned there, not below the ground).
const CEILING_CLOUD_BAND_PX := 400.0

## Bias power for ceiling-cloud y distribution.  > 1 packs clouds toward
## the ceiling (smaller y); < 1 spreads them toward the lower band edge.
## 1.8 gives a heavy cluster in the upper stratosphere with a soft fade.
const CEILING_CLOUD_BIAS_POWER := 1.8

## Default ground Y for converting ceiling altitude → world Y.  Mirrors
## Terrain.BASE_Y (650.0); kept local so this module stays node-free.
const DEFAULT_GROUND_Y := 650.0

## Vertical resolution of the cobalt gradient texture.  256 is enough for a
## smooth C¹ ramp without wasting GPU memory; the polygon's `texture_scale`
## stretches it across the full ridge height.
const COBALT_GRADIENT_HEIGHT := 256

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
# Cobalt mountain layer (Layer 2 — mid background)
# =============================================================================

## Build a vertical GradientTexture2D for the cobalt mountain polygon.
## The texture's TOP samples `peak_color` and the BOTTOM samples `base_color`,
## which (after texture_offset/texture_scale remapping in the caller) places
## the cobalt at the highest ridge vertices and the hazier blue-grey at the
## mountain base.  fill_from/fill_to define a top-to-bottom linear fill so
## the gradient interpolates smoothly along world-y.
static func make_cobalt_gradient(peak_color: Color, base_color: Color,
		width: int = 2, height: int = COBALT_GRADIENT_HEIGHT) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.add_point(0.0, peak_color)
	grad.add_point(1.0, base_color)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = width
	tex.height = height
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)   # top edge → offset 0 → peak_color
	tex.fill_to = Vector2(0.5, 1.0)     # bottom edge → offset 1 → base_color
	return tex

## Build the cobalt mountain polygon: ridge silhouette closed at `floor_y`,
## filled by a vertical gradient (cobalt peak → blue-grey base) that maps
## per-vertex world-y to the texture's vertical axis.  This produces
## atmospheric perspective on a single Polygon2D — no per-vertex colors and
## no shader needed.  `polygon.color` is set to white so the texture is
## rendered unmodified; the texture's own alpha controls coverage.
static func build_cobalt_mountain_polygon(ridge: PackedVector2Array, period: float,
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
	poly.color = Color(1.0, 1.0, 1.0, 1.0)   # texture provides the color
	# Find the highest peak (smallest y) for the texture remap anchor.
	var peak_y: float = INF
	for pt in ridge:
		peak_y = minf(peak_y, pt.y)
	if peak_y >= floor_y:
		peak_y = floor_y - 1.0  # degenerate: no relief, just return as-is
	var tex := make_cobalt_gradient(peak_color, base_color)
	poly.texture = tex
	# UV mapping: polygon y=peak_y → texture y=0 (peak_color);
	#             polygon y=floor_y → texture y=COBALT_GRADIENT_HEIGHT (base_color).
	# Polygon2D uses `uv = (local_pos - texture_offset) / texture_scale`.
	poly.texture_offset = Vector2(0.0, peak_y)
	poly.texture_scale = Vector2(1.0,
			(floor_y - peak_y) / float(COBALT_GRADIENT_HEIGHT))
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
# Flight-ceiling clouds (Layer 3 — nearest parallax)
# =============================================================================

## Build a layer of distinct, semi-transparent white puffy clouds clustered
## heavily in the upper stratosphere.  Each cluster is 4–8 overlapping
## rounded ellipse puffs (16-vertex polygons) sized like small cumulus
## humps, biased toward `ceiling_y` (low y) so the densest concentration
## sits just below the player's maximum altitude.  The band is anchored at
## `ceiling_y` (= DEFAULT_GROUND_Y - FLIGHT_CEILING_PX by default) and
## extends downward by `band_px`.  All clusters stay within the mirror
## period and wrap seamlessly with the rest of the parallax.
static func build_ceiling_clouds(seed: int, period: float, ceiling_y: float,
		band_px: float, count: int, alpha: float) -> Array[Polygon2D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var clouds: Array[Polygon2D] = []
	# Puff reach: max radius × cluster spread + one max radius.  Same math as
	# the cumulus builder so clusters never cross the period seam.
	var reach := 130.0 * 1.4 + 130.0
	for i in range(count):
		var cx := reach + rng.randf() * (period - 2.0 * reach)
		# Bias toward the ceiling: t = u^power, u ~ U(0,1), power > 1 packs
		# mass near t=0 (the ceiling).  Result: cy near ceiling_y, with a
		# soft tail into the lower stratosphere.
		var t := pow(rng.randf(), CEILING_CLOUD_BIAS_POWER)
		var cy := ceiling_y + t * band_px
		var puffs := rng.randi_range(4, 8)
		for j in range(puffs):
			var puff := Polygon2D.new()
			var rx := rng.randf_range(55.0, 130.0)
			var ry := rx * rng.randf_range(0.5, 0.7)        # rounder, puffier
			var center := Vector2(cx + rng.randf_range(-rx, rx) * 1.4,
								  cy + rng.randf_range(-15.0, 15.0))
			var verts := PackedVector2Array()
			for k in range(16):
				var a := TAU * k / 16.0
				verts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
			puff.polygon = verts
			puff.color = Color(1.0, 1.0, 1.0, alpha * rng.randf_range(0.7, 1.0))
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
