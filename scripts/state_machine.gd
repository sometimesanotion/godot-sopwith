class_name StateMachine
extends Node

signal state_changed(current_state: State)

@export var start_state: NodePath

var states_map: Dictionary = {}
var states_stack: Array[State] = []
var current_state: State = null
var _active: bool = false:
	set(value):
		_active = value
		set_active(value)

func _enter_tree() -> void:
	var initial_state: Node
	if start_state.is_empty():
		initial_state = get_child(0)
	else:
		initial_state = get_node(start_state)
	for child in get_children():
		if child is State:
			child.state_machine = self
			if not child.finished.is_connected(_change_state):
				child.finished.connect(_change_state)
	initialize(initial_state)

func initialize(initial_state: State) -> void:
	_active = true
	states_stack.clear()
	states_stack.push_front(initial_state)
	current_state = states_stack[0]
	current_state.enter()

func set_active(value: bool) -> void:
	set_physics_process(value)
	set_process_input(value)
	if not _active:
		states_stack.clear()
		current_state = null

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.update(delta)
		current_state.physics_update(delta)

func _change_state(state_name: StringName) -> void:
	if not _active:
		return
	if not current_state:
		return
	current_state.exit()

	if state_name == &"previous":
		states_stack.pop_front()
	else:
		if state_name in states_map:
			states_stack[0] = states_map[state_name]

	current_state = states_stack[0] if states_stack.size() > 0 else null
	if current_state:
		state_changed.emit(current_state)
		if state_name != &"previous":
			current_state.enter()

func transition_to(state_name: StringName) -> void:
	_change_state(state_name)

func push_state(state_name: StringName) -> void:
	if not _active or not current_state:
		return
	if state_name in states_map:
		var new_state: State = states_map[state_name]
		current_state.exit()
		states_stack.push_front(new_state)
		current_state = new_state
		current_state.enter()
		state_changed.emit(current_state)

func pop_state() -> void:
	if not _active or not current_state:
		return
	current_state.exit()
	states_stack.pop_front()
	if states_stack.size() > 0:
		current_state = states_stack[0]
		state_changed.emit(current_state)
	else:
		current_state = null
