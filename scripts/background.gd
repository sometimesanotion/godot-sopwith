extends Node2D

const TERRAIN_LENGTH := 16384.0

var camera: Camera2D
var mountain_positions: Array[Vector2] = []
var cloud_positions: Array[Vector2] = []
var cloud_data: Array[Dictionary] = []

func _ready() -> void:
	if SvgManager and SvgManager.has_sprite("cloud"):
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_generate_background()

func _generate_background() -> void:
	randomize()
	for i in range(8):
		mountain_positions.append(Vector2(randf() * TERRAIN_LENGTH, 500 + randf() * 150))
	for i in range(20):
		var cx := randf() * TERRAIN_LENGTH
		var cy := 80 + randf() * 250
		var cloud := {
			"pos": Vector2(cx, cy),
			"puffs": [],
			"width": 240 + randf() * 200,
			"height": 120 + randf() * 80
		}
		var num_puffs := 20 + randi() % 20
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
	pass

func _draw() -> void:
	_draw_sky()
	_draw_mountains()
	_draw_clouds()

func _draw_sky() -> void:
	draw_rect(Rect2(-1000, -1000, TERRAIN_LENGTH + 2000, 2000), Color(0.1, 0.25, 0.35))

func _draw_mountains() -> void:
	for pos in mountain_positions:
		var screen_pos = pos
		var height = 80 + randf() * 60
		var points = PackedVector2Array([
			Vector2(screen_pos.x - 100, 750),
			Vector2(screen_pos.x - 30, 750 - height),
			Vector2(screen_pos.x + 40, 750 - height - 30),
			Vector2(screen_pos.x + 100, 750)
		])
		draw_colored_polygon(points, Color(0.15, 0.18, 0.22))

func _draw_clouds() -> void:
	if SvgManager and SvgManager.has_sprite("cloud"):
		for cloud in cloud_data:
			var pos: Vector2 = cloud["pos"]
			var w: float = cloud["width"]
			var h: float = cloud["height"]
			SvgManager.draw_sprite_centered(self, "cloud", pos, Vector2(w, h))
		return

	for cloud in cloud_data:
		for puff in cloud["puffs"]:
			var pos: Vector2 = cloud["pos"] + puff["offset"]
			draw_circle(pos, puff["radius"], puff["color"])