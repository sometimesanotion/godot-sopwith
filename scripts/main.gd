extends Node2D

@onready var camera: Camera2D = $Camera2D
@onready var biplane: Biplane = $Biplane
@onready var terrain: Node2D = $Terrain
@onready var background: Node2D = $Background
@onready var ui: CanvasLayer = $UI

const TERRAIN_LENGTH := 16384.0
const VIEWPORT_MIN_X := 0.0
const HOME_BASE := Vector2(5300, 650)

## Design resolution used for scaling all camera parameters.
const DESIGN_WIDTH := 3440
const DESIGN_HEIGHT := 1440

func _scale_x(v: float) -> float:
	return v * get_viewport_rect().size.x / DESIGN_WIDTH

func _scale_y(v: float) -> float:
	return v * get_viewport_rect().size.y / DESIGN_HEIGHT

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
const TANK_SCENE := preload("res://scenes/tank.tscn")
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
		if GameManager.screen_shake_requested.is_connected(_on_screen_shake):
			GameManager.screen_shake_requested.disconnect(_on_screen_shake)
		GameManager.screen_shake_requested.connect(_on_screen_shake)
	if RespawnManager:
		if RespawnManager.respawn_ready.is_connected(_respawn_biplane):
			RespawnManager.respawn_ready.disconnect(_respawn_biplane)
		RespawnManager.respawn_ready.connect(_respawn_biplane)
	if BuildingRegistry:
		if BuildingRegistry.buildings_destroyed.is_connected(_on_buildings_destroyed):
			BuildingRegistry.buildings_destroyed.disconnect(_on_buildings_destroyed)
		BuildingRegistry.buildings_destroyed.connect(_on_buildings_destroyed)
	if GraphicsSettings:
		if not GraphicsSettings.settings_changed.is_connected(_on_graphics_settings_changed):
			GraphicsSettings.settings_changed.connect(_on_graphics_settings_changed)
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

	var ke := event as InputEventKey
	if ke.keycode == KEY_F9 and not ke.pressed and not ke.is_echo():
		if game_state == "PLAYING" and GameManager:
			GameManager.debug_hud = not GameManager.debug_hud
			biplane.queue_redraw()
			for e in enemies:
				if e and is_instance_valid(e) and e.has_method("queue_redraw"):
					e.queue_redraw()
			for t in get_tree().get_nodes_in_group("tank"):
				if t and is_instance_valid(t):
					t.queue_redraw()

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
		var vp := get_viewport_rect().size
		var title_zoom := 0.3 * vp.x / DESIGN_WIDTH
		camera.position = Vector2(TERRAIN_LENGTH * 0.5, 400.0 * vp.y / DESIGN_HEIGHT / title_zoom)
		camera.zoom = Vector2(title_zoom, title_zoom)
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
		var vp := get_viewport_rect().size
		var title_zoom := 0.3 * vp.x / DESIGN_WIDTH
		camera.enabled = true
		camera.position = Vector2(TERRAIN_LENGTH * 0.5, 400.0 * vp.y / DESIGN_HEIGHT / title_zoom)
		camera.zoom = Vector2(title_zoom, title_zoom)
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

func _on_graphics_settings_changed() -> void:
	if game_state == "TITLE":
		if camera:
			var vp := get_viewport_rect().size
			var title_zoom := 0.3 * vp.x / DESIGN_WIDTH
			camera.position = Vector2(TERRAIN_LENGTH * 0.5, 400.0 * vp.y / DESIGN_HEIGHT / title_zoom)
			camera.zoom = Vector2(title_zoom, title_zoom)
			camera.reset_smoothing()

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
			biplane.setup_faction_homebase(0, PLAYER_SPAWN_X, Terrain.RUNWAY_LENGTH, Vector2(PLAYER_SPAWN_X, ground_y - Biplane.GROUND_SURFACE_OFFSET), 0.0, player_faction_enum)
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
		camera.position = Vector2(PLAYER_SPAWN_X, _scale_y(400.0))
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
		camera.position = Vector2(PLAYER_SPAWN_X, _scale_y(400.0))
	_spawn_enemies_and_targets()
	_create_home_base()
	_create_enemy_bases()
	_spawn_cows()
	# Built last so the minimap samples terrain only after every runway
	# (player + all enemy bases via add_runway) has been placed and the
	# ground points fully regenerated — otherwise it shows a stale snapshot.
	_create_minimap()
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
	enemy_base_faces_left.clear()
	_occupied_positions.clear()
	if BuildingRegistry:
		BuildingRegistry.reset()

	var num_bases: int = GameManager.enemy_homebases if GameManager else 4
	# D10 base layout: one base west of the player, the rest east.  The east
	# bases spawn inverted (leftward launch) via `faces_left`.  Consecutive
	# bases are spaced ~3200 px apart (≥ MIN_ENEMY_DISTANCE) and all runways
	# fit inside the map; both invariants are checked by _validate_base_layout.
	# East bases are spread further than the original 2500 to give each
	# homebase more territory and reduce base clustering.
	var possible_bases: Array[float] = [
		2400.0,
		8500.0,
		11800.0,
		15100.0,
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
		# Runway span: rightward bases → [base_x+50, base_x+50+LEN] (runway on
		# the right); leftward bases → [base_x-50-LEN, base_x-50] (runway on
		# the left).  LEN = Terrain.RUNWAY_LENGTH (widened 20% in T-runway).
		var runway_left: float = (base_x - (Terrain.RUNWAY_LENGTH + 50.0)) if faces_left else (base_x + 50.0)
		var runway_right: float = runway_left + Terrain.RUNWAY_LENGTH
		var spawn_x: float = (runway_right - ENEMY_SPAWN_RUNWAY_EDGE_MARGIN) if faces_left \
							else (runway_left + ENEMY_SPAWN_RUNWAY_EDGE_MARGIN)
		# Register the runway first so the surrounding terrain (and therefore
		# this base's spawn elevation) is built around its own height.
		if terrain and terrain.has_method("add_runway"):
			terrain.add_runway(runway_left)
		var enemy: RigidBody2D = ENEMY_SCENE.instantiate()
		var ground_y := 650.0
		if terrain and terrain.has_method("get_ground_height_at"):
			ground_y = terrain.get_ground_height_at(spawn_x)
		var spawn_pos := Vector2(spawn_x, ground_y - Biplane.GROUND_SURFACE_OFFSET)
		enemy.position = spawn_pos
		enemy.rotation = spawn_rot
		enemy.add_to_group("destructible")
		enemy.add_to_group("enemy_plane")
		if enemy.has_node("EnemyAI"):
			var ai := enemy.get_node("EnemyAI")
			ai.target = biplane
			ai.biplane = enemy
			ai.home_base_x = base_x
			ai.homebase_id = i + 1
			ai.unlimited_fuel_ammo = is_vs_computer
		if enemy.has_method("setup_faction_homebase"):
			enemy.setup_faction_homebase(i + 1, base_x, Terrain.RUNWAY_LENGTH, spawn_pos, spawn_rot, enemy_faction_enum)
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
			enemy.set_home_base(enemy.get_avatar_data(0), i + 1)
		if enemy.has_method("set_game_active"):
			enemy.set_game_active(true)
		enemy.is_player_controlled = false
		if enemy.has_node("EnemyAI"):
			# Initial heading must match the parked orientation so the AI
			# doesn't try to yaw 180° on the first decision tick.
			enemy.get_node("EnemyAI").pilots[0].desired_heading = spawn_rot
		# Guarantee the initial spawn exactly matches the homebase spawn point.
		# The homebase above was built from this same spawn_pos / spawn_rot, so
		# re-deriving the parked transform from the homebase itself means the
		# plane can never drift from where it is meant to sit, and a respawn
		# (which also reads get_homebase_spawn_position) lands in the same spot.
		if enemy.has_method("get_homebase_spawn_position") \
				and enemy.has_method("get_homebase_spawn_rotation") \
				and enemy.has_method("get_avatar_data"):
			var hb_av = enemy.get_avatar_data(0)
			enemy.global_position = enemy.get_homebase_spawn_position(hb_av)
			enemy.rotation = enemy.get_homebase_spawn_rotation(hb_av)
		if is_vs_computer:
			var takeoff_delay := i * 1.5
			if enemy.has_node("EnemyAI"):
				enemy.get_node("EnemyAI").takeoff_delay = takeoff_delay
		add_child(enemy)
		enemies.append(enemy)

	var lm: float = GameManager.get_level_multiplier() if GameManager else 1.0
	var bird_count_map: Dictionary = {"None": 0, "Few": 3, "Normal": 5, "Many": 8}
	var num_birds: int = int(bird_count_map.get(GameManager.bird_count if GameManager else "Normal", 6) * lm)
	for i in range(num_birds):
		var flock: Node2D = BIRD_FLOCK_SCENE.instantiate()
		flock.position = Vector2(200 + randf() * 16000, -300 - randf() * 1200)
		add_child(flock)

## Spawn cows across the terrain, excluding homebase zones (player + enemy)
## and runways. Called after all bases, tanks, and structures are placed so
## cows never clip through buildings or block vehicle paths.
func _spawn_cows() -> void:
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
			if on_runway:
				attempts += 1
				continue
			var near_homebase := false
			if absf(cow_x - PLAYER_SPAWN_X) < 500.0:
				near_homebase = true
			else:
				for hx in enemy_home_positions:
					if absf(cow_x - hx) < 500.0:
						near_homebase = true
						break
			if not near_homebase:
				break
			attempts += 1
		var cow: Node2D = COW_SCENE.instantiate()
		var cow_y: float = terrain.get_ground_height_at(cow_x) if terrain and terrain.has_method("get_ground_height_at") else 650.0
		cow.position = Vector2(cow_x, cow_y)
		add_child(cow)

func _get_target_half_width(target_type: String) -> float:
	match target_type:
		"building": return 52.5
		"hangar": return 67.5
		"ammo_depot": return 52.5
		"fuel_depot": return 60.0
		"tank": return 45.0
		"flak_cannon": return 45.0
		"machine_gun_nest": return 35.0
		_: return 45.0

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

## Registry homebase id for the PLAYER base.  Enemy bases use base_idx+1
## (see _create_enemy_bases) so every homebase has a globally unique
## id in BuildingRegistry (the player biplane and each enemy biplane
## keep their OWN per-instance _homebases dict, but the registry is
## shared, so ids must not collide).
const PLAYER_HOMEBASE_ID := 0

## Instantiate one ground target as part of a homebase cluster.  Sets the
## (shared) homebase id, the enemy flag, and the AA rule: ONLY the flak cannon
## and machine gun nest are armed — hangars, buildings, ammo depots and fuel
## depots never fire.  (Tanks are no longer ground targets — they are spawned
## separately as AI ground vehicles; see _spawn_tank.)
## The target is ground-sampled at its x so it sits flush on the terrain.
func _spawn_base_target(homebase_id: int, target_type: String, x: float, is_enemy: bool) -> void:
	var t: Node2D = GROUND_TARGET_SCENE.instantiate()
	t.target_type = target_type
	t.homebase_id = homebase_id
	t.is_enemy = is_enemy
	t.has_aa = (target_type == "flak_cannon" or target_type == "machine_gun_nest")
	var gy: float = terrain.get_ground_height_at(x) if terrain and terrain.has_method("get_ground_height_at") else 650.0
	t.position = Vector2(x, gy)
	if is_enemy:
		t.add_to_group("enemy_target")
	add_child(t)
	var hw := _get_target_half_width(target_type)
	_mark_position_occupied(x, hw)

## Spawn a tank ground vehicle for a homebase.  Tanks are NOT buildings — they
## are Biplane-derived RigidBody2Ds driven by a ground-mode EnemyAI.  They crawl
## the map, aim a turret at hostile units, and fire machine guns.
func _spawn_tank(homebase_id: int, base_x: float, x: float, is_enemy: bool, facing_dir: float) -> void:
	var t: Node2D = TANK_SCENE.instantiate()
	var gy: float = terrain.get_ground_height_at(x) if terrain and terrain.has_method("get_ground_height_at") else 650.0
	t.position = Vector2(x, gy)
	t.rotation = 0.0 if facing_dir > 0.0 else PI

	var faction_enum: int = Biplane.Faction.BRITISH
	if is_enemy:
		match _get_enemy_faction(GameManager.player_faction if GameManager else "British"):
			"German": faction_enum = Biplane.Faction.GERMAN
			"French": faction_enum = Biplane.Faction.FRENCH
			_: faction_enum = Biplane.Faction.BRITISH
	else:
		match GameManager.player_faction if GameManager else "British":
			"French": faction_enum = Biplane.Faction.FRENCH
			"German": faction_enum = Biplane.Faction.GERMAN
			_: faction_enum = Biplane.Faction.BRITISH

	var av = t.get_avatar_data(0)
	av.faction = faction_enum
	av.team = Biplane.Team.ENEMY if is_enemy else Biplane.Team.ALLIED
	av.homebase_id = homebase_id
	av.travel_dir = facing_dir
	av.pitch_angle = 0.0 if facing_dir > 0.0 else PI
	av.is_barrel_rolled = facing_dir < 0.0
	if t.has_method("set_home_base"):
		t.set_home_base(av, homebase_id)

	if t.has_node("EnemyAI"):
		var ai = t.get_node("EnemyAI")
		ai.target = biplane
		ai.biplane = t
		ai.home_base_x = base_x
		ai.homebase_id = homebase_id
		ai.is_ground_vehicle = true
		ai.patrol_range = 5000.0
		ai.takeoff_delay = 0.0

	t.add_to_group("destructible")
	t.add_to_group("tank")
	if is_enemy:
		t.add_to_group("enemy_target")
	else:
		t.add_to_group("player")
	if t.has_method("set_game_active"):
		t.set_game_active(true)
	t.is_player_controlled = false
	add_child(t)

## Lay out a list of structures on ONE side of the runway, starting just
## off `edge` and stepping outward in `dir` (+1 = +x, -1 = -x).
## `dir` also encodes which side: the "building side" (opposite the
## takeoff direction) and the "opposite side" use mirrored dirs so
## each list lands on a distinct side of the strip.
func _spawn_structures_on_side(hb_id: int, types: PackedStringArray, edge: float, dir: float, is_enemy: bool) -> void:
	var cursor: float = edge + dir * 10.0
	for target_type in types:
		var hw := _get_target_half_width(target_type)
		cursor += dir * hw
		_spawn_base_target(hb_id, target_type, cursor, is_enemy)
		cursor += dir * (hw + 10.0)

func _create_home_base() -> void:
	# Player runway sits at RUNWAY_START..RUNWAY_END; the structure
	# cluster is laid out to its LEFT.  Every homebase spawns with
	# at least one hangar (required to respawn the player's planes)
	# plus an ammo depot (reloads) and a fuel depot (refuel).
	var runway_left = Terrain.RUNWAY_START - 150.0
	var runway_right: float = runway_left + Terrain.RUNWAY_LENGTH
	# Player faces right -> building side is the LEFT of the runway,
	# opposite side is the RIGHT of the runway.
	# The building side is anchored 150px LEFT of the real runway
	# start (runway_left = RUNWAY_START - 150); mirror that
	# clearance on the opposite side by anchoring it 150px RIGHT
	# of the real runway end (not the shifted runway_right, which
	# sits 150px short and would drop structures onto the strip).
	var build_edge: float = runway_left
	var build_dir: float = -1.0
	var opp_edge: float = Terrain.RUNWAY_END + 150.0
	var opp_dir: float = 1.0

	# All static structures stay together on the building side behind the
	# runway — hangars, buildings, ammo/fuel depots, plus the flak cannon.
	# The machine gun nest is NOT here — it sits on the forward (second)
	# spawn point, behind the tanks (see below).  None of these are vehicles.
	# The flak cannon sits AHEAD of the hangar at the spawn point (closest
	# to the runway edge), with the hangar and other buildings behind it.
	var building_side := PackedStringArray([
		"flak_cannon", "hangar", "building", "ammo_depot", "fuel_depot"])

	_spawn_structures_on_side(PLAYER_HOMEBASE_ID, building_side, build_edge, build_dir, false)

	# The machine gun nest goes on the forward (second) spawn point, BEHIND
	# the tanks — closer to the runway than the tank column so the tanks
	# screen it.  Spawned on the far side of the runway.
	_spawn_base_target(PLAYER_HOMEBASE_ID, "machine_gun_nest", opp_edge + opp_dir * 40.0, false)

	# The forward (second) spawn point is reserved for TANKS — ground
	# vehicles that crawl out to hunt the enemy (they never respawn).  The
	# friendly homebase fields 1 + any extra tanks earned from previous
	# level completions.  Spawned on the far side of the runway, in front
	# of the machine gun nest, facing right (toward the foe).
	var player_tank_count := 1
	if GameManager:
		player_tank_count += GameManager.player_extra_tanks
	for k in range(player_tank_count):
		var tx := opp_edge + opp_dir * (140.0 + k * 90.0)
		_spawn_tank(PLAYER_HOMEBASE_ID, PLAYER_SPAWN_X, tx, false, 1.0)

func _create_enemy_bases() -> void:
	for base_idx in range(enemy_home_positions.size()):
		var home_x: float = enemy_home_positions[base_idx]
		if abs(home_x - PLAYER_SPAWN_X) < SAFE_ZONE_RADIUS:
			continue

		# Mirror the runway-side decision from _spawn_enemies_and_targets:
		# rightward bases have their runway on the right; leftward bases on
		# the left (D10).  The building side is the OPPOSITE of
		# the takeoff direction (plane rolls AWAY from its base).
		var faces_left: bool = enemy_base_faces_left[base_idx] if base_idx < enemy_base_faces_left.size() else (home_x > PLAYER_SPAWN_X)
		var runway_left: float = (home_x - (Terrain.RUNWAY_LENGTH + 50.0)) if faces_left else (home_x + 50.0)
		var runway_right: float = runway_left + Terrain.RUNWAY_LENGTH

		# Edge/direction of each runway side.  The "building side"
		# (away from takeoff) and the "opposite side" use mirrored
		# directions so a base's defences cover BOTH approach
		# vectors, not just the hangar side.
		var build_edge: float = runway_left if not faces_left else runway_right
		var build_dir: float = -1.0 if not faces_left else 1.0
		var opp_edge: float = runway_right if not faces_left else runway_left
		var opp_dir: float = 1.0 if not faces_left else -1.0

		var hb_id: int = base_idx + 1
		var lv: int = GameManager.current_level if GameManager else 1

		# Every 3rd level: +1 flak battery per base.
		# Machine gun nests stay at a base of 1 (no level scaling).
		var flak_total: int = 1 + int(lv / 3)
		var mg_total: int = 1
		var building_side := PackedStringArray([
			"flak_cannon", "hangar", "building", "ammo_depot", "fuel_depot"])
		for i in range(flak_total - 1):
			building_side.append("flak_cannon")
		_spawn_structures_on_side(hb_id, building_side, build_edge, build_dir, true)

		# Machine gun nests on the forward (second) spawn point, clustered
		# just behind the tank column (closer to the runway) so the tanks
		# screen them.  Hostile bases keep one at level 1 and add more with
		# level.
		for i in range(mg_total):
			var mx := opp_edge + opp_dir * (40.0 + i * 90.0)
			_spawn_base_target(hb_id, "machine_gun_nest", mx, true)

		# Tanks: crawl out from the OPPOSITE (second) spawn point, IN FRONT
		# of the machine gun nests, to hunt the player.  Hostile homebases
		# field a count driven by the `enemy_tanks` preference (None=0,
		# Few=1, Normal=2, Many=3 at level 1) and add +1 every 2nd level.
		# Tanks never respawn.
		var tank_base_map: Dictionary = {"None": 0, "Few": 1, "Normal": 2, "Many": 3}
		var tanks_per_base: int = tank_base_map.get(GameManager.enemy_tanks if GameManager else "Normal", 2) + int(lv / 2)
		var tank_start: float = 40.0 + mg_total * 90.0 + 60.0
		for k in range(tanks_per_base):
			var dir := -1.0 if faces_left else 1.0
			# Spawn PAST the machine gun nests, not relative to home_x —
			# home_x sits beside the strip, so an offset from it lands the
			# tank on the runway itself.
			var tx := opp_edge + opp_dir * (tank_start + k * 90.0)
			_spawn_tank(hb_id, home_x, tx, true, dir)

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

func _on_buildings_destroyed(homebase_id: int) -> void:
	## The player's homebase shares registry id 0.  When its LAST building
	## falls, the player can no longer put planes back in the air, so their
	## remaining spare planes collapse to 1 — the next death ends the game (no
	## further respawn).  Enemy bases are handled by the respawn gate in
	## enemy_ai (a base with no buildings simply stops respawning).
	if homebase_id == PLAYER_HOMEBASE_ID and GameManager:
		var spare_planes := GameManager.get_spare_planes(0)
		if spare_planes > 1:
			GameManager.set_spare_planes(0, 1)

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

	if avatar_id == 0 and GameManager and GameManager.get_spare_planes(0) <= 0:
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

## Compute level-completion bonuses without applying them (pure query).
## Returns { bonus_planes: int, surviving_tanks: int, bonus_text: String }.
func _compute_level_bonuses() -> Dictionary:
	var result := {
		"bonus_planes": 0,
		"surviving_tanks": 0,
		"bonus_text": "",
	}
	if not BuildingRegistry:
		return result
	# Player homebase (id=0) always spawns these 6 building types:
	var player_types := PackedStringArray([
		"flak_cannon", "hangar", "building",
		"ammo_depot", "fuel_depot", "machine_gun_nest"])
	var survived := 0
	for t in player_types:
		survived += BuildingRegistry.count(PLAYER_HOMEBASE_ID, t)
	var hangar_survived := BuildingRegistry.count(PLAYER_HOMEBASE_ID, "hangar") > 0
	var half_survived := survived >= player_types.size() / 2
	if half_survived:
		result["bonus_planes"] += 1
	if hangar_survived:
		result["bonus_planes"] += 1
	# Count surviving player tanks
	var player_tanks := get_tree().get_nodes_in_group("tank")
	for t in player_tanks:
		if t.is_in_group("player"):
			var av = t.get_avatar_data(0) if t.has_method("get_avatar_data") else null
			if av and av.damage.damage_state != DamageData.DamageState.DESTROYED:
				result["surviving_tanks"] += 1
	# Build display text
	var lines: PackedStringArray = []
	if half_survived:
		lines.append("Friendly buildings survived: +1 Plane")
	if hangar_survived:
		lines.append("Friendly hangar survived: +1 Plane")
	if result["bonus_planes"] > 0:
		lines.append("Total Bonus Lives: +%d" % result["bonus_planes"])
	if result["surviving_tanks"] > 0:
		lines.append("Friendly Tanks for Next Level: %d + 1 = %d" % [result["surviving_tanks"], (result["surviving_tanks"] + 1)])
	result["bonus_text"] = "\n".join(lines)
	return result

func _win_game() -> void:
	game_state = "LEVEL_COMPLETE"
	if GameManager:
		GameManager.game_win()
	var level_complete := LEVEL_COMPLETE_SCENE.instantiate()
	level_complete.next_level.connect(_on_next_level)
	level_complete.bonus_info = _compute_level_bonuses()["bonus_text"]
	add_child(level_complete)

func _award_level_completion_bonuses() -> void:
	var bonuses := _compute_level_bonuses()
	if not GameManager:
		return
	if bonuses["bonus_planes"] > 0:
		GameManager.set_spare_planes(0, GameManager.get_spare_planes(0) + bonuses["bonus_planes"])
	# Next level gets surviving_tanks + 1 on the player side
	GameManager.player_extra_tanks = bonuses["surviving_tanks"]

func _on_next_level() -> void:
	# --- 1. Award level-completion bonuses (check BEFORE clearing) ---
	_award_level_completion_bonuses()
	# --- 2. Advance level ---
	game_state = "PLAYING"
	if GameManager:
		GameManager.current_level += 1
	# --- 3. Compute enemy base count for the NEW level ---
	# Every 4th level adds a base, up to maximum of 6.
	var lv := GameManager.current_level if GameManager else 1
	var num_bases := mini(6, 2 + int(lv / 4))
	if GameManager:
		GameManager.enemy_homebases = num_bases
	if RespawnManager:
		RespawnManager.clear_all()
	_clear_game_objects()
	# --- 4. Regenerate terrain and background so every level is unique ---
	if GameManager:
		GameManager.terrain_seed = randi()
	if terrain and terrain.has_method("generate"):
		terrain.generate()
		terrain.visible = true
	if background and background.has_method("generate"):
		var seed_val: int = terrain.resolved_seed if terrain else 0
		background.generate(seed_val)
	# --- 5. Spawn fresh enemies, buildings, and tanks for the new level ---
	if biplane:
		biplane.set_game_active(false)
		biplane.visible = false
	_spawn_enemies_and_targets()
	_create_home_base()
	_create_enemy_bases()
	# --- 6. Rebuild minimap ---
	if minimap_instance and terrain and terrain.has_method("get_ground_points"):
		minimap_instance.update_terrain(terrain.get_ground_points())
	if minimap_instance and minimap_instance.has_method("clear"):
		minimap_instance.clear()
	# --- 7. Refresh player homebase to match the new terrain ---
	if biplane and biplane.has_method("setup_faction_homebase"):
		var ground_y := 650.0
		if terrain and terrain.has_method("get_ground_height_at"):
			ground_y = terrain.get_ground_height_at(PLAYER_SPAWN_X)
		var player_faction_enum = Biplane.Faction.BRITISH
		if GameManager:
			match GameManager.player_faction:
				"French":
					player_faction_enum = Biplane.Faction.FRENCH
				"German":
					player_faction_enum = Biplane.Faction.GERMAN
		biplane.setup_faction_homebase(
			0,
			PLAYER_SPAWN_X,
			Terrain.RUNWAY_LENGTH,
			Vector2(PLAYER_SPAWN_X, ground_y - Biplane.GROUND_SURFACE_OFFSET),
			0.0,
			player_faction_enum)
	# --- 8. Respawn the player ---
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

		var look_ahead_dist: float = _scale_x(200.0) * speed_coeff
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
	var vp_w := get_viewport_rect().size.x
	minimap_instance.position = Vector2((vp_w - 574) * 0.5, 20)
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