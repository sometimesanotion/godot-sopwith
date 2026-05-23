extends Node

var _sprite_cache: Dictionary = {}

const SVG_PATH := "res://assets/svg/"
const KNOWN_SPRITES := [
	"sopwith_camel", "fokker_d7", "cow", "bird", "fuel_depot", "building",
	"tank", "cloud", "bomb", "p-51", "spad_s13", "se5a"
]

func _ready() -> void:
	_preload_sprites()

func _preload_sprites() -> void:
	for name in KNOWN_SPRITES:
		_try_load_sprite(name)

func _try_load_sprite(name: String) -> Texture2D:
	if _sprite_cache.has(name):
		return _sprite_cache[name]
	var path := SVG_PATH + name + ".svg"
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex:
			_sprite_cache[name] = tex
			return tex
	return null

func has_sprite(name: String) -> bool:
	if _sprite_cache.has(name) and _sprite_cache[name] != null:
		return true
	return _try_load_sprite(name) != null

func get_sprite(name: String) -> Texture2D:
	if _sprite_cache.has(name):
		return _sprite_cache[name]
	return _try_load_sprite(name)

func calc_draw_rect(points: PackedVector2Array, padding: float = 0.0) -> Rect2:
	if points.size() < 2:
		return Rect2()
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for pt in points:
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)
		min_y = min(min_y, pt.y)
		max_y = max(max_y, pt.y)
	return Rect2(min_x - padding, min_y - padding, max_x - min_x + padding * 2, max_y - min_y + padding * 2)

func draw_sprite_fit(canvas: CanvasItem, name: String, rect: Rect2, modulate: Color = Color.WHITE) -> bool:
	var tex := get_sprite(name)
	if not tex:
		return false
	canvas.draw_texture_rect(tex, rect, false, modulate)
	return true

func draw_sprite_centered(canvas: CanvasItem, name: String, center: Vector2, size: Vector2, modulate: Color = Color.WHITE) -> bool:
	var tex := get_sprite(name)
	if not tex:
		return false
	var rect := Rect2(center.x - size.x * 0.5, center.y - size.y * 0.5, size.x, size.y)
	canvas.draw_texture_rect(tex, rect, false, modulate)
	return true

func draw_sprite_flipped(canvas: CanvasItem, name: String, center: Vector2, size: Vector2, flip_h: bool = false, modulate: Color = Color.WHITE) -> bool:
	var tex := get_sprite(name)
	if not tex:
		return false
	if flip_h:
		var rect := Rect2(center.x + size.x * 0.5, center.y - size.y * 0.5, -size.x, size.y)
		canvas.draw_texture_rect(tex, rect, false, modulate)
	else:
		var rect := Rect2(center.x - size.x * 0.5, center.y - size.y * 0.5, size.x, size.y)
		canvas.draw_texture_rect(tex, rect, false, modulate)
	return true

