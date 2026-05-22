extends CanvasLayer

var fuel_label: Label
var ammo_label: Label
var bombs_label: Label
var lives_label: Label
var score_label: Label
var speed_label: Label
var altitude_label: Label

var avatar: CharacterBody2D = null
var display_player_id: int = 0

func _ready() -> void:
	_create_ui_elements()
	if GameManager:
		GameManager.fuel_changed.connect(_on_fuel_changed)
		GameManager.lives_changed.connect(_on_lives_changed)
		GameManager.score_changed.connect(_on_score_changed)
		GameManager.ammo_changed.connect(_on_ammo_changed)
		GameManager.bombs_changed.connect(_on_bombs_changed)
		_update_display()

func _create_ui_elements() -> void:
	fuel_label = _create_label("FUEL: 100%", Vector2(20, 20))
	ammo_label = _create_label("AMMO: 100", Vector2(20, 50))
	bombs_label = _create_label("BOMBS: 5", Vector2(20, 80))
	lives_label = _create_label("LIVES: 5", Vector2(20, 110))
	score_label = _create_label("SCORE: 0", Vector2(20, 140))
	speed_label = _create_label("SPEED: 0", Vector2(20, 170))
	altitude_label = _create_label("ALT: 0", Vector2(20, 200))

func _create_label(text: String, pos: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	add_child(label)
	return label

func _process(_delta: float) -> void:
	if not avatar:
		avatar = get_parent().get_node_or_null("Biplane")

	if avatar and avatar.has_method("get_avatar_data"):
		var avatar_data = avatar.get_avatar_data(0)
		if avatar_data and avatar.has_method("get_avatar_speed"):
			var speed := int(avatar.get_avatar_speed(avatar_data))
			speed_label.text = "SPEED: %d" % speed

			var stall_speed_ms: float = avatar_data.model_params.get("stall_speed_ms", 21.4)
			var speed_ms: float = speed / avatar.pixels_per_meter
			if speed_ms < stall_speed_ms:
				var pulse := sin(Time.get_ticks_msec() * 0.015)
				var red := clampf(1.0 - pulse * 0.8, 0.2, 1.0)
				speed_label.modulate = Color(1, red, red)
			else:
				speed_label.modulate = Color(1, 1, 1)

			var ground_y := 650.0
			var alt := int(ground_y - avatar.position.y)
			alt = maxi(0, alt)
			altitude_label.text = "ALT: %d" % alt
	else:
		speed_label.modulate = Color(1, 1, 1)

func _on_fuel_changed(player_id: int, new_fuel: float) -> void:
	if player_id != display_player_id:
		return
	fuel_label.text = "FUEL: %.0f%%" % new_fuel
	if new_fuel < 20:
		fuel_label.modulate = Color(1, 0.3, 0.3)
	elif new_fuel < 50:
		fuel_label.modulate = Color(1, 0.8, 0.3)
	else:
		fuel_label.modulate = Color(1, 1, 1)

func _on_lives_changed(player_id: int, new_lives: int) -> void:
	if player_id != display_player_id:
		return
	lives_label.text = "LIVES: %d" % new_lives

func _on_score_changed(new_score: int) -> void:
	score_label.text = "SCORE: %d" % new_score

func _on_ammo_changed(player_id: int, new_ammo: int) -> void:
	if player_id != display_player_id:
		return
	ammo_label.text = "AMMO: %d" % new_ammo
	if new_ammo < 20:
		ammo_label.modulate = Color(1, 0.3, 0.3)
	else:
		ammo_label.modulate = Color(1, 1, 1)

func _on_bombs_changed(player_id: int, new_bombs: int) -> void:
	if player_id != display_player_id:
		return
	bombs_label.text = "BOMBS: %d" % new_bombs
	if new_bombs == 0:
		bombs_label.modulate = Color(1, 0.3, 0.3)
	else:
		bombs_label.modulate = Color(1, 1, 1)

func _update_display() -> void:
	if GameManager:
		var player_data := GameManager.get_player_data(display_player_id)
		var avatar := Biplane.get_avatar(display_player_id)
		if avatar:
			fuel_label.text = "FUEL: %.0f%%" % avatar.fuel
			ammo_label.text = "AMMO: %d" % avatar.ammo
			bombs_label.text = "BOMBS: %d" % avatar.bombs
		if player_data:
			lives_label.text = "LIVES: %d" % player_data.lives
		score_label.text = "SCORE: %d" % GameManager.get_player_data(display_player_id).score

func set_display_player(player_id: int) -> void:
	display_player_id = player_id
	_update_display()