## sound_manager.gd
## Autoload singleton: Project > Project Settings > Autoload as "SoundManager"
##
## Audio bus layout expected in AudioServer (Project > Project Settings > Audio):
##   Master
##   └── Music   (for engine loops and BGM — add a LowPassFilter effect if desired)
##   └── SFX     (for all one-shot and looping effects)
##
## File-naming convention for variant groups (auto-discovered):
##   res://assets/sounds/bang_01.wav, bang_02.wav …   → SoundEvent.BANG
##   res://assets/sounds/gun_01.wav, gun_02.wav  …    → SoundEvent.GUN
##
## Engine loops (SoundEvent.ENGINE) should be a single looping file at:
##   res://assets/sounds/engine_loop.wav  (or .ogg)
##
##   SoundManager.play_sfx(SoundManager.SoundEvent.BANG)
##   SoundManager.play_sfx(SoundManager.SoundEvent.GUN, {"pan": -0.4})
##   SoundManager.play_music("res://assets/music/title.ogg")
##   SoundManager.set_engine_rpm(0.6)   # 0.0 = idle, 1.0 = full throttle
##   SoundManager.pause_all()
##   SoundManager.resume_all()

extends Node

# ---------------------------------------------------------------------------
# Public API types
# ---------------------------------------------------------------------------

## Every distinct sound the game can request.
## Add new entries freely; matching audio files are discovered automatically.
enum SoundEvent {
	ENGINE,       ## Continuous loop — use set_engine_rpm() to modulate
	GUN,          ## Machine-gun burst
	BOMB_WHISTLE, ## Bomb falling (looping while in air)
	EXPLOSION,    ## Ground / target impact
	BANG,         ## Generic bang/hit
	YELL,         ## Random yells
	BOING,        ## Silly bounce
	BUMP,         ## Soft collision
	PICKUP,       ## Collect an item
	PLAYER_HIT,   ## Player takes damage
}

# ---------------------------------------------------------------------------
# Configuration — tweak without touching the rest of the file
# ---------------------------------------------------------------------------

## Where one-shot / variant SFX files live.
const SFX_DIR := "res://assets/sounds/"
## Where music files live (used only as a reminder; pass full paths to play_music).
const MUSIC_DIR := "res://assets/music/"

## Number of polyphony voices available for simultaneous SFX.
## 32 is comfortable for an arcade game; raise if you hear voice stealing.
const SFX_POLYPHONY := 32

## Stem names that map each SoundEvent to its file prefix.
## For events with variants, files must be <stem>_01.wav, <stem>_02.wav, …
## For the ENGINE loop, only a single file is expected: <stem>.wav / .ogg
const EVENT_STEMS: Dictionary = {
	SoundEvent.ENGINE:       "engine_loop",
	SoundEvent.GUN:          "gun",
	SoundEvent.BOMB_WHISTLE: "bomb_whistle",
	SoundEvent.EXPLOSION:    "explosion",
	SoundEvent.BANG:         "bang",
	SoundEvent.YELL:         "yell",
	SoundEvent.BOING:        "boing",
	SoundEvent.BUMP:         "bump",
	SoundEvent.PICKUP:       "pickup",
	SoundEvent.PLAYER_HIT:   "player_hit",
}

## Per-event tuning.  All fields are optional; omit to use defaults.
## volume_db_min/max: random range in dB      (default 0.0 / 0.0)
## pitch_min/max:     random pitch-scale range (default 1.0 / 1.0)
## pan_min/max:       random stereo pan range  (default 0.0 / 0.0)
## max_polyphony:     how many simultaneous copies (default 4)
const EVENT_CONFIG: Dictionary = {
	SoundEvent.ENGINE: {
		"volume_db_min": -6.0, "volume_db_max": -6.0,
		"pitch_min": 0.8, "pitch_max": 1.0,  # overridden by set_engine_rpm()
	},
	SoundEvent.GUN: {
		"volume_db_min": -2.0, "volume_db_max": 0.0,
		"pitch_min": 0.95, "pitch_max": 1.05,
		"max_polyphony": 8,
	},
	SoundEvent.BOMB_WHISTLE: {
		"volume_db_min": -4.0, "volume_db_max": 0.0,
		"pitch_min": 1.0, "pitch_max": 1.0,
	},
	SoundEvent.EXPLOSION: {
		"volume_db_min": -1.0, "volume_db_max": 1.0,
		"pitch_min": 0.9, "pitch_max": 1.1,
	},
	SoundEvent.BANG: {
		"volume_db_min": -3.0, "volume_db_max": 0.0,
		"pitch_min": 0.9, "pitch_max": 1.1,
	},
	SoundEvent.YELL: {
		"volume_db_min": -3.0, "volume_db_max": 0.0,
		"pitch_min": 0.9, "pitch_max": 1.1,
	},
	SoundEvent.BOING: {
		"volume_db_min": -6.0, "volume_db_max": -2.0,
		"pitch_min": 0.85, "pitch_max": 1.15,
	},
	SoundEvent.BUMP: {
		"volume_db_min": -8.0, "volume_db_max": -4.0,
		"pitch_min": 0.9, "pitch_max": 1.1,
	},
	SoundEvent.PICKUP: {
		"volume_db_min": -4.0, "volume_db_max": 0.0,
		"pitch_min": 0.95, "pitch_max": 1.05,
	},
	SoundEvent.PLAYER_HIT: {
		"volume_db_min": 0.0, "volume_db_max": 0.0,
		"pitch_min": 0.95, "pitch_max": 1.05,
	},
}

## Engine RPM → pitch mapping.  x = normalised RPM (0–1), y = pitch scale.
const ENGINE_PITCH_IDLE    := 0.70
const ENGINE_PITCH_FULL    := 1.30
const ENGINE_VOLUME_IDLE   := -10.0  # dB
const ENGINE_VOLUME_FULL   :=  -6.0  # dB

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

## Loaded AudioStream arrays, keyed by SoundEvent.
var _streams: Dictionary = {}

## The single polyphonic SFX player.
var _sfx_player: AudioStreamPlayer
var _sfx_playback: AudioStreamPlaybackPolyphonic

## Dedicated looping player for the engine sound.
var _engine_player: AudioStreamPlayer
var _engine_active := false

## Dedicated looping player for bomb whistle.
var _bomb_whistle_player: AudioStreamPlayer
var _bomb_whistle_active := false

## Music player pair (A/B crossfade support).
var _music_player_a: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _music_active_player: AudioStreamPlayer  # whichever is currently audible
var _music_fade_tween: Tween

## Master pause state.
var _paused := false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_sfx_player()
	_build_engine_player()
	_build_bomb_whistle_player()
	_build_music_players()
	_load_all_streams()


## Call every frame (or from your plane's _process) to keep the engine sound alive.
func _process(_delta: float) -> void:
	# Keep the engine player looping if it fell off somehow.
	if _engine_active and not _engine_player.playing and not _paused:
		_engine_player.play()
	# Keep the bomb whistle player looping if it fell off somehow.
	if _bomb_whistle_active and not _bomb_whistle_player.playing and not _paused:
		_bomb_whistle_player.play()

# ---------------------------------------------------------------------------
# Builder helpers
# ---------------------------------------------------------------------------

func _build_sfx_player() -> void:
	var poly_stream := AudioStreamPolyphonic.new()
	poly_stream.polyphony = SFX_POLYPHONY

	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "SFXPlayer"
	_sfx_player.stream = poly_stream
	_sfx_player.bus = &"SFX"
	add_child(_sfx_player)
	_sfx_player.play()  # must be playing to obtain playback object
	_sfx_playback = _sfx_player.get_stream_playback() as AudioStreamPlaybackPolyphonic


func _build_engine_player() -> void:
	_engine_player = AudioStreamPlayer.new()
	_engine_player.name = "EnginePlayer"
	_engine_player.bus = &"SFX"
	_engine_player.volume_db = ENGINE_VOLUME_IDLE
	_engine_player.pitch_scale = ENGINE_PITCH_IDLE
	add_child(_engine_player)


func _build_bomb_whistle_player() -> void:
	_bomb_whistle_player = AudioStreamPlayer.new()
	_bomb_whistle_player.name = "BombWhistlePlayer"
	_bomb_whistle_player.bus = &"SFX"
	_bomb_whistle_player.volume_db = -6.0
	_bomb_whistle_player.pitch_scale = 1.0
	add_child(_bomb_whistle_player)


func _build_music_players() -> void:
	_music_player_a = _make_music_player("MusicA")
	_music_player_b = _make_music_player("MusicB")
	_music_active_player = _music_player_a


func _make_music_player(p_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = p_name
	player.bus = &"Music"
	player.volume_db = -80.0  # start silent
	add_child(player)
	return player

# ---------------------------------------------------------------------------
# Asset loading — discovers variant files automatically
# ---------------------------------------------------------------------------

func _load_all_streams() -> void:
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		push_error("SoundManager: SFX directory not found: %s" % SFX_DIR)
		return

	# Gather all .wav / .ogg / .mp3 filenames.
	var all_files: Array[String] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var lower := fname.to_lower()
			if lower.ends_with(".wav") or lower.ends_with(".ogg") or lower.ends_with(".mp3"):
				all_files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	all_files.sort()

	# Map each SoundEvent stem to any matching files.
	for event: int in EVENT_STEMS:
		var stem: String = EVENT_STEMS[event]
		var matched: Array[AudioStream] = []
		for f in all_files:
			var base := f.get_basename().to_lower()  # strip extension
			# Matches "engine_loop", "bang_01", "bang_02", …
			if base == stem or (base.begins_with(stem + "_") and base.substr(stem.length() + 1).is_valid_int()):
				var res := load(SFX_DIR + f) as AudioStream
				if res:
					matched.append(res)
				else:
					push_warning("SoundManager: could not load %s" % (SFX_DIR + f))

		if matched.is_empty():
			push_warning("SoundManager: no files found for event %s (stem '%s')" % [SoundEvent.keys()[event], stem])
		else:
			_streams[event] = matched

		# Wire engine loop stream.
		if event == SoundEvent.ENGINE and not matched.is_empty():
			_engine_player.stream = matched[0]
		# Wire bomb whistle stream.
		if event == SoundEvent.BOMB_WHISTLE and not matched.is_empty():
			_bomb_whistle_player.stream = matched[0]

# ---------------------------------------------------------------------------
# Public — SFX
# ---------------------------------------------------------------------------

## Play a sound event.
## Optional overrides dict keys: "volume_db", "pitch", "pan"
func play_sfx(event: SoundEvent, overrides: Dictionary = {}) -> void:
	if _paused:
		return
	if not _streams.has(event):
		push_warning("SoundManager: no streams loaded for event %s" % SoundEvent.keys()[event])
		return
	if event == SoundEvent.ENGINE:
		push_warning("SoundManager: use start_engine() / stop_engine() for the engine loop.")
		return

	var variants: Array = _streams[event]
	var stream: AudioStream = variants[randi() % variants.size()]
	var cfg: Dictionary = EVENT_CONFIG.get(event, {})

	var vol_db: float = overrides.get("volume_db",
		randf_range(cfg.get("volume_db_min", 0.0), cfg.get("volume_db_max", 0.0)))
	var pitch: float = overrides.get("pitch",
		randf_range(cfg.get("pitch_min", 1.0), cfg.get("pitch_max", 1.0)))
	var pan: float = overrides.get("pan",
		randf_range(cfg.get("pan_min", 0.0), cfg.get("pan_max", 0.0)))

	if GameManager and not is_nan(GameManager.sound_fx_volume) and GameManager.sound_fx_volume >= 0.0:
		vol_db += linear_to_db(GameManager.sound_fx_volume)
	if is_nan(vol_db) or is_inf(vol_db):
		vol_db = 0.0

	# AudioStreamPlaybackPolyphonic.play_stream(stream, from_offset, volume_db, pitch_scale, playback_type, bus)
	_sfx_playback.play_stream(stream, 0.0, vol_db, pitch)

	# Stereo panning: AudioStreamPlayer has a `panning_strength` and individual
	# bus sends, but the simplest approach for a non-3D game is a helper node.
	# We schedule a panned one-shot on demand only when pan != 0.
	if not is_zero_approx(pan):
		_play_panned(stream, vol_db, pitch, pan)


## Convenience wrapper: play with explicit left/right world position (–1.0 to 1.0).
func play_sfx_panned(event: SoundEvent, pan: float) -> void:
	play_sfx(event, {"pan": clampf(pan, -1.0, 1.0)})

# ---------------------------------------------------------------------------
# Public — Engine loop
# ---------------------------------------------------------------------------

## Activate the looping engine sound.
func start_engine() -> void:
	if not _streams.has(SoundEvent.ENGINE):
		return
	_engine_active = true
	if not _engine_player.playing:
		_engine_player.play()


## Deactivate the engine loop gracefully.
func stop_engine(fade_out: float = 0.15) -> void:
	_engine_active = false
	if fade_out > 0.0:
		var t := create_tween()
		t.tween_property(_engine_player, "volume_db", -80.0, fade_out)
		t.tween_callback(_engine_player.stop)
	else:
		_engine_player.stop()


## Drive the engine sound from your plane's RPM each frame.
## p_rpm_norm: 0.0 = idle, 1.0 = full throttle
func set_engine_rpm(p_rpm_norm: float) -> void:
	if not _engine_active:
		return
	var t := clampf(p_rpm_norm, 0.0, 1.0)
	_engine_player.pitch_scale = lerpf(ENGINE_PITCH_IDLE, ENGINE_PITCH_FULL, t)
	var base_vol := lerpf(ENGINE_VOLUME_IDLE, ENGINE_VOLUME_FULL, t)
	var sfx_vol := base_vol
	if GameManager and not is_nan(GameManager.sound_fx_volume) and GameManager.sound_fx_volume >= 0.0:
		sfx_vol = base_vol + linear_to_db(GameManager.sound_fx_volume)
	if is_nan(sfx_vol) or is_inf(sfx_vol) or sfx_vol < -80.0:
		sfx_vol = ENGINE_VOLUME_IDLE
	_engine_player.volume_db = sfx_vol


# ---------------------------------------------------------------------------
# Public — Bomb whistle
# ---------------------------------------------------------------------------

## Activate the looping bomb whistle sound.
func start_bomb_whistle() -> void:
	if not _streams.has(SoundEvent.BOMB_WHISTLE):
		return
	_bomb_whistle_active = true
	if not _bomb_whistle_player.playing:
		_bomb_whistle_player.play()


## Deactivate the bomb whistle loop.
func stop_bomb_whistle(fade_out: float = 0.1) -> void:
	_bomb_whistle_active = false
	if fade_out > 0.0:
		var t := create_tween()
		t.tween_property(_bomb_whistle_player, "volume_db", -80.0, fade_out)
		t.tween_callback(_bomb_whistle_player.stop)
	else:
		_bomb_whistle_player.stop()


## Drive the bomb whistle pitch as it falls. p_rpm_norm: 0.0 = high pitch, 1.0 = low pitch.
func set_bomb_whistle_rpm(p_rpm_norm: float) -> void:
	if not _bomb_whistle_active:
		return
	var t := clampf(p_rpm_norm, 0.0, 1.0)
	_bomb_whistle_player.pitch_scale = lerpf(1.5, 0.6, t)
	var sfx_vol := -6.0
	if GameManager and not is_nan(GameManager.sound_fx_volume) and GameManager.sound_fx_volume >= 0.0:
		sfx_vol = -6.0 + linear_to_db(GameManager.sound_fx_volume)
	if is_nan(sfx_vol) or is_inf(sfx_vol) or sfx_vol < -80.0:
		sfx_vol = -6.0
	_bomb_whistle_player.volume_db = sfx_vol

# ---------------------------------------------------------------------------
# Public — Music
# ---------------------------------------------------------------------------

## Play a music track with optional fade in/out crossfade.
## Pass an empty string or null to stop music.
func play_music(path: String, fade_duration: float = 0.1) -> void:
	if _music_fade_tween and _music_fade_tween.is_valid():
		_music_fade_tween.kill()

	var incoming := _inactive_music_player()

	if path == "" or path == null:
		_fade_out_music(_music_active_player, fade_duration)
		return

	var stream := load(path) as AudioStream
	if stream == null:
		push_error("SoundManager: could not load music '%s'" % path)
		return

	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()

	var music_target_vol := 0.0
	if GameManager and not is_nan(GameManager.music_volume) and GameManager.music_volume >= 0.0:
		music_target_vol = linear_to_db(GameManager.music_volume)
	if is_nan(music_target_vol) or is_inf(music_target_vol):
		music_target_vol = 0.0

	_music_fade_tween = create_tween().set_parallel(true)
	_music_fade_tween.tween_property(incoming, "volume_db", music_target_vol, fade_duration)
	_music_fade_tween.tween_property(_music_active_player, "volume_db", -80.0, fade_duration)
	_music_fade_tween.chain().tween_callback(func():
		_music_active_player.stop()
		_music_active_player.volume_db = -80.0
		_music_active_player = incoming
	)


## Pause the current music track with a fade.
func pause_music(fade_duration: float = 0.1) -> void:
	if not _music_active_player.playing:
		return
	_fade_out_music(_music_active_player, fade_duration, true)


## Resume a paused music track with a fade in.
func resume_music(fade_duration: float = 0.1) -> void:
	if _music_active_player.stream == null:
		return
	if not _music_active_player.playing:
		_music_active_player.play(_music_active_player.get_playback_position())
	var t := create_tween()
	t.tween_property(_music_active_player, "volume_db", 0.0, fade_duration)


## Stop music immediately (no fade).
func stop_music() -> void:
	_music_player_a.stop()
	_music_player_b.stop()

## Fade out current music track to silence over `duration` seconds, then stop.
func fade_out_music(duration: float = 0.1) -> void:
	if _music_fade_tween and _music_fade_tween.is_valid():
		_music_fade_tween.kill()
	_fade_out_music(_music_active_player, maxf(duration, 0.0))

# ---------------------------------------------------------------------------
# Public — Global pause / resume
# ---------------------------------------------------------------------------

func pause_all() -> void:
	if _paused:
		return
	_paused = true
	get_tree().paused = true  # pauses the scene tree; AudioStreamPlayer respects this


func resume_all() -> void:
	if not _paused:
		return
	_paused = false
	get_tree().paused = false

# ---------------------------------------------------------------------------
# Volume helpers (bus-level — affects all sounds on that bus)
# ---------------------------------------------------------------------------

func set_sfx_volume(linear: float) -> void:
	_set_bus_volume(&"SFX", linear)
	if GameManager:
		GameManager.sound_fx_volume = linear


func set_music_volume(linear: float) -> void:
	_set_bus_volume(&"Music", linear)
	if GameManager:
		GameManager.music_volume = linear


func set_master_volume(linear: float) -> void:
	_set_bus_volume(&"Master", linear)

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _inactive_music_player() -> AudioStreamPlayer:
	return _music_player_b if _music_active_player == _music_player_a else _music_player_a


func _fade_out_music(player: AudioStreamPlayer, duration: float, and_pause := false) -> void:
	var t := create_tween()
	t.tween_property(player, "volume_db", -80.0, duration)
	if and_pause:
		t.tween_callback(func(): player.stream_paused = true)
	else:
		t.tween_callback(player.stop)


## Spawn a temporary panned player for a single shot.
## The node frees itself via the finished signal.
func _play_panned(stream: AudioStream, vol_db: float, pitch: float, pan: float) -> void:
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = pitch
	# AudioStreamPlayer.panning_strength is 0 (center) to ±1 (full).
	# The property doesn't exist directly; we use AudioServer bus send panning
	# via a per-instance effect, but the simplest Godot-4 approach is a 2D player
	# placed at a world x offset.  For a flat arcade game we just nudge volume_db
	# on left/right ear via the mix target.  A clean zero-node approach:
	# set volume_db slightly and accept that full-stereo requires AudioStreamPlayer2D.
	# For future: replace this node with AudioStreamPlayer2D at (pan * SCREEN_HALF, 0).
	p.volume_db = vol_db + (absf(pan) * -2.0)  # very panned sounds drop slightly
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		push_warning("SoundManager: audio bus '%s' not found." % bus_name)
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 2.0)))
