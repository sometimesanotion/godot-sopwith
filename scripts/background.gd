extends Node2D
## Owns the sky gradient (unchanged) and assembles the deterministic, seed-driven
## 3-layer vector parallax (D6–D9).  `generate(seed)` is called by main.gd after
## `terrain.generate()`; the seed is the world seed so terrain + backdrop agree.

const TERRAIN_LENGTH := 16384.0

var sky_layer: CanvasLayer
var sky_rect: ColorRect
var sky_material: ShaderMaterial

var parallax: ParallaxBackground
var _generated := false

## Parallax layer specifications (D6).  `period = TERRAIN_LENGTH * scale` is the
## mirroring period that makes each layer wrap seamlessly at the map seam.
const LAYER_SPECS := [
	{"salt": 201, "scale": 0.1, "freq": 0.004, "amp": 420.0, "base": 650.0,
	 "seg": 32.0, "floor": 1400.0, "color": Color(0.62, 0.68, 0.78)},
	{"salt": 202, "scale": 0.3, "freq": 0.008, "amp": 180.0, "base": 680.0,
	 "seg": 48.0, "floor": 1400.0, "color": Color(0.35, 0.52, 0.48)},
	{"salt": 203, "scale": 0.6, "freq": 0.014, "amp": 90.0,  "base": 720.0,
	 "seg": 64.0, "floor": 1400.0, "color": Color(0.24, 0.42, 0.30)},
]
const CLOUD_SALT := 204
const CLOUD_COUNT := 14

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

## Assemble the deterministic, seed-driven 3-layer vector parallax (D6–D9).
## Called explicitly by main.gd after terrain.generate() so the world seed is
## shared.  Idempotent: the first call builds everything; subsequent calls are
## no-ops.  All children are static — zero per-frame `_draw` (D9 / T4 fix).
func generate(seed: int) -> void:
	if _generated:
		return
	_generated = true
	parallax = ParallaxBackground.new()
	parallax.layer = -15                       # behind world (0), in front of sky (-20)
	add_child(parallax)
	for spec in LAYER_SPECS:
		var s: float = spec["scale"]
		var period := TERRAIN_LENGTH * s       # D6 mirroring math
		var layer := ParallaxLayer.new()
		layer.motion_scale = Vector2(s, s)
		layer.motion_mirroring = Vector2(period, 0.0)
		parallax.add_child(layer)
		var ridge := ParallaxScenery.build_ridge_points(
			TerrainNoise.derive_seed(seed, spec["salt"]),
			period, spec["base"], spec["amp"], spec["freq"], spec["seg"])
		layer.add_child(ParallaxScenery.make_ridge_polygon(
			ridge, period, spec["floor"], spec["color"]))
		layer.add_child(ParallaxScenery.make_trim_line(ridge, spec["color"]))
	# Layer 3 atmosphere (D9): clouds ride the fastest layer (index 2) at 0.6 rate.
	var cloud_layer := parallax.get_child(2) as ParallaxLayer
	for puff in ParallaxScenery.build_clouds(
			TerrainNoise.derive_seed(seed, CLOUD_SALT),
			TERRAIN_LENGTH * LAYER_SPECS[2]["scale"], CLOUD_COUNT):
		cloud_layer.add_child(puff)
