extends CharacterBody2D

var gravity: float = 147.15
var explosion_radius: float = 80.0
var explosion_damage: float = 50.0

var _bomb_owner: Node = null
var has_exploded: bool = false

signal exploded(position: Vector2, radius: float, damage: float)

const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")

func _ready() -> void:
	motion_mode = MotionMode.MOTION_MODE_FLOATING
	add_to_group("destructible")
	add_to_group("bomb")

func take_damage(amount: float, attacker: Node) -> void:
	explode()

func initialize(owner: Node, inherit_velocity: Vector2) -> void:
	_bomb_owner = owner
	velocity = inherit_velocity * 0.7

func _physics_process(delta: float) -> void:
	if has_exploded:
		return

	velocity.y += gravity * delta

	var collision := move_and_collide(velocity * delta)
	if collision:
		explode()
		return
	
	_check_ground_hit()

func _check_ground_hit() -> void:
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		var ground_y = terrain.get_ground_height_at(global_position.x)
		if global_position.y >= ground_y - 5:
			explode()

func explode() -> void:
	if has_exploded:
		return
	has_exploded = true

	exploded.emit(global_position, explosion_radius, explosion_damage)

	_spawn_explosion_effect()

	var bodies := get_tree().get_nodes_in_group("destructible")
	for body in bodies:
		if body == self:
			continue
		if body is Node2D and body.global_position.distance_to(global_position) < explosion_radius:
			if body.has_method("take_damage"):
				if body.has_method("is_player_plane") or body.has_method("is_enemy_plane"):
					body.take_damage(200.0, _bomb_owner)
				else:
					body.take_damage(explosion_damage, _bomb_owner)

	queue_free()

func _spawn_explosion_effect() -> void:
	var explosion: GPUParticles2D = EXPLOSION_SCENE.instantiate()
	explosion.global_position = global_position
	get_parent().add_child(explosion)

	if GameManager:
		GameManager.request_screen_shake(20.0)

func get_bomb_owner() -> Node:
	return _bomb_owner