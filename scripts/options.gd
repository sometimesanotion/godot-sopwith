extends CanvasLayer

signal back_to_menu

var thrust_slider: HSlider
var thrust_value_label: Label

func _ready() -> void:
	_create_ui()

func _create_ui() -> void:
	var bg := ColorRect.new()
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.color = Color(0.1, 0.1, 0.15, 0.95)
	add_child(bg)

	var title := Label.new()
	title.text = "Options"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.position = Vector2(540, 50)
	add_child(title)

	var thrust_label := Label.new()
	thrust_label.text = "Thrust Multiplier:"
	thrust_label.position = Vector2(400, 150)
	add_child(thrust_label)

	thrust_slider = HSlider.new()
	thrust_slider.min_value = 1.0
	thrust_slider.max_value = 5.0
	thrust_slider.step = 0.5
	thrust_slider.value = GameManager.thrust_multiplier if GameManager else 3.0
	thrust_slider.position = Vector2(400, 180)
	thrust_slider.custom_minimum_size = Vector2(200, 30)
	thrust_slider.value_changed.connect(_on_thrust_changed)
	add_child(thrust_slider)

	thrust_value_label = Label.new()
	thrust_value_label.text = "%.1fx" % thrust_slider.value
	thrust_value_label.position = Vector2(620, 180)
	add_child(thrust_value_label)

	var hint := Label.new()
	hint.text = "1.0 = Realistic | 3.0 = Default | 5.0 = Arcade"
	hint.position = Vector2(400, 220)
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(hint)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.position = Vector2(540, 350)
	back_btn.pressed.connect(_on_back)
	add_child(back_btn)

func _on_thrust_changed(value: float) -> void:
	thrust_value_label.text = "%.1fx" % value
	if GameManager:
		GameManager.set_thrust_multiplier(value)

func _on_back() -> void:
	back_to_menu.emit()
	queue_free()