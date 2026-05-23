extends CanvasLayer

signal start_single_player
signal start_network_game
signal back_to_menu

enum Mode { MAIN, CONFIGURE, KEYS }

var current_mode: int = Mode.MAIN

var control_title: Label
var control_content: Label
var header_bg: ColorRect
var cp_bg: ColorRect
var title_label: Label
var bip_sprite: Node2D
var sop_sprite: Node2D

var selected_key_index: int = -1
var waiting_for_key: bool = false
var key_actions: Array[String] = []
var key_labels_arr: Array[String] = []
var _last_known_size := Vector2(-1, -1)

func _ready() -> void:
	get_viewport().size_changed.connect(_rebuild_all)

func _rebuild_all() -> void:
	var vp := get_viewport()
	if not vp:
		return
	var vs: Vector2 = vp.size
	if vs == _last_known_size:
		return
	_last_known_size = vs
	print("TitleScreen rebuild: ", vs)
	_update_layout_from_scratch()

func _update_layout_from_scratch() -> void:
	_clear_all()

	var vs: Vector2 = get_viewport().size
	var hh: float = vs.y * 0.12
	var cp_height: float = min(vs.y - hh - 40, 700.0)
	var cp_y: float = hh + (vs.y - hh - cp_height) * 0.5

	header_bg = ColorRect.new()
	header_bg.name = "HeaderBg"
	header_bg.color = Color(0.0, 0.0, 0.0, 0.55)
	header_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	header_bg.position = Vector2.ZERO
	header_bg.size = Vector2(vs.x, hh)
	add_child(header_bg)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "SOPWITH 2026"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", maxi(16, int(hh * 0.35)))
	title_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title_label.add_theme_constant_override("outline_size", 3)
	title_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title_label.position = Vector2.ZERO
	title_label.size = Vector2(vs.x, hh)
	add_child(title_label)

	var svg_h: float = hh * 0.40
	var bip_path := "res://assets/svg/biplane.svg"
	var sop_path := "res://assets/svg/sopwith.svg"

	if ResourceLoader.exists(bip_path):
		var tex: Texture2D = load(bip_path)
		var asp: float = float(tex.get_width()) / float(max(tex.get_height(), 1))
		var sw: float = svg_h * asp
		bip_sprite = Node2D.new()
		bip_sprite.name = "BiplaneNode"
		bip_sprite.position = Vector2(20.0 + sw * 0.5, hh * 0.5)
		add_child(bip_sprite)
		var sp := Sprite2D.new()
		sp.texture = tex
		var sc: float = svg_h / max(tex.get_height(), 1)
		sp.scale = Vector2(sc, sc)
		sp.rotation_degrees = 0.0
		sp.flip_v = false
		bip_sprite.add_child(sp)

	if ResourceLoader.exists(sop_path):
		var tex: Texture2D = load(sop_path)
		var asp: float = float(tex.get_width()) / float(max(tex.get_height(), 1))
		var sw: float = svg_h * asp
		sop_sprite = Node2D.new()
		sop_sprite.name = "SopwithNode"
		sop_sprite.position = Vector2(vs.x - 20.0 - sw * 0.5, hh * 0.5)
		add_child(sop_sprite)
		var sp := Sprite2D.new()
		sp.texture = tex
		var sc: float = svg_h / max(tex.get_height(), 1)
		sp.scale = Vector2(sc, sc)
		sp.flip_h = true
		sop_sprite.add_child(sp)

	cp_bg = ColorRect.new()
	cp_bg.name = "ControlBg"
	cp_bg.color = Color(0.0, 0.0, 0.0, 0.80)
	cp_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cp_bg.position = Vector2(0, cp_y)
	cp_bg.size = Vector2(vs.x, cp_height)
	add_child(cp_bg)

	control_title = Label.new()
	control_title.name = "ControlTitle"
	control_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	control_title.add_theme_font_size_override("font_size", maxi(12, int(cp_height * 0.07)))
	control_title.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	control_title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control_title.position = Vector2(0, cp_y + cp_height * 0.04)
	control_title.size = Vector2(vs.x, cp_height * 0.18)
	add_child(control_title)

	control_content = Label.new()
	control_content.name = "ControlContent"
	control_content.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	control_content.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	control_content.autowrap_mode = TextServer.AUTOWRAP_WORD
	control_content.add_theme_font_size_override("font_size", maxi(10, int(cp_height * 0.04)))
	control_content.add_theme_color_override("font_color", Color(1, 1, 1))
	control_content.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control_content.position = Vector2(vs.x * 0.06, cp_y + cp_height * 0.2)
	control_content.size = Vector2(vs.x * 0.88, cp_height * 0.5)
	add_child(control_content)

	match current_mode:
		Mode.MAIN: _show_main_menu()
		Mode.CONFIGURE: _show_configure_menu()
		Mode.KEYS: _show_keys_menu()

func _clear_all() -> void:
	for c in get_children():
		c.queue_free()
	header_bg = null
	title_label = null
	bip_sprite = null
	sop_sprite = null
	cp_bg = null
	control_title = null
	control_content = null



func _show_main_menu() -> void:
	current_mode = Mode.MAIN
	if SoundManager:
		SoundManager.play_music("res://assets/music/title.ogg")
	if control_title:
		control_title.text = ""
	if control_content:
		control_content.text = "    S  - Start Single Player\n    N  - Start Network Game\n    C  - Configure Gameplay\n    K  - Key Layouts\n    Q  - Quit"

func _show_configure_menu() -> void:
	current_mode = Mode.CONFIGURE
	if control_title:
		control_title.text = "CONFIGURE GAMEPLAY"
	_update_config_text()

func _update_config_text() -> void:
	if not control_content or not control_title:
		return
	var tanks_str: String = GameManager.enemy_tanks
	var birds_str: String = GameManager.bird_count
	var cows_str: String = GameManager.cow_count
	var sfx_str: String = str(GameManager.sound_fx_volume) if GameManager.sound_fx_volume > 0 else "None"
	var music_str: String = str(GameManager.music_volume) if GameManager.music_volume > 0 else "None"
	control_content.text = "1 - Faction:  " + GameManager.player_faction + "\n"
	control_content.text += "2 - Enemy Planes:  " + ("ON" if GameManager.enemy_planes else "OFF") + "\n"
	control_content.text += "3 - Enemy Bombs:  " + ("ON" if GameManager.enemy_bombs else "OFF") + "\n"
	control_content.text += "4 - Huge Explosions:  " + ("ON" if GameManager.huge_explosions else "OFF") + "\n"
	control_content.text += "5 - Enemy Homebases:  " + str(GameManager.enemy_homebases) + "\n"
	control_content.text += "6 - Bird Flocks:  " + birds_str + "\n"
	control_content.text += "7 - Cows:  " + cows_str + "\n"
	control_content.text += "8 - Enemy Tanks:  " + tanks_str + "\n"
	control_content.text += "9 - Debug HUD:  " + ("ON" if GameManager.debug_hud else "OFF") + "\n"
	control_content.text += "S - Sound FX Volume:  " + sfx_str + "\n"
	control_content.text += "M - Music Volume:  " + music_str + "\n\n"
	control_content.text += "Q - Back to Menu"

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
		control_content.text += str(num) + " - " + action_name.replace("_", " ").capitalize() + ":  " + key_name + "\n"
	control_content.text += "\nPress number for key to rebind, Q to cancel, Enter to save"

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
		KEY_K:
			_show_keys_menu()
		KEY_Q:
			get_tree().quit()

func _handle_configure_input(ke: InputEventKey) -> void:
	match ke.keycode:
		KEY_Q:
			_show_main_menu()
		KEY_1:
			var faction_opts := ["United Kingdom", "France", "Germany"]
			var idx := faction_opts.find(GameManager.player_faction)
			GameManager.player_faction = faction_opts[(idx + 1) % faction_opts.size()]
			_update_config_text()
		KEY_2:
			GameManager.enemy_planes = not GameManager.enemy_planes
			_update_config_text()
		KEY_3:
			GameManager.enemy_bombs = not GameManager.enemy_bombs
			_update_config_text()
		KEY_4:
			GameManager.huge_explosions = not GameManager.huge_explosions
			_update_config_text()
		KEY_5:
			var opts := [2, 3, 4, 5, 6]
			var idx := opts.find(GameManager.enemy_homebases)
			GameManager.enemy_homebases = opts[(idx + 1) % opts.size()]
			_update_config_text()
		KEY_6:
			var opts := ["None", "Few", "Normal", "Many"]
			var idx := opts.find(GameManager.bird_count)
			GameManager.bird_count = opts[(idx + 1) % opts.size()]
			_update_config_text()
		KEY_7:
			var opts := ["None", "Few", "Normal", "Many"]
			var idx := opts.find(GameManager.cow_count)
			GameManager.cow_count = opts[(idx + 1) % opts.size()]
			_update_config_text()
		KEY_8:
			var opts := ["None", "Few", "Normal", "Many"]
			var idx := opts.find(GameManager.enemy_tanks)
			GameManager.enemy_tanks = opts[(idx + 1) % opts.size()]
			_update_config_text()
		KEY_9:
			GameManager.debug_hud = not GameManager.debug_hud
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

func _process(_delta: float) -> void:
	if _last_known_size == Vector2(-1, -1):
		var vq := get_viewport()
		if vq:
			var vs: Vector2 = vq.size
			if vs.x > 100 and vs.y > 100:
				_rebuild_all()
