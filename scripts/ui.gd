extends CanvasLayer

var fuel_label: Label
var ammo_label: Label
var bombs_label: Label
var spare_planes_label: Label
var score_label: Label
var speed_label: Label
var altitude_label: Label

var avatar: RigidBody2D = null
var display_player_id: int = 0

var enemy_labels: Array[Label] = []

## No stretch mode: the window is laid out in real pixels, so UI positions and
## fonts are scaled relative to the actual window/screen size.

func _design_width() -> float:
	return get_viewport().size.x
func _design_height() -> float:
	return get_viewport().size.y

func _get_vp_size() -> Vector2:
	return get_viewport().size

func _scale_x(x: float) -> float:
	return x * get_viewport().size.x / _design_width()

func _scale_y(y: float) -> float:
	return y * get_viewport().size.y / _design_height()

func _scale_font(size: float) -> int:
	return maxi(8, int(size * get_viewport().size.y / _design_height()))

const AI_STATE_NAMES := {
	0: "GROUNDED",
	1: "TAKING_OFF",
	2: "PATROLLING",
	3: "ENGAGING",
	4: "EVADING",
	5: "RETURNING",
	6: "DESTROYED"
}

const FLIGHT_STATE_NAMES := {
	0: "FLYING",
	1: "STALLED",
	2: "FALLING",
	3: "LANDED",
	4: "DAMAGED",
	5: "CRASHED"
}

const DAMAGE_STATE_NAMES := {
	0: "INTACT",
	1: "LIGHT",
	2: "MODERATE",
	3: "SEVERE",
	4: "DESTROYED"
}

## Recovery sub-mode for enemy pilots in combat. Matches the
## RECOVERY_NONE / RECOVERY_DIVE / RECOVERY_CLIMB constants on EnemyAI
## (see scripts/enemy_ai.gd).  PURSUE is the default — the plane is
## tracking and firing.  RECOVER_DIVE / RECOVER_CLIMB are the energy-
## management break-offs taken when the fight becomes unwinnable.
const RECOVERY_MODE_NAMES := {
	0: "PURSUE",
	1: "RECOVER_DIVE",
	2: "RECOVER_CLIMB",
}

func _ready() -> void:
	_create_ui_elements()
	get_viewport().size_changed.connect(_rebuild_ui)
	if GameManager:
		GameManager.fuel_changed.connect(_on_fuel_changed)
		GameManager.spare_planes_changed.connect(_on_spare_planes_changed)
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
	bombs_label = _create_label("BOMBS: 6", Vector2(x_margin, y_start + line_h * 2))
	spare_planes_label = _create_label("PLANES: 3", Vector2(x_margin, y_start + line_h * 3))
	score_label = _create_label("SCORE: 0", Vector2(x_margin, y_start + line_h * 4))
	speed_label = _create_label("SPEED: 0", Vector2(x_margin, y_start + line_h * 5))
	altitude_label = _create_label("ALT: 0", Vector2(x_margin, y_start + line_h * 6))
	_create_enemy_debug_panel()

func _create_enemy_debug_panel() -> void:
	var vs := _get_vp_size()
	var base_x: float = vs.x - _scale_x(240)
	var line_h := _scale_y(14)
	var block_h := _scale_y(64)

	for i in range(8):
		var base_y: float = _scale_y(20.0) + i * block_h
		for j in range(4):
			var label := Label.new()
			label.name = "EnemyDebug_%d_%d" % [i, j]
			label.text = ""
			label.position = Vector2(base_x, base_y + j * line_h)
			label.add_theme_font_size_override("font_size", _scale_font(13))
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

			var stall_speed_ms: float = avatar_data.model_params.get("stall_speed_ms", 21.4) * Aerodynamics.STALL_SPEED_MARGIN
			var speed_ms: float = speed / avatar.pixels_per_meter
			if speed_ms < stall_speed_ms:
				var pulse := sin(Time.get_ticks_msec() * 0.015)
				var red := clampf(1.0 - pulse * 0.8, 0.2, 1.0)
				speed_label.modulate = Color(1, red, red)
			else:
				speed_label.modulate = Color(1, 1, 1)

			var main_node := get_parent()
			var ground_y := 650.0
			if main_node.has_method("terrain") and main_node.terrain:
				var terrain_node = main_node.terrain
				if terrain_node.has_method("get_ground_height_at"):
					ground_y = terrain_node.get_ground_height_at(avatar.global_position.x)
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
	spare_planes_label = null
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

func _on_spare_planes_changed(player_id: int, new_spare_planes: int) -> void:
	if player_id != display_player_id:
		return
	spare_planes_label.text = "PLANES: %d" % new_spare_planes

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
			spare_planes_label.text = "PLANES: %d" % player_data.spare_planes
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
		var label_idx := idx * 4

		for j in range(4):
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
	var label_idx := idx * 4

	for j in range(4):
		if label_idx + j < enemy_labels.size():
			enemy_labels[label_idx + j].text = ""

	if not avatar:
		avatar = entity.get_avatar_data(0) if entity.has_method("get_avatar_data") else null
	if not avatar:
		return

	var entity_id: String = "P0" if is_player else "E%d" % idx

	var flight_state_text := "---"
	var damage_state_text := "---"

	var entity_ground_y := base_ground_y
	if entity.has_method("_ground_y"):
		entity_ground_y = entity._ground_y(entity.global_position.x)

	var alt := int(entity_ground_y - entity.global_position.y)
	alt = maxi(0, alt)

	var speed_text := "---"
	if entity.has_method("get_avatar_speed") and avatar:
		speed_text = "%d" % int(entity.get_avatar_speed(avatar))
	else:
		var vel: Vector2 = entity.get("velocity") if entity.get("velocity") != null else Vector2.ZERO
		speed_text = "%d" % int(vel.length())

	if "flight_state" in avatar:
		flight_state_text = FLIGHT_STATE_NAMES.get(int(avatar.flight_state), "UNKNOWN")

	if "damage" in avatar and avatar.damage:
		damage_state_text = DAMAGE_STATE_NAMES.get(int(avatar.damage.damage_state), "UNKNOWN")

	# --- Player line: one compact header ---
	if is_player:
		enemy_labels[label_idx].text = "%s: FLT=%s DMG=%s ALT=%d SPD=%s" % [
			entity_id, flight_state_text, damage_state_text, alt, speed_text]
		for j in range(1, 4):
			enemy_labels[label_idx + j].text = ""
		return

	# --- Enemy: 4-line block with AI state, recovery, stats, target ---
	var ai_state_text := "---"
	var recovery_mode_text := ""
	var fuel_text := "---"
	var sr_text := "---"
	var target_name := "---"

	var ai_node: Node = entity.get_node_or_null("EnemyAI") if entity.has_node("EnemyAI") else null
	if ai_node and ai_node.ai_fsm:
		ai_state_text = AI_STATE_NAMES.get(ai_node.ai_fsm.get_ai_state_enum(), "UNKNOWN")
		if ai_node.pilots.size() > 0:
			var rm: int = ai_node.pilots[0].recovery_mode
			if rm != 0:
				recovery_mode_text = RECOVERY_MODE_NAMES.get(rm, "?")
		if ai_node.target:
			target_name = ai_node.target.name

	if "fuel" in avatar:
		fuel_text = "%.0f" % avatar.fuel

	var vel: Vector2 = entity.get("velocity") if entity.get("velocity") != null else Vector2.ZERO
	if vel.length() > 0.0 and "stall_speed_ms" in avatar:
		var ppm: float = entity.pixels_per_meter if "pixels_per_meter" in entity else 13.0
		sr_text = "%.2f" % (vel.length() / ppm / maxf(avatar.stall_speed_ms, 1.0))

	enemy_labels[label_idx].text = "%s: %s %s" % [entity_id, ai_state_text, recovery_mode_text]
	enemy_labels[label_idx + 1].text = "  FLT=%s DMG=%s" % [flight_state_text, damage_state_text]
	enemy_labels[label_idx + 2].text = "  ALT=%d SPD=%s FUEL=%s" % [alt, speed_text, fuel_text]
	enemy_labels[label_idx + 3].text = "  SR=%s TGT=%s" % [sr_text, target_name]
