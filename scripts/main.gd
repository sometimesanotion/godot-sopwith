extends Node2D

@onready var camera: Camera2D = $Camera2D
@onready var biplane: Biplane = $Biplane
@onready var terrain: Node2D = $Terrain
@onready var ui: CanvasLayer = $UI

const TERRAIN_LENGTH := 16384.0
const VIEWPORT_MIN_X := 0.0
const VIEWPORT_MAX_X := 1280.0
const HOME_BASE := Vector2(6500, 650)
const RESPAWN_DELAY := 2.0

const RUNWAY_START := 6500.0
const RUNWAY_END := 7100.0

const PLAYER_SPAWN_X := 6530.0
const SAFE_ZONE_RADIUS := 1500.0
const MIN_ENEMY_DISTANCE := 2458.0

const TITLE_SCENE := preload("res://scenes/title_screen.tscn")
const GAME_OVER_SCENE := preload("res://scenes/game_over.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/pause_menu.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy_biplane.tscn")
const GROUND_TARGET_SCENE := preload("res://scenes/ground_target.tscn")
const MINIMAP_SCENE := preload("res://scenes/minimap.tscn")
const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")
const LEVEL_COMPLETE_SCENE := preload("res://scenes/level_complete.tscn")

var game_state: String = "TITLE"
var title_screen: CanvasLayer = null
var pause_menu: CanvasLayer = null
var is_paused: bool = false
var respawn_timer: float = 0.0
var is_respawning: bool = false
var is_waiting_for_crash_land: bool = false
var screen_shake_intensity: float = 0.0
var enemies: Array = []
var minimap_instance: Control = null
var is_vs_computer: bool = false
var _showing_title_screen: bool = false
var _respawn_guard: bool = false
var respawn_cooldown_timer: float = 0.0

func _get_plane_model_for_faction(faction: String) -> String:
	match faction:
		"United Kingdom":
			return "sopwith_camel"
		"France":
			return "spad_s13"
		"Germany":
			return "fokker_d7"
		_:
			return "sopwith_camel"

func _get_enemy_faction(player_faction: String) -> String:
	match player_faction:
		"United Kingdom", "France":
			return "Germany"
		"Germany":
			return "France"
		_:
			return "Germany"

func _ready() -> void:
	add_to_group("main")
	_load_keybindings()
	if GameManager:
		GameManager.screen_shake_requested.connect(_on_screen_shake)
	print("Main _ready: showing world with title overlay")
	_show_startup_world()

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

	if event is InputEventKey and (event as InputEventKey).keycode == KEY_P:
		if game_state == "PLAYING":
			_toggle_pause()

	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		if game_state == "PLAYING":
			_abort_game()


func _abort_game() -> void:
	if game_state != "PLAYING":
		return
	_showing_title_screen = false
	game_state = "TITLE"
	is_paused = false
	is_vs_computer = false
	if biplane:
		biplane.velocity = Vector2.ZERO
		biplane.visible = false
		biplane.set_game_active(false)
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			avatar.is_player = true
	if pause_menu:
		pause_menu.queue_free()
		pause_menu = null
	get_tree().paused = false
	_clear_game_objects()
	if SoundManager:
		SoundManager.stop_engine()
		SoundManager.stop_bomb_whistle()
	if title_screen:
		title_screen.queue_free()
		title_screen = null
	if minimap_instance:
		minimap_instance.queue_free()
		minimap_instance = null
	if ui:
		ui.visible = false
	if camera:
		camera.position = Vector2(TERRAIN_LENGTH * 0.5, 400)
		camera.zoom = Vector2(0.3, 0.3)
		camera.reset_smoothing()
	_show_title_screen()

func _clear_game_objects() -> void:
	enemies.clear()
	enemy_home_positions.clear()
	_occupied_positions.clear()
	var children = get_children()
	for child in children:
		if child != biplane and child != camera and child != terrain and child != ui and child.name != "Background":
			if child.has_method("queue_free"):
				if child.is_in_group("enemy_target"):
					child.remove_from_group("enemy_target")
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

func _show_startup_world() -> void:
	if title_screen and is_instance_valid(title_screen):
		return
	if terrain and terrain.has_method("generate"):
		terrain.generate()
		terrain.visible = true
	if camera:
		camera.enabled = true
		camera.position = Vector2(TERRAIN_LENGTH * 0.5, 400)
		camera.zoom = Vector2(0.3, 0.3)
		camera.reset_smoothing()
	if biplane:
		biplane.visible = false
		biplane.set_game_active(false)
	if ui:
		ui.visible = false
	_show_title_screen()

func _show_title_screen() -> void:
	if _showing_title_screen:
		print("_show_title_screen blocked (flag already true)")
		return
	_showing_title_screen = true
	game_state = "TITLE"
	title_screen = TITLE_SCENE.instantiate()
	title_screen.start_single_player.connect(_on_start_game)
	title_screen.start_network_game.connect(_on_start_network_game)
	title_screen.back_to_menu.connect(_on_back_to_menu)
	add_child(title_screen)
	print("Title screen added to scene")

func _on_back_to_menu() -> void:
	_showing_title_screen = false
	_clear_game_objects()
	if minimap_instance:
		minimap_instance.queue_free()
		minimap_instance = null
	_show_startup_world()

func _on_start_game() -> void:
	is_vs_computer = false
	_start_playing()

func _on_start_network_game() -> void:
	is_vs_computer = false
	_start_playing()

func _start_playing() -> void:
	game_state = "PLAYING"
	_showing_title_screen = false

	if title_screen:
		title_screen.queue_free()
		title_screen = null

	if terrain and terrain.has_method("generate"):
		terrain.visible = true

	if biplane:
		biplane.visible = true
		biplane.set_game_active(true)
		if SoundManager:
			SoundManager.start_engine()
			SoundManager.set_engine_rpm(0.0)
	if camera:
		camera.enabled = true
		camera.zoom = Vector2(1, 1)
		camera.position = Vector2(PLAYER_SPAWN_X, 400)
	if ui:
		ui.visible = true

	if GameManager:
		GameManager.reset_game()
		var player_data := GameManager.register_player(0)
		player_data.set_avatar_id(0)

	var ground_y := 650.0
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(PLAYER_SPAWN_X)

	if biplane:
		biplane.position = Vector2(PLAYER_SPAWN_X, ground_y - 12)
		biplane.rotation = 0
		biplane.velocity = Vector2.ZERO
		if biplane.has_method("reset_flight_state"):
			biplane.reset_flight_state()
		var avatar := biplane.get_avatar_data(0)
		avatar.is_player = true
		if biplane.has_method("assign_plane_model"):
			var player_model := _get_plane_model_for_faction(GameManager.player_faction if GameManager else "United Kingdom")
			biplane.assign_plane_model(avatar, player_model)
			avatar.bombs = avatar.model_params.get("max_bombs", 0)
		if biplane.has_method("setup_faction_homebase"):
			var player_faction_enum = Biplane.Faction.BRITISH
			if GameManager.player_faction == "France":
				player_faction_enum = Biplane.Faction.FRENCH
			elif GameManager.player_faction == "Germany":
				player_faction_enum = Biplane.Faction.GERMAN
			biplane.setup_faction_homebase(0, PLAYER_SPAWN_X, 200.0, Vector2(PLAYER_SPAWN_X, ground_y - 12), 0.0, player_faction_enum)
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
		camera.position = Vector2(PLAYER_SPAWN_X, 400)
	_create_minimap()
	_spawn_enemies_and_targets()
	_create_home_base()
	_create_enemy_bases()
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

	var num_bases: int = GameManager.enemy_homebases if GameManager else 4
	var possible_bases: Array[float] = [
		2458.0,
		4916.0,
		7500.0,
		10374.0,
		12500.0,
		14832.0
	]
	possible_bases = possible_bases.slice(0, num_bases)

	var spawn_enemies: bool = GameManager.enemy_planes if GameManager else true

	var enemy_faction_str := _get_enemy_faction(GameManager.player_faction if GameManager else "United Kingdom")
	var enemy_faction_enum = Biplane.Faction.GERMAN if enemy_faction_str == "Germany" else Biplane.Faction.BRITISH

	for i in range(possible_bases.size()):
		var base_x: float = possible_bases[i]
		enemy_home_positions.append(base_x)
		if not spawn_enemies:
			continue
		var enemy: CharacterBody2D = ENEMY_SCENE.instantiate()
		var ground_y := 650.0
		if terrain and terrain.has_method("get_ground_height_at"):
			ground_y = terrain.get_ground_height_at(base_x)
		enemy.position = Vector2(base_x + 50, ground_y - 12)
		enemy.rotation = 0
		enemy.add_to_group("destructible")
		if enemy.has_node("EnemyAI"):
			var ai := enemy.get_node("EnemyAI")
			ai.target = biplane
			ai.biplane = enemy
			ai.home_base_x = base_x
			ai.unlimited_fuel_ammo = is_vs_computer
		if enemy.has_method("setup_faction_homebase"):
			enemy.setup_faction_homebase(i, base_x, 200.0, Vector2(base_x + 50, 650 - 12), 0.0, enemy_faction_enum)
		if enemy.has_method("get_avatar_data"):
			var enemy_avatar = enemy.get_avatar_data(0)
			enemy_avatar.is_player = false
			if enemy.has_method("assign_plane_model") and enemy.has_method("get_default_plane_model"):
				var enemy_model = enemy.get_default_plane_model(enemy_faction_enum)
				enemy.assign_plane_model(enemy_avatar, enemy_model)
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
			terrain.add_runway(base_x + 50)

	var lm: float = GameManager.get_level_multiplier() if GameManager else 1.0
	var cow_count_map: Dictionary = {"None": 0, "Few": 6, "Normal": 12, "Many": 24}
	var num_cows: int = int(cow_count_map.get(GameManager.cow_count if GameManager else "Normal", 6) * lm)
	for i in range(num_cows):
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
		var cow: Node2D = COW_SCENE.instantiate()
		cow.position = Vector2(cow_x, 650)
		add_child(cow)

	var bird_count_map: Dictionary = {"None": 0, "Few": 3, "Normal": 5, "Many": 8}
	var num_birds: int = int(bird_count_map.get(GameManager.bird_count if GameManager else "Normal", 6) * lm)
	for i in range(num_birds):
		var flock: Node2D = BIRD_FLOCK_SCENE.instantiate()
		flock.position = Vector2(200 + randf() * 16000, 150 + randf() * 200)
		add_child(flock)

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
		ground_y = terrain.get_ground_height_at(PLAYER_SPAWN_X)

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
	var lm: float = GameManager.get_level_multiplier() if GameManager else 1.0
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

		var tanks_setting: String = GameManager.enemy_tanks if GameManager else "Normal"
		var num_extra: Dictionary = {"None": 0, "Few": 1, "Normal": 3, "Many": 6}
		var extra_count: int = int(num_extra.get(tanks_setting, 3) * lm)
		for i in range(extra_count):
			var target_type: String = ["building", "hangar", "tank"].pick_random()
			var target_hw: float = _get_target_half_width(target_type)
			var target_x: float = home_x - 200 - i * 160
			var attempts := 0
			while attempts < 20:
				if not _is_position_occupied(target_x, target_hw):
					break
				target_x -= target_hw * 2 + 10
				attempts += 1
			if _is_position_occupied(target_x, target_hw):
				continue
			var target: Node2D = GROUND_TARGET_SCENE.instantiate()
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
		_update_camera(delta)
		_update_minimap()

	if is_waiting_for_crash_land:
		if biplane and biplane.has_method("get_avatar_data"):
			var avatar = biplane.get_avatar_data(0)
			if avatar and avatar.has_hit_ground:
				is_waiting_for_crash_land = false
				is_respawning = true
				respawn_timer = RESPAWN_DELAY

	if is_respawning:
		respawn_timer -= delta
		if respawn_timer <= 0:
			_respawn_biplane()

	if respawn_cooldown_timer > 0.0:
		respawn_cooldown_timer -= delta

func _on_biplane_crashed() -> void:
	if _respawn_guard:
		return
	if respawn_cooldown_timer > 0.0:
		return
	_respawn_guard = true
	is_waiting_for_crash_land = true

	if biplane and biplane.has_method("create_explosion"):
		biplane.create_explosion()
		GameManager.request_screen_shake(25.0)

	if SoundManager:
		SoundManager.stop_engine()
		SoundManager.play_sfx(SoundManager.SoundEvent.EXPLOSION)

func _on_biplane_damaged(impact_force: float, v_perp: float) -> void:
	GameManager.request_screen_shake(10.0)
	if SoundManager:
		SoundManager.play_sfx(SoundManager.SoundEvent.BUMP)

func _respawn_biplane() -> void:
	if not is_respawning:
		return
	is_respawning = false
	_respawn_guard = false
	respawn_cooldown_timer = 5.0
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
				avatar.ammo = 500
				avatar.bombs = avatar.model_params.get("max_bombs", 0)
				GameManager.fuel_changed.emit(0, avatar.fuel)
				GameManager.ammo_changed.emit(0, avatar.ammo)
				GameManager.bombs_changed.emit(0, avatar.bombs)
	else:
		_show_game_over()

func _win_game() -> void:
	game_state = "LEVEL_COMPLETE"
	if GameManager:
		GameManager.game_win()
	var level_complete := LEVEL_COMPLETE_SCENE.instantiate()
	level_complete.next_level.connect(_on_next_level)
	add_child(level_complete)

func _on_next_level() -> void:
	game_state = "PLAYING"
	if GameManager:
		GameManager.current_level += 1
	_clear_game_objects()
	if biplane:
		biplane.set_game_active(false)
		biplane.visible = false
	_spawn_enemies_and_targets()
	_create_home_base()
	_create_enemy_bases()
	if minimap_instance and minimap_instance.has_method("clear"):
		minimap_instance.clear()
	if biplane:
		var ground_y := 650.0
		if terrain and terrain.has_method("get_ground_height_at"):
			ground_y = terrain.get_ground_height_at(PLAYER_SPAWN_X)
		biplane.position = Vector2(PLAYER_SPAWN_X, ground_y - 12)
		biplane.rotation = 0
		biplane.velocity = Vector2.ZERO
		if biplane.has_method("reset_flight_state"):
			biplane.reset_flight_state()
		var avatar := biplane.get_avatar_data(0) if biplane.has_method("get_avatar_data") else null
		if avatar:
			avatar.fuel = 100.0
			avatar.ammo = 500
			avatar.bombs = avatar.model_params.get("max_bombs", 0)
		biplane.set_game_active(true)
		biplane.visible = true
		if camera:
			camera.position = Vector2(PLAYER_SPAWN_X, ground_y - 250)

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

	var avatar = biplane.get_avatar_data(0) if biplane.has_method("get_avatar_data") else null

	var is_crashed: bool = avatar and avatar.flight_state == biplane.FlightState.CRASHED
	var is_landed: bool = avatar and avatar.flight_state == biplane.FlightState.LANDED

	var speed_coeff: float = 1.0
	var target_pos: Vector2

	if is_crashed or is_landed:
		target_pos = biplane.position
	else:
		var stall_speed_ms: float = 21.4 / 2.2
		if biplane.has_method("get_avatar_speed"):
			var speed_si: float = biplane.get_avatar_speed(null) / biplane.pixels_per_meter
			if speed_si > stall_speed_ms:
				speed_coeff = clampf(speed_si / stall_speed_ms, 1.0, 4.0)

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

	## Limit camera Y so ground occupies ≤20% of viewport height.
	var ground_y := 650.0
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(target_pos.x)
	var view_h := get_viewport_rect().size.y
	var max_camera_y := ground_y - 0.3 * view_h / camera.zoom.y
	target_pos.y = minf(target_pos.y, max_camera_y)

	var lerp_rate: float = 0.4 if is_landed else 0.4 * speed_coeff
	camera.position = camera.position.lerp(target_pos, delta * lerp_rate)

func _handle_wrap_around() -> void:
	if not biplane:
		return

	var pos: Vector2 = biplane.position

	if pos.x < VIEWPORT_MIN_X:
		biplane.position.x = TERRAIN_LENGTH - 1
		camera.position.x += TERRAIN_LENGTH
	elif pos.x >= TERRAIN_LENGTH:
		biplane.position.x = VIEWPORT_MIN_X + 1
		camera.position.x -= TERRAIN_LENGTH


func _create_minimap() -> void:
	minimap_instance = MINIMAP_SCENE.instantiate()
	ui.add_child(minimap_instance)
	var design_w: float = ProjectSettings.get_setting("display/window/size/viewport_width", 1920)
	minimap_instance.position = Vector2((design_w - 574) / 2, 20)
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

	var birds: Array = get_tree().get_nodes_in_group("flock")
	minimap_instance.update_birds(birds)

	if enemy_targets.size() == 0 and game_state == "PLAYING":
		_win_game()