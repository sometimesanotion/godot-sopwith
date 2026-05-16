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
			KEY_K:
				print("K pressed - keys")
				_show_key_assignment()
			KEY_Q:
				print("Q pressed - quit")
				get_tree().quit()

func _show_options() -> void:
	var options = load("res://scenes/options.tscn").instantiate()
	get_parent().add_child(options)
	queue_free()

func _show_key_assignment() -> void:
	var key_screen = load("res://scenes/key_assignment.tscn").instantiate()
	get_parent().add_child(key_screen)
	queue_free()