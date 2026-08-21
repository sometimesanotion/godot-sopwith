extends Node

## GraphicsSettings — autoload singleton for window mode and resolution.
## Applies immediately and persists to user://graphics.cfg.
## Other nodes connect to settings_changed to adapt layouts.

signal settings_changed

enum WindowMode { WINDOWED, BORDERLESS, FULLSCREEN }

var window_mode: int = WindowMode.FULLSCREEN
var resolution_x: int = 3440
var resolution_y: int = 1440

const COMMON_WIDTHS := [1280, 1366, 1600, 1920, 2560, 3440, 3840]
const COMMON_HEIGHTS := [720, 768, 900, 1080, 1200, 1440, 2160]
const DESIGN_WIDTH := 3440
const DESIGN_HEIGHT := 1440

func _ready() -> void:
	_load_settings()
	apply_settings()

func apply_settings() -> void:
	_apply_window()
	_apply_viewport_size()
	settings_changed.emit()
	_save_settings()

func _apply_window() -> void:
	match window_mode:
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(Vector2i(resolution_x, resolution_y))
		WindowMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(Vector2i(resolution_x, resolution_y))

func _apply_viewport_size() -> void:
	ProjectSettings.set_setting("display/window/size/viewport_width", resolution_x)
	ProjectSettings.set_setting("display/window/size/viewport_height", resolution_y)
	get_viewport().set_size(Vector2i(resolution_x, resolution_y))

func get_window_mode_name() -> String:
	match window_mode:
		WindowMode.WINDOWED: return "Windowed"
		WindowMode.BORDERLESS: return "Borderless"
		WindowMode.FULLSCREEN: return "Fullscreen"
	return "Windowed"

func cycle_window_mode() -> void:
	window_mode = (window_mode + 1) % 3
	apply_settings()

func cycle_resolution_width() -> void:
	var idx := COMMON_WIDTHS.find(resolution_x)
	idx = (idx + 1) % COMMON_WIDTHS.size()
	resolution_x = COMMON_WIDTHS[idx]
	apply_settings()

func cycle_resolution_height() -> void:
	var idx := COMMON_HEIGHTS.find(resolution_y)
	idx = (idx + 1) % COMMON_HEIGHTS.size()
	resolution_y = COMMON_HEIGHTS[idx]
	apply_settings()

func fit_to_screen() -> void:
	var screen_id := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen_id)
	resolution_x = screen_size.x
	resolution_y = screen_size.y
	window_mode = WindowMode.FULLSCREEN
	apply_settings()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://graphics.cfg") == OK:
		window_mode = cfg.get_value("graphics", "window_mode", WindowMode.FULLSCREEN)
		resolution_x = cfg.get_value("graphics", "resolution_x", 3440)
		resolution_y = cfg.get_value("graphics", "resolution_y", 1440)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "window_mode", window_mode)
	cfg.set_value("graphics", "resolution_x", resolution_x)
	cfg.set_value("graphics", "resolution_y", resolution_y)
	cfg.save("user://graphics.cfg")
