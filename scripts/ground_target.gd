extends StaticBody2D

var damage: DamageData = DamageData.new()
@export var max_health: float = 50.0
@export var target_type: String = "building"
@export var has_aa: bool = false
@export var aa_range: float = 400.0
@export var aa_cooldown: float = 1.0
@export var is_wreck: bool = false
@export var is_enemy: bool = false

var is_destroyed: bool = false
var aa_timer: float = 0.0
var polygon_points: PackedVector2Array = []
var _collision_polygon: CollisionPolygon2D = null
var _svg_sprite_name: String = ""

const AA_PROJECTILE := preload("res://scenes/bullet.tscn")

func _ready() -> void:
	add_to_group("destructible")
	add_to_group("ground_target")
	_svg_sprite_name = target_type
	damage = DamageData.new()
	if damage.damage_state_changed.is_connected(_on_ground_damage_state_changed):
		damage.damage_state_changed.disconnect(_on_ground_damage_state_changed)
	damage.damage_state_changed.connect(_on_ground_damage_state_changed)
	_create_visuals()
	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	queue_redraw()

func _physics_process(delta: float) -> void:
	if has_aa and not is_destroyed:
		aa_timer -= delta
		if aa_timer <= 0:
			_try_aa_fire()

func _try_aa_fire() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return

	var to_player: Vector2 = player.global_position - global_position
	var dist := to_player.length()
	if dist > aa_range:
		return

	var angle_from_horizontal := atan2(to_player.y, to_player.x)
	if angle_from_horizontal > deg_to_rad(-10):
		return

	aa_timer = aa_cooldown

	var bullet: CharacterBody2D = AA_PROJECTILE.instantiate()
	bullet.global_position = global_position + Vector2(15, -45)
	bullet.rotation = to_player.angle()
	bullet.speed = 500
	bullet.damage = 60.0
	bullet.assign_owner(self)
	get_parent().add_child(bullet)

func _create_visuals() -> void:
	_collision_polygon = CollisionPolygon2D.new()
	if target_type == "hangar":
		_create_hangar(_collision_polygon)
	elif target_type == "tank":
		_create_tank(_collision_polygon)
	elif target_type == "fuel_depot":
		_create_fuel_depot(_collision_polygon)
	else:
		_create_building(_collision_polygon)
	add_child(_collision_polygon)
	polygon_points = _collision_polygon.polygon
	var min_y := INF
	var max_y := -INF
	for pt in polygon_points:
		min_y = min(min_y, pt.y)
		max_y = max(max_y, pt.y)

func _create_hangar(polygon: CollisionPolygon2D) -> void:
	var points := PackedVector2Array([
		Vector2(-40, 35),
		Vector2(-40, -25),
		Vector2(-20, -35),
		Vector2(20, -35),
		Vector2(40, -25),
		Vector2(40, 35)
	])
	polygon.polygon = points

func _create_tank(polygon: CollisionPolygon2D) -> void:
	var points := PackedVector2Array([
		Vector2(-25, 18),
		Vector2(-25, -10),
		Vector2(-15, -10),
		Vector2(-10, -18),
		Vector2(10, -18),
		Vector2(15, -10),
		Vector2(25, -10),
		Vector2(25, 18)
	])
	polygon.polygon = points

func _create_fuel_depot(polygon: CollisionPolygon2D) -> void:
	var points := PackedVector2Array([
		Vector2(-15, 25),
		Vector2(-15, -20),
		Vector2(-10, -25),
		Vector2(10, -25),
		Vector2(15, -20),
		Vector2(15, 25)
	])
	polygon.polygon = points

func _create_building(polygon: CollisionPolygon2D) -> void:
	var points := PackedVector2Array([
		Vector2(-30, 40),
		Vector2(-30, -30),
		Vector2(-15, -40),
		Vector2(15, -40),
		Vector2(30, -30),
		Vector2(30, 40)
	])
	polygon.polygon = points

func _draw() -> void:
	if polygon_points.size() < 3:
		return

	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		var draw_rect := SvgManager.calc_draw_rect(polygon_points)
		SvgManager.draw_sprite_fit(self, _svg_sprite_name, draw_rect)
		return

	var color := Color(0.3, 0.3, 0.35)
	if target_type == "hangar":
		color = Color(0.4, 0.2, 0.2)
	elif target_type == "tank":
		color = Color(0.2, 0.3, 0.2)
	elif target_type == "fuel_depot":
		color = Color(0.2, 0.5, 0.2)
	elif target_type == "building":
		color = Color(0.35, 0.35, 0.4)

	draw_colored_polygon(polygon_points, color)

	if target_type == "hangar":
		draw_hangar_details()
	elif target_type == "tank":
		draw_tank_details()
	elif target_type == "fuel_depot":
		draw_fuel_depot_details()
	elif target_type == "building":
		draw_building_details()

func draw_hangar_details() -> void:
	draw_line(Vector2(-35, -20), Vector2(-35, -25), Color(0.2, 0.1, 0.1), 2)
	draw_line(Vector2(0, -30), Vector2(0, -38), Color(0.2, 0.1, 0.1), 2)
	draw_line(Vector2(35, -20), Vector2(35, -25), Color(0.2, 0.1, 0.1), 2)
	draw_rect(Rect2(-5, -5, 10, 5), Color(0.1, 0.1, 0.15))

func draw_tank_details() -> void:
	draw_circle(Vector2(-5, -12), 3, Color(0.1, 0.2, 0.1))
	draw_line(Vector2(-20, -15), Vector2(-25, -18), Color(0.15, 0.25, 0.15), 2)
	draw_line(Vector2(20, -15), Vector2(25, -18), Color(0.15, 0.25, 0.15), 2)

func draw_fuel_depot_details() -> void:
	draw_line(Vector2(-12, -18), Vector2(-14, -22), Color(0.1, 0.2, 0.1), 2)
	draw_line(Vector2(12, -18), Vector2(14, -22), Color(0.1, 0.2, 0.1), 2)
	draw_rect(Rect2(-3, -22, 6, 3), Color(0.3, 0.2, 0.1))
	draw_line(Vector2(0, -25), Vector2(0, -28), Color(0.8, 0.4, 0.1), 2)

func draw_building_details() -> void:
	draw_rect(Rect2(-22, -35, 44, 5), Color(0.2, 0.2, 0.25))
	draw_rect(Rect2(-15, -40, 12, 10), Color(0.15, 0.15, 0.2))
	draw_rect(Rect2(3, -40, 12, 10), Color(0.15, 0.15, 0.2))

var _last_attacker_player_id: int = 0

func take_damage(amount: float, attacker: Node) -> void:
	if is_destroyed:
		return

	if max_health <= 0:
		return

	var dmg_pct := amount / max_health
	damage.take_damage(dmg_pct)
	if damage.is_destroyed():
		_destroy(attacker)
		return

	_last_attacker_player_id = _get_player_id_from_attacker(attacker)
	if _last_attacker_player_id >= 0 and GameManager:
		GameManager.add_score(_last_attacker_player_id, int(amount))

func _get_player_id_from_attacker(attacker: Node) -> int:
	if attacker and attacker.has_method("is_player_plane"):
		if GameManager and GameManager.is_player(0):
			return 0
	return -1

func _on_ground_damage_state_changed(_from: DamageData.DamageState, _to: DamageData.DamageState) -> void:
	if is_destroyed:
		return
	var pos := global_position
	if EffectManager:
		EffectManager.spawn_damage_effects(pos, damage.damage_state, damage.damage_percent)

func _polygon_centroid(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for pt in points:
		sum += pt
	return sum / float(points.size())

func _destroy(attacker: Node) -> void:
	is_destroyed = true

	# Anchor the blast at the building's true center (polygon centroid in world
	# space), not the node origin — for non-symmetric shapes the origin can sit
	# well off-center, which made debris appear to rain in from elsewhere.
	var pos := global_position + _polygon_centroid(polygon_points)
	var debris_color := get_dominant_color()

	if EffectManager:
		var huge := GameManager.huge_explosions if GameManager else true
		if target_type == "fuel_depot" and huge:
			EffectManager.spawn_explosion_style(pos, 200.0, EffectManager.ExplosionStyle.FUEL_DEPOT, 12, debris_color, EffectManager.FireColorPreset.STANDARD, polygon_points)
		else:
			EffectManager.spawn_explosion_style(pos, 100.0, EffectManager.ExplosionStyle.NORMAL, 8, debris_color, EffectManager.FireColorPreset.STANDARD, polygon_points)

	_create_wreck()

	if GameManager:
		var player_id := _get_player_id_from_attacker(attacker)
		if player_id < 0:
			player_id = 0
		var points := 100
		if target_type == "fuel_depot":
			points = 200
		GameManager.add_score(player_id, points)

	queue_free()

func _create_fire_plume() -> Node2D:
	return EffectManager.spawn_open_fire_with_smoke(global_position, 10.0) if EffectManager else null

func _create_heavy_black_smoke() -> Node2D:
	return EffectManager.spawn_black_smoke(global_position, 30) if EffectManager else null

func _damage_nearby_planes(radius: float) -> void:
	var planes = get_tree().get_nodes_in_group("destructible")
	for plane in planes:
		if plane.has_method("take_damage") and plane != self:
			if plane.global_position.distance_to(global_position) < radius:
				plane.take_damage(50.0, self)

func _create_building_smoke_puffs() -> void:
	if not EffectManager:
		return
	for i in range(3):
		var smoke_pos := global_position + Vector2(randf_range(-15, 15), randf_range(-35, -10))
		EffectManager.spawn_black_smoke(smoke_pos, 20)

func _create_fading_smoke_puff() -> Node2D:
	return EffectManager.spawn_black_smoke(global_position, 20) if EffectManager else null

func _create_wreck() -> void:
	var wreck: StaticBody2D = StaticBody2D.new()
	wreck.position = global_position
	wreck.set_meta("is_wreck", true)
	wreck.add_to_group("destructible")
	wreck.add_to_group("wreck")

	var collision_poly := CollisionPolygon2D.new()
	var wrecked_points := PackedVector2Array()
	for pt in polygon_points:
		wrecked_points.append(pt + Vector2(randf_range(-3, 3), randf_range(-3, 3)))
	collision_poly.polygon = wrecked_points
	wreck.add_child(collision_poly)

	var wreck_draw := Node2D.new()
	wreck_draw.set_script(_get_wreck_draw_script())
	wreck_draw.set_meta("wreck_color", _get_wreck_color())
	wreck_draw.set_meta("wreck_points", wrecked_points)
	wreck.add_child(wreck_draw)

	get_parent().call_deferred("add_child", wreck)

func _get_wreck_color() -> Color:
	var color := Color(0.15, 0.15, 0.18)
	if target_type == "hangar":
		color = Color(0.2, 0.1, 0.1)
	elif target_type == "tank":
		color = Color(0.1, 0.15, 0.1)
	elif target_type == "fuel_depot":
		color = Color(0.1, 0.25, 0.1)
	return color

func _get_wreck_draw_script() -> GDScript:
	return load("res://scripts/wreck_draw.gd")

func get_health() -> float:
	return (1.0 - damage.damage_percent) * max_health

func get_damage_percent() -> float:
	return damage.damage_percent

func get_damage_state() -> int:
	return damage.damage_state

func get_dominant_color() -> Color:
	match target_type:
		"building":
			return Color(0.35, 0.35, 0.4)
		"hangar":
			return Color(0.4, 0.2, 0.2)
		"tank":
			return Color(0.2, 0.3, 0.2)
		"fuel_depot":
			return Color(0.2, 0.5, 0.2)
		_:
			return Color(0.3, 0.3, 0.35)

func get_visual_top() -> float:
	var min_y := INF
	for pt in polygon_points:
		min_y = min(min_y, pt.y)
	return global_position.y + min_y

func get_polygon_bounds() -> Dictionary:
	var min_y := INF
	var max_y := -INF
	var min_x := INF
	var max_x := -INF
	for pt in polygon_points:
		min_y = min(min_y, pt.y)
		max_y = max(max_y, pt.y)
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)
	return {
		"min_y": min_y,
		"max_y": max_y,
		"min_x": min_x,
		"max_x": max_x,
		"global_top_y": global_position.y + min_y,
		"global_bottom_y": global_position.y + max_y,
	}

func get_collision_response(other: Node, other_avatar: Variant, other_speed: float,
		plane_soft_landing: float = 100.0, plane_hard_landing: float = 200.0) -> Biplane.CollisionResult:
	var result := Biplane.CollisionResult.new()
	if is_destroyed:
		return result
	var hit_r: float = _get_collision_radius()
	var dist := global_position.distance_to(other.global_position)
	result.impact_speed = other_speed

	if dist < hit_r:
		result.hit = true
		var plane_v_perp: float = plane_hard_landing
		if other_speed <= plane_soft_landing:
			result.damage = 0.0
		elif other_speed < plane_hard_landing:
			result.damage = (other_speed - plane_soft_landing) / (plane_hard_landing - plane_soft_landing)
		else:
			result.damage = 1.0
		if other_avatar != null:
			result.is_midair = other_avatar.is_airborne if "is_airborne" in other_avatar else false
		else:
			result.is_midair = other_speed > plane_soft_landing * 0.5
	return result

func _get_collision_radius() -> float:
	var pbounds := get_polygon_bounds()
	var horizontal_extent := maxf(abs(pbounds["min_x"]), abs(pbounds["max_x"]))
	var vertical_extent := maxf(abs(pbounds["min_y"]), abs(pbounds["max_y"]))
	return maxf(horizontal_extent, vertical_extent) + 5.0