extends Node


## Diagnostic logging singleton for debugging respawn/crash issues.
## Disable at runtime:  DLog.enabled = false
var enabled: bool = true


const MAX_BUFFER_SIZE := 500
const AUTO_FLUSH_INTERVAL := 30.0

var _buffer: Array[Dictionary] = []
var _flush_path: String = ""
var _auto_flush_timer: float = 0.0
var _initialized: bool = false

static var _inst: Node = null


func _init_buffer() -> void:
	if _initialized:
		return
	_initialized = true
	var timestamp = Time.get_unix_time_from_system()
	var dt = Time.get_datetime_dict_from_unix_time(timestamp)
	var ts_str = "%04d%02d%02d_%02d%02d%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
	_flush_path = "user://dlog_%s.json" % ts_str
	_auto_flush_timer = AUTO_FLUSH_INTERVAL


func _ready() -> void:
	_inst = self
	_init_buffer()


func _process(delta: float) -> void:
	if not enabled:
		return
	_auto_flush_timer -= delta
	if _auto_flush_timer <= 0.0:
		_auto_flush_timer = AUTO_FLUSH_INTERVAL
		flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and enabled:
		flush()


static func _check() -> bool:
	return _inst != null and _inst.enabled


static func _push(entry: Dictionary) -> void:
	if not _check():
		return
	_inst._buffer.append(entry)
	if _inst._buffer.size() > MAX_BUFFER_SIZE:
		_inst._buffer.pop_front()


static func event(source: String, kind: String, data: Dictionary = {}) -> void:
	if not _check():
		return
	var entry: Dictionary = {
		"t": Time.get_ticks_msec() / 1000.0,
		"source": source,
		"kind": kind,
	}
	for key in data:
		entry[key] = data[key]
	_push(entry)


static func crash_enter(avatar_id: int, cause: String, detail: Dictionary = {}) -> void:
	if not _check():
		return
	var entry: Dictionary = {
		"t": Time.get_ticks_msec() / 1000.0,
		"source": "biplane",
		"kind": "crash_enter",
		"avatar_id": avatar_id,
		"cause": cause,
	}
	if not detail.is_empty():
		entry["detail"] = detail
	_push(entry)


static func crash_guard(avatar_id: int, guard_name: String) -> void:
	if not _check():
		return
	var entry: Dictionary = {
		"t": Time.get_ticks_msec() / 1000.0,
		"source": "biplane",
		"kind": "crash_guard",
		"avatar_id": avatar_id,
		"guard": guard_name,
	}
	_push(entry)


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
	_push(entry)


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
	_push(entry)


static func flush() -> void:
	if not _check() or _inst._buffer.is_empty():
		return
	var file = FileAccess.open(_inst._flush_path, FileAccess.READ_WRITE)
	if not file:
		file = FileAccess.open(_inst._flush_path, FileAccess.WRITE)
	if not file:
		return
	file.seek_end()
	for entry in _inst._buffer:
		file.store_line(JSON.stringify(entry))
	_inst._buffer.clear()


static func clear() -> void:
	if not _check():
		return
	_inst._buffer.clear()


static func dump_recent(count: int = 20) -> String:
	if not _check() or _inst._buffer.is_empty():
		return ""
	var start = maxi(0, _inst._buffer.size() - count)
	var lines: PackedStringArray = []
	for i in range(start, _inst._buffer.size()):
		lines.append(JSON.stringify(_inst._buffer[i]))
	return "\n".join(lines)
