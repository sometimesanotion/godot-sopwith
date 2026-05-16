extends CharacterBody2D

var gravity: float = 400.0
var explosion_radius: float = 80.0
var explosion_damage: float = 50.0

var _bomb_owner: Node2D = null
var has_exploded: bool = false

signal exploded(position: Vector2, radius: float, damage: float)

const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")

func _ready() -> void:
	motion_mode = MotionMode.MOTION_MODE_FLOATING

func initialize(owner: Node2D, inherit_velocity: Vector2) -> void:
	_bomb_owner = owner
	velocity = inherit_velocity

func _physics_process(delta: float) -> void:
	if has_exploded:
		return

	velocity.y += gravity * delta
	velocity.x *= 0.99

	var collision := move_and_collide(velocity * delta)
	if collision:
		explode()

func explode() -> void:
	if has_exploded:
		return
	has_exploded = true

	exploded.emit(global_position, explosion_radius, explosion_damage)

	_spawn_explosion_effect()

	var bodies := get_tree().get_nodes_in_group("destructible")
	for body in bodies:
		if body.global_position.distance_to(global_position) < explosion_radius:
			if body.has_method("take_damage"):
				body.take_damage(explosion_damage, _bomb_owner)

	queue_free()

func _spawn_explosion_effect() -> void:
	var explosion: GPUParticles2D = EXPLOSION_SCENE.instantiate()
	explosion.global_position = global_position
	get_parent().add_child(explosion)

	if GameManager:
		GameManager.request_screen_shake(20.0)

func get_bomb_owner() -> Node2D:
	return _bomb_owner