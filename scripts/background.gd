extends Node2D
## Sky gradient + 3-layer seed-driven vector parallax.
## generate(seed) called by main.gd after terrain.generate().

const TERRAIN_LENGTH := 16384.0

# =============================================================================
# PALETTE CONSTANTS — Final Atmospheric Depth Palette
# =============================================================================
## Layer 1 (Farthest): Monolithic Alps. Deep regal cobalt blues.
const COBALT_ALPS_CREST := Color(0.06, 0.14, 0.48)
const COBALT_ALPS_BASE  := Color(0.10, 0.22, 0.55)

## Layer 2 (Mid): Misty transition hills.
const MID_MOUNTAIN_CREST := Color(0.10, 0.25, 0.42)
const MID_MOUNTAIN_BASE  := Color(0.08, 0.24, 0.36)

## Layer 3 (Nearest): Foreground backdrop hills.
const FOREGROUND_HILL_CREST := Color(0.10, 0.30, 0.25)
const FOREGROUND_HILL_BASE  := Color(0.12, 0.26, 0.20)

const DEFAULT_SNOW_LINE_Y := 600.0

# =============================================================================
# PARALLAX LAYER TUNING  (edit these to retune the background)
# =============================================================================
# Every background-layer placement and camera-tracking knob lives here so a
# human coder can adjust the scenery without touching the build code.
#
#   *_MOTION_SCALE_X : horizontal scroll factor vs. the camera
#                      (0 = static, 1 = locked to the foreground world).
#   *_MOTION_SCALE_Y : vertical camera-follow factor — how fast the layer tracks
#                      the camera up/down (0 = fixed; far layers barely move).
#   *_BASELINE_Y     : initial Y of the ridge silhouette (larger Y = lower).
#   *_FLOOR_Y        : Y the ridge polygon is closed down to (fills below hills).
#   *_AMPLITUDE_PX   : vertical height of the ridge noise.
#   *_FREQUENCY      : ridge noise frequency (smaller = broader, smoother hills).
#   *_SEGMENT_PX     : horizontal sampling step of the silhouette.
#   *_SEED_SALT      : deterministic per-layer noise seed offset.
#   *_USE_GRADIENT   : true = vertical color gradient, false = flat `color`.
# =============================================================================

# --- Layer 1: Farthest monolithic Alps (slowest, highest, barely tracks) ---
const LAYER1_MOTION_SCALE_X := 0.05
const LAYER1_MOTION_SCALE_Y := 0.25
const LAYER1_BASELINE_Y     := 850.0
const LAYER1_FLOOR_Y        := 1200.0
# PERIOD is the repeating width of the silhouette (and the parallax mirror
# distance).  It is its OWN knob — NOT derived from MOTION_SCALE_X — so widening
# the pattern does not change how fast the layer pans with the camera.  The old
# value was TERRAIN_LENGTH*MOTION_SCALE_X = 819 px, which tiled ~14× across the
# background; the wider value below repeats only ~2× and stays seamless.
const LAYER1_PERIOD         := 4000.0
# ZOOM: vertical scale of the range.  Larger amplitude = taller, more imposing
# (more "zoomed-in") alps.  LAYER1_FREQUENCY is the horizontal detail/zoom knob
# (smaller = broader, smoother mountains).
const LAYER1_AMPLITUDE_PX   := 500.0
const LAYER1_FREQUENCY      := 0.0018
const LAYER1_SEGMENT_PX     := 64.0
const LAYER1_SEED_SALT      := 201
const LAYER1_USE_GRADIENT   := true
const LAYER1_SNOW_LINE_Y    := 400.0   # Y above which snow caps are drawn

# --- Layer 2: Mid misty transition hills ---
const LAYER2_MOTION_SCALE_X := 0.15
const LAYER2_MOTION_SCALE_Y := 0.35
const LAYER2_BASELINE_Y     := 820.0
const LAYER2_FLOOR_Y        := 1400.0
const LAYER2_PERIOD         := 8000.0
const LAYER2_AMPLITUDE_PX   := 210.0
const LAYER2_FREQUENCY      := 0.0028
const LAYER2_SEGMENT_PX     := 56.0
const LAYER2_SEED_SALT      := 202
const LAYER2_USE_GRADIENT   := true

# --- Layer 3: Nearest foreground hills (fastest, tracks closest) ---
const LAYER3_MOTION_SCALE_X := 0.3
const LAYER3_MOTION_SCALE_Y := 0.5
const LAYER3_BASELINE_Y     := 800.0
const LAYER3_FLOOR_Y        := 1600.0
const LAYER3_PERIOD         := 12000.0
const LAYER3_AMPLITUDE_PX   := 110.0
const LAYER3_FREQUENCY      := 0.0035
const LAYER3_SEGMENT_PX     := 64.0
const LAYER3_SEED_SALT      := 203
const LAYER3_USE_GRADIENT   := true

# Assembled per-layer spec consumed by generate(). Built from the named knobs
# above so the build loop stays data-driven while tuning stays self-documenting.
const LAYER_SPECS := [
	{"salt": LAYER1_SEED_SALT, "scale": LAYER1_MOTION_SCALE_X,
	 "period": LAYER1_PERIOD,
	 "v_scale": LAYER1_MOTION_SCALE_Y, "freq": LAYER1_FREQUENCY,
	 "amp": LAYER1_AMPLITUDE_PX, "base": LAYER1_BASELINE_Y,
	 "seg": LAYER1_SEGMENT_PX, "floor": LAYER1_FLOOR_Y,
	 "gradient": LAYER1_USE_GRADIENT,
	 "grad_crest": COBALT_ALPS_CREST, "grad_base": COBALT_ALPS_BASE,
	 "snow": true, "snow_line": LAYER1_SNOW_LINE_Y},
	{"salt": LAYER2_SEED_SALT, "scale": LAYER2_MOTION_SCALE_X,
	 "period": LAYER2_PERIOD,
	 "v_scale": LAYER2_MOTION_SCALE_Y, "freq": LAYER2_FREQUENCY,
	 "amp": LAYER2_AMPLITUDE_PX, "base": LAYER2_BASELINE_Y,
	 "seg": LAYER2_SEGMENT_PX, "floor": LAYER2_FLOOR_Y,
	 "gradient": LAYER2_USE_GRADIENT,
	 "grad_crest": MID_MOUNTAIN_CREST, "grad_base": MID_MOUNTAIN_BASE},
	{"salt": LAYER3_SEED_SALT, "scale": LAYER3_MOTION_SCALE_X,
	 "period": LAYER3_PERIOD,
	 "v_scale": LAYER3_MOTION_SCALE_Y, "freq": LAYER3_FREQUENCY,
	 "amp": LAYER3_AMPLITUDE_PX, "base": LAYER3_BASELINE_Y,
	 "seg": LAYER3_SEGMENT_PX, "floor": LAYER3_FLOOR_Y,
	 "gradient": LAYER3_USE_GRADIENT,
	 "grad_crest": FOREGROUND_HILL_CREST, "grad_base": FOREGROUND_HILL_BASE},
]

# =============================================================================
# CLOUD STYLING (per parallax layer)
# =============================================================================
# Only cirrus streaks are used. Each entry is the cloud config for the matching
# layer index; `count == 0` disables clouds for that layer (Layer 3 here).
#   count   : number of cirrus clusters generated for the layer.
#   alpha   : opacity multiplier for the streaks.
#   cy_min/ : vertical band the streak centers are placed within (Y placement;
#   cy_max   larger Y = lower in the sky).
#   salt_offset : distinguishes each layer's cloud noise from the others.
#   scale   : independent per-layer cloud scale coefficient (see
#             build_cirrus_clouds).
# =============================================================================
const CLOUD_SALT := 204
const CLOUD_LAYERS := [
	{"count": 6, "alpha": 0.04, "cy_min": -400.0, "cy_max": 100.0,
	 "salt_offset": 0, "scale": 6.0},
	{"count": 8, "alpha": 0.02, "cy_min": -200.0, "cy_max": 60.0,
	 "salt_offset": 1, "scale": 6.0},
	{"count": 0, "salt_offset": 2, "scale": 6.0},
]

# Global horizontal-motion multiplier applied to every layer's X scale.
const MOTION_SCALE_X_MUL := 0.5

# Y the sky-gradient shader treats as the ground horizon. Controls how the sky
# darkens with altitude; independent from the terrain's ground height.
const SKY_HORIZON_Y := 800.0

# Default snow line for any non-Layer-1 gradient layer that opts into snow.
const SNOW_LINE_Y := DEFAULT_SNOW_LINE_Y

# Viewport coverage for parallax mirroring.
const MIN_ZOOM := 0.3
const MAX_VIEWPORT := 2560.0
const COVER_LOCAL := MAX_VIEWPORT / MIN_ZOOM * 1.4

# =============================================================================
# Runtime state
# =============================================================================
var sky_layer: CanvasLayer
var sky_rect: ColorRect
var sky_material: ShaderMaterial

var parallax: ParallaxBackground
var _generated := false

# =============================================================================
# Instance methods
# =============================================================================

func _coverage_periods(period: float) -> int:
	return int(ceil(COVER_LOCAL / period)) + 1

func _ready() -> void:
	_create_sky_gradient()

func _create_sky_gradient() -> void:
	var sky_shader := load("res://shaders/sky_gradient.gdshader")
	sky_material = ShaderMaterial.new()
	sky_material.shader = sky_shader

	sky_layer = CanvasLayer.new()
	sky_layer.layer = -20
	add_child(sky_layer)

	sky_rect = ColorRect.new()
	sky_rect.material = sky_material
	sky_rect.anchors_preset = Control.PRESET_FULL_RECT
	sky_rect.size = get_viewport_rect().size
	sky_layer.add_child(sky_rect)

func _process(_delta: float) -> void:
	if sky_rect and sky_rect.size != get_viewport_rect().size:
		sky_rect.size = get_viewport_rect().size
	if sky_material:
		sky_material.set_shader_parameter("ground_y", SKY_HORIZON_Y)
	var main_camera = get_tree().get_first_node_in_group("camera")
	if not main_camera:
		var main_node = get_parent()
		if main_node and main_node.has_node("Camera2D"):
			main_camera = main_node.get_node("Camera2D")
	if main_camera:
		sky_material.set_shader_parameter("camera_y", main_camera.position.y)

## Build the 3-layer parallax. Idempotent — first call builds, subsequent are no-ops.
func generate(seed: int) -> void:
	if _generated:
		return
	_generated = true
	parallax = ParallaxBackground.new()
	parallax.layer = -15
	add_child(parallax)
	for i in range(LAYER_SPECS.size()):
		var spec: Dictionary = LAYER_SPECS[i]
		var s: float = spec["scale"]
		# Period is a dedicated knob (decoupled from motion_scale): widening the
		# silhouette's repeating width must not change how fast the layer pans
		# with the camera.  Layers without an explicit "period" fall back to the
		# legacy TERRAIN_LENGTH*scale.
		var period := float(spec.get("period", TERRAIN_LENGTH * s))
		var span := _coverage_periods(period)
		var layer := ParallaxLayer.new()
		layer.motion_scale = Vector2(s * MOTION_SCALE_X_MUL, spec["v_scale"])
		layer.motion_mirroring = Vector2(period, 0.0)
		parallax.add_child(layer)
		var ridge := build_ridge_points(
			TerrainNoise.derive_seed(seed, spec["salt"]),
			period, spec["base"], spec["amp"], spec["freq"], spec["seg"], span)
		# Layer body
		var is_gradient: bool = spec.get("gradient", false)
		var body_color: Color
		if is_gradient:
			body_color = spec["grad_crest"]
			layer.add_child(build_gradient_mountain_polygon(
				ridge, period, spec["floor"], spec["grad_crest"], spec["grad_base"]))
		else:
			body_color = spec["color"]
			layer.add_child(make_ridge_polygon(
				ridge, period, spec["floor"], body_color))
			if spec.get("snow", false):
				var snow_line: float = spec.get("snow_line", SNOW_LINE_Y)
				for cap in build_snow_caps(ridge, snow_line):
					layer.add_child(cap)
		# Cloud decoration (cirrus only; count == 0 disables a layer)
		var cstyle: Dictionary = CLOUD_LAYERS[i]
		var ccount: int = cstyle["count"]
		if ccount > 0:
			var cseed: int = TerrainNoise.derive_seed(
				seed, CLOUD_SALT + int(cstyle["salt_offset"]))
			var clouds := build_cirrus_clouds(
				cseed, period, ccount, float(cstyle["alpha"]),
				float(cstyle["cy_min"]), float(cstyle["cy_max"]),
				float(cstyle["scale"]))
			for puff in clouds:
				layer.add_child(puff)

# =============================================================================
# Static vector-parallax builders (pure functions; no node references)
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
