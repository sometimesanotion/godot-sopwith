extends CanvasLayer

func _ready() -> void:
	process_mode = PROCESS_MODE_WHEN_PAUSED

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume_game()
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.is_echo() and ke.keycode == KEY_Q:
			get_viewport().set_input_as_handled()
			resume_game()

func resume_game() -> void:
	get_tree().paused = false
	queue_free()
