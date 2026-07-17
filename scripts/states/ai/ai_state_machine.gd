class_name AIStateMachine
extends StateMachine

var ai_controller: Node = null

func _ready() -> void:
	super._ready()

func set_ai_controller(controller: Node) -> void:
	ai_controller = controller

## Single source of truth for AI state ordinals. Order matches the FSM children;
## `get_ai_state_enum()` is just a key -> ordinal lookup over this array.
const AI_STATE_ORDER := [
	&"grounded",
	&"taking_off",
	&"patrolling",
	&"engaging",
	&"evading",
	&"returning",
	&"destroyed",
]

func get_ai_state_enum() -> int:
	return AI_STATE_ORDER.find(current_key)
