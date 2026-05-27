class_name Damageable
extends Node

var damage: DamageData = DamageData.new()

func take_damage(amount: float, attacker: Node = null) -> void:
	if damage.take_damage(amount):
		_on_damage_state_changed()
	if damage.is_destroyed():
		_on_destroyed(attacker)

func _on_damage_state_changed() -> void:
	pass

func _on_destroyed(attacker: Node = null) -> void:
	pass
