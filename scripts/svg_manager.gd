extends Node

var _sprite_cache: Dictionary = {}
var _animation_cache: Dictionary = {}

const SVG_PATH := "res://assets/svg/"
const KNOWN_SPRITES := [
	"biplane", "cow", "bird", "fuel_depot", "runway",
	"hangar", "building", "tank", "cloud"
]
const ANIMATION_FPS := 8.0

func _ready() -> void:
	_preload_sprites()

func _preload_sprites() -> void:
	for name in KNOWN_SPRITES:
		_try_load_sprite(name)
	for name in KNOWN_SPRITES:
		_detect_animation(name)

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

func _detect_animation(base_name: String) -> void:
	var frames: Array = []
	var i := 1
	while true:
		var frame_name := base_name + "_" + "%02d" % i
		var path := SVG_PATH + frame_name + ".svg"
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex:
				_sprite_cache[frame_name] = tex
				frames.append(tex)
				i += 1
				continue
		break
	if frames.size() > 1:
		_animation_cache[base_name] = frames

func has_sprite(name: String) -> bool:
	if _sprite_cache.has(name) and _sprite_cache[name] != null:
		return true
	return _try_load_sprite(name) != null

func get_sprite(name: String) -> Texture2D:
	if _sprite_cache.has(name):
		return _sprite_cache[name]
	return _try_load_sprite(name)

func has_animation(name: String) -> bool:
	return _animation_cache.has(name)

func get_animation_frame(name: String, time: float, fps: float = ANIMATION_FPS) -> Texture2D:
	if _animation_cache.has(name):
		var frames: Array = _animation_cache[name]
		var index: int = int(time * fps) % frames.size()
		return frames[index]
	return get_sprite(name)

func get_animation_frame_count(name: String) -> int:
	if not _animation_cache.has(name):
		return 0
	return _animation_cache[name].size()

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

func draw_animation_frame_fit(canvas: CanvasItem, anim_name: String, time: float, rect: Rect2, fps: float = ANIMATION_FPS, modulate: Color = Color.WHITE) -> bool:
	var tex := get_animation_frame(anim_name, time, fps)
	if not tex:
		return false
	canvas.draw_texture_rect(tex, rect, false, modulate)
	return true

func draw_animation_frame_centered(canvas: CanvasItem, anim_name: String, center: Vector2, size: Vector2, time: float, fps: float = ANIMATION_FPS, modulate: Color = Color.WHITE) -> bool:
	var tex := get_animation_frame(anim_name, time, fps)
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

func draw_animation_frame_flipped(canvas: CanvasItem, anim_name: String, center: Vector2, size: Vector2, time: float, flip_h: bool = false, fps: float = ANIMATION_FPS, modulate: Color = Color.WHITE) -> bool:
	var tex := get_animation_frame(anim_name, time, fps)
	if not tex:
		return false
	if flip_h:
		var rect := Rect2(center.x + size.x * 0.5, center.y - size.y * 0.5, -size.x, size.y)
		canvas.draw_texture_rect(tex, rect, false, modulate)
	else:
		var rect := Rect2(center.x - size.x * 0.5, center.y - size.y * 0.5, size.x, size.y)
		canvas.draw_texture_rect(tex, rect, false, modulate)
	return true