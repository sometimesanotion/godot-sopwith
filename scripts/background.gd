extends Node2D
## Sky gradient + 3-layer seed-driven vector parallax.
## generate(seed) called by main.gd after terrain.generate().

const TERRAIN_LENGTH := 16384.0

var sky_layer: CanvasLayer
var sky_rect: ColorRect
var sky_material: ShaderMaterial

var parallax: ParallaxBackground
var _generated := false

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
#
# Gradient colors (CREST/BASE per layer) are defined as named constants in
# parallax_scenery.gd: COBALT_ALPS_*, MID_MOUNTAIN_*, FOREGROUND_HILL_*.
# =============================================================================

# --- Layer 1: Farthest monolithic Alps (slowest, highest, barely tracks) ---
const LAYER1_MOTION_SCALE_X := 0.05
const LAYER1_MOTION_SCALE_Y := 0.25
const LAYER1_BASELINE_Y     := 820.0
const LAYER1_FLOOR_Y        := 1600.0
const LAYER1_AMPLITUDE_PX   := 480.0
const LAYER1_FREQUENCY      := 0.0018
const LAYER1_SEGMENT_PX     := 64.0
const LAYER1_SEED_SALT      := 201
const LAYER1_USE_GRADIENT   := true
const LAYER1_SNOW_LINE_Y    := 400.0   # Y above which snow caps are drawn

# --- Layer 2: Mid misty transition hills ---
const LAYER2_MOTION_SCALE_X := 0.15
const LAYER2_MOTION_SCALE_Y := 0.35
const LAYER2_BASELINE_Y     := 820.0
const LAYER2_FLOOR_Y        := 1600.0
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
const LAYER3_AMPLITUDE_PX   := 110.0
const LAYER3_FREQUENCY      := 0.0035
const LAYER3_SEGMENT_PX     := 64.0
const LAYER3_SEED_SALT      := 203
const LAYER3_USE_GRADIENT   := true

# Assembled per-layer spec consumed by generate(). Built from the named knobs
# above so the build loop stays data-driven while tuning stays self-documenting.
const LAYER_SPECS := [
	{"salt": LAYER1_SEED_SALT, "scale": LAYER1_MOTION_SCALE_X,
	 "v_scale": LAYER1_MOTION_SCALE_Y, "freq": LAYER1_FREQUENCY,
	 "amp": LAYER1_AMPLITUDE_PX, "base": LAYER1_BASELINE_Y,
	 "seg": LAYER1_SEGMENT_PX, "floor": LAYER1_FLOOR_Y,
	 "gradient": LAYER1_USE_GRADIENT,
	 "grad_crest": ParallaxScenery.COBALT_ALPS_CREST,
	 "grad_base": ParallaxScenery.COBALT_ALPS_BASE,
	 "snow": true, "snow_line": LAYER1_SNOW_LINE_Y},
	{"salt": LAYER2_SEED_SALT, "scale": LAYER2_MOTION_SCALE_X,
	 "v_scale": LAYER2_MOTION_SCALE_Y, "freq": LAYER2_FREQUENCY,
	 "amp": LAYER2_AMPLITUDE_PX, "base": LAYER2_BASELINE_Y,
	 "seg": LAYER2_SEGMENT_PX, "floor": LAYER2_FLOOR_Y,
	 "gradient": LAYER2_USE_GRADIENT,
	 "grad_crest": ParallaxScenery.MID_MOUNTAIN_CREST,
	 "grad_base": ParallaxScenery.MID_MOUNTAIN_BASE},
	{"salt": LAYER3_SEED_SALT, "scale": LAYER3_MOTION_SCALE_X,
	 "v_scale": LAYER3_MOTION_SCALE_Y, "freq": LAYER3_FREQUENCY,
	 "amp": LAYER3_AMPLITUDE_PX, "base": LAYER3_BASELINE_Y,
	 "seg": LAYER3_SEGMENT_PX, "floor": LAYER3_FLOOR_Y,
	 "gradient": LAYER3_USE_GRADIENT,
	 "grad_crest": ParallaxScenery.FOREGROUND_HILL_CREST,
	 "grad_base": ParallaxScenery.FOREGROUND_HILL_BASE},
]
const CLOUD_SALT := 204

# =============================================================================
# CLOUD STYLING (per parallax layer)
# =============================================================================
#   type       : "cirrus_narrow" | "stratum" | "ceiling" | "none"
#   count      : number of cloud clusters generated for the layer.
#   alpha*     : opacity (alpha_min/alpha_max range for "ceiling").
#   cy_min/    : vertical band the cloud centers are placed within (Y placement;
#   cy_max       larger Y = lower in the sky).
#   salt_offset : distinguishes each layer's cloud noise from the others.
# =============================================================================
const CLOUD_STYLES := [
	{"type": "cirrus_narrow", "count": 6, "alpha": 0.04, "cy_min": -400.0,
	 "cy_max": 100.0, "salt_offset": 0},
	{"type": "cirrus_narrow", "count": 8, "alpha": 0.02, "cy_min": -200.0,
	 "cy_max": 60.0, "salt_offset": 1},
	{"type": "none", "count": 0, "salt_offset": 2},
]

# Global horizontal-motion multiplier applied to every layer's X scale.
const MOTION_SCALE_X_MUL := 0.5

# Y the sky-gradient shader treats as the ground horizon. Controls how the sky
# darkens with altitude; independent from the terrain's ground height.
const SKY_HORIZON_Y := 800.0

# Default snow line for any non-Layer-1 gradient layer that opts into snow.
const SNOW_LINE_Y := ParallaxScenery.DEFAULT_SNOW_LINE_Y
const CEILING_CLOUD_CEILING_Y := ParallaxScenery.DEFAULT_GROUND_Y \
		- ParallaxScenery.FLIGHT_CEILING_PX
const LAYER3_CLOUD_TOP_Y := ParallaxScenery.LAYER3_CLOUD_TOP_Y

# Viewport coverage for parallax mirroring.
const MIN_ZOOM := 0.3
const MAX_VIEWPORT := 2560.0
const COVER_LOCAL := MAX_VIEWPORT / MIN_ZOOM * 1.4

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
		var period := TERRAIN_LENGTH * s
		var span := _coverage_periods(period)
		var layer := ParallaxLayer.new()
		layer.motion_scale = Vector2(s * MOTION_SCALE_X_MUL, spec["v_scale"])
		layer.motion_mirroring = Vector2(period, 0.0)
		parallax.add_child(layer)
		var ridge := ParallaxScenery.build_ridge_points(
			TerrainNoise.derive_seed(seed, spec["salt"]),
			period, spec["base"], spec["amp"], spec["freq"], spec["seg"], span)
		# Layer body
		var is_gradient: bool = spec.get("gradient", false)
		var body_color: Color
		if is_gradient:
			body_color = spec["grad_crest"]
			layer.add_child(ParallaxScenery.build_gradient_mountain_polygon(
				ridge, period, spec["floor"], spec["grad_crest"], spec["grad_base"]))
		else:
			body_color = spec["color"]
			layer.add_child(ParallaxScenery.make_ridge_polygon(
				ridge, period, spec["floor"], body_color))
			if spec.get("snow", false):
				var snow_line: float = spec.get("snow_line", SNOW_LINE_Y)
				for cap in ParallaxScenery.build_snow_caps(ridge, snow_line):
					layer.add_child(cap)
		# Cloud decoration
		var cstyle: Dictionary = CLOUD_STYLES[i]
		var clouds: Array[Polygon2D] = []
		var cseed: int = TerrainNoise.derive_seed(
			seed, CLOUD_SALT + int(cstyle["salt_offset"]))
		match String(cstyle["type"]):
			"cirrus_narrow":
				clouds = ParallaxScenery.build_cirrus_clouds(
					cseed, period, int(cstyle["count"]), float(cstyle["alpha"]),
					float(cstyle["cy_min"]), float(cstyle["cy_max"]))
			# "stratum":
			# 	clouds = ParallaxScenery.build_stratum_clouds(
			# 		cseed, period, int(cstyle["count"]), float(cstyle["alpha"]),
			# 		float(cstyle["cy_min"]), float(cstyle["cy_max"]))
			# "ceiling":
			# 	clouds = ParallaxScenery.build_ceiling_clouds(
			# 		cseed, period, LAYER3_CLOUD_TOP_Y, CEILING_CLOUD_CEILING_Y,
			# 		int(cstyle["count"]), float(cstyle["alpha_min"]),
			# 		float(cstyle["alpha_max"]))
			"none", "":
				clouds = []
			_:
				push_warning("Background: unknown cloud type '%s' on layer %d"
						% [cstyle["type"], i])
				clouds = []
		for puff in clouds:
			layer.add_child(puff)
