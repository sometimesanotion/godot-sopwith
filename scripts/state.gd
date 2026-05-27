class_name State
extends Node

signal finished(next_state_name: StringName)

var state_machine: StateMachine = null

func enter() -> void:
	pass

func exit() -> void:
	pass

func handle_input(_event: InputEvent) -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass

func _on_animation_finished(_anim_name: String) -> void:
	pass
