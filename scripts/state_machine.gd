class_name StateMachine
extends Node

signal state_changed(current_state: State)

## Single, DRY registration of State children. Keys are the child node name in
## snake_case ("TakingOff" -> &"taking_off"); every existing FSM's handwritten
## `states_map` literal matched this exactly, so those literals are deleted.
var states_map: Dictionary = {}          # StringName key -> State (auto-built)
var current_state: State = null
var current_key: StringName = &""
var previous_key: StringName = &""
var self_driven: bool = true             # false = owner calls tick() manually
var _active: bool = false

func _ready() -> void:
	for child in get_children():
		if child is State:
			child.state_machine = self
			if not child.finished.is_connected(_change_state):
				child.finished.connect(_change_state)
			states_map[child.name.to_snake_case()] = child

## Owner calls this explicitly after any external references (e.g. controller)
## are wired into the FSM. Replaces the old `_enter_tree` auto-init ordering trap
## and the no-op start-state assignment.
func initialize(start_key: StringName) -> void:
	if not states_map.has(start_key):
		push_warning("StateMachine.initialize: unknown start key '%s'" % start_key)
		return
	_active = true
	if current_state and current_state != states_map[start_key]:
		current_state.exit()
	current_state = states_map[start_key]
	current_key = start_key
	previous_key = &""
	current_state.enter()

func is_active() -> bool:
	return _active

func set_active(value: bool) -> void:
	_active = value

## Advance the current state exactly once. Used both by the self-driven
## `_physics_process` and by owners that drive the FSM manually at a cadence
## they control (e.g. the AI controller at its decision interval).
func tick(delta: float) -> void:
	if current_state:
		current_state.update(delta)
		current_state.physics_update(delta)

func transition_to(state_name: StringName) -> void:
	_change_state(state_name)

func _change_state(state_name: StringName) -> void:
	if not _active:
		return
	if not current_state:
		return
	# Idempotent: re-entering the current state is a no-op.
	if state_name == current_key:
		return
	if not states_map.has(state_name):
		push_warning("StateMachine._change_state: unknown state '%s'" % state_name)
		return
	previous_key = current_key
	current_state.exit()
	current_state = states_map[state_name]
	current_key = state_name
	current_state.enter()
	state_changed.emit(current_state)

func _physics_process(delta: float) -> void:
	if _active and self_driven and current_state:
		tick(delta)
