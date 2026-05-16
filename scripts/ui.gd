extends CanvasLayer

var fuel_label: Label
var ammo_label: Label
var bombs_label: Label
var lives_label: Label
var score_label: Label
var speed_label: Label
var altitude_label: Label

var biplane: CharacterBody2D = null

func _ready() -> void:
	_create_ui_elements()
	if GameManager:
		GameManager.fuel_changed.connect(_on_fuel_changed)
		GameManager.lives_changed.connect(_on_lives_changed)
		GameManager.score_changed.connect(_on_score_changed)
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
	if not biplane:
		biplane = get_parent().get_node_or_null("Biplane")

	if biplane and biplane.has_method("get_speed"):
		var speed := int(biplane.get_speed())
		speed_label.text = "SPEED: %d" % speed

		if biplane.is_stalling():
			var pulse := sin(Time.get_ticks_msec() * 0.015)
			var red := clampf(1.0 - pulse * 0.8, 0.2, 1.0)
			speed_label.modulate = Color(1, red, red)
		else:
			speed_label.modulate = Color(1, 1, 1)

		var ground_y := 650.0
		var alt := int(ground_y - biplane.position.y)
		alt = maxi(0, alt)
		altitude_label.text = "ALT: %d" % alt
	else:
		speed_label.modulate = Color(1, 1, 1)

func _on_fuel_changed(new_fuel: float) -> void:
	fuel_label.text = "FUEL: %.0f%%" % new_fuel
	if new_fuel < 20:
		fuel_label.modulate = Color(1, 0.3, 0.3)
	elif new_fuel < 50:
		fuel_label.modulate = Color(1, 0.8, 0.3)
	else:
		fuel_label.modulate = Color(1, 1, 1)

func _on_lives_changed(new_lives: int) -> void:
	lives_label.text = "LIVES: %d" % new_lives

func _on_score_changed(new_score: int) -> void:
	score_label.text = "SCORE: %d" % new_score

func _update_display() -> void:
	if GameManager:
		fuel_label.text = "FUEL: %.0f%%" % GameManager.fuel
		ammo_label.text = "AMMO: %d" % GameManager.ammo
		bombs_label.text = "BOMBS: %d" % GameManager.bombs
		lives_label.text = "LIVES: %d" % GameManager.lives
		score_label.text = "SCORE: %d" % GameManager.score