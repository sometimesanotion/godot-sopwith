extends Control

const TERRAIN_LENGTH := 16384.0
const MINIMAP_WIDTH := 400.0
const MINIMAP_HEIGHT := 80.0
const GROUND_Y := 650.0
const MAX_ALTITUDE := 600.0

var terrain_points: PackedVector2Array = []
var player_dot: ColorRect
var enemy_dots: Array[ColorRect] = []
var target_dots: Array[ColorRect] = []
var home_marker: ColorRect
var terrain_line: Line2D
var terrain_fill: Polygon2D

func _ready() -> void:
	custom_minimum_size = Vector2(MINIMAP_WIDTH, MINIMAP_HEIGHT)
	_create_background()
	_create_terrain_line()
	_create_terrain_fill()
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

func _create_terrain_fill() -> void:
	terrain_fill = Polygon2D.new()
	terrain_fill.color = Color(0.1, 0.3, 0.1, 0.5)
	add_child(terrain_fill)

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
	var terrain_fill_points := PackedVector2Array()
	var scale_x: float = MINIMAP_WIDTH / TERRAIN_LENGTH
	var ground_y_map: float = MINIMAP_HEIGHT - 5
	
	for point: Vector2 in terrain_points:
		if point.x <= TERRAIN_LENGTH:
			var map_x: float = point.x * scale_x
			var map_y: float = _altitude_to_map_y(point.y)
			terrain_line.add_point(Vector2(map_x, map_y))
			terrain_fill_points.append(Vector2(map_x, map_y))
	
	terrain_fill_points.append(Vector2(MINIMAP_WIDTH, ground_y_map))
	terrain_fill_points.append(Vector2(0, ground_y_map))
	terrain_fill.polygon = terrain_fill_points

func _altitude_to_map_y(world_y: float) -> float:
	var altitude: float = GROUND_Y - world_y
	var normalized_alt: float = clampf(altitude / MAX_ALTITUDE, 0.0, 1.0)
	var map_y: float = lerp(float(MINIMAP_HEIGHT - 5), 5.0, normalized_alt)
	return map_y

func update_player(world_pos: Vector2) -> void:
	var scale: float = MINIMAP_WIDTH / TERRAIN_LENGTH
	var map_x: float = wrapf(world_pos.x, 0.0, TERRAIN_LENGTH) * scale
	var map_y: float = _altitude_to_map_y(world_pos.y)
	player_dot.position = Vector2(map_x - 3.0, map_y - 3.0)

func update_enemies(enemies: Array) -> void:
	while enemy_dots.size() < enemies.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(4, 4)
		dot.color = Color(0.8, 0.2, 0.2)
		add_child(dot)
		enemy_dots.append(dot)
	
	while enemy_dots.size() > enemies.size():
		var dot: ColorRect = enemy_dots.pop_back()
		dot.queue_free()
	
	for i: int in range(enemies.size()):
		if enemies[i]:
			var world_pos: Vector2 = enemies[i].global_position
			var map_x: float = wrapf(world_pos.x, 0.0, TERRAIN_LENGTH) * (MINIMAP_WIDTH / TERRAIN_LENGTH)
			var map_y: float = _altitude_to_map_y(world_pos.y)
			enemy_dots[i].position = Vector2(map_x - 2.0, map_y - 2.0)
			enemy_dots[i].visible = true

func update_home(base_x: float) -> void:
	var scale: float = MINIMAP_WIDTH / TERRAIN_LENGTH
	var map_x: float = base_x * scale
	var map_y: float = _altitude_to_map_y(GROUND_Y)
	home_marker.position = Vector2(map_x - 4.0, map_y - 4.0)

func update_targets(targets: Array) -> void:
	while target_dots.size() < targets.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(3, 3)
		dot.color = Color(0.8, 0.1, 0.1)
		add_child(dot)
		target_dots.append(dot)

	while target_dots.size() > targets.size():
		var dot: ColorRect = target_dots.pop_back()
		dot.queue_free()

	var scale: float = MINIMAP_WIDTH / TERRAIN_LENGTH

	for i: int in range(targets.size()):
		var target = targets[i]
		if is_instance_valid(target):
			var world_pos: Vector2 = target.global_position
			var map_x: float = wrapf(world_pos.x, 0.0, TERRAIN_LENGTH) * scale
			var map_y: float = _altitude_to_map_y(world_pos.y)
			target_dots[i].position = Vector2(map_x - 1.5, map_y - 1.5)
			target_dots[i].visible = true
		else:
			target_dots[i].visible = false