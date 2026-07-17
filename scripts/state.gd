class_name State
extends Node

signal finished(next_state_name: StringName)

var state_machine: StateMachine = null

func enter() -> void:
	pass

func exit() -> void:
	pass

## Reserved hook: invoked by the base class for input events. Currently unused
## (input is handled directly by the owner, e.g. Biplane._handle_input); kept as
## an extension point for future state-driven input handling.
func handle_input(_event: InputEvent) -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass

## Reserved hook: invoked on AnimationPlayer animation_finished. Currently unused
## (no state drives an animation); kept as an extension point.
func _on_animation_finished(_anim_name: String) -> void:
	pass
