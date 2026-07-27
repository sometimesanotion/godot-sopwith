extends Node

## Per-homebase tally of still-standing buildings, keyed by type.
##
## A homebase's buildings are registered the moment a ground target is
## instantiated (main.gd sets `homebase_id`) and unregistered the instant
## its wreck is created (ground_target.gd._destroy), so a building struck
## down mid-frame is already gone from the count before any refuel/rearm
## or respawn check runs that same frame.
##
## Homebase id scheme (must be globally unique across every biplane
## instance, unlike the per-instance _homebases dict):
##   * player homebase  -> 0
##   * enemy base `i`    -> i + 1
## This is the single source of truth for "does this base still have a
## hangar / fuel depot / ammo depot" used by biplane._check_home_refuel
## and by the AI respawn gate.

signal buildings_destroyed(homebase_id: int)

var _counts: Dictionary = {}  # homebase_id -> Dictionary[type: String -> int]

func reset() -> void:
	_counts.clear()

func register(homebase_id: int, target_type: String) -> void:
	var by_type: Dictionary = _counts.get(homebase_id, {})
	by_type[target_type] = by_type.get(target_type, 0) + 1
	_counts[homebase_id] = by_type

func unregister(homebase_id: int, target_type: String) -> void:
	if not _counts.has(homebase_id):
		return
	var by_type: Dictionary = _counts[homebase_id]
	var n: int = by_type.get(target_type, 0)
	if n <= 0:
		return
	n -= 1
	if n <= 0:
		by_type.erase(target_type)
		if by_type.is_empty():
			_counts.erase(homebase_id)
			# The base has lost its LAST standing building — this is the
			# moment it can no longer respawn planes.
			buildings_destroyed.emit(homebase_id)
	else:
		by_type[target_type] = n

func count(homebase_id: int, target_type: String) -> int:
	if not _counts.has(homebase_id):
		return 0
	return _counts[homebase_id].get(target_type, 0)

## Total surviving buildings of ANY type for this homebase.
func get_total_count(homebase_id: int) -> int:
	if not _counts.has(homebase_id):
		return 0
	var total := 0
	for type in _counts[homebase_id]:
		total += _counts[homebase_id][type]
	return total

func has_hangar(homebase_id: int) -> bool:
	return count(homebase_id, "hangar") > 0

## True when the homebase still has at least one standing building of
## ANY type.  A base with no buildings left can no longer put planes
## back in the air.
func has_any_building(homebase_id: int) -> bool:
	return _counts.has(homebase_id) and not _counts[homebase_id].is_empty()

func has_fuel_depot(homebase_id: int) -> bool:
	return count(homebase_id, "fuel_depot") > 0

func has_ammo_depot(homebase_id: int) -> bool:
	return count(homebase_id, "ammo_depot") > 0
