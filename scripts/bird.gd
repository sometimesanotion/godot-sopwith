extends CharacterBody2D

var move_direction: Vector2 = Vector2(100, 0)
var wing_flap: float = 0.0
var is_scattered: bool = false
var scatter_target: Vector2 = Vector2.ZERO

var _svg_sprite_name: String = "bird"
var _svg_size: Vector2 = Vector2(20, 14)

signal bird_destroyed(pos: Vector2)

const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")
const TERRAIN_LENGTH := 16384.0

func _ready() -> void:
	add_to_group("obstacle")
	add_to_group("destructible")
	add_to_group("bird")
	motion_mode = MotionMode.MOTION_MODE_FLOATING
	move_direction = Vector2(80 + randf() * 40, randf() * 20 - 10)
	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func scatter_from(from_pos: Vector2) -> void:
	if is_scattered:
		return
	is_scattered = true
	var away_dir = (global_position - from_pos).normalized()
	var random_offset = Vector2(randf() * 100 - 50, randf() * 60 - 30)
	scatter_target = global_position + away_dir * 200 + random_offset
	move_direction = away_dir * (150 + randf() * 100) + Vector2(0, randf() * 40 - 20)

func _physics_process(delta: float) -> void:
	if is_scattered and scatter_target != Vector2.ZERO:
		var to_target = scatter_target - global_position
		if to_target.length() > 10:
			var desired_heading = to_target.normalized()
			move_direction = move_direction.lerp(desired_heading * move_direction.length(), delta * 3.0)

	var collision := move_and_collide(move_direction * delta)
	if collision:
		var collider := collision.get_collider()
		if collider and collider.has_method("take_damage") and collider.has_method("get_avatar_data"):
			var bird_damage := randi_range(10, 50)
			var av = collider.get_avatar_data(0) if collider.has_method("get_avatar_data") else null
			if av:
				collider.take_damage(av, bird_damage, self)
			else:
				collider.take_damage(bird_damage, self)
			_destroy_bird()
			return
		elif collider and collider.has_method("take_damage"):
			collider.take_damage(100.0, self)
			_destroy_bird()
			return
		else:
			_destroy_bird()
			return
	else:
		global_position += move_direction * delta

	wing_flap += delta * 15
	queue_redraw()

	if global_position.x > TERRAIN_LENGTH + 500:
		_destroy_bird()
	elif global_position.x < -500:
		_destroy_bird()

func _draw() -> void:
	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		var flip_h = move_direction.x < 0
		SvgManager.draw_sprite_flipped(self, _svg_sprite_name, Vector2.ZERO, _svg_size, flip_h)
		return

	var flap_angle = sin(wing_flap) * 0.5
	draw_line(Vector2(-8, 0), Vector2(-12, -8 * flap_angle - 4), Color(0.2, 0.2, 0.2), 2)
	draw_line(Vector2(-8, 0), Vector2(-12, 8 * flap_angle + 4), Color(0.2, 0.2, 0.2), 2)
	draw_circle(Vector2(0, 0), 4, Color(0.15, 0.15, 0.15))
	draw_line(Vector2(4, 0), Vector2(10, -2), Color(0.2, 0.2, 0.2), 2)
	draw_line(Vector2(4, 0), Vector2(10, 2), Color(0.2, 0.2, 0.2), 2)

func take_damage(amount: float, attacker: Node) -> void:
	_destroy_bird()

func _destroy_bird() -> void:
	if not is_scattered:
		_spawn_explosion_effect()
	bird_destroyed.emit(global_position)
	queue_free()

func _spawn_explosion_effect() -> void:
	if EXPLOSION_SCENE:
		var explosion = EXPLOSION_SCENE.instantiate()
		explosion.global_position = global_position
		get_parent().add_child(explosion)
		if GameManager:
			GameManager.request_screen_shake(5.0)

