extends Node2D

@onready var camera: Camera2D = $Camera2D
@onready var biplane: CharacterBody2D = $Biplane
@onready var terrain: Node2D = $Terrain
@onready var ui: CanvasLayer = $UI
@onready var minimap: Control = $UI/Minimap

const TERRAIN_LENGTH := 4096.0
const VIEWPORT_MIN_X := 0.0
const VIEWPORT_MAX_X := 1280.0
const GHOST_THRESHOLD := 300.0
const HOME_BASE := Vector2(400, 650)
const RESPAWN_DELAY := 2.0

const TITLE_SCENE := preload("res://scenes/title_screen.tscn")
const GAME_OVER_SCENE := preload("res://scenes/game_over.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/pause_menu.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy_biplane.tscn")
const GROUND_TARGET_SCENE := preload("res://scenes/ground_target.tscn")
const MINIMAP_SCENE := preload("res://scenes/minimap.tscn")

var ghost_biplane: Node2D
var ghost_terrain: Node2D
var game_state: String = "TITLE"
var title_screen: CanvasLayer = null
var pause_menu: CanvasLayer = null
var is_paused: bool = false
var respawn_timer: float = 0.0
var is_respawning: bool = false
var screen_shake_intensity: float = 0.0
var enemies: Array = []
var minimap_instance: Control = null

func _ready() -> void:
	add_to_group("main")
	_load_keybindings()
	if GameManager:
		GameManager.screen_shake_requested.connect(_on_screen_shake)
	_show_title_screen()

func get_biplane_position() -> float:
	if biplane:
		return biplane.position.x
	return 400.0

func _load_keybindings() -> void:
	var config = ConfigFile.new()
	if config.load("user://keybindings.cfg") == OK:
		var actions = ["throttle_up", "throttle_down", "pull_up", "pull_down", "roll", "fire", "bomb", "autopilot"]
		for action_name in actions:
			var keycode = config.get_value("input", action_name + "_keycode", 0)
			var physical = config.get_value("input", action_name + "_physical", 0)
			
			if (keycode > 0 or physical > 0) and InputMap.has_action(action_name):
				var event := InputEventKey.new()
				event.keycode = keycode
				event.physical_keycode = physical
				event.pressed = false
				InputMap.action_erase_events(action_name)
				InputMap.action_add_event(action_name, event)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		if game_state == "TITLE" and title_screen:
			title_screen.queue_free()
		elif game_state == "GAME_OVER":
			get_tree().reload_current_scene()

	if event.is_action_pressed("roll"):
		if game_state == "PLAYING" and not is_paused:
			_toggle_pause()

	if event.is_action_pressed("ui_cancel"):
		if game_state == "PLAYING" and not is_paused:
			_toggle_pause()

	if event.is_action_just_pressed("autopilot"):
		if game_state == "PLAYING" and biplane and biplane.has_method("enable_autopilot"):
			if biplane.autopilot_enabled:
				biplane.disable_autopilot()
			else:
				biplane.enable_autopilot()

func _toggle_pause() -> void:
	if game_state != "PLAYING":
		return

	is_paused = not is_paused

	if is_paused:
		pause_menu = PAUSE_MENU_SCENE.instantiate()
		add_child(pause_menu)
		get_tree().paused = true
	else:
		if pause_menu:
			pause_menu.queue_free()
			pause_menu = null
		get_tree().paused = false

func _on_screen_shake(intensity: float) -> void:
	screen_shake_intensity = intensity

func _show_title_screen() -> void:
	game_state = "TITLE"
	title_screen = TITLE_SCENE.instantiate()
	title_screen.start_game.connect(_on_start_game)
	add_child(title_screen)

func _on_start_game() -> void:
	game_state = "PLAYING"
	if GameManager:
		GameManager.reset_game()
	if biplane:
		biplane.position = Vector2(400, 630)
		biplane.rotation = 0
		biplane.velocity = Vector2.ZERO
		if biplane.has_method("reset_flight_state"):
			biplane.reset_flight_state()
		biplane.set_player(true)
		biplane.add_to_group("player")
		if biplane.has_signal("crashed"):
			biplane.crashed.connect(_on_biplane_crashed)
	if camera:
		camera.position = Vector2(400, 500)
	if SoundManager:
		SoundManager.play_music()
	_create_minimap()
	_create_ghost_biplane()
	_spawn_enemies_and_targets()

func _spawn_enemies_and_targets() -> void:
	enemies.clear()
	for i in range(3):
		var enemy := ENEMY_SCENE.instantiate()
		enemy.position = Vector2(800 + i * 500, 300 + randf() * 200)
		enemy.rotation = randf() * TAU
		if enemy.has_node("EnemyAI"):
			var ai := enemy.get_node("EnemyAI")
			ai.target = biplane
			ai.biplane = enemy
		add_child(enemy)
		enemies.append(enemy)

	_create_home_base()

func _create_home_base() -> void:
	var building := GROUND_TARGET_SCENE.instantiate()
	building.target_type = "building"
	building.position = Vector2(350, 650)
	building.has_aa = false
	add_child(building)
	
	var fuel_tank := GROUND_TARGET_SCENE.instantiate()
	fuel_tank.target_type = "fuel_tank"
	fuel_tank.position = Vector2(480, 640)
	fuel_tank.has_aa = false
	add_child(fuel_tank)

	for i in range(3):
		var target := GROUND_TARGET_SCENE.instantiate()
		target.target_type = ["building", "hangar", "tank"].pick_random()
		target.position = Vector2(800 + i * 600, 650)
		if target.target_type == "building":
			target.has_aa = false
		else:
			target.has_aa = randf() > 0.5
		add_child(target)

func _physics_process(delta: float) -> void:
	if game_state != "PLAYING" or is_paused:
		return

	if biplane:
		if biplane.autopilot_enabled:
			biplane.update_autopilot(HOME_BASE)

		_handle_wrap_around()
		_update_ghost_biplane()
		_update_camera(delta)
		_check_runway_landing()
		_update_ghost_terrain()
		_update_minimap()

	if is_respawning:
		respawn_timer -= delta
		if respawn_timer <= 0:
			_respawn_biplane()

func _on_biplane_crashed() -> void:
	is_respawning = true
	respawn_timer = RESPAWN_DELAY
	if SoundManager:
		SoundManager.play_explosion()

func _respawn_biplane() -> void:
	is_respawning = false
	if GameManager and GameManager.lives > 0:
		biplane.position = Vector2(400, 500)
		biplane.rotation = 0
		biplane.velocity = Vector2.ZERO
		if biplane.has_method("reset_flight_state"):
			biplane.reset_flight_state()
	else:
		_show_game_over()

func _show_game_over() -> void:
	game_state = "GAME_OVER"
	var game_over := GAME_OVER_SCENE.instantiate()
	game_over.restart_game.connect(_on_restart_game)
	add_child(game_over)

func _on_restart_game() -> void:
	get_tree().reload_current_scene()

func _update_camera(delta: float) -> void:
	if not biplane:
		return

	var look_ahead := Vector2(50, 0)
	if biplane.velocity.x < 0:
		look_ahead = Vector2(-50, 0)

	var target_pos := biplane.position + look_ahead

	if screen_shake_intensity > 0:
		target_pos += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * screen_shake_intensity
		screen_shake_intensity = max(0, screen_shake_intensity - 5.0 * delta)

	camera.position = camera.position.lerp(target_pos, delta * 2.0)

func _handle_wrap_around() -> void:
	if not biplane:
		return

	var pos := biplane.position

	if pos.x < VIEWPORT_MIN_X:
		biplane.position.x = TERRAIN_LENGTH - 1
	elif pos.x >= TERRAIN_LENGTH:
		biplane.position.x = VIEWPORT_MIN_X + 1

func _check_runway_landing() -> void:
	if not biplane or not terrain:
		return

	if terrain.has_method("is_on_runway") and terrain.has_method("get_ground_height_at"):
		var ground_y: float = terrain.get_ground_height_at(biplane.position.x)
		if terrain.is_on_runway(biplane.position.x):
			if biplane.position.y >= ground_y - 10:
				if biplane.get_speed() < 30:
					_on_landed(delta)

var refuel_rate: float = 10.0

func _on_landed(delta: float) -> void:
	if GameManager:
		if GameManager.fuel < 100:
			GameManager.refuel(refuel_rate * delta)
		if GameManager.ammo < 100:
			GameManager.reload_weapons(delta)
		if GameManager.bombs < 5:
			GameManager.reload_bombs(delta)

func _create_ghost_biplane() -> void:
	ghost_biplane = Node2D.new()
	ghost_biplane.name = "GhostBiplane"
	add_child(ghost_biplane)

	if biplane and biplane.has_node("Visual"):
		var original_visual = biplane.get_node("Visual")
		if original_visual:
			var ghost_visual = original_visual.duplicate()
			ghost_biplane.add_child(ghost_visual)
			ghost_visual.position = Vector2.ZERO
			ghost_visual.modulate.a = 0.5

func _update_ghost_biplane() -> void:
	if not ghost_biplane or not biplane:
		return

	var pos := biplane.position
	var wrapped_x := wrapf(pos.x, 0, TERRAIN_LENGTH)

	if pos.x < GHOST_THRESHOLD:
		ghost_biplane.visible = true
		ghost_biplane.position = Vector2(wrapped_x + TERRAIN_LENGTH - pos.x, pos.y)
		ghost_biplane.rotation = biplane.rotation
	elif pos.x > TERRAIN_LENGTH - GHOST_THRESHOLD:
		ghost_biplane.visible = true
		ghost_biplane.position = Vector2(wrapped_x - TERRAIN_LENGTH + pos.x, pos.y)
		ghost_biplane.rotation = biplane.rotation
	else:
		ghost_biplane.visible = false

func _create_ghost_terrain() -> void:
	ghost_terrain = Node2D.new()
	ghost_terrain.name = "GhostTerrain"
	if terrain and terrain.has_method("get_visual_line"):
		var ghost_line = terrain.get_visual_line().duplicate()
		ghost_terrain.add_child(ghost_line)
	add_child(ghost_terrain)

func _update_ghost_terrain() -> void:
	if not ghost_terrain:
		_create_ghost_terrain()

	if not biplane:
		return

	var pos := biplane.position

	if pos.x < GHOST_THRESHOLD:
		ghost_terrain.visible = true
		ghost_terrain.position.x = TERRAIN_LENGTH
		ghost_terrain.position.y = 0
	elif pos.x > TERRAIN_LENGTH - GHOST_THRESHOLD:
		ghost_terrain.visible = true
		ghost_terrain.position.x = -TERRAIN_LENGTH
		ghost_terrain.position.y = 0
	else:
		ghost_terrain.visible = false

func _create_minimap() -> void:
	minimap_instance = MINIMAP_SCENE.instantiate()
	ui.add_child(minimap_instance)
	minimap_instance.update_home(HOME_BASE.x)
	if terrain and terrain.has_method("get_ground_points"):
		minimap_instance.update_terrain(terrain.get_ground_points())

func _update_minimap() -> void:
	if not minimap_instance or not biplane:
		return
	minimap_instance.update_player(biplane.position)
	minimap_instance.update_enemies(enemies)