extends StaticBody2D

var _svg_sprite_name: String = "cow"
var _svg_size: Vector2 = Vector2(72, 84)

func _ready() -> void:
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

func take_damage(amount: float, attacker: Node) -> void:
	if GameManager:
		var player_id := 0
		if attacker:
			if attacker.has_method("get_bullet_owner"):
				var bullet_owner = attacker.get_bullet_owner()
				if bullet_owner and bullet_owner.has_method("is_player_plane"):
					player_id = _get_player_id_from_biplane(bullet_owner)
			elif attacker.has_method("is_player_plane"):
				player_id = _get_player_id_from_biplane(attacker)
		GameManager.add_score(player_id, -100)
	queue_free()

func _get_player_id_from_biplane(biplane: Node) -> int:
	var avatar = Biplane.get_avatar(0)
	if avatar and avatar.is_player:
		return avatar.id
	return 0