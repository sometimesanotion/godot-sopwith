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
## Per-layer cloud styling (T-clouds).  Nearer layers (larger scale) are puffy
## cumulus and more translucent; the distant layer is minimalist cirrus.  The
## `salt_offset` keeps each layer's cloud layout independent & deterministic.
const CLOUD_STYLES := [
	{"type": "cirrus",  "count": 10, "alpha": 0.30, "puff_scale": 1.0, "salt_offset": 0},
	{"type": "cumulus", "count": 10, "alpha": 0.22, "puff_scale": 0.8, "salt_offset": 1},
	{"type": "cumulus", "count": 12, "alpha": 0.15, "puff_scale": 1.1, "salt_offset": 2},
]

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
	for i in range(LAYER_SPECS.size()):
		var spec: Dictionary = LAYER_SPECS[i]
		var s: float = spec["scale"]
		var period := TERRAIN_LENGTH * s       # D6 mirroring math
		var span := _coverage_periods(period)  # wide enough to fill the screen
		var layer := ParallaxLayer.new()
		layer.motion_scale = Vector2(s, s)
		layer.motion_mirroring = Vector2(period, 0.0)
		parallax.add_child(layer)
		var ridge := ParallaxScenery.build_ridge_points(
			TerrainNoise.derive_seed(seed, spec["salt"]),
			period, spec["base"], spec["amp"], spec["freq"], spec["seg"], span)
		layer.add_child(ParallaxScenery.make_ridge_polygon(
			ridge, period, spec["floor"], spec["color"]))
		layer.add_child(ParallaxScenery.make_trim_line(ridge, spec["color"]))
		# Clouds on EVERY layer (T-clouds): distant = minimalist cirrus, near =
		# puffy translucent cumulus.  Per-layer seed keeps layouts independent.
		var cstyle: Dictionary = CLOUD_STYLES[i]
		var clouds: Array[Polygon2D] = []
		var cseed: int = TerrainNoise.derive_seed(seed, CLOUD_SALT + int(cstyle["salt_offset"]))
		if cstyle["type"] == "cirrus":
			clouds = ParallaxScenery.build_cirrus_clouds(
				cseed, period, int(cstyle["count"]), float(cstyle["alpha"]))
		else:
			clouds = ParallaxScenery.build_cumulus_clouds(
				cseed, period, int(cstyle["count"]), float(cstyle["alpha"]),
				float(cstyle["puff_scale"]))
		for puff in clouds:
			layer.add_child(puff)
