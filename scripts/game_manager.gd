extends Node

signal lives_changed(new_lives: int)
signal fuel_changed(new_fuel: float)
signal score_changed(new_score: int)
signal screen_shake_requested(intensity: float)

var lives: int = 5
var fuel: float = 100.0
var score: int = 0
var ammo: int = 100
var bombs: int = 5

const MAX_LIVES := 5
const MAX_FUEL := 100.0
const MAX_AMMO := 100
const MAX_BOMBS := 5

var game_state: String = "PLAYING"

func request_screen_shake(intensity: float) -> void:
	screen_shake_requested.emit(intensity)

func _ready() -> void:
	reset_game()

func reset_game() -> void:
	lives = MAX_LIVES
	fuel = MAX_FUEL
	score = 0
	ammo = MAX_AMMO
	bombs = MAX_BOMBS
	game_state = "PLAYING"
	emit_signals()

func emit_signals() -> void:
	lives_changed.emit(lives)
	fuel_changed.emit(fuel)
	score_changed.emit(score)

func take_damage() -> void:
	lives -= 1
	lives_changed.emit(lives)
	if lives <= 0:
		game_over()

func add_score(points: int) -> void:
	score += points
	score_changed.emit(score)

func use_fuel(amount: float) -> void:
	fuel = max(0, fuel - amount)
	fuel_changed.emit(fuel)

func refuel(amount: float = MAX_FUEL) -> void:
	fuel = min(MAX_FUEL, fuel + amount)
	fuel_changed.emit(fuel)

func use_ammo() -> bool:
	if ammo > 0:
		ammo -= 1
		return true
	return false

func use_bomb() -> bool:
	if bombs > 0:
		bombs -= 1
		return true
	return false

func reload_weapons(amount: float = 0.0) -> void:
	if amount > 0:
		ammo = min(MAX_AMMO, ammo + amount * 50)
	else:
		ammo = MAX_AMMO

func reload_bombs(amount: float = 0.0) -> void:
	if amount > 0:
		bombs = min(MAX_BOMBS, bombs + amount)
	else:
		bombs = MAX_BOMBS

func game_over() -> void:
	game_state = "GAME_OVER"

func game_win() -> void:
	game_state = "WINNER"