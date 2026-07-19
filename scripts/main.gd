extends Node2D

@onready var camera: Camera2D = $Camera2D
@onready var biplane: Biplane = $Biplane
@onready var terrain: Node2D = $Terrain
@onready var background: Node2D = $Background
@onready var ui: CanvasLayer = $UI

const TERRAIN_LENGTH := 16384.0
const VIEWPORT_MIN_X := 0.0
const VIEWPORT_MAX_X := 1280.0
const HOME_BASE := Vector2(5300, 650)

# Enemy runways span [base_x + 50, base_x + 50 + LEN] (rightward) or
# [base_x - 50 - LEN, base_x - 50] (leftward), LEN = Terrain.RUNWAY_LENGTH.
# from the runway edge facing their takeoff direction (so they have the full
# runway ahead for the roll): rightward launchers sit on the left edge, leftward
# launchers (the inverted east-side bases) sit on the right edge.  Both are
# the same distance from the building cluster that lives just before the
# runway's "back" end.
const ENEMY_SPAWN_RUNWAY_EDGE_MARGIN := 30.0
const ENEMY_SPAWN_RUNWAY_OFFSET := 50.0 + ENEMY_SPAWN_RUNWAY_EDGE_MARGIN  # 80.0

const PLAYER_SPAWN_X := 5330.0
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
var screen_shake_intensity: float = 0.0
var enemies: Array = []
var minimap_instance: Control = null
var is_vs_computer: bool = false
var _showing_title_screen: bool = false
## Set once per life so the ground-impact re-signal (biplane respawn timer
## shortening) does not spawn a second player explosion/sfx.
var _player_crashed_exploded: bool = false

func _get_plane_model_for_faction(faction: String) -> String:
	match faction:
		"British":
			return "sopwith_camel"
		"French":
			return "spad_s13"
		"German":
			return "fokker_d7"
		_:
			return "sopwith_camel"

func _get_enemy_faction(player_faction: String) -> String:
	match player_faction:
		"British", "French":
			return "German"
		"German":
			return "French"
		_:
			return "German"

func _ready() -> void:
	add_to_group("main")
	_load_keybindings()
	if GameManager:
		GameManager.screen_shake_requested.connect(_on_screen_shake)
	if RespawnManager:
		if RespawnManager.respawn_ready.is_connected(_respawn_biplane):
			RespawnManager.respawn_ready.disconnect(_respawn_biplane)
		RespawnManager.respawn_ready.connect(_respawn_biplane)
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
	if RespawnManager:
		RespawnManager.clear_all()
	is_paused = false
	is_vs_computer = false
	if biplane:
		var ground_y := 650.0
		if terrain and terrain.has_method("get_ground_height_at"):
			ground_y = terrain.get_ground_height_at(PLAYER_SPAWN_X)
		biplane.teleport_to(Vector2(PLAYER_SPAWN_X, ground_y - Biplane.GROUND_SURFACE_OFFSET))
		biplane.visible = false
		biplane.set_game_active(false)
		if GameManager:
			GameManager.get_player_data(0).is_player = true
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
	if biplane:
		var ground_y := 650.0
		if terrain and terrain.has_method("get_ground_height_at"):
			ground_y = terrain.get_ground_height_at(PLAYER_SPAWN_X)
		biplane.teleport_to(Vector2(PLAYER_SPAWN_X, ground_y - Biplane.GROUND_SURFACE_OFFSET))
		biplane.visible = false
		biplane.set_game_active(false)
	if terrain and terrain.has_method("generate"):
		terrain.generate()
		terrain.visible = true
	if background and background.has_method("generate"):
		background.generate(terrain.resolved_seed)
	if camera:
		camera.enabled = true
		camera.position = Vector2(TERRAIN_LENGTH * 0.5, 400)
		camera.zoom = Vector2(0.3, 0.3)
		camera.reset_smoothing()
	if ui:
		ui.visible = false
	if title_screen and is_instance_valid(title_screen):
		title_screen.queue_free()
		title_screen = null
		_showing_title_screen = false
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

	var ground_y := 650.0
	if terrain and terrain.has_method("get_ground_height_at"):
		ground_y = terrain.get_ground_height_at(PLAYER_SPAWN_X)

	biplane.visible = true
	biplane.set_game_active(true)

	if GameManager:
		GameManager.reset_game()
		var player_data := GameManager.register_player(0)
		player_data.set_avatar_id(0)
		var avatar := biplane.get_avatar_data(0)
		if biplane.has_method("assign_plane_model"):
			var player_model := _get_plane_model_for_faction(GameManager.player_faction if GameManager else "British")
			biplane.assign_plane_model(avatar, player_model)
			avatar.bombs = avatar.model_params.get("max_bombs", 0)
		if biplane.has_method("setup_faction_homebase"):
			var player_faction_enum = Biplane.Faction.BRITISH
			if GameManager.player_faction == "French":
				player_faction_enum = Biplane.Faction.FRENCH
			elif GameManager.player_faction == "German":
				player_faction_enum = Biplane.Faction.GERMAN
			biplane.setup_faction_homebase(0, PLAYER_SPAWN_X, 200.0, Vector2(PLAYER_SPAWN_X, ground_y - Biplane.GROUND_SURFACE_OFFSET), 0.0, player_faction_enum)
		if biplane.has_method("set_home_base"):
			biplane.set_home_base(avatar, 0)

	if biplane.has_method("respawn"):
		biplane.respawn(0, camera)
	elif biplane.has_method("teleport_to"):
		biplane.teleport_to(Vector2(PLAYER_SPAWN_X, ground_y - Biplane.GROUND_SURFACE_OFFSET))
	else:
		biplane.position = Vector2(PLAYER_SPAWN_X, ground_y - Biplane.GROUND_SURFACE_OFFSET)
		biplane.rotation = 0
		biplane.velocity = Vector2.ZERO

	if SoundManager:
		SoundManager.start_engine()
		SoundManager.set_engine_rpm(0.0)
	if camera:
		camera.enabled = true
		camera.zoom = Vector2(1, 1)
		camera.position = Vector2(PLAYER_SPAWN_X, 400)
	if ui:
		ui.visible = true

	biplane.add_to_group("player")
	biplane.is_player_controlled = true
	biplane.add_to_group("destructible")
	if biplane.has_signal("crashed"):
		if biplane.crashed.is_connected(_on_biplane_crashed):
			biplane.crashed.disconnect(_on_biplane_crashed)
		biplane.crashed.connect(_on_biplane_crashed)
	if biplane.has_signal("crashed_landed"):
		if biplane.crashed_landed.is_connected(_on_biplane_landed):
			biplane.crashed_landed.disconnect(_on_biplane_landed)
		biplane.crashed_landed.connect(_on_biplane_landed)
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
## Parallel to enemy_home_positions: true if this base launches leftward
## (runway sits on the left of base_x, buildings on the right).  Set in
## _spawn_enemies_and_targets; consumed by _create_enemy_bases.
var enemy_base_faces_left: Array[bool] = []

func _spawn_enemies_and_targets() -> void:
	enemies.clear()
	enemy_home_positions.clear()
	_occupied_positions.clear()

	var num_bases: int = GameManager.enemy_homebases if GameManager else 4
	# D10 base layout: one base west of the player, the rest east.  The east
	# bases spawn inverted (leftward launch) via `faces_left`.  Consecutive
	# bases are spaced 2500 px apart (≥ MIN_ENEMY_DISTANCE) and all runways
	# fit inside the map; both invariants are checked by _validate_base_layout.
	var possible_bases: Array[float] = [
		2400.0,
		8000.0,
		10500.0,
		13000.0,
		15500.0,
	]
	possible_bases = possible_bases.slice(0, num_bases)
	_validate_base_layout(possible_bases)

	var spawn_enemies: bool = GameManager.enemy_planes if GameManager else true

	var enemy_faction_str := _get_enemy_faction(GameManager.player_faction if GameManager else "British")
	var enemy_faction_enum: int
	match enemy_faction_str:
		"German":
			enemy_faction_enum = Biplane.Faction.GERMAN
		"French":
			enemy_faction_enum = Biplane.Faction.FRENCH
		_:
			enemy_faction_enum = Biplane.Faction.BRITISH

	for i in range(possible_bases.size()):
		var base_x: float = possible_bases[i]
		enemy_home_positions.append(base_x)
		# D10: enemies east of the player spawn inverted and launch leftward.
		# Respawn path (`biplane.respawn`) already handles inversion via the
		# homebase `spawn_rotation`; we just need the initial spawn to match.
		var faces_left := base_x > PLAYER_SPAWN_X
		enemy_base_faces_left.append(faces_left)
		if not spawn_enemies:
			continue
		var spawn_rot := PI if faces_left else 0.0
		var enemy: RigidBody2D = ENEMY_SCENE.instantiate()
		var ground_y := 650.0
		if terrain and terrain.has_method("get_ground_height_at"):
			ground_y = terrain.get_ground_height_at(base_x)
		# Runway span: rightward bases → [base_x+50, base_x+50+LEN] (runway on
		# the right); leftward bases → [base_x-50-LEN, base_x-50] (runway on
		# the left).  LEN = Terrain.RUNWAY_LENGTH (widened 20% in T-runway).
		var runway_left: float = (base_x - (Terrain.RUNWAY_LENGTH + 50.0)) if faces_left else (base_x + 50.0)
		var runway_right: float = runway_left + Terrain.RUNWAY_LENGTH
		var spawn_x: float = (runway_right - ENEMY_SPAWN_RUNWAY_EDGE_MARGIN) if faces_left \
							else (runway_left + ENEMY_SPAWN_RUNWAY_EDGE_MARGIN)
		var spawn_pos := Vector2(spawn_x, ground_y - Biplane.GROUND_SURFACE_OFFSET)
		enemy.position = spawn_pos
		enemy.rotation = spawn_rot
		enemy.add_to_group("destructible")
		if enemy.has_node("EnemyAI"):
			var ai := enemy.get_node("EnemyAI")
			ai.target = biplane
			ai.biplane = enemy
			ai.home_base_x = base_x
			ai.unlimited_fuel_ammo = is_vs_computer
		if enemy.has_method("setup_faction_homebase"):
			enemy.setup_faction_homebase(i, base_x, 200.0, spawn_pos, spawn_rot, enemy_faction_enum)
		if enemy.has_method("get_avatar_data"):
			var enemy_avatar = enemy.get_avatar_data(0)
			if enemy.has_method("assign_plane_model") and enemy.has_method("get_default_plane_model"):
				var enemy_model = enemy.get_default_plane_model(enemy_faction_enum)
				enemy.assign_plane_model(enemy_avatar, enemy_model)
			# D10: parked enemies must already be inverted if they will launch
			# leftward; biplane.respawn() does this on every respawn, so the
			# initial spawn just needs to match (otherwise the plane visually
			# flips on its first death).  Set via the geometric helper so the
			# field is always derived from the spawn rotation, never branched
			# on by callers.
			enemy_avatar.is_barrel_rolled = Biplane.AvatarData.rotation_is_leftward(spawn_rot)
			if enemy.has_method("reset_visual_transform"):
				enemy.reset_visual_transform(enemy_avatar)
		if enemy.has_method("set_home_base") and enemy.has_method("get_avatar_data"):
			enemy.set_home_base(enemy.get_avatar_data(0), i)
		if enemy.has_method("set_game_active"):
			enemy.set_game_active(true)
		enemy.is_player_controlled = false
		if enemy.has_node("EnemyAI"):
			# Initial heading must match the parked orientation so the AI
			# doesn't try to yaw 180° on the first decision tick.
			enemy.get_node("EnemyAI").pilots[0].desired_heading = spawn_rot
		if is_vs_computer:
			var takeoff_delay := i * 1.5
			if enemy.has_node("EnemyAI"):
				enemy.get_node("EnemyAI").takeoff_delay = takeoff_delay
		add_child(enemy)
		enemies.append(enemy)
		if terrain and terrain.has_method("add_runway"):
			# Runway start = runway_left (rightward bases: base_x+50, leftward
			# bases: base_x-50-LEN).  add_runway(x) registers [x, x+RUNWAY_LENGTH].
			terrain.add_runway(runway_left)

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
		var cow_y: float = terrain.get_ground_height_at(cow_x) if terrain and terrain.has_method("get_ground_height_at") else 650.0
		cow.position = Vector2(cow_x, cow_y)
		add_child(cow)

	var bird_count_map: Dictionary = {"None": 0, "Few": 3, "Normal": 5, "Many": 8}
	var num_birds: int = int(bird_count_map.get(GameManager.bird_count if GameManager else "Normal", 6) * lm)
	for i in range(num_birds):
		var flock: Node2D = BIRD_FLOCK_SCENE.instantiate()
		flock.position = Vector2(200 + randf() * 16000, 100 - randf() * 1200)
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

## Wrap-aware distance: returns the shortest arc between two x positions on the
## world torus (D10).  Used by `_validate_base_layout` so a base at x=200 and
## another at x=16200 are correctly seen as ~384 apart, not 16000.
func _wrap_distance(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, TERRAIN_LENGTH - d)

## Debug-only: assert every base clears MIN_ENEMY_DISTANCE from the player
## (wrap-aware) and that each base's runway fits inside the map.  Push-warns on
## violation.  Called from _spawn_enemies_and_targets in debug builds (M6.3).
func _validate_base_layout(bases: Array[float]) -> void:
	if not OS.is_debug_build():
		return
	for base_x in bases:
		var d := _wrap_distance(base_x, PLAYER_SPAWN_X)
		if d < MIN_ENEMY_DISTANCE:
			push_warning("Base layout: base at x=%f too close to player (d=%.1f < MIN_ENEMY_DISTANCE=%.1f)"
				% [base_x, d, MIN_ENEMY_DISTANCE])
		# Enemy runway is added at runway_left (rightward: base_x+50, leftward:
		# base_x-50-LEN) with length LEN = Terrain.RUNWAY_LENGTH (T-runway, +20%).
		# The widest span across both orientations is [base_x-50-LEN, base_x+50+LEN].
		var span_min: float = base_x - 50.0 - Terrain.RUNWAY_LENGTH
		var span_max: float = base_x + 50.0 + Terrain.RUNWAY_LENGTH
		if span_min < 0.0 or span_max > TERRAIN_LENGTH:
			push_warning("Base layout: base at x=%f runway does not fit in map (%.1f..%.1f)"
				% [base_x, span_min, span_max])
	# Pairwise check (catches two adjacent east bases).
	for i in range(bases.size()):
		for j in range(i + 1, bases.size()):
			var d2 := _wrap_distance(bases[i], bases[j])
			if d2 < MIN_ENEMY_DISTANCE:
				push_warning("Base layout: bases at x=%f and x=%f too close (d=%.1f)"
					% [bases[i], bases[j], d2])

func _create_home_base() -> void:
	var runway_left = Terrain.RUNWAY_START - 150.0
	var building_hw = _get_target_half_width("building")

	for i in range(2):
		var building_x = runway_left - 10 - building_hw - i * (building_hw * 2 + 10)
		var building := GROUND_TARGET_SCENE.instantiate()
		building.target_type = "building"
		var by: float = terrain.get_ground_height_at(building_x) if terrain and terrain.has_method("get_ground_height_at") else 650.0
		building.position = Vector2(building_x, by)
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
		var dy: float = terrain.get_ground_height_at(depot_x) if terrain and terrain.has_method("get_ground_height_at") else 650.0
		fuel_depot.position = Vector2(depot_x, dy)
		fuel_depot.has_aa = false
		fuel_depot.is_enemy = false
		add_child(fuel_depot)
		_mark_position_occupied(depot_x, depot_hw)

func _create_enemy_bases() -> void:
	var lm: float = GameManager.get_level_multiplier() if GameManager else 1.0
	for base_idx in range(enemy_home_positions.size()):
		var home_x: float = enemy_home_positions[base_idx]
		if abs(home_x - PLAYER_SPAWN_X) < SAFE_ZONE_RADIUS:
			continue

		# Mirror the runway-side decision from _spawn_enemies_and_targets:
		# rightward bases have their runway on the right ([home_x+50,
		# home_x+50+LEN]); leftward bases on the left ([home_x-50-LEN,
		# home_x-50]).  Buildings go on the OPPOSITE side from the takeoff
		# direction (so the plane rolls AWAY from its own homebase on takeoff).
		var faces_left: bool = enemy_base_faces_left[base_idx] if base_idx < enemy_base_faces_left.size() else (home_x > PLAYER_SPAWN_X)
		var runway_left: float = (home_x - (Terrain.RUNWAY_LENGTH + 50.0)) if faces_left else (home_x + 50.0)
		var runway_right: float = runway_left + Terrain.RUNWAY_LENGTH

		var building_hw = _get_target_half_width("building")

		# `build_dir` is +1 for buildings placed toward +x, -1 for -x.
		# For rightward bases (runway on the right of home_x), buildings go
		# LEFT of the runway: building_x = runway_left - 10 - hw - i*step.
		# For leftward  bases (runway on the left  of home_x), buildings go
		# RIGHT of the runway: building_x = runway_right + 10 + hw + i*step.
		var build_dir: float = -1.0 if not faces_left else 1.0
		var building_step: float = building_hw * 2.0 + 10.0
		var first_building_x: float = runway_left - 10.0 - building_hw if not faces_left \
									  else runway_right + 10.0 + building_hw
		for i in range(2):
			var building_x: float = first_building_x + build_dir * i * building_step
			var building := GROUND_TARGET_SCENE.instantiate()
			building.target_type = "building"
			# Per-building terrain sampling (D5 blend zone can already be
			# visibly off BASE_Y beyond ~80 px from the runway edge; tanks
			# further out, on grass, need it most).
			var by: float = terrain.get_ground_height_at(building_x) if terrain and terrain.has_method("get_ground_height_at") else 650.0
			building.position = Vector2(building_x, by)
			building.has_aa = true
			building.is_enemy = true
			building.add_to_group("enemy_target")
			add_child(building)
			_mark_position_occupied(building_x, building_hw)

		var depot_hw = _get_target_half_width("fuel_depot")
		var last_building_x: float = first_building_x + build_dir * 1 * building_step
		var first_depot_x: float = last_building_x + build_dir * (building_hw + 10.0 + depot_hw)
		var depot_step: float = depot_hw * 2.0 + 10.0

		for i in range(2):
			var depot_x: float = first_depot_x + build_dir * i * depot_step
			var fuel_depot := GROUND_TARGET_SCENE.instantiate()
			fuel_depot.target_type = "fuel_depot"
			var dy: float = terrain.get_ground_height_at(depot_x) if terrain and terrain.has_method("get_ground_height_at") else 650.0
			fuel_depot.position = Vector2(depot_x, dy)
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
			# Place extras on the building side (opposite the runway), so they
			# don't pile up on the runway.  For rightward: left of home_x.
			# For leftward:  right of home_x.
			var target_step: float = 160.0
			var target_x: float = home_x + build_dir * (200.0 + i * target_step)
			var attempts := 0
			while attempts < 20:
				if not _is_position_occupied(target_x, target_hw):
					break
				target_x += build_dir * (target_hw * 2.0 + 10.0)
				attempts += 1
			if _is_position_occupied(target_x, target_hw):
				continue
			var target: Node2D = GROUND_TARGET_SCENE.instantiate()
			target.target_type = target_type
			var target_ground_y: float = terrain.get_ground_height_at(target_x) if terrain and terrain.has_method("get_ground_height_at") else 650.0
			target.position = Vector2(target_x, target_ground_y)
			if target_type == "building":
				target.has_aa = false
			else:
				target.has_aa = randf() > 0.5
			target.is_enemy = true
			target.add_to_group("enemy_target")
			add_child(target)
			_mark_position_occupied(target_x, target_hw)

func _physics_process(delta: float) -> void:
	if game_state != "PLAYING" or get_tree().paused:
		return

	if biplane:
		_handle_wrap_around()
		_update_camera(delta)
		_update_minimap()

func _on_biplane_crashed(is_midair: bool = false) -> void:
	## The crash explosion, debris, fire, smoke, screen-shake and explosion
	## sound are now produced once inside Biplane._on_avatar_crashed (which is
	## the single funnel every destructive end-state reaches), so they are
	## identical for player and AI planes.  This handler is kept only for the
	## respawn bookkeeping flag.
	_player_crashed_exploded = true

func _on_biplane_landed(avatar_id: int) -> void:
	## The wreck has hit the ground — schedule the fixed 2s respawn.
	RespawnManager.queue_respawn(0, RespawnManager.RESPAWN_DELAY)

func _on_biplane_damaged(impact_force: float, v_perp: float) -> void:
	GameManager.request_screen_shake(10.0)
	if SoundManager:
		SoundManager.play_sfx(SoundManager.SoundEvent.BUMP)

func _respawn_biplane(avatar_id: int = 0) -> void:
	if not biplane or not biplane.has_method("respawn"):
		return

	if avatar_id == 0 and GameManager and GameManager.get_lives(0) <= 0:
		_show_game_over()
		return

	var avatar = biplane._avatars.get(avatar_id)
	if not avatar:
		if avatar_id == 0:
			_show_game_over()
		return

	var success := biplane.respawn(avatar_id, camera if avatar_id == 0 else null)
	_player_crashed_exploded = false
	if not success and avatar_id == 0:
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
	if RespawnManager:
		RespawnManager.clear_all()
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
		biplane.visible = true
		biplane.set_game_active(true)
		if biplane.has_method("respawn"):
			biplane.respawn(0, camera)
		elif biplane.has_method("teleport_to"):
			var ground_y := 650.0
			if terrain and terrain.has_method("get_ground_height_at"):
				ground_y = terrain.get_ground_height_at(PLAYER_SPAWN_X)
			biplane.teleport_to(Vector2(PLAYER_SPAWN_X, ground_y - Biplane.GROUND_SURFACE_OFFSET))
		else:
			var ground_y := 650.0
			if terrain and terrain.has_method("get_ground_height_at"):
				ground_y = terrain.get_ground_height_at(PLAYER_SPAWN_X)
			biplane.position = Vector2(PLAYER_SPAWN_X, ground_y - Biplane.GROUND_SURFACE_OFFSET)
			biplane.rotation = 0
			biplane.velocity = Vector2.ZERO
		var avatar := biplane.get_avatar_data(0) if biplane.has_method("get_avatar_data") else null
		if avatar:
			avatar.fuel = 100.0
			avatar.ammo = 500
			avatar.bombs = avatar.model_params.get("max_bombs", 0)

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

	## Camera when landed is clamped.
	var lerp_rate: float = (0.9 * speed_coeff) # if is_landed else 0.9 * speed_coeff
	camera.position = camera.position.lerp(target_pos, delta * lerp_rate)

func _handle_wrap_around() -> void:
	if not biplane:
		return

	var pos: Vector2 = biplane.position

	if pos.x < VIEWPORT_MIN_X:
		biplane.position.x = TERRAIN_LENGTH - 1
		camera.position.x += TERRAIN_LENGTH
		# The wrap jumps the camera position by a full terrain length.  With the
		# Camera2D's own position smoothing enabled this would pan slowly across
		# the whole map, so snap the rendered camera to the new location
		# instantly.  Only do this on an actual wrap — calling it every frame
		# would kill the camera's smoothing and make panning jerky.
		camera.reset_smoothing()
	elif pos.x >= TERRAIN_LENGTH:
		biplane.position.x = VIEWPORT_MIN_X + 1
		camera.position.x -= TERRAIN_LENGTH
		camera.reset_smoothing()


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