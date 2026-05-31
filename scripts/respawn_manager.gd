extends Node

## Autoload singleton. Sole authority for respawn timing and positioning.

const MAX_RESPAWN_DELAY := 10.0
const RESPAWN_DELAY := 2.0

var _queue: Dictionary[int, float] = {}

signal respawn_ready(avatar_id: int)

func queue_respawn(avatar_id: int, delay: float) -> void:
	if _queue.has(avatar_id):
		if delay >= _queue[avatar_id]:
			return
		_queue[avatar_id] = delay
		DLog.respawn_queue(avatar_id, "replace", {
			"delay": delay,
			"from": "shorter_replace",
		})
	else:
		_queue[avatar_id] = delay
		DLog.respawn_queue(avatar_id, "add", {
			"delay": delay,
			"from": "new_queue",
		})

func cancel_respawn(avatar_id: int) -> void:
	if _queue.erase(avatar_id):
		DLog.respawn_queue(avatar_id, "cancel", {})

func clear_all() -> void:
	_queue.clear()
	DLog.info("respawn_clear", {"queue_size": _queue.size()})

func _process(delta: float) -> void:
	var to_fire: Array[int] = []
	for avatar_id in _queue:
		_queue[avatar_id] -= delta
		if _queue[avatar_id] <= 0.0:
			to_fire.append(avatar_id)
	for avatar_id in to_fire:
		_queue.erase(avatar_id)
		DLog.respawn_queue(avatar_id, "fire", {
			"delay_used": 0.0,
		})
		respawn_ready.emit(avatar_id)
