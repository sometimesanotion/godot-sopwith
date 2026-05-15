extends Control

const TERRAIN_LENGTH := 4096.0
const MINIMAP_WIDTH := 400.0
const MINIMAP_HEIGHT := 80.0

var terrain_points: PackedVector2Array = []
var player_dot: ColorRect
var enemy_dots: Array[ColorRect] = []
var home_marker: ColorRect

var terrain_line: Line2D

func _ready() -> void:
	_minimum_size = Vector2(MINIMAP_WIDTH, MINIMAP_HEIGHT)
	_create_background()
	_create_terrain_line()
	_create_player_marker()
	_create_home_marker()

func _create_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var border := ColorRect.new()
	border.color = Color(0.4, 0.4, 0.4)
	border.custom_minimum_size = Vector2(2, MINIMAP_HEIGHT)
	border.position = Vector2(0, 0)
	add_child(border)
	
	var border2 := ColorRect.new()
	border2.color = Color(0.4, 0.4, 0.4)
	border2.custom_minimum_size = Vector2(2, MINIMAP_HEIGHT)
	border2.position = Vector2(MINIMAP_WIDTH - 2, 0)
	add_child(border2)

func _create_terrain_line() -> void:
	terrain_line = Line2D.new()
	terrain_line.width = 2.0
	terrain_line.default_color = Color(0.3, 0.6, 0.3)
	add_child(terrain_line)

func _create_player_marker() -> void:
	player_dot = ColorRect.new()
	player_dot.custom_minimum_size = Vector2(6, 6)
	player_dot.color = Color(0.2, 0.8, 0.2)
	add_child(player_dot)

func _create_home_marker() -> void:
	home_marker = ColorRect.new()
	home_marker.custom_minimum_size = Vector2(8, 8)
	home_marker.color = Color(0.8, 0.8, 0.2)
	add_child(home_marker)

func update_terrain(points: PackedVector2Array) -> void:
	terrain_points = points
	_update_terrain_display()

func _update_terrain_display() -> void:
	if terrain_points.size() == 0:
		return
	
	terrain_line.clear_points()
	var scale := MINIMAP_WIDTH / TERRAIN_LENGTH
	var base_y := MINIMAP_HEIGHT * 0.7
	
	for point in terrain_points:
		if point.x <= TERRAIN_LENGTH:
			var map_x := point.x * scale
			var map_y := base_y - (point.y - 600) * 0.15
			map_y = clamp(map_y, 5, MINIMAP_HEIGHT - 5)
			terrain_line.add_point(Vector2(map_x, map_y))

func update_player(world_pos: Vector2) -> void:
	var scale := MINIMAP_WIDTH / TERRAIN_LENGTH
	var map_x := wrapf(world_pos.x, 0, TERRAIN_LENGTH) * scale
	var base_y := MINIMAP_HEIGHT * 0.7
	var map_y := base_y - (world_pos.y - 600) * 0.15
	map_y = clamp(map_y, 5, MINIMAP_HEIGHT - 5)
	player_dot.position = Vector2(map_x - 3, map_y - 3)

func update_enemies(enemies: Array) -> void:
	while enemy_dots.size() < enemies.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(4, 4)
		dot.color = Color(0.8, 0.2, 0.2)
		add_child(dot)
		enemy_dots.append(dot)
	
	while enemy_dots.size() > enemies.size():
		var dot := enemy_dots.pop_back()
		dot.queue_free()
	
	var scale := MINIMAP_WIDTH / TERRAIN_LENGTH
	var base_y := MINIMAP_HEIGHT * 0.7
	
	for i in range(enemies.size()):
		if enemies[i]:
			var world_pos := enemies[i].global_position
			var map_x := wrapf(world_pos.x, 0, TERRAIN_LENGTH) * scale
			var map_y := base_y - (world_pos.y - 600) * 0.15
			map_y = clamp(map_y, 5, MINIMAP_HEIGHT - 5)
			enemy_dots[i].position = Vector2(map_x - 2, map_y - 2)
			enemy_dots[i].visible = true

func update_home(base_x: float) -> void:
	var scale := MINIMAP_WIDTH / TERRAIN_LENGTH
	var map_x := base_x * scale
	home_marker.position = Vector2(map_x - 4, MINIMAP_HEIGHT - 12)