extends CanvasLayer

signal start_single_player
signal start_network_game
signal back_to_menu

enum Mode { MAIN, CONFIGURE, KEYS }

const ENGINE_CUTOFF_ALTITUDE := 2000.0
const TERRAIN_LENGTH := 16384.0
const GROUND_Y := 650.0
const PLAYER_SPAWN_X := 6530.0
const SAFE_ZONE_RADIUS := 1500.0
const MARGIN_EDGE := 20.0
const PAN_SPEED := 400.0

const GROUND_TARGET_SCENE := preload("res://scenes/ground_target.tscn")
const COW_SCENE := preload("res://scenes/cow.tscn")
const BIRD_FLOCK_SCENE := preload("res://scenes/bird_flock.tscn")

var current_mode: int = Mode.MAIN
var scroll_x: float = TERRAIN_LENGTH / 2.0

var sub_viewport: SubViewport
var preview_camera: Camera2D
var sky_rect: ColorRect
var sky_material: ShaderMaterial
var world_container: Node2D
var vpc: SubViewportContainer
var control_title: Label
var control_content: Label
var header_bg: ColorRect
var cp_bg: ColorRect
var title_label: Label
var bip_sprite: Node2D
var sop_sprite: Node2D

var enemy_base_x_positions: Array[float] = [2458.0, 4916.0, 10374.0, 14832.0]
var building_hw: float = 35.0
var depot_hw: float = 20.0

var selected_key_index: int = -1
var waiting_for_key: bool = false
var key_actions: Array[String] = []
var key_labels_arr: Array[String] = []

func _ready() -> void:
	if GameManager:
		GameManager.terrain_seed = randi()
	_rebuild_all()
	get_viewport().size_changed.connect(_rebuild_all)

func _rebuild_all() -> void:
	_update_layout_from_scratch()

func _update_layout_from_scratch() -> void:
	_clear_all()

	var vs: Vector2 = get_viewport().size
	var hh: float = vs.y * 0.2
	var mh: float = vs.y * 0.5
	var mt: float = hh
	var ct: float = mt + mh
	var ch: float = max(vs.y - ct, 80.0)

	header_bg = ColorRect.new()
	header_bg.name = "HeaderBg"
	header_bg.color = Color(0.0, 0.0, 0.0, 0.7)
	header_bg.size = Vector2(vs.x, hh)
	header_bg.position = Vector2.ZERO
	add_child(header_bg)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "SOPWITH 2026"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", maxi(24, int(hh * 0.4)))
	title_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title_label.add_theme_constant_override("outline_size", 3)
	title_label.size = Vector2(vs.x, hh)
	title_label.position = Vector2.ZERO
	add_child(title_label)

	var svg_h: float = hh * 0.85
	var bip_path := "res://assets/svg/biplane.svg"
	var sop_path := "res://assets/svg/sopwith.svg"

	if ResourceLoader.exists(bip_path):
		var tex: Texture2D = load(bip_path)
		var asp: float = float(tex.get_width()) / float(max(tex.get_height(), 1))
		var sw: float = svg_h * asp
		bip_sprite = Node2D.new()
		bip_sprite.name = "BiplaneNode"
		bip_sprite.position = Vector2(MARGIN_EDGE + sw * 0.5, hh * 0.5)
		add_child(bip_sprite)
		var sp := Sprite2D.new()
		sp.texture = tex
		var sc: float = svg_h / max(tex.get_height(), 1)
		sp.scale = Vector2(sc * asp, sc)
		sp.rotation_degrees = 180.0
		sp.flip_v = true
		bip_sprite.add_child(sp)

	if ResourceLoader.exists(sop_path):
		var tex: Texture2D = load(sop_path)
		var asp: float = float(tex.get_width()) / float(max(tex.get_height(), 1))
		var sw: float = svg_h * asp
		sop_sprite = Node2D.new()
		sop_sprite.name = "SopwithNode"
		sop_sprite.position = Vector2(vs.x - MARGIN_EDGE - sw * 0.5, hh * 0.5)
		add_child(sop_sprite)
		var sp := Sprite2D.new()
		sp.texture = tex
		var sc: float = svg_h / max(tex.get_height(), 1)
		sp.scale = Vector2(sc * asp, sc)
		sp.flip_h = true
		sop_sprite.add_child(sp)

	_create_map_viewport(vs, mt, mh)

	cp_bg = ColorRect.new()
	cp_bg.name = "ControlBg"
	cp_bg.color = Color(0.0, 0.0, 0.0, 0.65)
	cp_bg.size = Vector2(vs.x, ch)
	cp_bg.position = Vector2(0, ct)
	add_child(cp_bg)

	control_title = Label.new()
	control_title.name = "ControlTitle"
	control_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	control_title.add_theme_font_size_override("font_size", maxi(16, int(ch * 0.16)))
	control_title.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	control_title.position = Vector2(0, ct + ch * 0.04)
	control_title.size = Vector2(vs.x, ch * 0.18)
	add_child(control_title)

	control_content = Label.new()
	control_content.name = "ControlContent"
	control_content.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	control_content.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	control_content.autowrap_mode = TextServer.AUTOWRAP_WORD
	control_content.add_theme_font_size_override("font_size", maxi(14, int(ch * 0.12)))
	control_content.add_theme_color_override("font_color", Color(1, 1, 1))
	control_content.position = Vector2(vs.x * 0.08, ct + ch * 0.22)
	control_content.size = Vector2(vs.x * 0.84, ch * 0.72)
	add_child(control_content)

	match current_mode:
		Mode.MAIN: _show_main_menu()
		Mode.CONFIGURE: _show_configure_menu()
		Mode.KEYS: _show_keys_menu()

func _clear_all() -> void:
	for c in get_children():
		c.queue_free()
	world_container = null
	preview_camera = null
	sky_rect = null
	sky_material = null
	sub_viewport = null
	vpc = null
	header_bg = null
	title_label = null
	bip_sprite = null
	sop_sprite = null
	cp_bg = null
	control_title = null
	control_content = null

func _create_map_viewport(vs: Vector2, mt: float, mh: float) -> void:
	vpc = SubViewportContainer.new()
	vpc.name = "MapViewportContainer"
	vpc.position = Vector2(0, mt)
	vpc.size = Vector2(vs.x, mh)
	vpc.stretch = true
	vpc.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(vpc)

	sub_viewport = SubViewport.new()
	sub_viewport.name = "MapViewport"
	sub_viewport.size = Vector2i(maxi(1, ceil(vs.x)), maxi(1, ceil(mh)))
	sub_viewport.transparent_bg = false
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	sub_viewport.disable_3d = true
	vpc.add_child(sub_viewport)

	var zoom: float = mh / ENGINE_CUTOFF_ALTITUDE
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky_gradient.gdshader")
	sky_material = sky_mat
	sky_rect = ColorRect.new()
	sky_rect.name = "SkyGradient"
	sky_rect.size = Vector2(vs.x, mh)
	sky_rect.material = sky_mat
	sub_viewport.add_child(sky_rect)

	preview_camera = Camera2D.new()
	preview_camera.name = "PreviewCamera"
	preview_camera.zoom = Vector2(zoom, zoom)
	preview_camera.position = Vector2(scroll_x, GROUND_Y - ENGINE_CUTOFF_ALTITUDE * 0.5)
	sub_viewport.add_child(preview_camera)

	world_container = Node2D.new()
	world_container.name = "WorldContainer"
	sub_viewport.add_child(world_container)

	_initialize_world_terrain()
	_spawn_clouds()
	_spawn_preview_targets()

func _initialize_world_terrain() -> void:
	var mt := Node2D.new()
	mt.name = "MapTerrain"
	mt.set_script(load("res://scripts/terrain.gd"))
	world_container.add_child(mt)
	mt.call_deferred(&"generate")

func _spawn_clouds() -> void:
	var svg_path := "res://assets/svg/cloud.svg"
	if not ResourceLoader.exists(svg_path):
		return
	var cloud_tex: Texture2D = load(svg_path)
	var tw: float = cloud_tex.get_width()
	var th: float = cloud_tex.get_height()
	if tw <= 0 or th <= 0:
		return
	for _i in range(12):
		var cloud := Sprite2D.new()
		cloud.texture = cloud_tex
		cloud.position = Vector2(randf() * TERRAIN_LENGTH, GROUND_Y - 100 - randf() * ENGINE_CUTOFF_ALTITUDE * 0.6)
		var w: float = 100.0 + randf() * 200.0
		var h: float = 60.0 + randf() * 100.0
		cloud.scale = Vector2(w / tw, h / th)
		cloud.z_index = -5
		world_container.add_child(cloud)

func _spawn_preview_targets() -> void:
	var ground_y := GROUND_Y
	var runway_left := 6500.0

	for i in range(2):
		var bx := runway_left - 10 - building_hw - i * (building_hw * 2 + 10)
		var b := GROUND_TARGET_SCENE.instantiate()
		b.target_type = "building"
		b.position = Vector2(bx, ground_y)
		b.has_aa = false
		b.is_enemy = false
		world_container.add_child(b)

	var last_bx := runway_left - 10 - building_hw - 1 * (building_hw * 2 + 10)
	for i in range(2):
		var dx := last_bx - building_hw - 10 - depot_hw - i * (depot_hw * 2 + 10)
		var d := GROUND_TARGET_SCENE.instantiate()
		d.target_type = "fuel_depot"
		d.position = Vector2(dx, ground_y)
		d.has_aa = false
		d.is_enemy = false
		world_container.add_child(d)

	for hx in enemy_base_x_positions:
		var e_ground_y := GROUND_Y
		for i in range(2):
			var bx := hx + 50 - 10 - building_hw - i * (building_hw * 2 + 10)
			var b := GROUND_TARGET_SCENE.instantiate()
			b.target_type = "building"
			b.position = Vector2(bx, e_ground_y)
			b.has_aa = true
			b.is_enemy = true
			world_container.add_child(b)
		var last_e_bx := hx + 50 - 10 - building_hw - 1 * (building_hw * 2 + 10)
		for i in range(2):
			var dx := last_e_bx - building_hw - 10 - depot_hw - i * (depot_hw * 2 + 10)
			var d := GROUND_TARGET_SCENE.instantiate()
			d.target_type = "fuel_depot"
			d.position = Vector2(dx, e_ground_y)
			d.has_aa = false
			d.is_enemy = true
			world_container.add_child(d)
		for i in range(3):
			var tx := hx - 200 - i * 160
			var t := GROUND_TARGET_SCENE.instantiate()
			t.target_type = ["building", "hangar", "tank"].pick_random()
			t.position = Vector2(tx, e_ground_y)
			t.has_aa = false
			t.is_enemy = true
			world_container.add_child(t)

	for i in range(6):
		var cx := 200 + randf() * 16000
		var cow := COW_SCENE.instantiate()
		cow.position = Vector2(cx, GROUND_Y)
		world_container.add_child(cow)

	for i in range(1):
		var flock := BIRD_FLOCK_SCENE.instantiate()
		flock.position = Vector2(200 + randf() * 16000, 150 + randf() * 200)
		world_container.add_child(flock)

func _show_main_menu() -> void:
	current_mode = Mode.MAIN
	if control_title:
		control_title.text = ""
	if control_content:
		control_content.text = "    S  - Start Single Player\n    N  - Start Network Game\n    C  - Configure Gameplay\n    M  - Reset Map\n    K  - Key Layouts\n    Q  - Quit"

func _show_configure_menu() -> void:
	current_mode = Mode.CONFIGURE
	if control_title:
		control_title.text = "CONFIGURE GAMEPLAY"
	_update_config_text()

func _update_config_text() -> void:
	if not control_content or not control_title:
		return
	var diff_labels := {0.5: "EASY (0.5x)", 1.0: "NORMAL (1.0x)", 1.5: "HARD (1.5x)"}
	var diff_str: String = diff_labels.get(GameManager.difficulty, "NORMAL")
	var tanks_str: String = GameManager.enemy_tanks
	var cows_str: String = GameManager.cow_count
	var sfx_str: String = str(GameManager.sound_fx_volume) if GameManager.sound_fx_volume > 0 else "None"
	var music_str: String = str(GameManager.music_volume) if GameManager.music_volume > 0 else "None"
	control_content.text = ""
	control_content.text += "    1  Difficulty:  " + diff_str + "\n"
	control_content.text += "    2  Enemy Planes:  " + ("ON" if GameManager.enemy_planes else "OFF") + "\n"
	control_content.text += "    3  Enemy Bombs:  " + ("ON" if GameManager.enemy_bombs else "OFF") + "\n"
	control_content.text += "    4  Enemy Homebases:  " + str(GameManager.enemy_homebases) + "\n"
	control_content.text += "    5  Enemy Tanks:  " + tanks_str + "\n"
	control_content.text += "    6  Huge Explosions:  " + ("ON" if GameManager.huge_explosions else "OFF") + "\n"
	control_content.text += "    7  Bird Flocks:  " + ("ON" if GameManager.bird_flocks else "OFF") + "\n"
	control_content.text += "    8  Cows:  " + cows_str + "\n"
	control_content.text += "    S  Sound FX Volume:  " + sfx_str + "\n"
	control_content.text += "    M  Music Volume:  " + music_str + "\n"
	control_content.text += "\n    Q  - Back to Menu"

func _show_keys_menu() -> void:
	current_mode = Mode.KEYS
	if control_title:
		control_title.text = "KEY LAYOUTS"
	waiting_for_key = false
	selected_key_index = -1
	key_actions = [
		"throttle_up", "throttle_down", "pull_up", "pull_down",
		"roll", "fire", "bomb"
	]
	key_labels_arr = []
	if not control_content:
		return
	control_content.text = ""
	for i in key_actions.size():
		var action_name: String = key_actions[i]
		var input_events: Array[InputEvent] = InputMap.action_get_events(action_name)
		var key_name: String = "?"
		if input_events.size() > 0 and input_events[0] is InputEventKey:
			key_name = _get_key_name(input_events[0] as InputEventKey)
		key_labels_arr.append(key_name)
		var num: int = i + 1
		control_content.text += "    " + str(num) + "  " + action_name.replace("_", " ").capitalize() + ":  " + key_name + "\n"
	control_content.text += "\nPress number key to rebind, Q to cancel, Enter to save"

func _get_key_name(event: InputEventKey) -> String:
	var pk := event.physical_keycode
	match pk:
		KEY_SPACE: return "Space"
		KEY_BACKSPACE: return "Backspace"
		KEY_TAB: return "Tab"
		KEY_ENTER: return "Enter"
		KEY_LEFT: return "Left"
		KEY_UP: return "Up"
		KEY_RIGHT: return "Right"
		KEY_DOWN: return "Down"
		KEY_SHIFT: return "Shift"
		KEY_CTRL: return "Ctrl"
		KEY_ALT: return "Alt"
		KEY_ESCAPE: return "Esc"
		KEY_COMMA: return ","
		KEY_PERIOD: return "."
		KEY_SLASH: return "/"
		KEY_BACKSLASH: return "\\"
		KEY_BRACKETLEFT: return "["
		KEY_BRACKETRIGHT: return "]"
		KEY_SEMICOLON: return ";"
		KEY_APOSTROPHE: return "'"
		KEY_EQUAL: return "="
		KEY_MINUS: return "-"
		KEY_0: return "0"
		KEY_1: return "1"
		KEY_2: return "2"
		KEY_3: return "3"
		KEY_4: return "4"
		KEY_5: return "5"
		KEY_6: return "6"
		KEY_7: return "7"
		KEY_8: return "8"
		KEY_9: return "9"
		KEY_A: return "A"
		KEY_B: return "B"
		KEY_C: return "C"
		KEY_D: return "D"
		KEY_E: return "E"
		KEY_F: return "F"
		KEY_G: return "G"
		KEY_H: return "H"
		KEY_I: return "I"
		KEY_J: return "J"
		KEY_K: return "K"
		KEY_L: return "L"
		KEY_M: return "M"
		KEY_N: return "N"
		KEY_O: return "O"
		KEY_P: return "P"
		KEY_Q: return "Q"
		KEY_R: return "R"
		KEY_S: return "S"
		KEY_T: return "T"
		KEY_U: return "U"
		KEY_V: return "V"
		KEY_W: return "W"
		KEY_X: return "X"
		KEY_Y: return "Y"
		KEY_Z: return "Z"
		_: return "Key " + str(pk)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var ke := event as InputEventKey
	if not ke.pressed or ke.is_echo():
		return

	if waiting_for_key:
		if ke.keycode == KEY_ESCAPE:
			waiting_for_key = false
			_show_keys_menu()
		elif ke.keycode != KEY_ENTER and ke.keycode != KEY_Q:
			_assign_key(ke)
		return

	match current_mode:
		Mode.MAIN:
			_handle_main_input(ke)
		Mode.CONFIGURE:
			_handle_configure_input(ke)
		Mode.KEYS:
			_handle_keys_input(ke)
	get_viewport().set_input_as_handled()

func _handle_main_input(ke: InputEventKey) -> void:
	match ke.keycode:
		KEY_S:
			start_single_player.emit()
			queue_free()
		KEY_N:
			start_network_game.emit()
			queue_free()
		KEY_C:
			_show_configure_menu()
		KEY_M:
			_reset_map()
		KEY_K:
			_show_keys_menu()
		KEY_Q:
			get_tree().quit()

func _handle_configure_input(ke: InputEventKey) -> void:
	match ke.keycode:
		KEY_Q:
			_show_main_menu()
		KEY_1:
			var opts := [0.5, 1.0, 1.5]
			var idx := opts.find(GameManager.difficulty)
			GameManager.difficulty = opts[(idx + 1) % opts.size()]
			_update_config_text()
		KEY_2:
			GameManager.enemy_planes = not GameManager.enemy_planes
			_update_config_text()
		KEY_3:
			GameManager.enemy_bombs = not GameManager.enemy_bombs
			_update_config_text()
		KEY_4:
			var opts := [2, 3, 4, 5, 6]
			var idx := opts.find(GameManager.enemy_homebases)
			GameManager.enemy_homebases = opts[(idx + 1) % opts.size()]
			_update_config_text()
		KEY_5:
			var opts := ["None", "Few", "Normal", "Many"]
			var idx := opts.find(GameManager.enemy_tanks)
			GameManager.enemy_tanks = opts[(idx + 1) % opts.size()]
			_update_config_text()
		KEY_6:
			GameManager.huge_explosions = not GameManager.huge_explosions
			_update_config_text()
		KEY_7:
			GameManager.bird_flocks = not GameManager.bird_flocks
			_update_config_text()
		KEY_8:
			var opts := ["None", "Few", "Normal", "Many"]
			var idx := opts.find(GameManager.cow_count)
			GameManager.cow_count = opts[(idx + 1) % opts.size()]
			_update_config_text()
		KEY_S:
			var opts := [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
			var idx := opts.find(GameManager.sound_fx_volume)
			GameManager.sound_fx_volume = opts[(idx + 1) % opts.size()]
			_update_config_text()
		KEY_M:
			var opts := [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
			var idx := opts.find(GameManager.music_volume)
			GameManager.music_volume = opts[(idx + 1) % opts.size()]
			_update_config_text()

func _handle_keys_input(ke: InputEventKey) -> void:
	match ke.keycode:
		KEY_Q:
			_show_main_menu()
		KEY_ENTER:
			_show_main_menu()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
			var idx := ke.keycode - KEY_1
			if idx < key_actions.size():
				selected_key_index = idx
				waiting_for_key = true
				control_content.text = "Press key for " + key_actions[idx].replace("_", " ").capitalize() + "\n\nEsc to cancel"

func _assign_key(ke: InputEventKey) -> void:
	if selected_key_index < 0 or selected_key_index >= key_actions.size():
		return
	var action_name: String = key_actions[selected_key_index]
	var new_event: InputEventKey = InputEventKey.new()
	new_event.keycode = ke.keycode
	new_event.physical_keycode = ke.physical_keycode
	new_event.pressed = false
	if InputMap.has_action(action_name):
		InputMap.action_erase_events(action_name)
	InputMap.action_add_event(action_name, new_event)
	_save_bindings()
	waiting_for_key = false
	selected_key_index = -1
	_show_keys_menu()

func _save_bindings() -> void:
	var cfg := ConfigFile.new()
	for action_name in key_actions:
		var evts: Array[InputEvent] = InputMap.action_get_events(action_name)
		if evts.size() > 0 and evts[0] is InputEventKey:
			var e: InputEventKey = evts[0] as InputEventKey
			cfg.set_value("input", action_name + "_keycode", e.keycode)
			cfg.set_value("input", action_name + "_physical", e.physical_keycode)
	cfg.save("user://keybindings.cfg")

func _process(delta: float) -> void:
	_handle_mouse_panning(delta)
	if preview_camera:
		preview_camera.position.x = scroll_x
	_update_sky_shader()

func _handle_mouse_panning(delta: float) -> void:
	if not preview_camera:
		return
	var mp: Vector2 = get_viewport().get_mouse_position()
	var vs: Vector2 = get_viewport().size
	var pan_zone: float = vs.x * 0.08
	var zoom: float = preview_camera.zoom.x
	var pan_speed: float = PAN_SPEED / zoom

	if mp.x < pan_zone:
		var factor: float = 1.0 - mp.x / pan_zone
		scroll_x -= pan_speed * factor * delta
	elif mp.x > vs.x - pan_zone:
		var factor: float = 1.0 - (vs.x - mp.x) / pan_zone
		scroll_x += pan_speed * factor * delta

	var half_w: float = ENGINE_CUTOFF_ALTITUDE * 0.5
	scroll_x = clampf(scroll_x, half_w, TERRAIN_LENGTH - half_w)

func _update_sky_shader() -> void:
	if preview_camera and sky_material:
		sky_material.set_shader_parameter("camera_y", preview_camera.position.y)
		sky_material.set_shader_parameter("ground_y", GROUND_Y)
		sky_material.set_shader_parameter("max_altitude", ENGINE_CUTOFF_ALTITUDE)

func _reset_map() -> void:
	if world_container:
		for c in world_container.get_children():
			c.queue_free()
		if GameManager:
			GameManager.terrain_seed = randi()
		_initialize_world_terrain()
		_spawn_clouds()
		_spawn_preview_targets()
	scroll_x = TERRAIN_LENGTH / 2.0
	if preview_camera:
		preview_camera.position.x = scroll_x
