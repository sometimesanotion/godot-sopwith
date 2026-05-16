extends CanvasLayer

signal start_game
signal start_vs_computer
signal back_to_menu

var selected_index: int = 0

func _ready() -> void:
	print("Title screen ready")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		match event.keycode:
			KEY_S:
				print("S pressed - starting single player")
				start_game.emit()
				queue_free()
			KEY_C:
				print("C pressed - starting vs computer")
				start_vs_computer.emit()
				queue_free()
			KEY_O:
				print("O pressed - options")
				_show_options()
			
			KEY_Q:
				print("Q pressed - quit")
				get_tree().quit()
			KEY_K:
				print("K pressed - temp test key_assignment")
				var key_screen = load("res://scenes/key_assignment.tscn").instantiate()
				key_screen.back_to_menu.connect(_on_key_assignment_back)
				get_parent().add_child(key_screen)
				visible = false

func _show_options() -> void:
	var options = load("res://scenes/options.tscn").instantiate()
	options.back_to_menu.connect(_on_options_back)
	get_parent().add_child(options)
	visible = false

func _on_options_back() -> void:
	print("Options back to menu")
	visible = true

func _on_key_assignment_back() -> void:
	visible = true
