extends Node

signal lives_changed(player_id: int, new_lives: int)
signal fuel_changed(player_id: int, new_fuel: float)
signal ammo_changed(player_id: int, new_ammo: int)
signal bombs_changed(player_id: int, new_bombs: int)
signal score_changed(player_id: int, new_score: int)
signal screen_shake_requested(player_id: int, intensity: float)
signal player_destroyed(player_id: int)
signal model_changed(player_id: int, model_name: String)

const MAX_LIVES := 5

var game_fsm = null
var game_state: String = "PLAYING"

var terrain_seed: int = 0

var enemy_planes: bool = true
var enemy_bombs: bool = true
var enemy_homebases: int = 4
var enemy_tanks: String = "Normal"
var huge_explosions: bool = true
var bird_count: String = "Normal"
var cow_count: String = "Normal"
var sound_fx_volume: float = 0.2
var music_volume: float = 0.2
var debug_hud: bool = false
var player_faction: String = "British"

var current_level: int = 1

func get_level_multiplier() -> float:
	return 1.0 + 0.1 * (current_level - 1)

var _players: Dictionary = {}

func is_player(avatar_id: int) -> bool:
	return _players.has(avatar_id) and _players[avatar_id].is_player

func _ready() -> void:
	_load_settings()
	reset_game()
	_init_game_fsm()

func _init_game_fsm() -> void:
	var GameStateMachineClass = load("res://scripts/states/game/game_state_machine.gd")
	game_fsm = GameStateMachineClass.new()
	game_fsm.name = "GameStateMachine"

	var state_scripts := {
		"Title": load("res://scripts/states/game/title_state.gd"),
		"Playing": load("res://scripts/states/game/playing_state.gd"),
		"Paused": load("res://scripts/states/game/paused_state.gd"),
		"GameOver": load("res://scripts/states/game/game_over_state.gd"),
		"LevelComplete": load("res://scripts/states/game/level_complete_state.gd"),
	}
	var StateClass = load("res://scripts/state.gd")
	for state_name in state_scripts:
		var state_node = StateClass.new()
		state_node.name = state_name
		state_node.set_script(state_scripts[state_name])
		game_fsm.add_child(state_node)

	add_child(game_fsm)
	game_fsm.start_state = game_fsm.get_node("Playing").get_path()
	game_fsm.game_state_changed.connect(_on_game_state_changed)

func _on_game_state_changed(state_name: String) -> void:
	game_state = state_name

func get_current_game_state() -> String:
	if game_fsm and game_fsm.current_state:
		return game_fsm.current_state.name
	return game_state

func get_player_data(player_id: int) -> PlayerData:
	if not _players.has(player_id):
		var PlayerDataClass = load("res://scripts/player_data.gd")
		_players[player_id] = PlayerDataClass.new()
	return _players[player_id]

func get_or_create_player(player_id: int) -> PlayerData:
	var data = get_player_data(player_id)
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
	if game_fsm and game_fsm._active:
		game_fsm.transition_to(&"playing")

func register_player(player_id: int) -> PlayerData:
	var data = get_or_create_player(player_id)
	data.reset()
	data.is_player = true
	data.is_active = true
	emit_signals_for_player(player_id)
	return data

func unregister_player(player_id: int) -> void:
	if _players.has(player_id):
		_players[player_id].is_active = false

func emit_signals_for_player(player_id: int) -> void:
	var data = get_player_data(player_id)
	lives_changed.emit(player_id, data.lives)

	var BiplaneClass = load("res://scripts/biplane.gd")
	var avatar = BiplaneClass.get_avatar(player_id)
	if avatar:
		fuel_changed.emit(player_id, avatar.fuel)
		ammo_changed.emit(player_id, avatar.ammo)
		bombs_changed.emit(player_id, avatar.bombs)

func get_lives(player_id: int) -> int:
	return get_player_data(player_id).lives

func set_lives(player_id: int, value: int) -> void:
	var data = get_player_data(player_id)
	data.lives = value
	lives_changed.emit(player_id, data.lives)

func add_score(player_id: int, points: int) -> void:
	var data = get_player_data(player_id)
	data.score += points
	score_changed.emit(data.score)

func destroy_player(player_id: int) -> void:
	var data = get_player_data(player_id)
	data.lives -= 1
	lives_changed.emit(player_id, data.lives)
	player_destroyed.emit(player_id)
	if not has_active_players():
		game_over()

func game_over() -> void:
	game_state = "GAME_OVER"
	if game_fsm and game_fsm._active:
		game_fsm.transition_to(&"game_over")

func game_win() -> void:
	game_state = "WINNER"
	if game_fsm and game_fsm._active:
		game_fsm.transition_to(&"level_complete")
