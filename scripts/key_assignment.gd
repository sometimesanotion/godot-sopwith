extends CanvasLayer

signal controls_set
signal back_to_menu

var key_mappings := {
	"throttle_up": {"action": "throttle_up", "label": "Accelerate", "default_key": "X", "current_key": null},
	"throttle_down": {"action": "throttle_down", "label": "Decelerate", "default_key": "Z", "current_key": null},
	"pull_up": {"action": "pull_up", "label": "Pull Up", "default_key": ",", "current_key": null},
	"pull_down": {"action": "pull_down", "label": "Pull Down", "default_key": "/", "current_key": null},
	"roll": {"action": "roll", "label": "Flip/Roll", "default_key": ".", "current_key": null},
	"fire": {"action": "fire", "label": "Fire Machine Gun", "default_key": "Space", "current_key": null},
	"bomb": {"action": "bomb", "label": "Drop Bomb", "default_key": "B", "current_key": null},
	"abort": {"action": "abort", "label": "Abort/Exit", "default_key": "Q", "current_key": null}
}

var mapping_buttons: Dictionary = {}
var selected_action: String = ""
var is_waiting_for_key: bool = false

@onready var container: VBoxContainer = $VBoxContainer
@onready var instructions: Label = $InstructionsLabel

func _ready() -> void:
	_load_current_bindings()
	_create_buttons()

func _load_current_bindings() -> void:
	for action_name in key_mappings.keys():
		var events = InputMap.get_action_list(action_name)
		if events.size() > 0:
			var event = events[0]
			if event is InputEventKey:
				key_mappings[action_name]["current_key"] = _get_key_name(event)

func _get_key_name(event: InputEventKey) -> String:
	var keycode := event.keycode
	var physical_keycode := event.physical_keycode
	
	match physical_keycode:
		KEY_SPACE: return "Space"
		KEY_BACKSPACE: return "Backspace"
		KEY_TAB: return "Tab"
		KEY_ENTER: return "Enter"
		KEY_LEFT: return "Left Arrow"
		KEY_UP: return "Up Arrow"
		KEY_RIGHT: return "Right Arrow"
		KEY_DOWN: return "Down Arrow"
		KEY_SHIFT: return "Shift"
		KEY_CTRL: return "Ctrl"
		KEY_ALT: return "Alt"
		KEY_ESCAPE: return "Escape"
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
		_: return "Key " + str(physical_keycode)

func _create_buttons() -> void:
	for action_name in key_mappings.keys():
		var mapping = key_mappings[action_name]
		var hbox := HBoxContainer.new()
		
		var label := Label.new()
		label.text = mapping["label"]
		label.custom_minimum_size.x = 200
		hbox.add_child(label)
		
		var key_label := Label.new()
		var display_key = mapping["current_key"] if mapping["current_key"] else mapping["default_key"]
		key_label.text = display_key
		key_label.custom_minimum_size.x = 120
		hbox.add_child(key_label)
		
		var button := Button.new()
		button.text = "Bind"
		button.pressed.connect(_on_bind_pressed.bind(action_name, key_label))
		hbox.add_child(button)
		
		container.add_child(hbox)
		mapping_buttons[action_name] = {"button": button, "key_label": key_label}

func _on_bind_pressed(action_name: String, key_label: Label) -> void:
	if is_waiting_for_key:
		return
	
	selected_action = action_name
	is_waiting_for_key = true
	instructions.text = "Press any key to bind to " + key_mappings[action_name]["label"]
	
	for btn in mapping_buttons.values():
		btn["button"].disabled = true

func _input(event: InputEvent) -> void:
	if not is_waiting_for_key:
		return
	
	if event is InputEventKey and event.pressed and event.keycode != KEY_ESCAPE:
		_assign_key(event)
		is_waiting_for_key = false
		instructions.text = "Press any key to rebind, ESC to return to menu"
		
		for btn in mapping_buttons.values():
			btn["button"].disabled = false
	
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		is_waiting_for_key = false
		instructions.text = "Press any key to rebind, ESC to return to menu"
		for btn in mapping_buttons.values():
			btn["button"].disabled = false

func _assign_key(event: InputEventKey) -> void:
	if event.keycode == KEY_ESCAPE:
		return
	
	var action_name = selected_action
	
	var new_event := InputEventKey.new()
	new_event.keycode = event.keycode
	new_event.physical_keycode = event.physical_keycode
	new_event.pressed = false
	
	if InputMap.has_action(action_name):
		InputMap.action_erase_events(action_name)
	
	InputMap.action_add_event(action_name, new_event)
	
	key_mappings[action_name]["current_key"] = _get_key_name(event)
	mapping_buttons[action_name]["key_label"].text = _get_key_name(event)
	_save_bindings()

func _save_bindings() -> void:
	var config = ConfigFile.new()
	for action_name in key_mappings.keys():
		var events = InputMap.get_action_list(action_name)
		if events.size() > 0 and events[0] is InputEventKey:
			var event = events[0]
			config.set_value("input", action_name + "_keycode", event.keycode)
			config.set_value("input", action_name + "_physical", event.physical_keycode)
	
	config.save("user://keybindings.cfg")

func _load_bindings() -> void:
	var config = ConfigFile.new()
	if config.load("user://keybindings.cfg") == OK:
		for action_name in key_mappings.keys():
			var keycode = config.get_value("input", action_name + "_keycode", 0)
			var physical = config.get_value("input", action_name + "_physical", 0)
			
			if keycode > 0 or physical > 0:
				var new_event := InputEventKey.new()
				new_event.keycode = keycode
				new_event.physical_keycode = physical
				new_event.pressed = false
				
				if InputMap.has_action(action_name):
					InputMap.action_erase_events(action_name)
				InputMap.action_add_event(action_name, new_event)

func _on_back_pressed() -> void:
	back_to_menu.emit()
	queue_free()

func _on_reset_pressed() -> void:
	_reset_to_defaults()
	_load_current_bindings()
	_create_buttons()

func _reset_to_defaults() -> void:
	var defaults := {
		"throttle_up": {"keycode": 0, "physical": 88},
		"throttle_down": {"keycode": 0, "physical": 90},
		"pull_up": {"keycode": 0, "physical": 44},
		"pull_down": {"keycode": 0, "physical": 47},
		"roll": {"keycode": 0, "physical": 46},
		"fire": {"keycode": 0, "physical": 32},
		"bomb": {"keycode": 0, "physical": 66},
	}
	
	for action_name in defaults.keys():
		var d = defaults[action_name]
		var event := InputEventKey.new()
		event.keycode = d["keycode"]
		event.physical_keycode = d["physical"]
		event.pressed = false
		
		if InputMap.has_action(action_name):
			InputMap.action_erase_events(action_name)
		InputMap.action_add_event(action_name, event)
	
	if FileAccess.file_exists("user://keybindings.cfg"):
		DirAccess.remove_absolute("user://keybindings.cfg")