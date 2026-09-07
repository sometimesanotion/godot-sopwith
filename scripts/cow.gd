extends RigidBody2D
class_name Cow

const COW_KILLER_PENALTY := 50
const ANGER_DURATION_MS := 600

var _svg_sprite_name: String = "cow"
var _svg_size: Vector2 = Vector2(72, 84)
var _health: float = 20.0
var _max_health: float = 20.0
var _last_hit_time: int = -ANGER_DURATION_MS * 2
var _anger_level: int = 0
var _physics_impact_velocity_threshold: float = 120.0
var _physics_impact_cooldown_ms: int = 250
var _last_physics_impact_time: int = -_physics_impact_cooldown_ms * 2

func _ready() -> void:
	z_index = 1
	mass = 200.0 + randf() * 80.0
	gravity_scale = 0.0
	contact_monitor = true
	max_contacts_reported = 8
	add_to_group("obstacle")
	add_to_group("destructible")
	add_to_group("cow")
	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	queue_redraw()
	set_process(true)
	body_entered.connect(_on_physics_body_entered)

func _process(_delta: float) -> void:
	var elapsed = Time.get_ticks_msec() - _last_hit_time
	if elapsed < ANGER_DURATION_MS or _anger_level > 0:
		queue_redraw()

func _draw() -> void:
	if SvgManager and SvgManager.has_sprite(_svg_sprite_name):
		SvgManager.draw_sprite_centered(self, _svg_sprite_name, Vector2(0, -14), _svg_size)
	else:
		_draw_fallback()

	var elapsed = Time.get_ticks_msec() - _last_hit_time
	if elapsed < ANGER_DURATION_MS:
		var alpha := 1.0 - float(elapsed) / float(ANGER_DURATION_MS)
		var shake := sin(Time.get_ticks_msec() * 0.02) * 2.0 * minf(_anger_level + 1, 3)
		for i in range(minf(_anger_level + 1, 3)):
			var sx := -6.0 + i * 6.0 + shake
			var sy := -34.0 - i * 2.0
			draw_line(
				Vector2(sx - 3, sy + 4 + shake), Vector2(sx + 3, sy + 4 + shake),
				Color(1.0, 0.3, 0.1, alpha), 2
			)
			draw_line(
				Vector2(sx - 3, sy - 2 + shake), Vector2(sx + 3, sy - 2 + shake),
				Color(1.0, 0.3, 0.1, alpha), 2
			)
	elif _anger_level > 0:
		_anger_level = 0

func _on_physics_body_entered(body: Node) -> void:
	## Handle physical collisions from bullets and destroyed (crashed) plane
	## wreck bodies that tumble into us.  The analytical collision check
	## (_check_obstacle_collision) covers live planes only; this covers
	## everything else that hits us through the physics engine.
	## Bullets already apply their own damage via take_damage(), so skip them.
	if body and body.get_meta("bullet", false):
		return
	if body.has_method("get_primary_entity"):
		var av = body.get_primary_entity()
		if av:
			## Live aerodynamic planes are already handled by the analytical
			## _check_obstacle_collision path, so skip them here to avoid
			## double damage.  Destroyed/falling planes are NOT handled there
			## (the CRASHED state skips that check), so let them damage us.
			if av.is_aerodynamic() and av.flight_state != Biplane.FlightState.CRASHED:
				return
			## Non-aerodynamic ground vehicles (tanks) roll through obstacles
			## by design — they engage buildings with weapons, not mass.
			if not av.is_aerodynamic():
				return
	var now := Time.get_ticks_msec()
	if now - _last_physics_impact_time < _physics_impact_cooldown_ms:
		return
	if body == null or not is_instance_valid(body):
		return
	# Don't damage ourselves from passive contact with static terrain/ground.
	if body is StaticBody2D or body.is_in_group("ground"):
		return
	var impact_speed: float = 0.0
	if body is RigidBody2D:
		impact_speed = body.linear_velocity.length()
	elif body is CharacterBody2D:
		impact_speed = body.velocity.length()
	if impact_speed < _physics_impact_velocity_threshold:
		return
	_last_physics_impact_time = now
	var dmg := clampf(impact_speed / 428.0, 0.25, 0.5) * 100.0
	take_damage(dmg * 0.5, body)

func _draw_fallback() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-15, 0), Vector2(-15, -20), Vector2(-10, -28),
		Vector2(10, -28), Vector2(15, -20), Vector2(15, 0)
	]), Color(0.9, 0.9, 0.9))
	draw_rect(Rect2(-12, -18, 8, 8), Color(0.1, 0.1, 0.1))
	draw_circle(Vector2(12, -22), 4, Color(0.1, 0.1, 0.1))
	draw_line(Vector2(-8, -28), Vector2(-10, -32), Color(0.3, 0.3, 0.3), 2)
	draw_line(Vector2(0, -28), Vector2(0, -33), Color(0.3, 0.3, 0.3), 2)
	draw_line(Vector2(8, -28), Vector2(10, -32), Color(0.3, 0.3, 0.3), 2)
	draw_circle(Vector2(10, -8), 3, Color(0.2, 0.2, 0.2))

func take_damage(amount: float, attacker: Node = null) -> void:
	_health -= amount
	_last_hit_time = Time.get_ticks_msec()
	_anger_level = mini(_anger_level + 1, 5)
	if _health <= 0.0:
		_do_destroy(attacker)

func _do_destroy(attacker: Node = null) -> void:
	if attacker and attacker.has_method("is_player_plane"):
		if GameManager:
			GameManager.add_score(0, -COW_KILLER_PENALTY)
	# Spawn a wreck (fallen cow) and keep it
	var wreck := Node2D.new()
	wreck.name = "CowWreck"
	wreck.position = global_position
	wreck.rotation = randf_range(-0.3, 0.3)
	wreck.z_index = -1
	wreck.add_to_group("wreck")
	var draw_script := load("res://scripts/cow_wreck_draw.gd")
	var draw_node := Node2D.new()
	draw_node.set_script(draw_script)
	draw_node.set_meta("wreck_color", Color(0.7, 0.7, 0.7))
	wreck.add_child(draw_node)
	get_parent().call_deferred("add_child", wreck)
	queue_free()

func get_visual_top() -> float:
	return global_position.y - 14.0 - 42.0

class CowCollisionResult:
	var hit: bool = false
	var damage: float = 0.0
	var is_midair: bool = false
	var impact_speed: float = 0.0

func get_collision_response(other: Node, _other_avatar: Variant, other_speed: float,
		_plane_soft_landing: float = 100.0, _plane_hard_landing: float = 200.0) -> CowCollisionResult:
	var result := CowCollisionResult.new()
	var hit_radius: float = 40.0
	var dist := global_position.distance_to(other.global_position)
	result.impact_speed = other_speed
	if dist < hit_radius and other_speed > 10.0:
		result.hit = true
		result.damage = clampf(other_speed / 428.0, 0.25, 0.5)
		result.is_midair = true
	return result
