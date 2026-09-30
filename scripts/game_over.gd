extends CanvasLayer

signal restart_game

var _header_bg: ColorRect
var _cp_bg: ColorRect
var _title_label: Label
var _score_label: Label
var _info_label: Label
var _bip_sprite: Node2D
var _sop_sprite: Node2D
var _last_known_size := Vector2(-1, -1)

func _design_size() -> Vector2:
	return get_viewport().size

func _ready() -> void:
	get_viewport().size_changed.connect(_rebuild_all)
	if GraphicsSettings:
		GraphicsSettings.settings_changed.connect(_rebuild_all)

func _rebuild_all() -> void:
	var vs := _design_size()
	if vs == _last_known_size:
		return
	_last_known_size = vs
	_update_layout_from_scratch()

func _update_layout_from_scratch() -> void:
	_clear_all()

	var vs := _design_size()
	var hh: float = vs.y * 0.12
	var cp_height: float = min(vs.y - hh - 40, vs.y * 0.6)
	var cp_y: float = hh + (vs.y - hh - cp_height) * 0.5

	_header_bg = ColorRect.new()
	_header_bg.name = "HeaderBg"
	_header_bg.color = Color(0.0, 0.0, 0.0, 0.55)
	_header_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_header_bg.position = Vector2.ZERO
	_header_bg.size = Vector2(vs.x, hh)
	add_child(_header_bg)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = "GAME OVER"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", maxi(16, int(hh * 0.35)))
	_title_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_title_label.add_theme_constant_override("outline_size", 3)
	_title_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_title_label.position = Vector2.ZERO
	_title_label.size = Vector2(vs.x, hh)
	add_child(_title_label)

	var svg_h: float = hh * 0.40
	var bip_path := "res://assets/svg/biplane.svg"
	var sop_path := "res://assets/svg/sopwith.svg"

	if ResourceLoader.exists(bip_path):
		var tex: Texture2D = load(bip_path)
		var asp: float = float(tex.get_width()) / float(max(tex.get_height(), 1))
		var sw: float = svg_h * asp
		_bip_sprite = Node2D.new()
		_bip_sprite.name = "BiplaneNode"
		_bip_sprite.position = Vector2(20.0 + sw * 0.5, hh * 0.5)
		add_child(_bip_sprite)
		var sp := Sprite2D.new()
		sp.texture = tex
		var sc: float = svg_h / max(tex.get_height(), 1)
		sp.scale = Vector2(sc, sc)
		_bip_sprite.add_child(sp)

	if ResourceLoader.exists(sop_path):
		var tex: Texture2D = load(sop_path)
		var asp: float = float(tex.get_width()) / float(max(tex.get_height(), 1))
		var sw: float = svg_h * asp
		_sop_sprite = Node2D.new()
		_sop_sprite.name = "SopwithNode"
		_sop_sprite.position = Vector2(vs.x - 20.0 - sw * 0.5, hh * 0.5)
		add_child(_sop_sprite)
		var sp := Sprite2D.new()
		sp.texture = tex
		var sc: float = svg_h / max(tex.get_height(), 1)
		sp.scale = Vector2(sc, sc)
		sp.flip_h = true
		_sop_sprite.add_child(sp)

	_cp_bg = ColorRect.new()
	_cp_bg.name = "ControlBg"
	_cp_bg.color = Color(0.0, 0.0, 0.0, 0.80)
	_cp_bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cp_bg.position = Vector2(0, cp_y)
	_cp_bg.size = Vector2(vs.x, cp_height)
	add_child(_cp_bg)

	var score_text: String = "Score: 0"
	if GameManager:
		var pd = GameManager.get_player_data(0)
		score_text = "Score: %d" % pd.score

	_score_label = Label.new()
	_score_label.name = "ScoreLabel"
	_score_label.text = score_text
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", maxi(14, int(cp_height * 0.10)))
	_score_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	_score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_score_label.add_theme_constant_override("outline_size", 2)
	_score_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_score_label.position = Vector2(0, cp_y + cp_height * 0.20)
	_score_label.size = Vector2(vs.x, cp_height * 0.25)
	add_child(_score_label)

	_info_label = Label.new()
	_info_label.name = "InfoLabel"
	_info_label.text = "Press ENTER or FIRE to Quit"
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_label.add_theme_font_size_override("font_size", maxi(10, int(cp_height * 0.04)))
	_info_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_info_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_info_label.position = Vector2(vs.x * 0.06, cp_y + cp_height * 0.50)
	_info_label.size = Vector2(vs.x * 0.88, cp_height * 0.30)
	add_child(_info_label)

func _clear_all() -> void:
	for c in get_children():
		c.queue_free()
	_header_bg = null
	_cp_bg = null
	_title_label = null
	_score_label = null
	_info_label = null
	_bip_sprite = null
	_sop_sprite = null

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var ke := event as InputEventKey
	if not ke.pressed or ke.is_echo():
		return
	port = get_viewport()
	match ke.keycode:
		KEY_ENTER, KEY_SPACE:
			restart_game.emit()
			if port:
				port.set_input_as_handled()
			queue_free()
			return
	if port:
		port.set_input_as_handled()

func _process(_delta: float) -> void:
	if _last_known_size == Vector2(-1, -1):
		_rebuild_all()
