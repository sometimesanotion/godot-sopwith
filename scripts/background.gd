extends Node2D

const TERRAIN_LENGTH := 16384.0

var camera: Camera2D
var mountain_data: Array[Dictionary] = []
var cloud_data: Array[Dictionary] = []
var sky_layer: CanvasLayer
var sky_rect: ColorRect
var sky_material: ShaderMaterial

## Camera world-x cached once per _draw so every wrapped element shares the
## same tiling reference (and we don't query the viewport per element).
var _cam_x_cache: float = 0.0

func _ready() -> void:
	if SvgManager and SvgManager.has_sprite("cloud"):
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_generate_background()
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

func _generate_background() -> void:
	randomize()
	for i in range(8):
		var px := randf() * TERRAIN_LENGTH
		mountain_data.append({
			"pos": Vector2(px, 500 + randf() * 150),
			"height": 80 + randf() * 150
		})
	for i in range(20):
		var cx := randf() * TERRAIN_LENGTH
		var cy := 400 - randf() * 1500
		var cloud := {
			"pos": Vector2(cx, cy),
			"puffs": [],
			"width": 200 + randf() * 300,
			"height": 160 + randf() * 80
		}
		var num_puffs := 100 + randi() % 100
		for j in range(num_puffs):
			var px: float = (randf() - 0.5) * cloud["width"]
			var py: float = (randf() - 0.5) * cloud["height"]
			var pr: float = 25 + randf() * 40
			var shade: float = 0.55 + randf() * 0.25
			var alpha: float = 0.5 + randf() * 0.3
			cloud["puffs"].append({"offset": Vector2(px, py), "radius": pr, "color": Color(shade, shade, shade, alpha)})
		cloud_data.append(cloud)

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

func _draw() -> void:
	_cam_x_cache = _camera_world_x()
	_draw_mountains()
	_draw_clouds()

## World-x position of the active camera, used to centre the tiling modulus.
func _camera_world_x() -> float:
	var cam = get_viewport().get_camera_2d()
	if cam:
		return cam.position.x
	return 0.0

## Integer copy indices `k` for which `base_x + k*TERRAIN_LENGTH` lies within
## the visible world-x band (plus a margin for camera lag).  Because the
## viewport is far narrower than TERRAIN_LENGTH this yields at most two or
## three copies, but it guarantees an element is drawn on BOTH sides of the
## wrap seam so nothing pops in after crossing the edge.
func _tile_k_range(base_x: float) -> Array[int]:
	var cam_x := _cam_x_cache
	var half_w := 2000.0
	var cam = get_viewport().get_camera_2d()
	if cam:
		half_w = (get_viewport_rect().size.x / cam.zoom.x) * 0.5
	var margin := half_w + 1500.0
	var left := cam_x - margin
	var right := cam_x + margin
	var k_min := int(floor((left - base_x) / TERRAIN_LENGTH))
	var k_max := int(ceil((right - base_x) / TERRAIN_LENGTH))
	var ks: Array[int] = []
	for k in range(k_min, k_max + 1):
		ks.append(k)
	return ks

func _draw_mountains() -> void:
	for data in mountain_data:
		var pos: Vector2 = data["pos"]
		var height: float = data["height"]
		for k in _tile_k_range(pos.x):
			var x := pos.x + k * TERRAIN_LENGTH
			var points = PackedVector2Array([
				Vector2(x - 600, 750),
				Vector2(x - 300, 750 - height),
				Vector2(x - 120, 550 - height),
				Vector2(x + 120, 550 - height - 30),
				Vector2(x + 300, 750 - height - 30),
				Vector2(x + 600, 750)
			])
			draw_colored_polygon(points, Color(0.10, 0.20, 0.40))

func _draw_clouds() -> void:
	if SvgManager and SvgManager.has_sprite("cloud"):
		for cloud in cloud_data:
			var pos: Vector2 = cloud["pos"]
			var w: float = cloud["width"]
			var h: float = cloud["height"]
			for k in _tile_k_range(pos.x):
				SvgManager.draw_sprite_centered(self, "cloud", Vector2(pos.x + k * TERRAIN_LENGTH, pos.y), Vector2(w, h))
		return

	for cloud in cloud_data:
		var cy: float = cloud["pos"].y
		for k in _tile_k_range(cloud["pos"].x):
			var base_x: float = cloud["pos"].x + k * TERRAIN_LENGTH
			for puff in cloud["puffs"]:
				var pos: Vector2 = Vector2(base_x, cy) + puff["offset"]
				draw_circle(pos, puff["radius"], puff["color"])