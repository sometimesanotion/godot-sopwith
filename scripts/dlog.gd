extends Node


## Diagnostic logging — prints JSON damage/destruction events to stdout.
## Only active when GameManager.debug_hud is true.
## Disable at runtime:  GameManager.debug_hud = false

static var _inst: Node = null


func _ready() -> void:
	_inst = self


static func _check() -> bool:
	if _inst == null:
		return false
	if not GameManager or not GameManager.debug_hud:
		return false
	return true


static func crash_enter(avatar_id: int, cause: String, data: Dictionary = {}) -> void:
	if not _check():
		return
	var entry: Dictionary = {
		"t": Time.get_ticks_msec() / 1000.0,
		"source": "biplane",
		"kind": "crash_enter",
		"avatar_id": avatar_id,
		"cause": cause,
	}
	for key in data:
		entry[key] = data[key]
	print("[DLog] ", JSON.stringify(entry))


static func crash_guard(avatar_id: int, guard_name: String, data: Dictionary = {}) -> void:
	if not _check():
		return
	var entry: Dictionary = {
		"t": Time.get_ticks_msec() / 1000.0,
		"source": "biplane",
		"kind": "crash_guard",
		"avatar_id": avatar_id,
		"guard": guard_name,
	}
	for key in data:
		entry[key] = data[key]
	print("[DLog] ", JSON.stringify(entry))


static func respawn_queue(avatar_id: int, action: String, data: Dictionary = {}) -> void:
	if not _check():
		return
	var entry: Dictionary = {
		"t": Time.get_ticks_msec() / 1000.0,
		"source": "main",
		"kind": "respawn_queue",
		"avatar_id": avatar_id,
		"action": action,
	}
	for key in data:
		entry[key] = data[key]
	print("[DLog] ", JSON.stringify(entry))


static func respawn_enemy(enemy_id: int, action: String, data: Dictionary = {}) -> void:
	if not _check():
		return
	var entry: Dictionary = {
		"t": Time.get_ticks_msec() / 1000.0,
		"source": "enemy_ai",
		"kind": "respawn_enemy",
		"enemy_id": enemy_id,
		"action": action,
	}
	for key in data:
		entry[key] = data[key]
	print("[DLog] ", JSON.stringify(entry))


static func info(category: String, data: Dictionary = {}) -> void:
	if not _check():
		return
	var entry: Dictionary = {
		"t": Time.get_ticks_msec() / 1000.0,
		"source": "test",
		"kind": "info",
		"category": category,
	}
	for key in data:
		entry[key] = data[key]
	print("[DLog] ", JSON.stringify(entry))
