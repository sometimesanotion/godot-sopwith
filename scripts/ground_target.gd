extends StaticBody2D

@export var health: float = 50.0
@export var max_health: float = 50.0
@export var target_type: String = "building"
@export var has_aa: bool = false
@export var aa_range: float = 400.0
@export var aa_cooldown: float = 2.0

var is_destroyed: bool = false
var aa_timer: float = 0.0
var polygon_points: PackedVector2Array = []
var _collision_polygon: CollisionPolygon2D = null

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

	var dist := global_position.distance_to(player.global_position)
	if dist > aa_range:
		return

	aa_timer = aa_cooldown

	var to_player: Vector2 = player.global_position - global_position
	var bullet: CharacterBody2D = AA_PROJECTILE.instantiate()
	bullet.global_position = global_position + Vector2(0, -20)
	bullet.rotation = to_player.angle()
	bullet.speed = 300
	bullet.assign_owner(self)
	get_parent().add_child(bullet)

func _create_visuals() -> void:
	_collision_polygon = CollisionPolygon2D.new()
	if target_type == "hangar":
		_create_hangar(_collision_polygon)
	elif target_type == "tank":
		_create_tank(_collision_polygon)
	elif target_type == "fuel_tank":
		_create_fuel_tank(_collision_polygon)
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

func _create_fuel_tank(polygon: CollisionPolygon2D) -> void:
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
	elif target_type == "fuel_tank":
		color = Color(0.2, 0.5, 0.2)
		draw_fuel_tank_details()
	elif target_type == "building":
		color = Color(0.35, 0.35, 0.4)
		draw_building_details()

	draw_colored_polygon(polygon_points, color)

func draw_hangar_details() -> void:
	draw_line(Vector2(-35, -20), Vector2(-35, -25), Color(0.2, 0.1, 0.1), 2)
	draw_line(Vector2(0, -30), Vector2(0, -38), Color(0.2, 0.1, 0.1), 2)
	draw_line(Vector2(35, -20), Vector2(35, -25), Color(0.2, 0.1, 0.1), 2)
	draw_rect(Rect2(-5, -5, 10, 5), Color(0.1, 0.1, 0.15))

func draw_tank_details() -> void:
	draw_circle(Vector2(-5, -12), 3, Color(0.1, 0.2, 0.1))
	draw_line(Vector2(-20, -15), Vector2(-25, -18), Color(0.15, 0.25, 0.15), 2)
	draw_line(Vector2(20, -15), Vector2(25, -18), Color(0.15, 0.25, 0.15), 2)

func draw_fuel_tank_details() -> void:
	draw_line(Vector2(-12, -18), Vector2(-14, -22), Color(0.1, 0.2, 0.1), 2)
	draw_line(Vector2(12, -18), Vector2(14, -22), Color(0.1, 0.2, 0.1), 2)
	draw_rect(Rect2(-3, -22, 6, 3), Color(0.3, 0.2, 0.1))
	draw_line(Vector2(0, -25), Vector2(0, -28), Color(0.8, 0.4, 0.1), 2)

func draw_building_details() -> void:
	draw_rect(Rect2(-15, -35, 30, 5), Color(0.2, 0.2, 0.25))
	draw_rect(Rect2(-10, -40, 8, 10), Color(0.15, 0.15, 0.2))
	draw_rect(Rect2(2, -40, 8, 10), Color(0.15, 0.15, 0.2))

func take_damage(amount: float, attacker: Node) -> void:
	if is_destroyed:
		return

	health -= amount
	if health <= 0:
		_destroy()

	var attacker_owner: Node = null
	if attacker.has_method("get_bullet_owner"):
		attacker_owner = attacker.get_bullet_owner()
	elif attacker.has_method("get_bomb_owner"):
		attacker_owner = attacker.get_bomb_owner()

	if attacker_owner and attacker_owner.has_method("add_score"):
		attacker_owner.add_score(int(amount))

func _destroy() -> void:
	is_destroyed = true

	if target_type == "fuel_tank":
		_spawn_violent_explosion()
		_spawn_violent_explosion()
		_spawn_violent_explosion()
		if GameManager:
			GameManager.request_screen_shake(40.0)
	else:
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

		if GameManager:
			GameManager.request_screen_shake(15.0)

	if GameManager:
		GameManager.add_score(100)

	queue_free()

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
