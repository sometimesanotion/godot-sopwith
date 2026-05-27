extends CharacterBody2D

var gravity: float = 147.15
var explosion_radius: float = 100.0
var explosion_damage: float = 300.0

var _bomb_owner: Node = null
var has_exploded: bool = false
var whistle_start_time: float = -1.0

var _svg_sprite_name: String = "bomb"
var _svg_size: Vector2 = Vector2(20, 25)

signal exploded(position: Vector2, radius: float, damage: float)

const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")

func _ready() -> void:
	motion_mode = MotionMode.MOTION_MODE_FLOATING
	add_to_group("destructible")
	add_to_group("bomb")
	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_hide_visual_nodes()

func _hide_visual_nodes() -> void:
	var visual = get_node_or_null("BombVisual")
	if visual:
		visual.visible = false

func take_damage(amount: float, attacker: Node) -> void:
	explode()

func initialize(owner: Node, inherit_velocity: Vector2) -> void:
	_bomb_owner = owner
	velocity = inherit_velocity * 0.8

func _physics_process(delta: float) -> void:
	if has_exploded:
		return

	velocity.y += gravity * delta

	if SoundManager:
		if whistle_start_time < 0.0 and velocity.y > 0.0:
			whistle_start_time = 0.0
			SoundManager.start_bomb_whistle()
		if whistle_start_time >= 0.0:
			whistle_start_time += delta
			var t := whistle_start_time / maxf(1.0, 3.0)
			SoundManager.set_bomb_whistle_rpm(t)

	var collision := move_and_collide(velocity * delta)
	if collision:
		explode()
		return
	
	_check_ground_hit()

	if velocity.length() > 5.0:
		rotation = velocity.angle()
	queue_redraw()

func _check_ground_hit() -> void:
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain and terrain.has_method("get_ground_height_at"):
		var ground_y = terrain.get_ground_height_at(global_position.x)
		if global_position.y >= ground_y - 5:
			explode()

func _draw() -> void:
	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		SvgManager.draw_sprite_centered(self, _svg_sprite_name, Vector2.ZERO, _svg_size)
		return

	draw_rect(Rect2(-4, -6, 8, 12), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(-8, -2, 4, 4), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(4, -2, 4, 4), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(-1, -10, 2, 4), Color(0.5, 0.3, 0.1))

func explode() -> void:
	if has_exploded:
		return
	has_exploded = true

	if SoundManager:
		SoundManager.stop_bomb_whistle()

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
		body.take_damage(damage, _bomb_owner)

	queue_free()

func _spawn_explosion_effect() -> void:
	if EffectManager:
		EffectManager.spawn_explosion(global_position, 100.0)
		EffectManager.spawn_bomb_explosion_ring(global_position, explosion_radius, 0.1)
		EffectManager.spawn_explosion_debris(global_position, Color(0.3, 0.3, 0.2), 12, 15.0)
	if GameManager:
		GameManager.request_screen_shake(20.0)

func get_bomb_owner() -> Node:
	return _bomb_owner