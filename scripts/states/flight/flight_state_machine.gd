class_name FlightStateMachine
extends StateMachine

var biplane: RigidBody2D = null

func _ready() -> void:
	states_map = {
		&"flying": $Flying,
		&"stalling": $Stalling,
		&"falling": $Falling,
		&"damaged": $Damaged,
		&"landed": $Landed,
		&"crashed": $Crashed,
		&"refueling": $Refueling,
	}
	for child in get_children():
		if child is State:
			child.state_machine = self
			if not child.finished.is_connected(_change_state):
				child.finished.connect(_change_state)

func set_biplane(plane: RigidBody2D) -> void:
	biplane = plane

func get_flight_state_enum() -> int:
	if not current_state:
		return 0
	var state_name: String = current_state.name
	match state_name:
		"Flying": return 0
		"Stalling": return 1
		"Falling": return 2
		"Damaged": return 3
		"Landed": return 4
		"Crashed": return 5
		"Refueling": return 4
		_: return 0
