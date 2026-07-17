class_name GameStateMachine
extends StateMachine

signal game_state_changed(state_name: String)

## Registration is handled by the base StateMachine._ready (auto, DRY).
## Only the game-specific relay lives here.

func _change_state(state_name: StringName) -> void:
	super._change_state(state_name)
	if current_state:
		game_state_changed.emit(current_state.name)
