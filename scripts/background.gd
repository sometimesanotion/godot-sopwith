extends Node2D
## Owns the sky gradient (unchanged) and assembles the deterministic, seed-driven
## 3-layer vector parallax (D6–D9, M7 atmospheric re-architecture).  `generate(seed)`
## is called by main.gd after `terrain.generate()`; the seed is the world seed
## so terrain + backdrop agree.

const TERRAIN_LENGTH := 16384.0

var sky_layer: CanvasLayer
var sky_rect: ColorRect
var sky_material: ShaderMaterial

var parallax: ParallaxBackground
var _generated := false

# =============================================================================
# M7 — Parallax layer re-architecture
# =============================================================================
# 3 layers, each with a distinct role (Final Atmospheric Depth Palette):
#   Layer 1 (FARTHEST, scale 0.1): the distant Alps.
#     Deep regal cobalt blues (COBALT_ALPS_CREST → COBALT_ALPS_BASE).
#     Crisp white snow caps on the tallest summits.
#     Minimalist cirrus pinned to a low horizon band.
#   Layer 2 (MID, scale 0.3): misty transition foothills.
#     Blue-green peak to paler atmospheric green base (MID_MOUNTAIN_CREST →
#     MID_MOUNTAIN_BASE), simulating horizon mist.
#   Layer 3 (NEAREST, scale 0.6): foreground backdrop hills.
#     Deep cobalt blue (FOREGROUND_HILL_CREST → FOREGROUND_HILL_BASE)
#     echoing the classic game's primary background depth.
#     Massive translucent cumulus stratify through the flight band above.
# Frequencies: Layer 1 uses 0.0018 for grand monolithic sweeps; Layers 2–3
# use 0.0028 / 0.0035 for rolling intermediate landforms.
# motion_scale.x is halved (D9 / T4: emphasize immense scale, kill
# rapid background shifting); motion_scale.y is unchanged so vertical
# parallax (climb/dive) still tracks the camera at the original rate.

## Parallax layer specifications (D6).  `period = TERRAIN_LENGTH * scale` is the
## mirroring period that makes each layer wrap seamlessly at the map seam.
##
## Per-layer keys:
##   gradient : true → build_gradient_mountain_polygon(peak=grad_crest,
##             foot=grad_base); false → make_ridge_polygon(color) (+ snow).
##   snow     : true → also emit white snow caps above `snow_line`.
##   trim_color : Line2D outline tint (defaults to a lightened crest/body).
const LAYER_SPECS := [
	# Layer 1 — Distant Alps. Freq heavily lowered (0.0018) and Amp increased (380.0)
	# for massive, grand, sweeping monolithic blocks mimicking the original game aesthetic.
	{"salt": 201, "scale": 0.1, "freq": 0.0018, "amp": 380.0, "base": 680.0,
	 "seg": 64.0, "floor": 1400.0, "gradient": true,
	 "grad_crest": ParallaxScenery.COBALT_ALPS_CREST,
	 "grad_base": ParallaxScenery.COBALT_ALPS_BASE,
	 "snow": true, "snow_line": 400.0,
	 "trim_color": Color(0.25, 0.40, 0.68)},
	
	# Layer 2 — Foothills. Mid-frequency, rolling intermediate landforms.
	{"salt": 202, "scale": 0.3, "freq": 0.0028, "amp": 210.0, "base": 680.0,
	 "seg": 56.0, "floor": 1400.0, "gradient": true,
	 "grad_crest": ParallaxScenery.MID_MOUNTAIN_CREST,
	 "grad_base": ParallaxScenery.MID_MOUNTAIN_BASE,
	 "trim_color": Color(0.22, 0.45, 0.50)},
	
	# Layer 3 — Foreground Hills. Low-frequency wide waves that contrast gently with the ground.
	{"salt": 203, "scale": 0.6, "freq": 0.0035, "amp": 110.0, "base": 720.0,
	 "seg": 64.0, "floor": 1400.0, "gradient": true,
	 "grad_crest": ParallaxScenery.FOREGROUND_HILL_CREST,
	 "grad_base": ParallaxScenery.FOREGROUND_HILL_BASE,
	 "trim_color": Color(0.18, 0.44, 0.28)},
]
const CLOUD_SALT := 204

## Per-layer cloud styling (M7).  `type` selects the builder:
##   "cirrus_narrow" → build_cirrus_clouds, pinned to (cy_min, cy_max)
##   "stratum"       → build_stratum_clouds, mid-tier flat-base clouds
##   "none"          → no clouds on this layer
##   "ceiling"       → build_ceiling_clouds, stratified over the flight band
## `salt_offset` keeps each layer's cloud layout independent & deterministic.
const CLOUD_STYLES := [
	# Layer 1: cirrus high in the sky, well ABOVE the cobalt peaks (which
	# span y ≈ [400, 680]).  Pinned to a narrow band (100–300) with very low
	# alpha (0.05–0.1) so the wisps read as faint, distant haze floating over
	# the summits rather than hugging the horizon line.
	{"type": "cirrus_narrow", "count": 6, "alpha": 0.08, "cy_min": 100.0,
	 "cy_max": 300.0, "salt_offset": 0},
	# Layer 2: stratum midpoint — medium-thickness, gently rounded tops over
	# flat bases, filling the middle air corridors between the horizon wisps
	# and the Layer 3 cumulus.  y range sits above the cobalt peaks
	# (base 680 − amp 200 = 480 peak line) so clouds drift over the summits.
	{"type": "stratum", "count": 10, "alpha": 0.15, "cy_min": 80.0,
	 "cy_max": 460.0, "salt_offset": 1},
	# Layer 3: massive translucent cumulus stratified seamlessly from
	# 600 m above ground (LAYER3_CLOUD_TOP_Y) up to the flight-ceiling cap
	# (CEILING_CLOUD_CEILING_Y); alpha held in the delicate 0.1–0.2 range.
	{"type": "ceiling", "count": 20, "alpha_min": 0.1, "alpha_max": 0.2,
	 "salt_offset": 2},
]

## Horizontal motion_scale multiplier (D9).  Halved from 1.0 → 0.5 to
## emphasize immense scale and slow the background shift.  Vertical
## (motion_scale.y) is unchanged so climb/dive still scrolls at the
## original rate.
const MOTION_SCALE_X_MUL := 0.5

## Default snow-line y-threshold: vertices with y < SNOW_LINE_Y receive a
## white snow-cap polygon.  Per-layer `snow_line` in LAYER_SPECS overrides
## this; the value here is the legacy M7 default (top ~25% tier).
const SNOW_LINE_Y := ParallaxScenery.DEFAULT_SNOW_LINE_Y

## Anchor y for the Layer 3 cloud band's bottom edge (the flight-ceiling
## cap).  Computed once from ParallaxScenery constants so background.gd
## stays the single wiring site.
const CEILING_CLOUD_CEILING_Y := ParallaxScenery.DEFAULT_GROUND_Y \
		- ParallaxScenery.FLIGHT_CEILING_PX

## Top edge of the Layer 3 cloud band: 600 m above ground, converted to
## world Y by ParallaxScenery (650 − 600 · 13 = −7150).
const LAYER3_CLOUD_TOP_Y := ParallaxScenery.LAYER3_CLOUD_TOP_Y

## Minimum number of periods a layer tile must span so Godot's parallax
## mirroring always covers the viewport.  Godot computes its mirror repeat from
## the *screen* width and ignores camera zoom, so at the title-screen zoom
## (0.3) the visible world slice is ~2560/0.3 ≈ 8533 local units wide.  We size
## each tile to comfortably exceed that with margin for larger displays.
const MIN_ZOOM := 0.3
const MAX_VIEWPORT := 2560.0
const COVER_LOCAL := MAX_VIEWPORT / MIN_ZOOM * 1.4

func _coverage_periods(period: float) -> int:
	return int(ceil(COVER_LOCAL / period)) + 1

func _ready() -> void:
	# Sky only; parallax waits for the explicit `generate(seed)` call from
	# main.gd so the world seed is shared (D7).  This removes the prior
	# randomize()-driven background that disagreed with the terrain seed (T3).
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
		sky_material.set_shader_parameter("ground_y", 800.0)
		var main_camera = get_tree().get_first_node_in_group("camera")
		if not main_camera:
			var main_node = get_parent()
			if main_node and main_node.has_node("Camera2D"):
				main_camera = main_node.get_node("Camera2D")
		if main_camera:
			sky_material.set_shader_parameter("camera_y", main_camera.position.y)

## Assemble the deterministic, seed-driven 3-layer vector parallax (D6–D9,
## M7).  Called explicitly by main.gd after terrain.generate() so the world
## seed is shared.  Idempotent: the first call builds everything; subsequent
## calls are no-ops.  All children are static — zero per-frame `_draw`
## (D9 / T4 fix).  Per-layer:
##   - LAYER_SPECS[i]           : ridge tuning + fill mode (gradient/solid) + scale
##   - CLOUD_STYLES[i]          : which (if any) cloud builder to call
##   - solid (Layer 1) additionally gets white snow caps above its snow line.
func generate(seed: int) -> void:
	if _generated:
		return
	_generated = true
	parallax = ParallaxBackground.new()
	parallax.layer = -15                       # behind world (0), in front of sky (-20)
	add_child(parallax)
	for i in range(LAYER_SPECS.size()):
		var spec: Dictionary = LAYER_SPECS[i]
		var s: float = spec["scale"]
		var period := TERRAIN_LENGTH * s       # D6 mirroring math
		var span := _coverage_periods(period)  # wide enough to fill the screen
		var layer := ParallaxLayer.new()
		# M7 / D9: halve horizontal motion_scale to slow background scroll;
		# halve vertical motion_scale too to compress layers toward the horizon.
		layer.motion_scale = Vector2(s * MOTION_SCALE_X_MUL, s * 0.5)
		layer.motion_mirroring = Vector2(period, 0.0)
		parallax.add_child(layer)
		var ridge := ParallaxScenery.build_ridge_points(
			TerrainNoise.derive_seed(seed, spec["salt"]),
			period, spec["base"], spec["amp"], spec["freq"], spec["seg"], span)
		# --- Layer body: gradient mountains (all layers) ---
		var is_gradient: bool = spec.get("gradient", false)
		var body_color: Color
		if is_gradient:
			# True vertical gradient: base foot → crest (atmospheric
			# perspective).  Each ridge vertex is tinted by its normalized
			# height (see ParallaxScenery.build_gradient_mountain_polygon) so
			# the body blends crest→foot with no flat band and no white bleed.
			body_color = spec["grad_crest"]
			layer.add_child(ParallaxScenery.build_gradient_mountain_polygon(
				ridge, period, spec["floor"], spec["grad_crest"], spec["grad_base"]))
		else:
			# Solid fill + optional snow caps.
			body_color = spec["color"]
			layer.add_child(ParallaxScenery.make_ridge_polygon(
				ridge, period, spec["floor"], body_color))
			if spec.get("snow", false):
				var snow_line: float = spec.get("snow_line", SNOW_LINE_Y)
				for cap in ParallaxScenery.build_snow_caps(ridge, snow_line):
					layer.add_child(cap)
		# --- Per-layer cloud decoration (M7) ---
		var cstyle: Dictionary = CLOUD_STYLES[i]
		var clouds: Array[Polygon2D] = []
		var cseed: int = TerrainNoise.derive_seed(
			seed, CLOUD_SALT + int(cstyle["salt_offset"]))
		match String(cstyle["type"]):
			"cirrus_narrow":
				clouds = ParallaxScenery.build_cirrus_clouds(
					cseed, period, int(cstyle["count"]), float(cstyle["alpha"]),
					float(cstyle["cy_min"]), float(cstyle["cy_max"]))
			"stratum":
				clouds = ParallaxScenery.build_stratum_clouds(
					cseed, period, int(cstyle["count"]), float(cstyle["alpha"]),
					float(cstyle["cy_min"]), float(cstyle["cy_max"]))
			"ceiling":
				clouds = ParallaxScenery.build_ceiling_clouds(
					cseed, period, LAYER3_CLOUD_TOP_Y, CEILING_CLOUD_CEILING_Y,
					int(cstyle["count"]), float(cstyle["alpha_min"]),
					float(cstyle["alpha_max"]))
			"none", "":
				clouds = []
			_:
				push_warning("Background: unknown cloud type '%s' on layer %d"
						% [cstyle["type"], i])
				clouds = []
		for puff in clouds:
			layer.add_child(puff)
