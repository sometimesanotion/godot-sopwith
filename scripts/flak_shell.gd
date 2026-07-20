extends CharacterBody2D

## Flak shell fired by a homebase flak cannon.  Mirrors the bomb's
## AREA-damage explosion, but at 1/10th the bomb's strength:
##   * bomb:  explosion_damage = 300,  spawn_explosion energy = 100, screen shake = 20
##   * shell: explosion_damage =  30,  spawn_explosion energy =  10, screen shake =  2
## The shell is launched (not dropped) toward the target plane and
## detonates on contact or ground impact, scorching everything in
## its blast radius rather than relying on a direct hit.

var gravity: float = 60.0
var explosion_radius: float = 100.0
var explosion_damage: float = 30.0

var _owner: Node = null
var _has_exploded: bool = false
var _lifetime: float = 1.0

signal exploded(position: Vector2, radius: float, damage: float)

func _ready() -> void:
	motion_mode = MotionMode.MOTION_MODE_FLOATING
	add_to_group("destructible")

func _draw() -> void:
	draw_circle(Vector2.ZERO, 4.0, Color(0.15, 0.15, 0.15, 1.0))

func take_damage(amount: float, attacker: Node) -> void:
	explode()

## Launch the shell from `origin` toward `direction` (unit vector) at `speed`.
func fire(owner: Node, origin: Vector2, direction: Vector2, speed: float) -> void:
	_owner = owner
	global_position = origin
	velocity = direction * speed

func _physics_process(delta: float) -> void:
	if _has_exploded:
		return
	_lifetime -= delta
	if _lifetime <= 0.0:
		explode()
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
		if global_position.y >= ground_y - 5.0:
			explode()

func explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true
	exploded.emit(global_position, explosion_radius, explosion_damage)
	_spawn_explosion_effect()
	var bodies := get_tree().get_nodes_in_group("destructible")
	for body in bodies:
		if body == self:
			continue
		if not (body is Node2D and body.has_method("take_damage")):
			continue
		var distance: float = body.global_position.distance_to(global_position)
		if distance > explosion_radius:
			continue
		var damage: float = explosion_damage * (1.0 - distance / explosion_radius)
		body.take_damage(damage, _owner)
	queue_free()

func _spawn_explosion_effect() -> void:
	if EffectManager:
		EffectManager.spawn_explosion(global_position, 10.0)
		EffectManager.spawn_bomb_explosion_ring(global_position, explosion_radius, 0.1)
		EffectManager.spawn_explosion_debris(global_position, 10.0, 4, Color(0.1, 0.1, 0.08))
	if GameManager:
		GameManager.request_screen_shake(2.0)

func get_shell_owner() -> Node:
	return _owner
