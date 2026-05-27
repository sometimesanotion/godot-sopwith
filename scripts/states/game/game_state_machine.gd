class_name GameStateMachine
extends StateMachine

signal game_state_changed(state_name: String)

func _ready() -> void:
	states_map = {
		&"title": $Title,
		&"playing": $Playing,
		&"paused": $Paused,
		&"game_over": $GameOver,
		&"level_complete": $LevelComplete,
	}
	for child in get_children():
		if child is State:
			child.state_machine = self
			if not child.finished.is_connected(_change_state):
				child.finished.connect(_change_state)

func _change_state(state_name: StringName) -> void:
	super._change_state(state_name)
	if current_state:
		game_state_changed.emit(current_state.name)
