extends Node2D

## Draws a WW1 rhomboid tank (hull + tracks + turret) for the Tank node.
## The hull is drawn in the body's local frame (facing +x); the turret is
## drawn rotated by its world bearing relative to the body heading, so the
## "pitch" control axis visibly swings the gun independent of travel.

func _draw() -> void:
	var tank = get_parent()
	if not (tank and tank.has_method("get_avatar_data")):
		return
	var avatar = tank.get_avatar_data(0)
	if not avatar:
		return

	var destroyed: bool = (avatar.flight_state == Biplane.FlightState.CRASHED
			or avatar.flight_state == Biplane.FlightState.FALLING
			or avatar.damage.damage_state == DamageData.DamageState.DESTROYED)

	var body_color := Color(0.20, 0.34, 0.18)
	if avatar.team == Biplane.Team.ENEMY:
		body_color = Color(0.34, 0.22, 0.16)
	if destroyed:
		body_color = body_color.darkened(0.5)

	# Hull (rhomboid) in local space.
	var hull := PackedVector2Array([
		Vector2(30, 0),
		Vector2(18, -16),
		Vector2(-22, -16),
		Vector2(-30, -6),
		Vector2(-30, 6),
		Vector2(-22, 16),
		Vector2(18, 16)
	])
	draw_colored_polygon(hull, body_color)

	# Tracks (slightly inset dark bands top & bottom).
	draw_rect(Rect2(-28, 13, 56, 7), body_color.darkened(0.35))
	draw_rect(Rect2(-28, -20, 56, 7), body_color.darkened(0.35))
	# Track wheels hint.
	for wx in range(-22, 24, 8):
		draw_circle(Vector2(wx, 16), 3, body_color.darkened(0.2))
		draw_circle(Vector2(wx, -16), 3, body_color.darkened(0.2))

	# Turret — rotate the local frame by the turret bearing relative to the
	# body heading so it aims where the AI points it.
	var body_heading: float = avatar.pitch_angle
	var turret_local: float = avatar.turret_angle - body_heading
	draw_set_transform(Vector2.ZERO, turret_local, Vector2.ONE)
	var turret := PackedVector2Array([
		Vector2(14, 0),
		Vector2(6, -10),
		Vector2(-10, -10),
		Vector2(-12, 0),
		Vector2(-10, 10),
		Vector2(6, 10)
	])
	draw_colored_polygon(turret, body_color.lightened(0.12))
	# Barrel.
	draw_rect(Rect2(10, -2, 22, 4), Color(0.08, 0.08, 0.09))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
