extends RigidBody2D
class_name Cow

var _svg_sprite_name: String = "cow"
var _svg_size: Vector2 = Vector2(72, 84)
var _health: float = 100.0
var _max_health: float = 100.0

func _ready() -> void:
	mass = 450.0 + randf() * 100.0
	gravity_scale = 0.0
	add_to_group("obstacle")
	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	queue_redraw()

func _draw() -> void:
	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		SvgManager.draw_sprite_centered(self, _svg_sprite_name, Vector2(0, -14), _svg_size)
		return

	draw_colored_polygon(PackedVector2Array([
		Vector2(-15, 0), Vector2(-15, -20), Vector2(-10, -28),
		Vector2(10, -28), Vector2(15, -20), Vector2(15, 0)
	]), Color(0.9, 0.9, 0.9))

	draw_rect(Rect2(-12, -18, 8, 8), Color(0.1, 0.1, 0.1))
	draw_circle(Vector2(12, -22), 4, Color(0.1, 0.1, 0.1))

	draw_line(Vector2(-8, -28), Vector2(-10, -32), Color(0.3, 0.3, 0.3), 2)
	draw_line(Vector2(0, -28), Vector2(0, -33), Color(0.3, 0.3, 0.3), 2)
	draw_line(Vector2(8, -28), Vector2(10, -32), Color(0.3, 0.3, 0.3), 2)

	draw_circle(Vector2(10, -8), 3, Color(0.2, 0.2, 0.2))

func take_damage(amount: float, attacker: Node = null) -> void:
	_health -= amount
	if _health <= 0.0:
		_do_destroy(attacker)

func _do_destroy(attacker: Node = null) -> void:
	if GameManager and attacker:
		var bullet_owner: Node = null
		if attacker.has_method("get_bullet_owner"):
			bullet_owner = attacker.get_bullet_owner()
		elif attacker.has_method("get_bomb_owner"):
			bullet_owner = attacker.get_bomb_owner()
		if bullet_owner and bullet_owner.has_method("is_player_plane"):
			GameManager.add_score(0, -100)
	queue_free()

func _get_player_id_from_biplane(biplane: Node) -> int:
	if GameManager and GameManager.is_player(0):
		return 0
	return -1

func get_visual_top() -> float:
	return global_position.y - 14.0 - 42.0

class CowCollisionResult:
	var hit: bool = false
	var damage: float = 0.0
	var is_midair: bool = false
	var impact_speed: float = 0.0

func get_collision_response(other: Node, _other_avatar: Variant, other_speed: float) -> CowCollisionResult:
	var result := CowCollisionResult.new()
	var hit_radius: float = 40.0
	var dist := global_position.distance_to(other.global_position)
	result.impact_speed = other_speed

	if dist < hit_radius and other_speed > 10.0:
		result.hit = true
		result.damage = clampf(other_speed / 428.0, 0.25, 0.5)
		result.is_midair = true
	return result