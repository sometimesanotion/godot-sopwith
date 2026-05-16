extends CanvasLayer

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("flip") or Input.is_action_just_pressed("ui_cancel"):
		resume_game()

func resume_game() -> void:
	get_tree().paused = false
	queue_free()