class_name DamageData
extends RefCounted

enum DamageState { INTACT = 0, LIGHT = 1, MODERATE = 2, SEVERE = 3, DESTROYED = 4 }

var damage_percent: float = 0.0
var damage_state: DamageState = DamageState.INTACT
var previous_state: DamageState = DamageState.INTACT

var threshold_light: float = 0.25
var threshold_moderate: float = 0.50
var threshold_severe: float = 0.80
var threshold_destroyed: float = 1.00

signal damage_state_changed(from: DamageState, to: DamageState)
signal destroyed()

func take_damage(amount: float) -> bool:
	if damage_state == DamageState.DESTROYED:
		return false
	damage_percent = minf(1.0, damage_percent + amount)
	var new_state := get_damage_state()
	if new_state != damage_state:
		previous_state = damage_state
		damage_state = new_state
		damage_state_changed.emit(previous_state, damage_state)
		if damage_state == DamageState.DESTROYED:
			destroyed.emit()
		return true
	previous_state = damage_state
	damage_state = new_state
	return false

func repair(fully: bool = false, amount: float = 0.0) -> void:
	if fully:
		damage_percent = 0.0
	else:
		damage_percent = maxf(0.0, damage_percent - amount)
	var new_state := get_damage_state()
	if new_state != damage_state:
		previous_state = damage_state
		damage_state = new_state
		damage_state_changed.emit(previous_state, damage_state)

func reset() -> void:
	previous_state = damage_state
	damage_percent = 0.0
	damage_state = DamageState.INTACT
	if previous_state != DamageState.INTACT:
		damage_state_changed.emit(previous_state, DamageState.INTACT)

func get_damage_state() -> DamageState:
	if damage_percent >= threshold_destroyed:
		return DamageState.DESTROYED
	elif damage_percent >= threshold_severe:
		return DamageState.SEVERE
	elif damage_percent >= threshold_moderate:
		return DamageState.MODERATE
	elif damage_percent >= threshold_light:
		return DamageState.LIGHT
	return DamageState.INTACT

func is_destroyed() -> bool:
	return damage_state == DamageState.DESTROYED

func get_modifiers() -> Dictionary:
	match damage_state:
		DamageState.LIGHT:
			return {"reliability": 0.9, "drag_multiplier": 1.1, "thrust_multiplier": 0.95}
		DamageState.MODERATE:
			return {"reliability": 0.7, "drag_multiplier": 1.3, "thrust_multiplier": 0.85}
		DamageState.SEVERE:
			return {"reliability": 0.4, "drag_multiplier": 1.6, "thrust_multiplier": 0.7}
		DamageState.DESTROYED:
			return {"reliability": 0.0, "drag_multiplier": 2.0, "thrust_multiplier": 0.0}
		_:
			return {"reliability": 1.0, "drag_multiplier": 1.0, "thrust_multiplier": 1.0}
