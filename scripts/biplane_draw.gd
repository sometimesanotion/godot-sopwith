extends Node2D

@export var plane_color: Color = Color(0.9, 0.3, 0.3)
@export var wing_color: Color = Color(0.1, 0.1, 0.2)

var _svg_sprite_name: String = "biplane"
var _svg_size: Vector2 = Vector2(80, 48)
var _draw_offset: Vector2 = Vector2(0, 0)

func _ready() -> void:
	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	queue_redraw()

func _process(_delta: float) -> void:
	var biplane = get_parent()
	if biplane and biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			if _svg_sprite_name == "biplane" and avatar.is_player:
				_svg_sprite_name = "sopwith"
				if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
					texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	queue_redraw()

func _draw() -> void:
	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		SvgManager.draw_sprite_centered(self, _svg_sprite_name, _draw_offset, _svg_size)
		return

	var body_points: PackedVector2Array = [
		Vector2(20, 0),
		Vector2(10, -4),
		Vector2(-15, -4),
		Vector2(-20, 0),
		Vector2(-15, 4),
		Vector2(10, 4)
	]
	draw_colored_polygon(body_points, plane_color)

	var wing_top: PackedVector2Array = [
		Vector2(-5, -4),
		Vector2(-5, -12),
		Vector2(8, -12),
		Vector2(8, -4)
	]
	draw_colored_polygon(wing_top, wing_color)

	var wing_bottom: PackedVector2Array = [
		Vector2(-5, 4),
		Vector2(-5, 12),
		Vector2(8, 12),
		Vector2(8, 4)
	]
	draw_colored_polygon(wing_bottom, wing_color)

	var tail: PackedVector2Array = [
		Vector2(-18, 0),
		Vector2(-24, -6),
		Vector2(-24, 6)
	]
	draw_colored_polygon(tail, plane_color)

	draw_line(Vector2(8, 0), Vector2(16, 0), wing_color, 2.0)

	draw_circle(Vector2(-10, 0), 3, plane_color.darkened(0.2))