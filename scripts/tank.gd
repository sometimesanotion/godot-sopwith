extends Biplane
class_name Tank

## WW1-style ground-attack tank.
##
## Reuses the Biplane physics/avatar/weapon core but is a *ground* vehicle:
##   * `AvatarData` model_params leaves `wing_area == 0.0`, so Aerodynamics
##     generates no lift and the body stays earth-bound (gravity + terrain
##     clamp hold it down).  Aerodynamic capability is derived from wing_area
##     via `AvatarData.is_aerodynamic()`.
##   * The "pitch" control axis is repurposed to rotate a turret
##     (`AvatarData.turret_angle`, a world-space bearing).
##   * The "roll" control axis flips travel direction
##     (`AvatarData.travel_dir`: +1 = right, -1 = left) — exactly the control
##     mapping the AI uses, so a tank is driven with the same channels as a plane.

const TANK_BULLET_SPEED      := 800.0
const TANK_BULLET_DAMAGE     := 20.0
const TANK_BULLET_RANGE      := 600.0
const TANK_GUN_COOLDOWN      := 0.12
const TANK_DAMAGE_REDUCTION  := 8.0   ## points subtracted from every hit

## Set by the (ground-mode) EnemyAI each frame: does the turret want to fire?
var ai_fire_request: bool = false

func _ready() -> void:
	super._ready()

	var av := get_avatar_data(0)
	av.turret_angle = 0.0
	av.travel_dir = 1.0
	av.ammo = 99999
	av.bombs = 0
	av.unlimited_fuel_ammo = true

	# Tank "model" — heavy, low-powered, ground-bound.  wing_area == 0.0 makes
	# is_aerodynamic() false, so Aerodynamics skips lift; only mass / thrust /
	# drag / friction matter.
	var params := {
		"name": "Tank (Mk V)",
		"mass_kg": 1200.0,
		"engine_power_watts": 34000.0,
		"wing_area": 0.0,
		"zero_lift_drag_area": 1.4,
		"ar_efficiency": 2.0,
		"max_lift_coeff": 0.0,
		"max_aoa": 16.0,
		"max_speed_ms": 72.0,
		"stall_speed_ms": 21.4,
		"rotation_speed": 1.0,
		"negative_rotation_speed": 1.0,
		"rotation_inertia": 4.0,
		"bullet_spawn_offset": Vector2(20, 0),
		"bomb_spawn_offset": Vector2(0, 0),
		"max_bombs": 0,
		"visual_scale": Vector2.ONE,
		"bungee_time": 0.15,
		"max_landing_tilt_deg": 80.0,
		"soft_landing_vperp": 180.0,
		"hard_landing_vperp": 300.0,
		"svg_sprite_name": "",
		"color": Color(0.2, 0.35, 0.2)
	}
	av.model_params = params
	av.stall_speed_ms = params.get("stall_speed_ms", 21.4)
	av.max_landing_tilt = deg_to_rad(params.get("max_landing_tilt_deg", 80.0))
	av.soft_landing = params.get("soft_landing_vperp", 80.0)
	av.hard_landing = params.get("hard_landing_vperp", 200.0)
	av.bungee_time = params.get("bungee_time", 0.15)
	av.mass_kg = params.get("mass_kg", 1200.0)
	av.bullet_spawn_offset = params.get("bullet_spawn_offset", Vector2(20, 0))
	av.bomb_spawn_offset = params.get("bomb_spawn_offset", Vector2.ZERO)
	av.max_bullet_range = TANK_BULLET_RANGE
	av.damage.reset()
	av.flight_state = FlightState.FLYING

	# RigidBody tuning for a slow, stable crawler.
	mass = av.mass_kg
	gravity_scale = 0.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = CCD_MODE_CAST_SHAPE
	angular_damp = 6.0
	linear_damp = 0.0

	if has_node("Visual"):
		$Visual.set_script(load("res://scripts/tank_draw.gd"))
	reset_visual_transform(av)

## Visual reset is a no-op for the tank: the body heading is driven by
## `travel_dir` / `pitch_angle` and the turret by `turret_angle`; the rhomboid
## drawer reads those directly, so there is nothing to flip on the Visual node.
func reset_visual_transform(_avatar: AvatarData = null) -> void:
	var av := get_avatar_data(0)
	if av and has_node("GroundRay"):
		_update_ground_ray(av)

## Fired by the (ground-mode) EnemyAI.  The turret pulls the trigger whenever
## the AI reports a target in range and aligned.
func _handle_weapons(avatar: AvatarData, delta: float) -> void:
	avatar.gun_timer = maxf(0.0, avatar.gun_timer - delta)
	if ai_fire_request and avatar.gun_timer <= 0.0:
		fire_tank_gun(avatar)

func fire_tank_gun(avatar: AvatarData) -> void:
	if avatar.ammo <= 0:
		return
	avatar.gun_timer = TANK_GUN_COOLDOWN
	avatar.ammo -= 1

	var dir := Vector2(cos(avatar.turret_angle), sin(avatar.turret_angle))
	var muzzle := global_position + dir * 24.0

	var bullet = BULLET_SCENE.instantiate()
	bullet.speed = TANK_BULLET_SPEED
	bullet.damage = TANK_BULLET_DAMAGE
	bullet.global_position = muzzle
	bullet.rotation = avatar.turret_angle
	bullet.assign_owner(self, clampf(TANK_BULLET_RANGE / maxf(1.0, avatar.max_bullet_range), 0.0, 1.0))
	get_parent().add_child(bullet)
	fired_bullet.emit(muzzle, dir, TANK_BULLET_SPEED, self, 0.5)
	if SoundManager:
		SoundManager.play_sfx(SoundManager.SoundEvent.GUN)

## Tanks take 18 fewer points of damage from any source (weapons or
## collisions) — both routes funnel through this override.
func take_damage(avatar_or_amount, amount_or_attacker = null, _attacker = null) -> void:
	var avatar: AvatarData
	var amount: float
	if avatar_or_amount is AvatarData:
		avatar = avatar_or_amount
		amount = float(amount_or_attacker)
	else:
		avatar = get_avatar_data(0)
		amount = float(avatar_or_amount)
		_attacker = amount_or_attacker
	amount = maxf(0.0, amount - TANK_DAMAGE_REDUCTION)
	super.take_damage(avatar, amount, _attacker)
	# A tank is already on the ground, so a destructive hit should crash it
	# immediately rather than leaving it stuck spinning in FALLING (the
	# aircraft path waits for a mid-air wreck to reach the terrain first).
	if avatar.damage.damage_state == DamageData.DamageState.DESTROYED \
			and avatar.flight_state == FlightState.FALLING:
		_on_avatar_crashed(avatar)

## Drop the tank from the targeting/minimap bookkeeping the instant it is
## destroyed, so a wreck no longer counts as a live enemy target (which would
## otherwise block the win check).  Leaves a burned-out hull with smoke.
func _on_avatar_crashed(avatar: AvatarData) -> void:
	super._on_avatar_crashed(avatar)
	if is_in_group("enemy_target"):
		remove_from_group("enemy_target")
	if is_in_group("tank"):
		remove_from_group("tank")
	_create_tank_wreck()

## Create a persistent smoking wreck at the tank's position.
func _create_tank_wreck() -> void:
	var wreck := StaticBody2D.new()
	wreck.position = global_position
	wreck.add_to_group("wreck")

	var hull := get_plane_polygon()
	var wrecked_points := PackedVector2Array()
	for pt in hull:
		wrecked_points.append(pt + Vector2(randf_range(-2, 2), randf_range(-2, 2)))
	var collision_poly := CollisionPolygon2D.new()
	collision_poly.polygon = wrecked_points
	wreck.add_child(collision_poly)

	var hull_color := Color(0.12, 0.20, 0.10)
	var av := get_avatar_data(0)
	if av and av.team == Biplane.Team.ENEMY:
		hull_color = Color(0.20, 0.13, 0.09)
	var wreck_draw := Node2D.new()
	wreck_draw.set_script(preload("res://scripts/wreck_draw.gd"))
	wreck_draw.set_meta("wreck_color", hull_color)
	wreck_draw.set_meta("wreck_points", wrecked_points)
	wreck.add_child(wreck_draw)

	if EffectManager:
		EffectManager.spawn_open_fire_with_smoke(wreck.position, 8.0, 15, 25)

	get_parent().call_deferred("add_child", wreck)
	queue_free()

## AI entry point: ground-mode EnemyAI calls this instead of set_ai_input.
func set_tank_fire(v: bool) -> void:
	ai_fire_request = v

## Rhomboid outline used for crash debris (matches the drawn hull).
func get_plane_polygon() -> PackedVector2Array:
	var s := Vector2.ONE
	return PackedVector2Array([
		Vector2(30 * s.x, 0),
		Vector2(18 * s.x, -16 * s.y),
		Vector2(-22 * s.x, -16 * s.y),
		Vector2(-30 * s.x, -6 * s.y),
		Vector2(-30 * s.x, 6 * s.y),
		Vector2(-22 * s.x, 16 * s.y),
		Vector2(18 * s.x, 16 * s.y)
	])
