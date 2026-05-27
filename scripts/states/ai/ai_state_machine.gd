class_name AIStateMachine
extends StateMachine

var ai_controller: Node = null

func _ready() -> void:
	states_map = {
		&"grounded": $Grounded,
		&"taking_off": $TakingOff,
		&"patrolling": $Patrolling,
		&"engaging": $Engaging,
		&"evading": $Evading,
		&"returning": $Returning,
		&"destroyed": $Destroyed,
		&"refueling": $Refueling,
	}
	for child in get_children():
		if child is State:
			child.state_machine = self
			if not child.finished.is_connected(_change_state):
				child.finished.connect(_change_state)

func set_ai_controller(controller: Node) -> void:
	ai_controller = controller

func get_ai_state_enum() -> int:
	if not current_state:
		return 0
	var state_name: String = current_state.name
	match state_name:
		"Grounded": return 0
		"TakingOff": return 1
		"Patrolling": return 2
		"Engaging": return 3
		"Evading": return 4
		"Returning": return 5
		"Destroyed": return 6
		"Refueling": return 7
		_: return 0
