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
# 3 layers, each with a distinct role:
#   Layer 1 (FARTHEST, scale 0.1): distant sky & low clouds.
#     Subtle ridge that recedes into the horizon, minimalist cirrus
#     pinned to a narrow y-band just above the mountain base.
#   Layer 2 (MID, scale 0.3): cobalt mountains & snow peaks.
#     Single Polygon2D filled with a vertical GradientTexture2D
#     (cobalt peak → blue-grey base = atmospheric perspective) plus
#     per-peak white snow caps above the snow line.  No clouds.
#   Layer 3 (NEAREST, scale 0.6): foreground parallax & flight-ceiling cue.
#     Soft green-blue low hills, with distinct puffy white clouds
#     clustered heavily in the upper stratosphere as a visual
#     stall/ceiling indicator for the player.
# Frequencies have been lowered (0.002 / 0.003 / 0.004) for majestic,
# sweeping ridges instead of splintered peaks.
# motion_scale.x is halved (D9 / T4: emphasize immense scale, kill
# rapid background shifting); motion_scale.y is unchanged so vertical
# parallax (climb/dive) still tracks the camera at the original rate.

## Parallax layer specifications (D6).  `period = TERRAIN_LENGTH * scale` is the
## mirroring period that makes each layer wrap seamlessly at the map seam.
const LAYER_SPECS := [
	# Layer 1 — Distant Sky & Low Clouds (FARTHEST).
	# Reduced amplitude (was 420) so the ridge sits low on the horizon and
	# the cirrus reads as haze rather than a mountain wall.
	{"salt": 201, "scale": 0.1, "freq": 0.002, "amp": 280.0, "base": 650.0,
	 "seg": 48.0, "floor": 1400.0, "color": Color(0.62, 0.68, 0.78),
	 "trim_color": Color(0.72, 0.76, 0.84)},
	# Layer 2 — Cobalt Mountains & Snow Peaks (MID).
	# Slightly taller amp so snow-capped peaks stand above the cobalt base;
	# color slot now holds the PEAK color (gradient base_color is set in code).
	{"salt": 202, "scale": 0.3, "freq": 0.003, "amp": 200.0, "base": 680.0,
	 "seg": 48.0, "floor": 1400.0, "color": ParallaxScenery.COBALT_PEAK_COLOR,
	 "trim_color": ParallaxScenery.COBALT_PEAK_COLOR},
	# Layer 3 — Foreground Parallax & Flight-Ceiling Clouds (NEAREST).
	# Low rolling green-blue hills transition smoothly into the player's
	# real foreground terrain (Terrain.ground_color ≈ 0.12, 0.35, 0.12);
	# the hue here is lightened/desaturated to read as a softer mid-ground.
	{"salt": 203, "scale": 0.6, "freq": 0.004, "amp": 80.0,  "base": 720.0,
	 "seg": 64.0, "floor": 1400.0, "color": Color(0.24, 0.42, 0.30),
	 "trim_color": Color(0.30, 0.50, 0.38)},
]
const CLOUD_SALT := 204

## Per-layer cloud styling (M7).  `type` selects the builder:
##   "cirrus_narrow" → build_cirrus_clouds, pinned to (cy_min, cy_max)
##   "none"          → no clouds on this layer
##   "ceiling"       → build_ceiling_clouds, anchored at the flight ceiling
## `salt_offset` keeps each layer's cloud layout independent & deterministic.
const CLOUD_STYLES := [
	# Layer 1: cirrus in a narrow band right at the horizon (540–640 px), with
	# very low alpha (0.05–0.1) so it blends into the sky gradient.
	{"type": "cirrus_narrow", "count": 6, "alpha": 0.08, "cy_min": 540.0,
	 "cy_max": 640.0, "salt_offset": 0},
	# Layer 2: no clouds — cobalt mountains carry the layer alone.
	{"type": "none", "salt_offset": 1},
	# Layer 3: flight-ceiling cue.  Clouds are positioned in
	# y ∈ [ceiling_y, ceiling_y + CEILING_CLOUD_BAND_PX] where
	# ceiling_y = ground - FLIGHT_CEILING_PX; see ParallaxScenery for the
	# "200 m below ceiling" intent and band-width justification.
	{"type": "ceiling", "count": 14, "alpha": 0.45, "salt_offset": 2},
]

## Horizontal motion_scale multiplier (D9).  Halved from 1.0 → 0.5 to
## emphasize immense scale and slow the background shift.  Vertical
## (motion_scale.y) is unchanged so climb/dive still scrolls at the
## original rate.
const MOTION_SCALE_X_MUL := 0.5

## Snow line y-threshold for Layer 2 (cobalt mountains).  Vertices with
## y < SNOW_LINE_Y receive a white snow-cap polygon.  Picked so the
## tallest ~25% of macro/micro peaks breach it (Layer 2 base 680 −
## amp 200 = 480 peak; threshold 530 → top 50 px = upper quarter).
const SNOW_LINE_Y := ParallaxScenery.DEFAULT_SNOW_LINE_Y

## Anchor y for the Layer 3 flight-ceiling cloud band.  Computed once from
## ParallaxScenery constants so background.gd stays the single wiring site.
const CEILING_CLOUD_CEILING_Y := ParallaxScenery.DEFAULT_GROUND_Y \
		- ParallaxScenery.FLIGHT_CEILING_PX

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
##   - LAYER_SPECS[i]           : ridge tuning + scale + mirroring
##   - CLOUD_STYLES[i]          : which (if any) cloud builder to call
##   - Layer 2 additionally gets the cobalt gradient + snow caps.
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
		# keep vertical motion_scale at s so climb/dive parallax is unchanged.
		layer.motion_scale = Vector2(s * MOTION_SCALE_X_MUL, s)
		layer.motion_mirroring = Vector2(period, 0.0)
		parallax.add_child(layer)
		var ridge := ParallaxScenery.build_ridge_points(
			TerrainNoise.derive_seed(seed, spec["salt"]),
			period, spec["base"], spec["amp"], spec["freq"], spec["seg"], span)
		# --- Layer body: flat polygon (L1, L3) or gradient cobalt (L2) ---
		var body_color: Color = spec["color"]
		if i == 1:
			# Layer 2: cobalt mountains with vertical gradient.
			layer.add_child(ParallaxScenery.build_cobalt_mountain_polygon(
				ridge, period, spec["floor"],
				ParallaxScenery.COBALT_PEAK_COLOR,
				ParallaxScenery.COBALT_BASE_COLOR))
			# Conditional snow caps on the tallest peaks.
			for cap in ParallaxScenery.build_snow_caps(ridge, SNOW_LINE_Y):
				layer.add_child(cap)
			# Trim outline uses the cobalt peak tone for a clean alpine edge.
			body_color = ParallaxScenery.COBALT_PEAK_COLOR
		else:
			# Layers 1 and 3: flat-color ridge + trim outline.
			layer.add_child(ParallaxScenery.make_ridge_polygon(
				ridge, period, spec["floor"], body_color))
		# Trim line: use the explicit `trim_color` when present (so the
		# cobalt layer doesn't get an arbitrarily-lightened green), else
		# fall back to the body color (legacy behavior).
		var trim_color: Color = spec.get("trim_color", body_color)
		layer.add_child(ParallaxScenery.make_trim_line(ridge, trim_color))
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
			"ceiling":
				clouds = ParallaxScenery.build_ceiling_clouds(
					cseed, period, CEILING_CLOUD_CEILING_Y,
					ParallaxScenery.CEILING_CLOUD_BAND_PX,
					int(cstyle["count"]), float(cstyle["alpha"]))
			"none", "":
				clouds = []
			_:
				push_warning("Background: unknown cloud type '%s' on layer %d"
						% [cstyle["type"], i])
				clouds = []
		for puff in clouds:
			layer.add_child(puff)
