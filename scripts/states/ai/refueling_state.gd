extends State

func enter() -> void:
	pass

func exit() -> void:
	pass

func update(delta: float) -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if not ai:
		return
	if not ai._is_on_homebase_for_ai():
		finished.emit(&"landed")
