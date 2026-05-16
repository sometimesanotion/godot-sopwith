extends CanvasLayer

signal back_to_menu

var thrust_slider
var thrust_value_label
var key_mappings = {
	"throttle_up": {"action": "throttle_up", "label": "Accelerate", "default_key": "X", "current_key": null},
	"throttle_down": {"action": "throttle_down", "label": "Decelerate", "default_key": "Z", "current_key": null},
	"pull_up": {"action": "pull_up", "label": "Pull Up", "default_key": ",", "current_key": null},
	"pull_down": {"action": "pull_down", "label": "Pull Down", "default_key": "/", "current_key": null},
	"roll": {"action": "roll", "label": "Flip/Roll", "default_key": ".", "current_key": null},
	"fire": {"action": "fire", "label": "Fire Machine Gun", "default_key": "Space", "current_key": null},
	"bomb": {"action": "bomb", "label": "Drop Bomb", "default_key": "B", "current_key": null},
	"autopilot": {"action": "autopilot", "label": "Navigate Home", "default_key": "A", "current_key": null},
	"pause": {"action": "pause", "label": "Pause", "default_key": "P", "current_key": null},
	"abort": {"action": "abort", "label": "Abort/Exit", "default_key": "Q", "current_key": null}
}

var mapping_buttons = {}
var selected_action = ""
var is_waiting_for_key = false

var selected_index = 0
var controls = []
var selected_control = null

func _ready():
	_create_ui()

func _input(event):
	if is_waiting_for_key:
		_handle_keybinding_input(event)
		return
	
	if event is InputEventKey and event.pressed and not event.is_echo():
		match event.keycode:
			KEY_Q:
				_on_back()
			KEY_TAB:
				_cycle_selection(1)
			KEY_UP:
				_cycle_selection(-1)
			KEY_DOWN:
				_cycle_selection(1)
			KEY_LEFT:
				_adjust_slider(-1)
			KEY_RIGHT:
				_adjust_slider(1)
			KEY_ENTER, KEY_SPACE:
				_activate_selected()

func _handle_keybinding_input(event):
	if event is InputEventKey and event.pressed and event.keycode != KEY_ESCAPE:
		_assign_key(event)
		is_waiting_for_key = false
		_update_instructions("")
		for btn in mapping_buttons.values():
			btn["button"].disabled = false
		_update_controls_array()
	
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		is_waiting_for_key = false
		_update_instructions("")
		for btn in mapping_buttons.values():
			btn["button"].disabled = false
		_update_controls_array()

func _cycle_selection(delta):
	if controls.is_empty():
		return
	selected_index = (selected_index + delta + controls.size()) % controls.size()
	_select_control(controls[selected_index])

func _select_control(ctrl):
	if selected_control:
		_deselect_control(selected_control)
	selected_control = ctrl
	if ctrl:
		ctrl.modulate = Color(1.2, 1.2, 1.2)
		if ctrl is Button:
			ctrl.button_pressed = true
		elif ctrl is HSlider:
			ctrl.grab_focus()

func _deselect_control(ctrl):
	if ctrl:
		ctrl.modulate = Color(1, 1, 1)
		if ctrl is Button:
			ctrl.button_pressed = false

func _adjust_slider(delta):
	if selected_control is HSlider:
		var s = selected_control as HSlider
		s.value = clampf(s.value + (delta * s.step), s.min_value, s.max_value)
		_on_thrust_changed(s.value)

func _activate_selected():
	if selected_control is Button:
		(selected_control as Button).pressed.emit()

func _create_ui():
	controls.clear()
	
	var bg = ColorRect.new()
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.color = Color(0.1, 0.1, 0.15, 0.95)
	add_child(bg)
	
	var title = Label.new()
	title.text = "Options"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.position = Vector2(540, 30)
	add_child(title)
	
	var hint = Label.new()
	hint.text = "Tab/Arrows: Navigate  |  Enter: Select  |  Q: Back"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.position = Vector2(300, 70)
	add_child(hint)
	
	var thrust_lbl = Label.new()
	thrust_lbl.text = "Thrust Multiplier:"
	thrust_lbl.position = Vector2(80, 110)
	add_child(thrust_lbl)
	
	thrust_slider = HSlider.new()
	thrust_slider.min_value = 1.0
	thrust_slider.max_value = 10.0
	thrust_slider.step = 0.5
	thrust_slider.value = 5.0
	if GameManager:
		thrust_slider.value = GameManager.thrust_multiplier
	thrust_slider.position = Vector2(80, 135)
	thrust_slider.custom_minimum_size = Vector2(200, 30)
	thrust_slider.value_changed.connect(_on_thrust_changed)
	add_child(thrust_slider)
	controls.append(thrust_slider)
	
	thrust_value_label = Label.new()
	thrust_value_label.text = "%.1fx" % thrust_slider.value
	thrust_value_label.position = Vector2(290, 135)
	add_child(thrust_value_label)
	
	var thrust_hint = Label.new()
	thrust_hint.text = "1.0 (Realistic) - 10.0 (Arcade)"
	thrust_hint.position = Vector2(80, 165)
	thrust_hint.add_theme_font_size_override("font_size", 12)
	thrust_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(thrust_hint)
	
	var keys_title = Label.new()
	keys_title.text = "Key Bindings:"
	keys_title.position = Vector2(80, 200)
	keys_title.add_theme_font_size_override("font_size", 20)
	add_child(keys_title)
	
	var keys_desc = Label.new()
	keys_desc.text = "Select a row and press Enter or click Bind to rebind"
	keys_desc.position = Vector2(80, 225)
	keys_desc.add_theme_font_size_override("font_size", 12)
	keys_desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	add_child(keys_desc)
	
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(80, 250)
	scroll.custom_minimum_size = Vector2(350, 150)
	add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(350, 0)
	scroll.add_child(vbox)
	
	for action_name in key_mappings.keys():
		var mapping = key_mappings[action_name]
		var hbox = HBoxContainer.new()
		hbox.custom_minimum_size = Vector2(350, 30)
		
		var lbl = Label.new()
		lbl.text = mapping["label"]
		lbl.custom_minimum_size.x = 160
		hbox.add_child(lbl)
		
		var key_lbl = Label.new()
		var disp = mapping["current_key"] if mapping["current_key"] else mapping["default_key"]
		key_lbl.text = disp
		key_lbl.custom_minimum_size.x = 80
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hbox.add_child(key_lbl)
		
		var btn = Button.new()
		btn.text = "Bind"
		btn.custom_minimum_size.x = 70
		btn.pressed.connect(_on_bind_pressed.bind(action_name, key_lbl))
		hbox.add_child(btn)
		controls.append(btn)
		
		vbox.add_child(hbox)
		mapping_buttons[action_name] = {"button": btn, "key_label": key_lbl}
	
	var reset_btn = Button.new()
	reset_btn.text = "Reset Keys"
	reset_btn.position = Vector2(80, 410)
	reset_btn.pressed.connect(_on_reset_pressed)
	add_child(reset_btn)
	controls.append(reset_btn)
	
	var back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.position = Vector2(80, 450)
	back_btn.pressed.connect(_on_back)
	add_child(back_btn)
	controls.append(back_btn)
	
	if controls.size() > 0:
		selected_index = 0
		_select_control(controls[0])

func _update_controls_array():
	controls.clear()
	controls.append(thrust_slider)
	for k in mapping_buttons.keys():
		controls.append(mapping_buttons[k]["button"])
	
	var reset_btn = get_node_or_null("Button")
	var back_btn = get_node_or_null("Button (1)")
	if reset_btn:
		controls.append(reset_btn)
	if back_btn:
		controls.append(back_btn)
	
	if selected_control != null and selected_control not in controls:
		if controls.size() > 0:
			selected_index = 0
			selected_control = controls[0]
			_select_control(selected_control)

func _on_bind_pressed(action_name, key_label):
	if is_waiting_for_key:
		return
	selected_action = action_name
	is_waiting_for_key = true
	_update_instructions("Press key for " + key_mappings[action_name]["label"] + " (Esc to cancel)")
	for btn in mapping_buttons.values():
		btn["button"].disabled = true

func _update_instructions(text):
	var existing = get_node_or_null("InstructionsLabel")
	if existing:
		existing.queue_free()
	if text.is_empty():
		return
	var lbl = Label.new()
	lbl.name = "InstructionsLabel"
	lbl.text = text
	lbl.position = Vector2(80, 400)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	add_child(lbl)

func _assign_key(event):
	if event.keycode == KEY_ESCAPE:
		return
	var action_name = selected_action
	var new_event = InputEventKey.new()
	new_event.keycode = event.keycode
	new_event.physical_keycode = event.physical_keycode
	new_event.pressed = false
	if InputMap.has_action(action_name):
		InputMap.action_erase_events(action_name)
	InputMap.action_add_event(action_name, new_event)
	key_mappings[action_name]["current_key"] = _get_key_name(event)
	mapping_buttons[action_name]["key_label"].text = _get_key_name(event)
	_save_bindings()

func _get_key_name(event):
	var pk = event.physical_keycode
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

func _save_bindings():
	var cfg = ConfigFile.new()
	for an in key_mappings.keys():
		var evts = InputMap.action_get_events(an)
		if evts.size() > 0 and evts[0] is InputEventKey:
			var e = evts[0]
			cfg.set_value("input", an + "_keycode", e.keycode)
			cfg.set_value("input", an + "_physical", e.physical_keycode)
	cfg.save("user://keybindings.cfg")

func _on_reset_pressed():
	_reset_to_defaults()
	_load_current_bindings()
	_refresh_key_labels()

func _load_current_bindings():
	for an in key_mappings.keys():
		var evts = InputMap.action_get_events(an)
		if evts.size() > 0:
			var e = evts[0]
			if e is InputEventKey:
				key_mappings[an]["current_key"] = _get_key_name(e)

func _refresh_key_labels():
	for an in key_mappings.keys():
		var dk = key_mappings[an]["current_key"] if key_mappings[an]["current_key"] else key_mappings[an]["default_key"]
		mapping_buttons[an]["key_label"].text = dk

func _reset_to_defaults():
	var defaults = {
		"throttle_up": {"keycode": 0, "physical": 88},
		"throttle_down": {"keycode": 0, "physical": 90},
		"pull_up": {"keycode": 0, "physical": 44},
		"pull_down": {"keycode": 0, "physical": 47},
		"roll": {"keycode": 0, "physical": 46},
		"fire": {"keycode": 0, "physical": 32},
		"bomb": {"keycode": 0, "physical": 66},
		"autopilot": {"keycode": 0, "physical": 16777217},
		"abort": {"keycode": 0, "physical": 81}
	}
	for an in defaults.keys():
		var d = defaults[an]
		var ev = InputEventKey.new()
		ev.keycode = d["keycode"]
		ev.physical_keycode = d["physical"]
		ev.pressed = false
		if InputMap.has_action(an):
			InputMap.action_erase_events(an)
		InputMap.action_add_event(an, ev)
	if FileAccess.file_exists("user://keybindings.cfg"):
		DirAccess.remove_absolute("user://keybindings.cfg")

func _on_thrust_changed(value):
	thrust_value_label.text = "%.1fx" % value
	if GameManager:
		GameManager.set_thrust_multiplier(value)

func _on_back():
	back_to_menu.emit()
	queue_free()