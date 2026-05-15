extends Node

const SOUND_DIR := "res://assets/sounds/"
const MUSIC_DIR := "res://assets/music/"

var engine_sound: AudioStreamPlayer
var machine_gun_sound: AudioStreamPlayer
var explosion_sound: AudioStreamPlayer
var stall_warning_sound: AudioStreamPlayer
var music_player: AudioStreamPlayer

var engine_volume: float = 0.0
var is_playing: bool = false

func _ready() -> void:
	_setup_players()

func _setup_players() -> void:
	engine_sound = AudioStreamPlayer.new()
	engine_sound.name = "EngineSound"
	add_child(engine_sound)
	
	machine_gun_sound = AudioStreamPlayer.new()
	machine_gun_sound.name = "MachineGunSound"
	add_child(machine_gun_sound)
	
	explosion_sound = AudioStreamPlayer.new()
	explosion_sound.name = "ExplosionSound"
	add_child(explosion_sound)
	
	stall_warning_sound = AudioStreamPlayer.new()
	stall_warning_sound.name = "StallWarningSound"
	add_child(stall_warning_sound)
	
	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.bus = "Music"
	add_child(music_player)

func play_engine(throttle: float) -> void:
	if not engine_sound:
		return
	
	var pitch := 0.8 + throttle * 0.6
	engine_sound.pitch_scale = pitch
	engine_sound.volume_db = linear_to_db(0.3 + throttle * 0.4)
	
	if not engine_sound.playing and file_exists(SOUND_DIR + "engine.flac"):
		engine_sound.stream = load(SOUND_DIR + "engine.flac")
		engine_sound.play()

func stop_engine() -> void:
	if engine_sound:
		engine_sound.stop()

func play_machine_gun() -> void:
	if not machine_gun_sound:
		return
	
	if file_exists(SOUND_DIR + "machine_gun.flac"):
		if not machine_gun_sound.playing:
			machine_gun_sound.stream = load(SOUND_DIR + "machine_gun.flac")
			machine_gun_sound.play()
		else:
			machine_gun_sound.play()

func play_explosion() -> void:
	if not explosion_sound:
		return
	
	if file_exists(SOUND_DIR + "explosion.flac"):
		explosion_sound.stream = load(SOUND_DIR + "explosion.flac")
		explosion_sound.play()

func play_stall_warning() -> void:
	if not stall_warning_sound:
		return
	
	if file_exists(SOUND_DIR + "stall_warning.flac"):
		if not stall_warning_sound.playing:
			stall_warning_sound.stream = load(SOUND_DIR + "stall_warning.flac")
			stall_warning_sound.play()

func stop_stall_warning() -> void:
	if stall_warning_sound:
		stall_warning_sound.stop()

func play_music() -> void:
	if not music_player:
		return
	
	if file_exists(MUSIC_DIR + "theme.mp3"):
		music_player.stream = load(MUSIC_DIR + "theme.mp3")
		music_player.volume_db = linear_to_db(0.6)
		music_player.play()
		is_playing = true

func stop_music() -> void:
	if music_player:
		music_player.stop()
		is_playing = false

func pause_music() -> void:
	if music_player:
		music_player.stream_paused = true

func resume_music() -> void:
	if music_player:
		music_player.stream_paused = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		pause_music()
	elif what == NOTIFICATION_UNPAUSED:
		resume_music()

func file_exists(path: String) -> bool:
	return FileAccess.file_exists(path)