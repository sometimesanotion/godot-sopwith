extends Node2D

## Dual-purpose draw script for live tanks AND SVG-aware wrecks.
##
## Live mode — parent has get_avatar_data():
##   Hull + independently-tracking turret.  The hull rides the body's local
##   frame (parent rotation 0/PI carries travel direction).  The turret is
##   drawn at its LOCAL bearing (world turret_angle minus body heading) so
##   the "pitch" control axis visibly swings the gun independent of travel.
##
## Wreck mode — no avatar, "wreck_color" meta set:
##   Static darkened wreck.  Two sub-modes:
##     • Tank wreck (no "wreck_svg"): darkened hull + turret SVGs.
##     • Structure wreck ("wreck_svg" set): single darkened SVG fitted to
##       "wreck_rect", with "wreck_points" polygon fallback.

const HULL_SIZE := Vector2(72, 42)
const TURRET_SIZE := Vector2(32, 24)

func _ready() -> void:
	queue_redraw()

func _process(_delta: float) -> void:
	# Live tanks redraw every frame (turret tracks target, damage state
	# changes).  Wrecks are static — _ready's queue_redraw is sufficient.
	var tank = get_parent()
	if tank and tank.has_method("get_avatar_data"):
		queue_redraw()

func _draw() -> void:
	var tank = get_parent()
	var is_live := tank and tank.has_method("get_avatar_data")

	if is_live:
		_draw_live(tank)
	elif has_meta("wreck_color"):
		_draw_wreck()

func _draw_live(tank) -> void:
	var avatar = tank.get_avatar_data(0)
	if not avatar:
		return

	var destroyed: bool = (avatar.flight_state == Biplane.FlightState.CRASHED
			or avatar.flight_state == Biplane.FlightState.FALLING
			or avatar.damage.damage_state == DamageData.DamageState.DESTROYED)

	var body_color := Color(0.3, 0.4, 0.2)
	if avatar.team == Biplane.Team.ENEMY:
		body_color = Color(0.5, 0.3, 0.2)
	if destroyed:
		body_color = body_color.darkened(0.8)

	_draw_hull(body_color)

	# Turret — rotate the local frame by the turret bearing relative to the
	# body heading so it aims where the AI points it.  Centered on the hull
	# so the rotation spins the gun in place instead of orbiting it.
	var body_heading: float = avatar.pitch_angle
	var turret_local: float = avatar.turret_angle - body_heading
	draw_set_transform(Vector2.ZERO, turret_local, Vector2.ONE)
	_draw_turret(body_color.lightened(0.12))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_wreck() -> void:
	var color: Color = get_meta("wreck_color", Color(0.15, 0.15, 0.18))

	# Structure wreck — single darkened SVG fitted to the wreck rect.
	# The live building uses draw_sprite_fit; the wreck does the same with
	# the darkened color as modulate so the artwork's detail survives while
	# the overall tone reads as burned-out.
	if has_meta("wreck_svg"):
		var svg_name: String = get_meta("wreck_svg")
		var rect: Rect2 = get_meta("wreck_rect", Rect2(-40, -60, 80, 120))
		if SvgManager and SvgManager.has_sprite(svg_name):
			SvgManager.draw_sprite_fit(self, svg_name, rect, color)
			return
		# SVG fallback — draw the wreck polygon darkened.
		var points: PackedVector2Array = get_meta("wreck_points", PackedVector2Array())
		if points.size() >= 3:
			draw_colored_polygon(points, color)
		return

	# Tank wreck — darkened hull + turret.
	_draw_hull(color)
	_draw_turret(color.lightened(0.05))

func _draw_hull(body_color: Color) -> void:
	if SvgManager and SvgManager.has_sprite("tank"):
		SvgManager.draw_sprite_centered(self, "tank", Vector2.ZERO, HULL_SIZE, body_color)
		return
	# Fallback: WW1 rhomboid hull in local space.
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
	draw_rect(Rect2(-28, 13, 56, 7), body_color.darkened(0.35))
	draw_rect(Rect2(-28, -20, 56, 7), body_color.darkened(0.35))
	for wx in range(-22, 24, 8):
		draw_circle(Vector2(wx, 16), 3, body_color.darkened(0.2))
		draw_circle(Vector2(wx, -16), 3, body_color.darkened(0.2))

func _draw_turret(turret_color: Color) -> void:
	if SvgManager and SvgManager.has_sprite("turret"):
		SvgManager.draw_sprite_centered(self, "turret", Vector2.ZERO, TURRET_SIZE, turret_color)
		return
	var turret := PackedVector2Array([
		Vector2(14, 0),
		Vector2(6, -10),
		Vector2(-10, -10),
		Vector2(-12, 0),
		Vector2(-10, 10),
		Vector2(6, 10)
	])
	draw_colored_polygon(turret, turret_color)
	draw_rect(Rect2(10, -2, 22, 4), Color(0.08, 0.08, 0.09))
