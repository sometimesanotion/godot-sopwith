extends StaticBody2D

@export var health: float = 50.0
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
var original_health: float = 50.0

const AA_PROJECTILE := preload("res://scenes/bullet.tscn")
const SHATTER_SCENE := preload("res://scenes/shatter_effect.tscn")
const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")

func _ready() -> void:
	add_to_group("destructible")
	add_to_group("ground_target")
	_create_visuals()

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

func _create_hangar(polygon: CollisionPolygon2D) -> void:
	var points := PackedVector2Array([
		Vector2(-40, 0),
		Vector2(-40, -25),
		Vector2(-20, -35),
		Vector2(20, -35),
		Vector2(40, -25),
		Vector2(40, 0)
	])
	polygon.polygon = points

func _create_tank(polygon: CollisionPolygon2D) -> void:
	var points := PackedVector2Array([
		Vector2(-25, 0),
		Vector2(-25, -10),
		Vector2(-15, -10),
		Vector2(-10, -18),
		Vector2(10, -18),
		Vector2(15, -10),
		Vector2(25, -10),
		Vector2(25, 0)
	])
	polygon.polygon = points

func _create_fuel_depot(polygon: CollisionPolygon2D) -> void:
	var points := PackedVector2Array([
		Vector2(-15, 0),
		Vector2(-15, -20),
		Vector2(-10, -25),
		Vector2(10, -25),
		Vector2(15, -20),
		Vector2(15, 0)
	])
	polygon.polygon = points

func _create_building(polygon: CollisionPolygon2D) -> void:
	var points := PackedVector2Array([
		Vector2(-20, 0),
		Vector2(-20, -30),
		Vector2(-10, -40),
		Vector2(10, -40),
		Vector2(20, -30),
		Vector2(20, 0)
	])
	polygon.polygon = points

func _draw() -> void:
	if polygon_points.size() < 3:
		return

	var color := Color(0.3, 0.3, 0.35)
	if target_type == "hangar":
		color = Color(0.4, 0.2, 0.2)
		draw_hangar_details()
	elif target_type == "tank":
		color = Color(0.2, 0.3, 0.2)
		draw_tank_details()
	elif target_type == "fuel_depot":
		color = Color(0.2, 0.5, 0.2)
		draw_fuel_depot_details()
	elif target_type == "building":
		color = Color(0.35, 0.35, 0.4)
		draw_building_details()

	draw_colored_polygon(polygon_points, color)

	if is_enemy and not is_wreck:
		_draw_enemy_flag()

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
	draw_rect(Rect2(-15, -35, 30, 5), Color(0.2, 0.2, 0.25))
	draw_rect(Rect2(-10, -40, 8, 10), Color(0.15, 0.15, 0.2))
	draw_rect(Rect2(2, -40, 8, 10), Color(0.15, 0.15, 0.2))

func _draw_enemy_flag() -> void:
	var flag_x := 20.0
	var flag_top := -45.0
	draw_line(Vector2(flag_x, 0), Vector2(flag_x, flag_top), Color(0.6, 0.6, 0.6), 2)
	var flag_points := PackedVector2Array([
		Vector2(flag_x, flag_top),
		Vector2(flag_x + 15, flag_top + 5),
		Vector2(flag_x, flag_top + 10)
	])
	draw_colored_polygon(flag_points, Color(0.8, 0.1, 0.1))

var _last_attacker_player_id: int = 0

func take_damage(amount: float, attacker: Node) -> void:
	if is_destroyed:
		return

	health -= amount
	if health <= 0:
		_destroy(attacker)
		return

	_last_attacker_player_id = _get_player_id_from_attacker(attacker)
	if _last_attacker_player_id >= 0 and GameManager:
		GameManager.add_score(_last_attacker_player_id, int(amount))

func _get_player_id_from_attacker(attacker: Node) -> int:
	if attacker and attacker.has_method("is_player_plane"):
		var avatar = Biplane.get_avatar(0)
		if avatar and avatar.is_player:
			return avatar.id
	return -1

func _destroy(attacker: Node) -> void:
	is_destroyed = true

	if target_type == "fuel_depot":
		_create_fuel_depot_explosion()
		if GameManager:
			GameManager.request_screen_shake(50.0)
	else:
		_create_normal_explosion()

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

func _create_fuel_depot_explosion() -> void:
	for i in range(5):
		var explosion: Node = EXPLOSION_SCENE.instantiate()
		explosion.global_position = global_position + Vector2(randf_range(-30, 30), randf_range(-40, 10))
		get_parent().add_child(explosion)

	for i in range(5):
		var fire := GPUParticles2D.new()
		fire.name = "WreckFire"
		fire.emitting = true
		fire.one_shot = false
		fire.explosiveness = 0.0
		fire.amount = 30
		fire.lifetime = 4.0
		fire.position = global_position + Vector2(randf_range(-20, 20), randf_range(-20, 0))

		var fire_mat := ParticleProcessMaterial.new()
		fire_mat.emission_shape = 1
		fire_mat.emission_sphere_radius = 15.0
		fire_mat.gravity = Vector3(0, -50, 0)
		fire_mat.spread = 180.0
		fire_mat.initial_velocity_min = 30.0
		fire_mat.initial_velocity_max = 80.0
		fire_mat.scale_min = 3.0
		fire_mat.scale_max = 8.0
		fire_mat.color = Color(1, 0.4, 0.1, 1)
		fire.process_material = fire_mat
		get_parent().add_child(fire)

	for i in range(3):
		var smoke := GPUParticles2D.new()
		smoke.name = "WreckSmoke"
		smoke.emitting = true
		smoke.one_shot = false
		smoke.amount = 20
		smoke.lifetime = 6.0
		smoke.position = global_position + Vector2(randf_range(-15, 15), randf_range(-15, 0))

		var smoke_mat := ParticleProcessMaterial.new()
		smoke_mat.emission_shape = 1
		smoke_mat.emission_sphere_radius = 20.0
		smoke_mat.gravity = Vector3(0, -15, 0)
		smoke_mat.spread = 180.0
		smoke_mat.initial_velocity_min = 20.0
		smoke_mat.initial_velocity_max = 50.0
		smoke_mat.scale_min = 4.0
		smoke_mat.scale_max = 10.0
		smoke_mat.color = Color(0.1, 0.1, 0.1, 0.8)
		smoke.process_material = smoke_mat
		get_parent().add_child(smoke)

	if polygon_points.size() >= 3:
		var shatter: Node = SHATTER_SCENE.instantiate()
		shatter.setup(polygon_points, Color(0.2, 0.5, 0.2), global_position)
		get_parent().add_child(shatter)

func _create_fire_plume() -> Node2D:
	var plume := Node2D.new()
	plume.set_script(_get_fire_plume_script())
	plume.setup(10.0)
	return plume

func _get_fire_plume_script() -> GDScript:
	return load("res://scripts/fire_plume.gd")

func _create_heavy_black_smoke() -> Node2D:
	var smoke := Node2D.new()
	smoke.set_script(_get_heavy_smoke_script())
	smoke.setup(5.0, Color(0.05, 0.05, 0.05, 0.9))
	return smoke

func _get_heavy_smoke_script() -> GDScript:
	return load("res://scripts/smoke_puff.gd")

func _damage_nearby_planes(radius: float) -> void:
	var planes = get_tree().get_nodes_in_group("destructible")
	for plane in planes:
		if plane.has_method("take_damage") and plane != self:
			if plane.global_position.distance_to(global_position) < radius:
				plane.take_damage(50.0, self)

func _create_normal_explosion() -> void:
	var explosion: Node = EXPLOSION_SCENE.instantiate()
	explosion.global_position = global_position
	get_parent().add_child(explosion)

	var color := Color(0.3, 0.3, 0.35)
	if target_type == "hangar":
		color = Color(0.4, 0.2, 0.2)
	elif target_type == "tank":
		color = Color(0.2, 0.3, 0.2)

	if polygon_points.size() >= 3:
		var shatter: Node = SHATTER_SCENE.instantiate()
		shatter.setup(polygon_points, color, global_position)
		get_parent().add_child(shatter)

	# _create_building_smoke_puffs()

	if GameManager:
		GameManager.request_screen_shake(15.0)

func _create_building_smoke_puffs() -> void:
	for i in range(3):
		var smoke_puff := _create_fading_smoke_puff()
		smoke_puff.global_position = global_position + Vector2(randf_range(-15, 15), randf_range(-35, -10))
		smoke_puff.scale = Vector2(5, 5)
		get_parent().add_child(smoke_puff)

func _create_fading_smoke_puff() -> Node2D:
	var puff := Node2D.new()
	puff.set_script(_get_smoke_puff_script())
	puff.setup(2.0, Color(0.2, 0.2, 0.2, 0.8))
	return puff

func _get_smoke_puff_script() -> GDScript:
	return load("res://scripts/smoke_puff.gd")

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

	get_parent().add_child(wreck)

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

func _spawn_violent_explosion() -> void:
	var explosion: Node = EXPLOSION_SCENE.instantiate()
	explosion.global_position = global_position + Vector2(randf_range(-20, 20), randf_range(-30, 10))
	get_parent().add_child(explosion)

	var fire := GPUParticles2D.new()
	fire.emitting = true
	fire.one_shot = true
	fire.explosiveness = 1.0
	fire.amount = 40
	fire.lifetime = 0.8
	fire.position = Vector2.ZERO

	var fire_mat := ParticleProcessMaterial.new()
	fire_mat.emission_shape = 1
	fire_mat.emission_sphere_radius = 20.0
	fire_mat.gravity = Vector3(0, -80, 0)
	fire_mat.spread = 180.0
	fire_mat.initial_velocity_min = 100.0
	fire_mat.initial_velocity_max = 250.0
	fire_mat.scale_min = 4.0
	fire_mat.scale_max = 10.0
	fire_mat.color = Color(1, 0.3, 0, 1)
	fire.process_material = fire_mat
	add_child(fire)

	var smoke := GPUParticles2D.new()
	smoke.emitting = true
	smoke.one_shot = true
	smoke.explosiveness = 0.8
	smoke.amount = 30
	smoke.lifetime = 1.5
	smoke.position = Vector2.ZERO

	var smoke_mat := ParticleProcessMaterial.new()
	smoke_mat.emission_shape = 1
	smoke_mat.emission_sphere_radius = 25.0
	smoke_mat.gravity = Vector3(0, -20, 0)
	smoke_mat.spread = 180.0
	smoke_mat.initial_velocity_min = 50.0
	smoke_mat.initial_velocity_max = 120.0
	smoke_mat.scale_min = 5.0
	smoke_mat.scale_max = 12.0
	smoke_mat.color = Color(0.1, 0.1, 0.1, 1)
	smoke.process_material = smoke_mat
	add_child(smoke)

	if polygon_points.size() >= 3:
		var shatter: Node = SHATTER_SCENE.instantiate()
		shatter.setup(polygon_points, Color(0.2, 0.5, 0.2), global_position)
		get_parent().add_child(shatter)

func get_health() -> float:
	return health
