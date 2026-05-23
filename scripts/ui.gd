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

var enemy_labels: Array[Label] = []

## With canvas_items stretch mode, Godot scales the canvas to the window.
## All UI is laid out at the design resolution from project settings.
## get_viewport().size returns the window size, so we read from ProjectSettings.

func _get_vp_size() -> Vector2:
	return Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1720),
		ProjectSettings.get_setting("display/window/size/viewport_height", 720)
	)

func _scale_x(x: float) -> float:
	return x

func _scale_y(y: float) -> float:
	return y

func _scale_font(size: float) -> int:
	return maxi(8, int(size))

const AI_STATE_NAMES := {
	0: "GROUNDED",
	1: "TAKING_OFF",
	2: "PATROLLING",
	3: "ENGAGING",
	4: "EVADING",
	5: "RETURNING"
}

const FLIGHT_STATE_NAMES := {
	0: "FLYING",
	1: "STALLED",
	2: "FALLING",
	3: "DAMAGED",
	4: "LANDED",
	5: "CRASHED"
}

const DAMAGE_STATE_NAMES := {
	0: "INTACT",
	1: "LIGHT",
	2: "MODERATE",
	3: "SEVERE",
	4: "DESTROYED"
}

func _ready() -> void:
	_create_ui_elements()
	get_viewport().size_changed.connect(_rebuild_ui)
	if GameManager:
		GameManager.fuel_changed.connect(_on_fuel_changed)
		GameManager.lives_changed.connect(_on_lives_changed)
		GameManager.score_changed.connect(_on_score_changed)
		GameManager.ammo_changed.connect(_on_ammo_changed)
		GameManager.bombs_changed.connect(_on_bombs_changed)
		_update_display()

func _create_ui_elements() -> void:
	var x_margin := _scale_x(20)
	var y_start := _scale_y(20)
	var line_h := _scale_y(30)
	fuel_label = _create_label("FUEL: 100%", Vector2(x_margin, y_start))
	ammo_label = _create_label("AMMO: 100", Vector2(x_margin, y_start + line_h))
	bombs_label = _create_label("BOMBS: 5", Vector2(x_margin, y_start + line_h * 2))
	lives_label = _create_label("LIVES: 5", Vector2(x_margin, y_start + line_h * 3))
	score_label = _create_label("SCORE: 0", Vector2(x_margin, y_start + line_h * 4))
	speed_label = _create_label("SPEED: 0", Vector2(x_margin, y_start + line_h * 5))
	altitude_label = _create_label("ALT: 0", Vector2(x_margin, y_start + line_h * 6))
	_create_enemy_debug_panel()

func _create_enemy_debug_panel() -> void:
	var vs := _get_vp_size()
	var base_x: float = vs.x - _scale_x(220)
	var line_h := _scale_y(14)
	var block_h := _scale_y(56)

	for i in range(8):
		var base_y: float = _scale_y(20.0) + i * block_h
		for j in range(3):
			var label := Label.new()
			label.name = "EnemyDebug_%d_%d" % [i, j]
			label.text = ""
			label.position = Vector2(base_x, base_y + j * line_h)
			label.add_theme_font_size_override("font_size", _scale_font(14))
			label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
			label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
			label.add_theme_constant_override("outline_size", 2)
			add_child(label)
			enemy_labels.append(label)

func _create_label(text: String, pos: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", _scale_font(18))
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

	var main_node := get_parent()
	var show_debug := GameManager and GameManager.debug_hud if GameManager else false

	for label in enemy_labels:
		label.visible = show_debug

	if show_debug:
		_update_enemy_debug_panel(main_node)

func _rebuild_ui() -> void:
	for c in get_children():
		c.queue_free()
	fuel_label = null
	ammo_label = null
	bombs_label = null
	lives_label = null
	score_label = null
	speed_label = null
	altitude_label = null
	enemy_labels.clear()
	_create_ui_elements()
	_update_display()

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

func _update_enemy_debug_panel(main_node: Node) -> void:
	if not main_node:
		return

	var ground_y := 650.0
	if main_node.has_method("terrain") and main_node.terrain:
		var terrain_node = main_node.terrain
		if terrain_node.has_method("get_ground_height_at"):
			ground_y = terrain_node.get_ground_height_at(avatar.global_position.x)

	_update_debug_entry(0, avatar, ground_y, true)

	var enemies: Array = []
	var enemies_prop = main_node.get("enemies")
	if enemies_prop is Array:
		enemies = enemies_prop
	var idx := 1
	for enemy in enemies:
		if idx >= 8:
			break
		var label_idx := idx * 3

		for j in range(3):
			if label_idx + j < enemy_labels.size():
				enemy_labels[label_idx + j].text = ""

		if not enemy or not is_instance_valid(enemy):
			idx += 1
			continue

		if not enemy.has_method("get_avatar_data"):
			idx += 1
			continue

		var av = enemy.get_avatar_data(0)
		if not av:
			idx += 1
			continue

		_update_debug_entry(idx, enemy, ground_y, false, av)
		idx += 1

func _update_debug_entry(idx: int, entity: Node, base_ground_y: float, is_player: bool, avatar = null) -> void:
	var label_idx := idx * 3

	for j in range(3):
		if label_idx + j < enemy_labels.size():
			enemy_labels[label_idx + j].text = ""

	if not avatar:
		avatar = entity.get_avatar_data(0) if entity.has_method("get_avatar_data") else null
	if not avatar:
		return

	var entity_id: String = "P0" if is_player else "E%d" % idx
	var ai_state_text := "---"
	var flight_state_text := "---"
	var damage_state_text := "---"
	var alt_text := "---"
	var speed_text := "---"

	var entity_ground_y := base_ground_y
	if entity.has_method("_ground_y"):
		entity_ground_y = entity._ground_y(entity.global_position.x)

	var alt := int(entity_ground_y - entity.global_position.y)
	alt = maxi(0, alt)
	alt_text = "%d" % alt

	if entity.has_method("get_avatar_speed") and avatar:
		var speed := int(entity.get_avatar_speed(avatar))
		speed_text = "%d" % speed
	else:
		var vel: Vector2 = entity.get("velocity") if entity.get("velocity") != null else Vector2.ZERO
		speed_text = "%d" % int(vel.length())

	if not is_player:
		var ai_node: Node = entity.get_node_or_null("EnemyAI") if entity.has_node("EnemyAI") else null
		if ai_node and "ai_state" in ai_node:
			var state_val: int = int(ai_node.ai_state)
			ai_state_text = AI_STATE_NAMES.get(state_val, "UNKNOWN")

	if "flight_state" in avatar:
		var state_val: int = int(avatar.flight_state)
		flight_state_text = FLIGHT_STATE_NAMES.get(state_val, "UNKNOWN")

	if "damage_state" in avatar:
		var state_val: int = int(avatar.damage_state)
		damage_state_text = DAMAGE_STATE_NAMES.get(state_val, "UNKNOWN")

	enemy_labels[label_idx].text = "%s: AI=%s FST=%s" % [entity_id, ai_state_text, flight_state_text]
	enemy_labels[label_idx + 1].text = "    DST=%s ALT=%s" % [damage_state_text, alt_text]
	enemy_labels[label_idx + 2].text = "    SPD=%s" % speed_text
