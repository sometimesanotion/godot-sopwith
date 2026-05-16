extends CanvasLayer

signal start_game

const KEY_ASSIGNMENT_SCENE := preload("res://scenes/key_assignment.tscn")

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("fire"):
		start_game.emit()
		queue_free()
	
	if Input.is_key_pressed(KEY_K):
		_show_key_assignment()

func _show_key_assignment() -> void:
	var key_screen := KEY_ASSIGNMENT_SCENE.instantiate()
	get_parent().add_child(key_screen)
	queue_free()

func _on_key_settings_pressed() -> void:
	_show_key_assignment()