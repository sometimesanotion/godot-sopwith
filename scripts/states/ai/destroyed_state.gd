extends State

func enter() -> void:
	var ai = (state_machine as AIStateMachine).ai_controller
	if ai:
		ai.pilots[0].reset_control_outputs()

func exit() -> void:
	pass

func update(delta: float) -> void:
	pass
