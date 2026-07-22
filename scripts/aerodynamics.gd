class_name Aerodynamics
## Static-only aerodynamics module. All NASA-derived physics formulas live here.
## Biplane._integrate_forces calls Aerodynamics.calculate_forces() and applies the result.

## ── Input / Output data classes ────────────────────────────────────────────

class FlightInput:
	var velocity: Vector2       = Vector2.ZERO
	var pitch_angle: float      = 0.0
	var throttle: float         = 0.0
	var is_grounded: bool       = false
	var ground_normal: Vector2  = Vector2(0.0, -1.0)
	var on_runway: bool         = false
	var tilt_angle: float       = 0.0
	var global_position_y: float = 0.0
	var ground_y: float         = 650.0
	var is_barrel_rolled: bool       = false
	var engine_cutoff: bool    = false
	var mass_kg: float         = 422.0
	var model_params: Dictionary = {}
	var damage_drag_mult: float = 1.0
	var damage_thrust_mult: float = 1.0
	var stall_speed_ms: float  = 21.4
	var pixels_per_meter: float = 10.0
	var air_density: float     = 2.94
	var gravity: float         = 9.81
	var arcade_multiplier: float = 2.4
	var bungee_time: float     = 0.15
	var is_destroyed: bool     = false

class FlightOutput:
	var net_force: Vector2        = Vector2.ZERO
	var control_effectiveness: float = 1.0
	var is_stalled: bool          = false
	var weight_force: Vector2    = Vector2.ZERO
	var thrust_force: Vector2    = Vector2.ZERO
	var lift_force: Vector2      = Vector2.ZERO
	var drag_force: Vector2      = Vector2.ZERO
	var normal_force: Vector2    = Vector2.ZERO
	var friction_force: Vector2  = Vector2.ZERO
	var v_perp: float            = 0.0
	var impact_force: float      = 0.0
	var should_crash: bool       = false
	var crash_reason: String     = ""
	var ground_clamp_y: float    = -1.0
	var ground_velocity_cancel: Vector2 = Vector2.ZERO

## ── Friction coefficient constants (forward-declared for clarity) ──────────

const FRICTION_RUNWAY_ROLLING: float  = 0.03
const FRICTION_RUNWAY_BRAKING: float  = 2.00
const FRICTION_TERRAIN_ROLLING: float  = 0.07
const FRICTION_TERRAIN_BRAKING: float = 0.80
const THROTTLE_STEP: float            = 0.15

const ENGINE_EFFICIENCY_START_ALTITUDE: float = 1800.0
const ENGINE_CUTOFF_ALTITUDE: float            = 2000.0

## ── Stall-detection tuning ──────────────────────────────────────────────────
## The arcade_multiplier (2.3×) scales both thrust and air density, cancelling
## out for parasitic-drag top-speed equilibrium (the Camel still tops out at
## ~50.4 m/s ≈ 655 px/s, matching its historical 185 km/h).  Lift, however,
## enjoys the full 2.3× boost, so the physics can sustain flight down to ~10 m/s
## — well below the model's nominal 21.4 m/s stall.  The raw model stall speed
## therefore triggers far too eagerly: the HUD flashes and the flight state flips
## to STALLED during ordinary flight, and a transient high AoA while turning at
## speed wrongly drops lift.  These margins adapt stall detection to the
## playable envelope instead of the unrealistic physics-only value.
const STALL_SPEED_MARGIN       := 0.8   # speed-stall fires below stall × 0.8
const STALL_AOA_SPEED_MARGIN   := 1.2   # AoA stall only counts near/below stall speed

## ── Main calculation ──────────────────────────────────────────────────────

static func calculate_forces(inp: FlightInput) -> FlightOutput:
	var out := FlightOutput.new()
	if inp.is_destroyed:
		_calculate_crash_forces(inp, out)
		return out

	var forward := Vector2(cos(inp.pitch_angle), sin(inp.pitch_angle))
	var right   := Vector2(forward.y, -forward.x)
	var vel_si  := inp.velocity / inp.pixels_per_meter
	var speed_si := vel_si.length()

	out.weight_force = Vector2(0.0, inp.mass_kg * inp.gravity)

	out.thrust_force = forward * _calc_thrust(inp, speed_si, inp.ground_y)

	var aoa: float = 0.0
	if speed_si > 0.5:
		aoa = forward.angle_to(vel_si.normalized())

	var stall_aoa: float = deg_to_rad(inp.model_params.get("max_aoa", 16.0))
	# Stall detection — speed-aware so the plane isn't flagged stalled while it
	# clearly has forward momentum:
	#   • flying below the (margin-reduced) stall speed, OR
	#   • a transient high AoA (nose leading the velocity vector mid-turn) — but
	#     only near/below stall speed.  At higher speeds a high AoA just means
	#     extra drag, not a fall; flagging it drops lift to 30 % and turns a
	#     normal engagement turn into a mushy, sinking spiral.
	var speed_stall: bool = speed_si < inp.stall_speed_ms * STALL_SPEED_MARGIN
	var aoa_stall: bool = absf(aoa) > stall_aoa and speed_si < inp.stall_speed_ms * STALL_AOA_SPEED_MARGIN
	out.is_stalled = (not inp.is_grounded) and (speed_stall or aoa_stall)

	# Ground vehicles (wing_area == 0.0, e.g. tanks) generate no
	# lift — they are held on the terrain entirely by gravity + the ground
	# clamp, so skipping lift here is what keeps them from flying off.
	var max_cl: float = inp.model_params.get("max_lift_coeff", 1.4)
	var cl: float = clampf(aoa * 2.0 * PI, -max_cl, max_cl)
	if out.is_stalled:
		cl *= 0.3

	var altitude: float = maxf(0.0, inp.ground_y - inp.global_position_y)
	var density_factor: float = exp(-altitude / 2500.0)
	var rho: float = inp.air_density * density_factor
	var wing_area: float = inp.model_params.get("wing_area", 21.46)

	if wing_area > 0.0 and speed_si > 0.5:
		var lift_si: float = 0.5 * rho * speed_si * speed_si * wing_area * cl
		out.lift_force = right * lift_si

	var zero_lift_drag_area: float = inp.model_params.get("zero_lift_drag_area", 0.811)
	var ar_efficiency: float = inp.model_params.get("ar_efficiency", 11.0)

	var para_drag: float = 0.5 * rho * speed_si * speed_si * zero_lift_drag_area
	var induced_drag: float = 0.5 * rho * speed_si * speed_si * wing_area * (cl * cl) / ar_efficiency

	var eff_max_speed_ms: float = inp.model_params.get("max_speed_ms", 300.0)
	var speed_px: float = inp.velocity.length()
	# Unit-correct speed cap: compare in SI (m/s), NOT px/s, against the model's
	# physical top speed.  The old code compared the px/s velocity directly to
	# eff_max_speed_ms (m/s), so the limiter engaged at ~50 px/s (~1.3× stall)
	# instead of at the real ceiling — max_speed_ms × pixels_per_meter ≈ 810 px/s
	# for the Camel (~2.4× stall).  Computed in N (SI) so it adds directly to
	# para/induced drag with no pixels_per_meter conversion.
	var speed_si_lim: float = speed_px / inp.pixels_per_meter
	var speed_lim_drag: float = 0.0
	if speed_si_lim > eff_max_speed_ms:
		var over_ms: float = speed_si_lim - eff_max_speed_ms
		speed_lim_drag = 0.5 * over_ms * over_ms

	var total_drag: float = (para_drag + induced_drag + speed_lim_drag) * inp.damage_drag_mult
	if speed_si > 0.01:
		out.drag_force = -vel_si.normalized() * total_drag

	if inp.is_grounded:
		out.v_perp = maxf(0.0, -inp.velocity.dot(inp.ground_normal))
		out.impact_force = inp.mass_kg * (out.v_perp / inp.pixels_per_meter) / inp.bungee_time

		var net_aero := out.weight_force + out.thrust_force + out.lift_force + out.drag_force
		var into_gnd := -net_aero.dot(inp.ground_normal)
		if into_gnd > 0.0:
			out.normal_force = inp.ground_normal * into_gnd

		if speed_si > 0.01:
			var mu := _friction_coeff(inp.on_runway, inp.throttle)
			out.friction_force = -vel_si.normalized() * (maxf(0.0, into_gnd) * mu * 2.0)

	out.net_force = out.weight_force + out.thrust_force + out.lift_force + out.drag_force + out.normal_force + out.friction_force

	var sp_si := inp.velocity.length() / inp.pixels_per_meter
	# Control authority scales with dynamic pressure (speed²).  The divisor must
	# match the game's real envelope: it tops out near ~2.4× stall speed, so a
	# divisor of ~5 (not 50) lets authority climb from the 0.6 floor at stall to
	# full/boosted at cruise instead of being pinned at the minimum everywhere.
	out.control_effectiveness = clampf(
		(sp_si * sp_si) / (inp.stall_speed_ms * inp.stall_speed_ms * 5.0), 0.6, 1.8)

	return out

## ── Crash / destroyed physics ─────────────────────────────────────────────

static func _calculate_crash_forces(inp: FlightInput, out: FlightOutput) -> void:
	out.weight_force = Vector2(0.0, inp.mass_kg * inp.gravity / inp.pixels_per_meter)
	out.net_force = out.weight_force
	out.control_effectiveness = 0.0

## ── Thrust (static) ────────────────────────────────────────────────────────

static func _calc_thrust(inp: FlightInput, speed_si: float, ground_y: float) -> float:
	if inp.engine_cutoff:
		return 0.0

	var altitude := ground_y - inp.global_position_y
	var alt_eff := 1.0
	if altitude > ENGINE_EFFICIENCY_START_ALTITUDE:
		alt_eff = 1.0 - clampf(
			(altitude - ENGINE_EFFICIENCY_START_ALTITUDE) /
			(ENGINE_CUTOFF_ALTITUDE - ENGINE_EFFICIENCY_START_ALTITUDE),
			0.0, 1.0)

	var thr := inp.throttle * inp.damage_thrust_mult
	var engine_power: float = inp.model_params.get("engine_power_watts", 96941.0)

	if speed_si < 0.5:
		return 2000.0 * thr * alt_eff

	var eta := maxf(0.0, 0.8 * (1.0 - pow((speed_si - 40.0) / 40.0, 2)))
	return engine_power * eta / speed_si * thr * alt_eff * inp.arcade_multiplier

## ── Ground friction lookup ──────────────────────────────────────────────────

static func _friction_coeff(on_runway: bool, throttle: float) -> float:
	if on_runway:
		return FRICTION_RUNWAY_ROLLING if throttle >= THROTTLE_STEP else FRICTION_RUNWAY_BRAKING
	return FRICTION_TERRAIN_ROLLING if throttle >= THROTTLE_STEP else FRICTION_TERRAIN_BRAKING

## ── Stall check (standalone) ───────────────────────────────────────────────

static func is_stalled(pitch_angle: float, velocity: Vector2, is_grounded: bool,
		stall_speed_ms: float, pixels_per_meter: float, model_params: Dictionary) -> bool:
		if is_grounded:
			return false
		var vel_si := velocity / pixels_per_meter
		var speed_si := vel_si.length()
		if speed_si <= 0.5:
			return true
		var forward := Vector2(cos(pitch_angle), sin(pitch_angle))
		var aoa := forward.angle_to(vel_si.normalized())
		var stall_aoa: float = deg_to_rad(model_params.get("max_aoa", 16.0))
		var speed_stall: bool = speed_si < stall_speed_ms * STALL_SPEED_MARGIN
		var aoa_stall: bool = absf(aoa) > stall_aoa and speed_si < stall_speed_ms * STALL_AOA_SPEED_MARGIN
		return speed_stall or aoa_stall

## ── Control effectiveness (standalone) ──────────────────────────────────────

static func calculate_control_effectiveness(velocity: Vector2, stall_speed_ms: float,
		pixels_per_meter: float) -> float:
	var sp_si := velocity.length() / pixels_per_meter
	return clampf((sp_si * sp_si) / (stall_speed_ms * stall_speed_ms * 5.0), 0.6, 1.8)

## ── Landing impact classification ──────────────────────────────────────────

enum LandingImpact {
	CLEAN,
	HARD,
	CRASH
}

static func classify_landing_impact(v_perp: float, tilt_angle: float,
		max_landing_tilt_deg: float, soft_threshold: float, hard_threshold: float) -> int:
	if tilt_angle >= deg_to_rad(max_landing_tilt_deg):
		return LandingImpact.CRASH
	if v_perp <= soft_threshold:
		return LandingImpact.CLEAN
	if v_perp <= hard_threshold:
		return LandingImpact.HARD
	return LandingImpact.CRASH
