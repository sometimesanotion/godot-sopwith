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
	elif target_type == "tank":
		color = Color(0.2, 0.3, 0.2)
	elif target_type == "fuel_tank":
		color = Color(0.2, 0.5, 0.2)

	draw_colored_polygon(polygon_points, color)
	
	if target_type == "fuel_tank":
		draw_line(Vector2(-10, -15), Vector2(10, -15), Color(0.1, 0.3, 0.1), 2.0)

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
		GameManager.add_score(100)
		GameManager.request_screen_shake(15.0)

	queue_free()

func get_health() -> float:
	return health