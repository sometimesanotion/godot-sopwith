extends Node2D

const TERRAIN_LENGTH := 16384.0

var camera: Camera2D
var mountain_data: Array[Dictionary] = []
var cloud_positions: Array[Vector2] = []
var cloud_data: Array[Dictionary] = []
var sky_layer: CanvasLayer
var sky_rect: ColorRect
var sky_material: ShaderMaterial

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
		cloud_positions.append(Vector2(cx, cy))
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
	_draw_mountains()
	_draw_clouds()

## World-x position of the active camera, used to centre the tiling modulus.
func _camera_world_x() -> float:
	var cam = get_viewport().get_camera_2d()
	if cam:
		return cam.position.x
	return 0.0

## Wrap a base world-x to the copy nearest the camera so each background
## element repeats every TERRAIN_LENGTH and the wrap-around is seamless.
func _wrapped_x(base_x: float) -> float:
	var cam_x := _camera_world_x()
	return base_x + TERRAIN_LENGTH * round((cam_x - base_x) / TERRAIN_LENGTH)

func _draw_mountains() -> void:
	for data in mountain_data:
		var pos: Vector2 = data["pos"]
		var height: float = data["height"]
		var x := _wrapped_x(pos.x)
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
			SvgManager.draw_sprite_centered(self, "cloud", Vector2(_wrapped_x(pos.x), pos.y), Vector2(w, h))
		return

	for cloud in cloud_data:
		var base_x := _wrapped_x(cloud["pos"].x)
		for puff in cloud["puffs"]:
			var pos: Vector2 = Vector2(base_x, cloud["pos"].y) + puff["offset"]
			draw_circle(pos, puff["radius"], puff["color"])