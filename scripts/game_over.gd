extends CanvasLayer

signal restart_game

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("fire"):
		restart_game.emit()
		queue_free()