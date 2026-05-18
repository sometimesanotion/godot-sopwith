extends Node2D

@onready var camera: Camera2D = $Camera2D
@onready var biplane: Biplane = $Biplane
@onready var terrain: Node2D = $Terrain
@onready var ui: CanvasLayer = $UI

const TERRAIN_LENGTH := 16384.0
const VIEWPORT_MIN_X := 0.0
const VIEWPORT_MAX_X := 1280.0
const GHOST_THRESHOLD := 300.0
const HOME_BASE := Vector2(6454, 650)
const RESPAWN_DELAY := 2.0

const TITLE_SCENE := preload("res://scenes/title_screen.tscn")
const GAME_OVER_SCENE := preload("res://scenes/game_over.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/pause_menu.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy_biplane.tscn")
const GROUND_TARGET_SCENE := preload("res://scenes/ground_target.tscn")
const MINIMAP_SCENE := preload("res://scenes/minimap.tscn")
const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")

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
var is_vs_computer: bool = false

func _ready() -> void:
	add_to_group("main")
	_load_keybindings()
	if GameManager:
		GameManager.screen_shake_requested.connect(_on_screen_shake)
	print("Main _ready: hiding game elements and showing title")
	_hide_game_elements()
	_show_title_screen()

func _hide_game_elements() -> void:
	if biplane:
		biplane.visible = false
		biplane.set_game_active(false)
	if camera:
		camera.enabled = false
	if terrain:
		terrain.visible = false
	if ui:
		ui.visible = false

func get_biplane_position() -> float:
	if biplane:
		return biplane.position.x
	return 6554.0

func _load_keybindings() -> void:
	var config = ConfigFile.new()
	if config.load("user://keybindings.cfg") == OK:
		var actions = ["throttle_up", "throttle_down", "pull_up", "pull_down", "roll", "fire", "bomb"]
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
	if event is not InputEventKey:
		return

	if event.is_action_pressed("ui_accept"):
		if game_state == "TITLE" and title_screen:
			title_screen.queue_free()
		elif game_state == "GAME_OVER":
			get_tree().reload_current_scene()

	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and (event as InputEventKey).keycode == KEY_P):
		if game_state == "PLAYING":
			_toggle_pause()

	if event.is_action_pressed("abort"):
		if game_state == "PLAYING":
			_abort_game()
	
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_Q:
			if game_state == "PLAYING" or game_state == "GAME_OVER":
				_abort_game()

func _abort_game() -> void:
	game_state = "TITLE"
	is_paused = false
	is_vs_computer = false
	if biplane:
		biplane.velocity = Vector2.ZERO
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			avatar.is_ai_controlled = false
	if pause_menu:
		pause_menu.queue_free()
		pause_menu = null
	get_tree().paused = false
	_clear_game_objects()
	_show_title_screen()

func _clear_game_objects() -> void:
	var children = get_children()
	for child in children:
		if child != biplane and child != camera and child != terrain and child != ui and child.name != "Background" and child.name != "GhostBiplane" and child.name != "GhostTerrain":
			if child.has_method("queue_free"):
				child.queue_free()

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
	print("_show_title_screen: creating title screen")
	game_state = "TITLE"
	title_screen = TITLE_SCENE.instantiate()
	title_screen.start_game.connect(_on_start_game)
	title_screen.start_vs_computer.connect(_on_start_vs_computer)
	title_screen.back_to_menu.connect(_on_back_to_menu)
	add_child(title_screen)
	print("Title screen added to scene")

func _on_back_to_menu() -> void:
	biplane = null
	_hide_game_elements()
	_show_title_screen()

func _on_start_game() -> void:
	is_vs_computer = false
	_start_playing(false)

func _on_start_vs_computer() -> void:
	is_vs_computer = true
	_start_playing(true)

func _start_playing(is_vs_computer: bool) -> void:
	game_state = "PLAYING"
	
	if biplane:
		biplane.visible = true
		biplane.set_game_active(true)
	if camera:
		camera.enabled = true
		camera.position = Vector2(6520, 400)
	if terrain:
		terrain.visible = true
	if ui:
		ui.visible = true
	
	if GameManager:
		GameManager.reset_game()
		var player_data := GameManager.register_player(0)
		player_data.set_avatar_id(0)

	var ground_y := 650.0
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(6454.0)

	if biplane:
		biplane.position = Vector2(6520, ground_y - 12)
		biplane.rotation = 0
		biplane.velocity = Vector2.ZERO
		if biplane.has_method("reset_flight_state"):
			biplane.reset_flight_state()
		var avatar := biplane.get_avatar_data(0)
		avatar.is_player = true
		if biplane.has_method("setup_homebase"):
			biplane.setup_homebase(0, 6554.0, 200.0, Vector2(6520, ground_y - 12), 0.0)
		if biplane.has_method("set_home_base"):
			biplane.set_home_base(avatar, 0)
		biplane.add_to_group("player")
		biplane.add_to_group("destructible")
		if biplane.has_signal("crashed"):
			if biplane.crashed.is_connected(_on_biplane_crashed):
				biplane.crashed.disconnect(_on_biplane_crashed)
			biplane.crashed.connect(_on_biplane_crashed)
		if biplane.has_signal("damaged"):
			if biplane.damaged.is_connected(_on_biplane_damaged):
				biplane.damaged.disconnect(_on_biplane_damaged)
			biplane.damaged.connect(_on_biplane_damaged)
	if camera:
		camera.position = Vector2(6520, 400)
	if SoundManager:
		SoundManager.play_music()
	_create_minimap()
	_create_ghost_biplane()
	_spawn_enemies_and_targets()
	if GameManager and biplane and biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			GameManager.ammo_changed.emit(0, avatar.ammo)
			GameManager.bombs_changed.emit(0, avatar.bombs)
			GameManager.fuel_changed.emit(0, avatar.fuel)

const COW_SCENE := preload("res://scenes/cow.tscn")
const BIRD_FLOCK_SCENE := preload("res://scenes/bird_flock.tscn")

var enemy_home_positions: Array[float] = []

func _spawn_enemies_and_targets() -> void:
	enemies.clear()
	enemy_home_positions.clear()
	_occupied_positions.clear()

	var enemy_base_x := [
		2458.0,
		4916.0,
		10374.0,
		14832.0
	]

	for i in range(4):
		enemy_home_positions.append(enemy_base_x[i])
		var enemy: CharacterBody2D = ENEMY_SCENE.instantiate()
		var ground_y := 650.0
		if terrain and terrain.has_method("get_ground_height_at"):
			ground_y = terrain.get_ground_height_at(enemy_base_x[i])
		enemy.position = Vector2(enemy_base_x[i] + 60, ground_y - 12)
		enemy.rotation = 0
		enemy.add_to_group("destructible")
		if enemy.has_node("EnemyAI"):
			var ai := enemy.get_node("EnemyAI")
			ai.target = biplane
			ai.biplane = enemy
			ai.home_base_x = enemy_base_x[i]
			ai.unlimited_fuel_ammo = is_vs_computer
		if enemy.has_method("get_avatar_data"):
			enemy.get_avatar_data(0).is_player = false
		if enemy.has_method("setup_homebase"):
			enemy.setup_homebase(i, enemy_base_x[i], 200.0, Vector2(enemy_base_x[i] + 60, 650 - 12), 0.0)
		if enemy.has_method("set_home_base") and enemy.has_method("get_avatar_data"):
			enemy.set_home_base(enemy.get_avatar_data(0), i)
		if enemy.has_method("set_game_active"):
			enemy.set_game_active(true)
		if is_vs_computer:
			var takeoff_delay := i * 1.5
			if enemy.has_node("EnemyAI"):
				enemy.get_node("EnemyAI").takeoff_delay = takeoff_delay
				enemy.get_node("EnemyAI").ai_state = enemy.get_node("EnemyAI").AIState.GROUNDED
		add_child(enemy)
		enemies.append(enemy)
		if terrain and terrain.has_method("add_runway"):
			terrain.add_runway(enemy_base_x[i] + 50)

	for i in range(6):
		var cow_x: float
		var attempts := 0
		while attempts < 20:
			cow_x = 200 + randf() * 16000
			var on_runway := false
			if terrain and terrain.has_method("is_on_runway"):
				on_runway = terrain.is_on_runway(cow_x)
			if not on_runway:
				break
			attempts += 1
		var cow = COW_SCENE.instantiate()
		cow.position = Vector2(cow_x, 650)
		add_child(cow)

	for i in range(1):
		var flock = BIRD_FLOCK_SCENE.instantiate()
		flock.position = Vector2(200 + randf() * 16000, 150 + randf() * 200)
		add_child(flock)

	_create_home_base()
	_create_enemy_bases()

const RUNWAY_START := 6300.0
const RUNWAY_END := 6800.0

const PLAYER_SPAWN_X := 6520.0
const SAFE_ZONE_RADIUS := 1500.0
const MIN_ENEMY_DISTANCE := 2458.0

func _get_target_half_width(target_type: String) -> float:
	match target_type:
		"building": return 35.0
		"hangar": return 45.0
		"fuel_depot": return 20.0
		"tank": return 30.0
		_: return 30.0

var _occupied_positions: Array[Vector2] = []

func _is_position_occupied(x: float, half_width: float) -> bool:
	for pos in _occupied_positions:
		if abs(x - pos.x) < (half_width + pos.y):
			return true
	return false

func _mark_position_occupied(x: float, half_width: float) -> void:
	_occupied_positions.append(Vector2(x, half_width))

func _create_home_base() -> void:
	var ground_y := 650.0
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(6454.0)

	var runway_left = RUNWAY_START
	var building_hw = _get_target_half_width("building")

	for i in range(2):
		var building_x = runway_left - 10 - building_hw - i * (building_hw * 2 + 10)
		var building := GROUND_TARGET_SCENE.instantiate()
		building.target_type = "building"
		building.position = Vector2(building_x, ground_y)
		building.has_aa = false
		building.is_enemy = false
		add_child(building)
		_mark_position_occupied(building_x, building_hw)

	var depot_hw = _get_target_half_width("fuel_depot")
	var last_building_x = runway_left - 10 - building_hw - 1 * (building_hw * 2 + 10)

	for i in range(2):
		var depot_x = last_building_x - building_hw - 10 - depot_hw - i * (depot_hw * 2 + 10)
		var fuel_depot := GROUND_TARGET_SCENE.instantiate()
		fuel_depot.target_type = "fuel_depot"
		fuel_depot.position = Vector2(depot_x, ground_y)
		fuel_depot.has_aa = false
		fuel_depot.is_enemy = false
		add_child(fuel_depot)
		_mark_position_occupied(depot_x, depot_hw)

func _create_enemy_bases() -> void:
	for home_x in enemy_home_positions:
		if abs(home_x - PLAYER_SPAWN_X) < SAFE_ZONE_RADIUS:
			continue

		var ground_y := 650.0
		if terrain and terrain.has_method("get_ground_height_at"):
			ground_y = terrain.get_ground_height_at(home_x)

		var runway_left = home_x + 50
		var building_hw = _get_target_half_width("building")

		for i in range(2):
			var building_x = runway_left - 10 - building_hw - i * (building_hw * 2 + 10)
			var building := GROUND_TARGET_SCENE.instantiate()
			building.target_type = "building"
			building.position = Vector2(building_x, ground_y)
			building.has_aa = true
			building.is_enemy = true
			building.add_to_group("enemy_target")
			add_child(building)
			_mark_position_occupied(building_x, building_hw)

		var depot_hw = _get_target_half_width("fuel_depot")
		var last_building_x = runway_left - 10 - building_hw - 1 * (building_hw * 2 + 10)

		for i in range(2):
			var depot_x = last_building_x - building_hw - 10 - depot_hw - i * (depot_hw * 2 + 10)
			var fuel_depot := GROUND_TARGET_SCENE.instantiate()
			fuel_depot.target_type = "fuel_depot"
			fuel_depot.position = Vector2(depot_x, ground_y)
			fuel_depot.has_aa = false
			fuel_depot.is_enemy = true
			fuel_depot.add_to_group("enemy_target")
			add_child(fuel_depot)
			_mark_position_occupied(depot_x, depot_hw)

		for i in range(3):
			var target_type = ["building", "hangar", "tank"].pick_random()
			var target_hw = _get_target_half_width(target_type)
			var target_x := home_x - 200 - i * 160
			var attempts := 0
			while attempts < 20:
				if not _is_position_occupied(target_x, target_hw):
					break
				target_x -= target_hw * 2 + 10
				attempts += 1
			if _is_position_occupied(target_x, target_hw):
				continue
			var target := GROUND_TARGET_SCENE.instantiate()
			target.target_type = target_type
			if terrain and terrain.has_method("get_ground_height_at"):
				target.position = Vector2(target_x, terrain.get_ground_height_at(target_x))
			else:
				target.position = Vector2(target_x, ground_y)
			if target_type == "building":
				target.has_aa = false
			else:
				target.has_aa = randf() > 0.5
			target.is_enemy = true
			target.add_to_group("enemy_target")
			add_child(target)
			_mark_position_occupied(target_x, target_hw)

func _physics_process(delta: float) -> void:
	if game_state != "PLAYING" or is_paused:
		return

	if biplane:
		_handle_wrap_around()
		_update_ghost_biplane()
		_update_camera(delta)
		_check_runway_landing(delta, biplane)
		_update_ghost_terrain()
		_update_minimap()

	if is_respawning:
		respawn_timer -= delta
		if respawn_timer <= 0:
			_respawn_biplane()

func _on_biplane_crashed() -> void:
	is_respawning = true
	respawn_timer = RESPAWN_DELAY

	if biplane and biplane.has_method("create_explosion"):
		biplane.create_explosion()
		GameManager.request_screen_shake(25.0)

	if SoundManager:
		SoundManager.play_explosion()

func _on_biplane_damaged(impact_force: float, v_perp: float) -> void:
	GameManager.request_screen_shake(10.0)
	if SoundManager:
		SoundManager.play_explosion()

func _respawn_biplane() -> void:
	is_respawning = false
	if GameManager and GameManager.get_lives(0) > 0:
		var ground_y: float = 650.0
		if terrain and terrain.has_method("get_ground_height_at"):
			ground_y = terrain.get_ground_height_at(PLAYER_SPAWN_X)
		biplane.visible = true
		biplane.position = Vector2(PLAYER_SPAWN_X, ground_y - 12)
		biplane.rotation = 0
		biplane.velocity = Vector2.ZERO
		if biplane.has_method("reset_flight_state"):
			biplane.reset_flight_state()
		if biplane.has_method("set_game_active"):
			biplane.set_game_active(true)
		if camera:
			camera.position = Vector2(PLAYER_SPAWN_X, ground_y - 250)
		if GameManager and biplane and biplane.has_method("get_avatar_data"):
			var avatar = biplane.get_avatar_data(0)
			if avatar:
				avatar.fuel = 100.0
				avatar.ammo = 100
				avatar.bombs = 5
				GameManager.fuel_changed.emit(0, avatar.fuel)
				GameManager.ammo_changed.emit(0, avatar.ammo)
				GameManager.bombs_changed.emit(0, avatar.bombs)
	else:
		_show_game_over()

func _win_game() -> void:
	game_state = "WIN"
	if GameManager:
		GameManager.game_win()

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

	var is_crashed: bool = false
	if biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			is_crashed = avatar.flight_state == biplane.FlightState.CRASHED

	var speed_coeff: float = 1.0
	var stall_speed_ms: float = 21.4 / 2.2
	if biplane.has_method("get_avatar_speed"):
		var speed_si: float = biplane.get_avatar_speed(null) / biplane.pixels_per_meter
		if speed_si > stall_speed_ms:
			speed_coeff = clampf(speed_si / stall_speed_ms, 1.0, 4.0)

	var target_pos: Vector2

	if is_crashed:
		target_pos = biplane.position
	else:
		var look_ahead_dist: float = 200.0 * speed_coeff
		var look_ahead := Vector2(look_ahead_dist, 0)
		if biplane.velocity.x < 0:
			look_ahead.x = -look_ahead_dist
		if biplane.velocity.y > 0:
			look_ahead.y = biplane.velocity.y * 1.4

		target_pos = biplane.position + look_ahead

	if screen_shake_intensity > 0:
		target_pos += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * screen_shake_intensity
		screen_shake_intensity = max(0, screen_shake_intensity - 5.0 * delta)

	var lerp_rate: float = 0.4 * speed_coeff
	camera.position = camera.position.lerp(target_pos, delta * lerp_rate)

func _handle_wrap_around() -> void:
	if not biplane:
		return

	var pos: Vector2 = biplane.position

	if pos.x < VIEWPORT_MIN_X:
		biplane.position.x = TERRAIN_LENGTH - 1
	elif pos.x >= TERRAIN_LENGTH:
		biplane.position.x = VIEWPORT_MIN_X + 1

func _check_runway_landing(delta: float, obj: Node2D) -> void:
	if not obj or not terrain:
		return

	if terrain.has_method("is_on_runway") and terrain.has_method("get_ground_height_at"):
		var ground_y: float = terrain.get_ground_height_at(biplane.position.x)
		if terrain.is_on_runway(obj.position.x):
			if obj.position.y >= ground_y - 10:
				if obj.velocity.length() < 30:
					_on_landed(delta)

var refuel_rate: float = 10.0

func _on_landed(delta: float) -> void:
	if GameManager and biplane and biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			if avatar.fuel < 100:
				avatar.fuel = min(100.0, avatar.fuel + refuel_rate * delta)
				GameManager.fuel_changed.emit(0, avatar.fuel)
			if avatar.ammo < 100:
				avatar.ammo = min(100, avatar.ammo + int(5.0 * delta))
				GameManager.ammo_changed.emit(0, avatar.ammo)
			if avatar.bombs < 5:
				avatar.bombs = min(5, avatar.bombs + 1)
				GameManager.bombs_changed.emit(0, avatar.bombs)

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

	var pos: Vector2 = biplane.position
	var wrapped_x: float = wrapf(pos.x, 0, TERRAIN_LENGTH)

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
		var visual_line = terrain.get_visual_line()
		if visual_line:
			var ghost_line = visual_line.duplicate()
			ghost_terrain.add_child(ghost_line)
	add_child(ghost_terrain)

func _update_ghost_terrain() -> void:
	if not ghost_terrain:
		_create_ghost_terrain()

	if not biplane:
		return

	var pos: Vector2 = biplane.position

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

	var enemy_targets: Array = get_tree().get_nodes_in_group("enemy_target")
	minimap_instance.update_targets(enemy_targets)

	if enemy_targets.size() == 0 and game_state == "PLAYING":
		_win_game()