extends Node

signal lives_changed(player_id: int, new_lives: int)
signal fuel_changed(player_id: int, new_fuel: float)
signal ammo_changed(player_id: int, new_ammo: int)
signal bombs_changed(player_id: int, new_bombs: int)
signal score_changed(player_id: int, new_score: int)
signal screen_shake_requested(player_id: int, intensity: float)
signal player_destroyed(player_id: int)

const MAX_LIVES := 5

var game_state: String = "PLAYING"

var terrain_seed: int = 0

var enemy_planes: bool = true
var enemy_bombs: bool = true
var enemy_homebases: int = 4
var enemy_tanks: String = "Normal"
var huge_explosions: bool = true
var bird_count: String = "None"
var cow_count: String = "Normal"
var sound_fx_volume: float = 0.2
var music_volume: float = 0.2
var debug_hud: bool = true
var player_faction: String = "United Kingdom"

var current_level: int = 1

func get_level_multiplier() -> float:
	return 1.0 + 0.1 * (current_level - 1)

class PlayerData:
	var avatar_id: int = 0
	var lives: int = MAX_LIVES
	var is_active: bool = false
	var is_player: bool = true
	var score: int = 0

	func reset() -> void:
		lives = MAX_LIVES
		is_active = false
		score = 0

	func set_avatar_id(aid: int) -> void:
		avatar_id = aid

var _players: Dictionary = {}

func _ready() -> void:
	_load_settings()
	reset_game()

func get_player_data(player_id: int) -> PlayerData:
	if not _players.has(player_id):
		_players[player_id] = PlayerData.new()
	return _players[player_id]

func get_or_create_player(player_id: int) -> PlayerData:
	var data := get_player_data(player_id)
	data.is_active = true
	return data

func has_active_players() -> bool:
	for pid in _players:
		if _players[pid].is_active and _players[pid].lives > 0:
			return true
	return false

func get_total_active_players() -> int:
	var count := 0
	for pid in _players:
		if _players[pid].is_active and _players[pid].lives > 0:
			count += 1
	return count

func get_first_active_player_id() -> int:
	for pid in _players:
		if _players[pid].is_active and _players[pid].lives > 0:
			return pid
	return 0

func _save_settings() -> void:
	var config = ConfigFile.new()
	config.save("user://settings.cfg")

func _load_settings() -> void:
	var config = ConfigFile.new()

func request_screen_shake(intensity: float) -> void:
	screen_shake_requested.emit(intensity)

func reset_game() -> void:
	_players.clear()
	game_state = "PLAYING"
	current_level = 1
	for pid in _players:
		_players[pid] = 0
	emit_signal("score_changed", 0)

func register_player(player_id: int) -> PlayerData:
	var data := get_or_create_player(player_id)
	data.reset()
	data.is_active = true
	emit_signals_for_player(player_id)
	return data

func unregister_player(player_id: int) -> void:
	if _players.has(player_id):
		_players[player_id].is_active = false

func emit_signals_for_player(player_id: int) -> void:
	var data := get_player_data(player_id)
	lives_changed.emit(player_id, data.lives)

	var avatar: Biplane.AvatarData = Biplane.get_avatar(player_id)
	if avatar:
		fuel_changed.emit(player_id, avatar.fuel)
		ammo_changed.emit(player_id, avatar.ammo)
		bombs_changed.emit(player_id, avatar.bombs)

func get_lives(player_id: int) -> int:
	return get_player_data(player_id).lives

func set_lives(player_id: int, value: int) -> void:
	var data := get_player_data(player_id)
	data.lives = value
	lives_changed.emit(player_id, data.lives)

func add_score(player_id: int, points: int) -> void:
	var data := get_player_data(player_id)
	data.score += points
	score_changed.emit(data.score)

func destroy_player(player_id: int) -> void:
	var data := get_player_data(player_id)
	data.lives -= 1
	lives_changed.emit(player_id, data.lives)
	player_destroyed.emit(player_id)
	if not has_active_players():
		game_over()

func game_over() -> void:
	game_state = "GAME_OVER"

func game_win() -> void:
	game_state = "WINNER"
