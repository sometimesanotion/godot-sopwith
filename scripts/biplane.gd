## biplane.gd
## Sopwith Camel — unified aerodynamics controller with multi-model support.
##
## DESIGN PHILOSOPHY
##
## One class, one physics loop, zero abstraction layers.
##
## Flight state is the single authoritative representation that controls all
## behaviours. It is an enum (`Biplane.FlightState`) held on AvatarData and is
## written only through `AvatarData.set_flight_state()`, which no-ops on no-change
## and emits `flight_state_changed(from, to)` on real transitions. There is NO
## flight node-FSM — physics-driven transitions are detected in
## `_update_flight_state()`, and event-driven ones (damage, refuel-repair, crash)
## call the setter directly. Every per-entity value lives in AvatarData; the node
## itself is the view layer.
## The physics loop uses Aerodynamics.calculate_forces() to compute all forces
## in one pass every frame — via _integrate_forces() which delegates to the
## static Aerodynamics module.
## weight, thrust, lift, drag, ground normal, and ground friction — then
## integrates once. There are no separate physics regimes or edge cases.
##
## This design applies equally to planes, vehicles, and buildings via the
## same force-sum path; ground vehicles simply have no aerodynamic components.
##
## MULTI-MODEL SUPPORT
##
## • British faction: Sopwith Camels (assets/svg/sopwith.svg)
## • German faction: Fokker D.VII (assets/svg/biplane.svg)
## • Model-specific physics parameters (mass, power, wing area, etc.)
## • Dynamic model switching with visual updates
## • Ground vehicle support via wing_area == 0.0 (no lift)
##
## DEBUGGING FEATURES
##
## • Real-time debug overlay showing flight state, model, damage
## • Velocity and thrust vector visualization
## • Ground contact indicator
## • Entity creation utilities for testing
##
## Sopwith Camel baseline: 659 kg MTOW, 130 hp rotary, 21.46 m² wing area.
## Arcade feel: gravity multiplier and tuned propeller curve.

class_name Biplane
extends RigidBody2D

###############################################################################
# PLANE MODEL CONFIGURATION
###############################################################################

## Available plane models with their specifications
static var _PLANE_MODELS: Dictionary = {
	"sopwith_camel": {
		"name": "Sopwith Camel",
		"mass_kg": 422.0,
		"engine_power_watts": 96941.0,
		"wing_area": 21.46,
		"zero_lift_drag_area": 0.811,     # Loftin NASA SP-468: CD0=0.0378, drag area = 0.811 m²
		"ar_efficiency": 11.0,            # π × AR × e = π × 4.11 × 0.85 ≈ 10.97
		"max_lift_coeff": 1.4,            # Cambered biplane, standard WW1 value
		"max_aoa": 16.0,                  # ~16° stall AoA for thin biplane wing
		"max_speed_ms": 50.6,
		"stall_speed_ms": 21.4,
		"rotation_speed": 5.0,            # Baseline: notoriously fast pitch response
		"negative_rotation_speed": 3.2,   # Rotary engine gyroscope strongly biases against pitch-down
		"rotation_inertia": 4.0,
		"bullet_spawn_offset": Vector2(50, -5),
		"bomb_spawn_offset": Vector2(0, 32),
		"max_bombs": 6,
		"visual_scale": Vector2.ONE,
		"bungee_time": 0.15,
		"max_landing_tilt_deg": 34.0,
		"soft_landing_vperp": 40.0,
		"hard_landing_vperp": 80.0,
		"svg_sprite_name": "sopwith_camel",
		"color": Color(0.3, 0.80, 0.06)
	},
	"se5a": {
		"name": "S.E.5a",
		"mass_kg": 880.0,                # 902kg MTOW; ~880kg at typical combat fuel load
		"engine_power_watts": 149140.0,  # 200hp Wolseley Viper (licensed Hispano-Suiza 8a) × 745.7
		"wing_area": 22.67,              # 444 ft², confirmed: upper 11.8m² + lower 11.0m² + ailerons
		"zero_lift_drag_area": 0.771,    # CD0≈0.034 × 22.67m²; cleaner cowl than Camel (no exposed cylinders)
		"ar_efficiency": 15.1,           # π × AR × e = π × 5.79 × 0.83; AR = span/chord = 8.11/1.40
		"max_lift_coeff": 1.4,           # Standard cambered biplane, same as Camel
		"max_aoa": 16.0,                 # Thin biplane wing; more forgiving stall behavior than Camel
		"max_speed_ms": 53.6,            # 193 km/h at altitude; sea-level combat speed
		"stall_speed_ms": 21.1,          # Calculated from wing loading; comparable to Camel
		"rotation_speed": 3.8,           # Agile but not twitchy; designed for stability over dogfighting
		"negative_rotation_speed": 2.6,  # No rotary gyroscope bias; conventional inline V8
		"rotation_inertia": 4.0,
		"bullet_spawn_offset": Vector2(50, -5),
		"bomb_spawn_offset": Vector2(0, 32),
		"max_bombs": 4,
		"visual_scale": Vector2.ONE,
		"bungee_time": 0.15,
		"max_landing_tilt_deg": 34.0,
		"soft_landing_vperp": 40.0,
		"hard_landing_vperp": 80.0,
		"svg_sprite_name": "se5a",
		"color": Color(0.42, 0.38, 0.22)
	},
	"bristol_f2": {
		"name": "Bristol F.2B",
		"mass_kg": 973.0,
		"engine_power_watts": 205000.0,
		"wing_area": 37.6,
		"zero_lift_drag_area": 1.58,      # CD0≈0.042 (large two-seater, more struts/bracing) × 37.6m²
		"ar_efficiency": 9.3,             # π × AR × e = π × 3.80 × 0.78 ≈ 9.32; AR=11.96²/37.6
		"max_lift_coeff": 1.35,           # Heavier two-seater, slightly lower peak CL
		"max_aoa": 15.0,                  # Standard biplane thin wing, ~15°
		"max_speed_ms": 55.0,
		"stall_speed_ms": 22.0,
		"rotation_speed": 3.5,            # Heavy two-seater, notably less agile than Camel
		"negative_rotation_speed": 2.3,   # Heavier tail, slow pitch-down response
		"rotation_inertia": 8.0,
		"bullet_spawn_offset": Vector2(50, -5),
		"bomb_spawn_offset": Vector2(0, 32),
		"max_bombs": 3,
		"visual_scale": Vector2.ONE,
		"bungee_time": 0.15,
		"max_landing_tilt_deg": 34.0,
		"soft_landing_vperp": 40.0,
		"hard_landing_vperp": 80.0,
		"svg_sprite_name": "bristol_f2b",
		"color": Color(0.50, 0.42, 0.28)
	},
	"p-51d": {
		"name": "P-51D Mustang",
		"mass_kg": 3463.0,
		"engine_power_watts": 1280000.0,
		"wing_area": 21.8,
		"zero_lift_drag_area": 0.353,     # Loftin NASA SP-468: CD0=0.0161, drag area = 0.353 m²
		"ar_efficiency": 16.0,            # π × AR × e = π × 5.84 × 0.87 ≈ 15.95; AR=11.28²/21.8
		"max_lift_coeff": 1.55,           # Laminar flow wing with combat flaps; higher than WW1 biplanes
		"max_aoa": 16.0,                  # Laminar flow wing stalls cleanly around 15-17°
		"max_speed_ms": 197.2,
		"stall_speed_ms": 44.4,
		"rotation_speed": 3.2,            # Heavy fighter, good but not twitchy; roll-rate limited at speed
		"negative_rotation_speed": 2.2,   # Conventional design, slower pitch-down vs pitch-up
		"rotation_inertia": 4.0,
		"bullet_spawn_offset": Vector2(50, -5),
		"bomb_spawn_offset": Vector2(0, 32),
		"max_bombs": 6,
		"visual_scale": Vector2.ONE,
		"bungee_time": 0.15,
		"max_landing_tilt_deg": 34.0,
		"soft_landing_vperp": 40.0,
		"hard_landing_vperp": 80.0,
		"svg_sprite_name": "p-51",
		"color": Color(0.65, 0.63, 0.55)
	},
	"spad_s13": {
		"name": "SPAD S.XIII",
		"mass_kg": 602.0,
		"engine_power_watts": 161800.0,
		"wing_area": 21.11,
		"zero_lift_drag_area": 0.718,     # CD0≈0.034 (Loftin: "relatively low" for WW1) × 21.11m²
		"ar_efficiency": 7.5,             # π × AR × e = π × 3.05 × 0.78 ≈ 7.47; AR=8.02²/21.11
		"max_lift_coeff": 1.3,            # Thin wing, notoriously poor at low speed, tricky to land
		"max_aoa": 14.0,                  # Thin biplane wing, abrupt stall; SPAD was feared for this
		"max_speed_ms": 60.56,
		"stall_speed_ms": 23.3,
		"rotation_speed": 3.8,            # Stiffer controls than Camel; less agile in pitch
		"negative_rotation_speed": 2.6,   # Standard non-rotary inline engine behavior
		"rotation_inertia": 4.0,
		"bullet_spawn_offset": Vector2(50, -5),
		"bomb_spawn_offset": Vector2(0, 32),
		"max_bombs": 6,
		"visual_scale": Vector2.ONE,
		"bungee_time": 0.15,
		"max_landing_tilt_deg": 34.0,
		"soft_landing_vperp": 40.0,
		"hard_landing_vperp": 80.0,
		"svg_sprite_name": "spad_s13",
		"color": Color(0.33, 0.46, 0.05)
	},
	"fokker_d7": {
		"name": "Fokker D.VII",
		"mass_kg": 670.0,
		"engine_power_watts": 119000.0,
		"wing_area": 20.5,
		"zero_lift_drag_area": 0.759,     # CD0≈0.037 × 20.5m²; clean fuselage but strut-braced biplane
		"ar_efficiency": 9.7,             # π × AR × e = π × 3.86 × 0.80 ≈ 9.70; AR=8.9²/20.5
		"max_lift_coeff": 1.55,           # Thick Göttingen airfoil; hallmark high-AoA lift retention
		"max_aoa": 20.0,                  # Famous for hanging on its prop at extreme AoA without spinning
		"max_speed_ms": 52.5,
		"stall_speed_ms": 15.3,
		"rotation_speed": 4.2,            # Agile, but not as hair-trigger as the Camel
		"negative_rotation_speed": 2.8,   # Good but asymmetric pitch authority, as typical
		"rotation_inertia": 5.0,
		"bullet_spawn_offset": Vector2(50, -5),
		"bomb_spawn_offset": Vector2(0, 32),
		"max_bombs": 0,
		"visual_scale": Vector2(1.1, 1.1),
		"bungee_time": 0.15,
		"max_landing_tilt_deg": 34.0,
		"soft_landing_vperp": 40.0,
		"hard_landing_vperp": 80.0,
		"svg_sprite_name": "fokker_d7",
		"color": Color(0.60, 0.20, 0.20)
	}
}

static func get_plane_models() -> Dictionary:
	return _PLANE_MODELS

static func _get_svg_path_from_params(model_params: Dictionary) -> String:
	var sprite_name = model_params.get("svg_sprite_name", "sopwith_camel")
	return "res://assets/svg/" + sprite_name + ".svg"

###############################################################################
# EXPORTS
###############################################################################

@export_group("Scale & Arcade Tuning")
@export var pixels_per_meter: float = 13.0

@export_group("Flight Parameters (SI Units)")
@export var arcade_multiplier: float = 2.3
@export var gravity:            float = 9.81

@export_group("Aerodynamics")
@export var air_density:         float = 1.225 * arcade_multiplier
@export var stall_aoa:           float = deg_to_rad(16.0)

@export_group("Throttle")
@export var min_throttle: float = 0.0
@export var max_throttle: float = 1.0

@export_group("Weapons")
@export var gun_cooldown:  float = 0.07
@export var bomb_cooldown: float = 0.3
@export var bullet_speed:  float = 1600.0

@export_group("Control")
@export var is_player_controlled: bool = false

func is_player_plane() -> bool:
	return is_player_controlled

func is_enemy_plane() -> bool:
	return not is_player_controlled

###############################################################################
# MODEL-SPECIFIC CONSTANTS (no longer hardcoded)
##############################################################################

## Distance from plane origin to ground surface when at rest.
## Must equal the collision capsule radius so the capsule sits on the terrain
## without overlap, preventing the physics solver from pushing the body upward.
const GROUND_SURFACE_OFFSET := 0.0

## Grounded detection tolerance (px). Absorbs one-frame integration overshoot.
const GROUND_TOLERANCE := 2.0

## Generous terrain-proximity margin (px) used to decide a wreck is "near the
## ground" for respawn — covers upright, tilted, tumbled, and building-top rests.
## Set to ~2× the tallest building height (fuel depot ≈ 150 px) so a wreck
## resting on any structure registers as near-enough to the terrain surface.
const GROUND_REST_MARGIN := 300.0

## A destroyed plane's wreck must be at rest (speed below this, px/s) on the
## ground before its 2s respawn timer starts — avoids scheduling the respawn
## while the wreck is still skidding/rolling.
const RESPAWN_GROUND_SPEED := 20.0

## A destroyed plane's wreck must also have stopped spinning (rad/s) before its
## 2s respawn timer starts — a wreck still tumbling on the ground is not "at
## rest", so it should keep tumbling until it settles.
const RESPAWN_ANGULAR_REST_SPEED := 0.6

const THROTTLE_REPEAT_DELAY := 0.1
const THROTTLE_RAMP_SPEED   := 5.0

const MAX_AMMO  := 250	# 500 rounds, twin guns

const FLIP_DURATION   := 0.35
const FLIP_ARC_HEIGHT := 15.0

## Altitude at which engine efficiency begins to taper off.
const ENGINE_EFFICIENCY_START_ALTITUDE := 1800.0
## Altitude at which the engine cuts out entirely.
const ENGINE_CUTOFF_ALTITUDE           := 2000.0

## Ground friction coefficients — now in Aerodynamics static module.
## Kept here as reference; actual values used are in aerodynamics.gd.

## World wrap length in pixels.
const TERRAIN_LENGTH := 16384.0

## Total speed (px/s) below which a grounded plane is considered LANDED (at
## rest / taxiing) rather than still flying.  A plane skimming the terrain at
## speed during a low pass or fast rollout is genuinely airborne, so it must
## keep FlightState.FLYING — otherwise it gets stuck in LANDED while clearly
## flying (and the AI then keeps it ENGAGING instead of treating it as landed).
const LANDING_TAXI_SPEED := 120.0

## Angular velocity (rad/s) applied to a wreck while in the FALLING spin-out
## state (set by force_crash / heavy damage before it reaches the ground and
## becomes CRASHED). Single source — replaced the duplicated 1.0 in
## falling_state.gd (deleted) and the 1.22 literal in _integrate_forces.
const FALLING_SPIN_RATE := 1.2

const BULLET_SCENE := preload("res://scenes/bullet.tscn")
const BOMB_SCENE   := preload("res://scenes/bomb.tscn")

###############################################################################
# ENUMERATIONS
###############################################################################

## Primary FSM. All behaviour branches key off this value.
## Numeric values are stable — external code must use named references.
enum FlightState {
	FLYING  = 0,   ## Airborne and under aerodynamic control
	STALLED = 1,   ## Airborne but below stall speed / excess AoA
	FALLING = 2,   ## Spinning out of control; set by force_crash / heavy damage
	LANDED  = 3,   ## On the ground, stationary or taxiing
	DAMAGED = 4,   ## Crashed but not destroyed; partial damage
	CRASHED = 5    ## Destroyed; post-crash tumble physics only
}

## Faction for team/hostility checks.
enum Faction { BRITISH = 0, GERMAN = 1, FRENCH = 2, USA = 3, NEUTRAL = 4 }
enum Team    { ALLIED  = 0, ENEMY  = 1, NEUTRAL = 2 }

###############################################################################
# HOMEBASE DATA
###############################################################################

class HomebaseData:
	var id:               int     = 0
	var home_base_x:      float   = 6554.0
	var home_base_width:  float   = 1000.0
	var spawn_position:   Vector2 = Vector2(7000, 500)
	var spawn_rotation:    float   = 0.0
	var team:             Team    = Team.ALLIED
	var faction:          Faction = Faction.BRITISH

var _homebases: Dictionary[int, HomebaseData] = {}

###############################################################################
# AVATAR DATA
## One flat data object per entity. Carries all per-entity simulation state.
## There are no sub-components; fields are grouped by comment blocks.
## The physics loop reads and writes these fields directly.
###############################################################################

class AvatarData:
	## Single source of truth for flight state. Emitted on every real transition
	## (the same SSOT pattern used by DamageData.damage_state_changed). After M2
	## there is no node-FSM mirroring this field, so this signal is the only
	## outward notification of flight-state changes.
	signal flight_state_changed(from: int, to: int)

	# Identity
	var id:           int     = 0
	var faction:      Faction = Faction.BRITISH
	var team:         Team    = Team.ALLIED
	var homebase_id:  int     = 0
	var unlimited_fuel_ammo: bool = false
	var bombs_disabled:      bool = false

	# Plane Model
	var plane_model: String  = "sopwith_camel"  # Key from _PLANE_MODELS
	var model_params: Dictionary = {}  # Cached model-specific parameters
	func is_hostile_to(other: AvatarData) -> bool:
		if team == Team.NEUTRAL or other.team == Team.NEUTRAL:
			return false
		return team != other.team

	func get_model_param(param: String, default = null):
		return model_params.get(param, default)

	func update_model_params() -> void:
		var model_data = Biplane.get_plane_models().get(plane_model)
		if model_data:
			model_params = model_data
		else:
			push_error("Unknown plane model: %s" % plane_model)
			var plane_models = Biplane.get_plane_models()
			model_params = plane_models["sopwith_camel"]

		stall_speed_ms = model_params.get("stall_speed_ms", 21.4)
		max_landing_tilt = model_params.get("max_landing_tilt_deg", 34.0)
		soft_landing = model_params.get("soft_landing_vperp", 10.0)
		hard_landing = model_params.get("hard_landing_vperp", 20.0)

	func get_plane_name() -> String:
		return model_params.get("name", "Unknown")

	# Flight state (FSM)
	var flight_state: FlightState = FlightState.FLYING
	var stall_speed_ms: float        = 21.4

	## Single writable entry for `flight_state`. Idempotent: returns false and
	## does nothing when the value is unchanged; assigns, emits
	## `flight_state_changed`, and returns true otherwise. All transitions must
	## funnel through this so there is exactly one representation of flight state.
	func set_flight_state(new_state: FlightState) -> bool:
		if flight_state == new_state:
			return false
		var from: int = flight_state
		flight_state = new_state
		flight_state_changed.emit(from, int(new_state))
		return true

	# Damage
	var damage:          DamageData  = DamageData.new()
	var reliability:     float       = 1.0
	var refuel_timer:    float       = 0.0
	var refuel_cooldown: float       = 0.0
	## Throttle for sub-catastrophic impact damage (see _apply_impact): the
	## tick of the last applied hit, so sustained grinding cannot melt a
	## plane at 60 applications per second.  Catastrophic hits bypass it.
	var last_impact_ms:  int         = 0
	## Cached physics modifiers; recomputed by _refresh_damage_modifiers().
	var drag_multiplier:   float = 1.0
	var thrust_multiplier: float = 1.0

	# Kinematics
	var pitch_angle:         float = 0.0
	var angular_velocity:    float = 0.0
	var control_effectiveness: float = 1.0
	var is_airborne:         bool  = true
	## Last authoritatively set velocity (px/s): what the flight model (or
	## crash ballistics) commanded, BEFORE the solver mangles it into walls.
	## Impact severity reads intent, not solver output — a body pressed into
	## a wall reports ~0 solver velocity while still flying into it at full
	## command, so contact/closing math must use this.
	var commanded_vel:       Vector2 = Vector2.ZERO

	# Ground-vehicle support (tanks).  When the model has wing_area == 0.0,
	# Aerodynamics skips lift so the body stays earth-bound; the "pitch" control
	# axis is repurposed to aim a turret and the "roll" axis flips travel
	# direction.  Aerodynamic capability is derived from wing_area, not a flag.
	func is_aerodynamic() -> bool:
		return model_params.get("wing_area", 0.0) > 0.0
	## World-space turret bearing (rad). Driven by the AI/player "pitch"
	## channel for ground vehicles; unused by aircraft.
	var turret_angle:        float = 0.0
	## Travel heading for ground vehicles: +1.0 = rightward, -1.0 = leftward.
	var travel_dir:          float = 1.0

	# Throttle & engine
	var throttle:               float = 0.0
	var throttle_target:        float = 0.0
	var throttle_repeat_timer:  float = 0.0
	var engine_cutoff:          bool  = false
	var engine_restart_hold_time:     float = 0.0
	var engine_restart_required_time: float = 0.0
	var sputtering_timer:              float = 0.0

	# Flip / roll
	var is_barrel_rolled:    bool  = false
	var is_flipping:    bool  = false
	var flip_progress:  float = 0.0
	var flip_direction: int   = 0   ## 1 = upright→inverted, -1 = inverted→upright
	## True while a GROUNDED direction-reversal is animating: the physical
	## handover (velocity, heading, is_barrel_rolled) then fires atomically at
	## the tween midpoint instead of the airborne flag-only toggle.
	var flip_is_ground_reversal: bool = false
	## One-shot guard so the midpoint handover runs exactly once per tween.
	var flip_halfway_applied: bool = false

	## ── Attitude frame helpers ───────────────────────────────────────────
	## One small API hides every is_barrel_rolled / left-vs-right branch.
	## The GRAVITY FRAME measures pitch against the horizon: 0 = level,
	## positive = nose-down toward the ground, negative = nose-up toward the
	## sky — IDENTICAL for a level plane flying leftward inverted and one
	## flying rightward upright.  Pitch commands share that convention
	## (negative = climb, positive = dive — the same one the AI takeoff
	## outputs use), so behaviour code never re-checks is_barrel_rolled; the
	## single conversion back into the rotation frame happens in
	## pitch_command_to_rotation_input().

	## +1.0 when the nose points rightward, -1.0 when leftward (inverted).
	func travel_sign() -> float:
		return -1.0 if is_barrel_rolled else 1.0

	## World rotation (rad) of perfectly level flight along the travel direction.
	func level_rotation() -> float:
		return PI if is_barrel_rolled else 0.0

	## Current pitch relative to gravity: 0 = level, positive = nose down,
	## negative = nose up — same reading for the same attitude in either
	## travel direction.
	func gravity_pitch() -> float:
		return travel_sign() * wrapf(pitch_angle - level_rotation(), -PI, PI)

	## Pitch rate in the gravity frame (positive = rotating toward the ground).
	func gravity_pitch_rate() -> float:
		return travel_sign() * angular_velocity

	## Convert a world-space heading angle (Vector2.angle() convention) into
	## the gravity frame so it can be compared with gravity_pitch()
	## regardless of travel direction.
	func gravity_angle(heading: float) -> float:
		return travel_sign() * wrapf(heading - level_rotation(), -PI, PI)

	## Inverse of gravity_angle(): gravity-relative pitch → world heading angle.
	func world_angle(gravity_pitch_angle: float) -> float:
		return level_rotation() + travel_sign() * gravity_pitch_angle

	## Convert a gravity-frame pitch command (negative = climb, positive =
	## dive) into the rotation-frame control input.  THE one place the
	## is_barrel_rolled sign flip happens: AI and player code always command
	## in the gravity frame; only the integrator consumes this.
	func pitch_command_to_rotation_input(pitch_cmd: float) -> float:
		return travel_sign() * pitch_cmd

	## True when a world rotation aims the nose leftward — the canonical
	## derivation of is_barrel_rolled from a spawn/teleport rotation.
	static func rotation_is_leftward(rot: float) -> bool:
		return absf(wrapf(rot, -PI, PI)) > PI / 2.0

	# Control flags
	var has_hit_ground:    bool = false
	var crash_processed:    bool = false

	# Weapons
	var ammo:             int   = MAX_AMMO
	var bombs:            int   = 0
	var fuel:             float = 100.0
	var gun_timer:        float = 0.0
	var bomb_timer:       float = 0.0
	var max_bullet_range: float = 1000.0
	var last_shot_range:  float = 0.0

	# View-layer damage-FX handle (managed via EffectManager.sync_damage_fx).
	# One node covers every state: white smoke (LIGHT), black smoke
	# (MODERATE), wreck fire (SEVERE/DESTROYED — identical to a fresh tank
	# wreck).  Null when INTACT.
	var damage_fx: Node2D = null

	var max_landing_tilt: float = model_params.get("max_landing_tilt_deg", 34.0)
	var soft_landing: float = model_params.get("soft_landing_vperp", 80.0)
	var hard_landing: float = model_params.get("hard_landing_vperp", 200.0)
	var bungee_time: float = model_params.get("bungee_time", 0.15)
	var mass_kg: float = model_params.get("mass_kg", 447.0)

	var last_flight_output: Aerodynamics.FlightOutput = null

	var bullet_spawn_offset: Vector2 = model_params.get("bullet_spawn_offset", Vector2(50, -5))
	var bomb_spawn_offset: Vector2 = model_params.get("bomb_spawn_offset", Vector2(0, 32))

	func reset() -> void:
		set_flight_state(FlightState.FLYING)
		damage.reset()
		reliability      = 1.0
		drag_multiplier  = 1.0
		thrust_multiplier = 1.0
		refuel_timer     = 0.0
		refuel_cooldown  = 0.0
		last_impact_ms   = 0
		commanded_vel    = Vector2.ZERO
		pitch_angle      = 0.0
		angular_velocity  = 0.0
		control_effectiveness = 1.0
		is_airborne           = true
		turret_angle       = 0.0
		travel_dir         = 1.0
		throttle         = 0.0
		throttle_target  = 0.0
		throttle_repeat_timer = 0.0
		engine_cutoff    = false
		engine_restart_hold_time    = 0.0
		engine_restart_required_time = 0.0
		is_barrel_rolled      = false
		is_flipping      = false
		flip_progress    = 0.0
		flip_direction   = 0
		flip_is_ground_reversal = false
		flip_halfway_applied    = false
		has_hit_ground    = false
		ammo  = MAX_AMMO
		fuel  = 100.0
		gun_timer  = 0.0
		bomb_timer = 0.0
		last_shot_range = 0.0
		last_flight_output = null
		# Respawn is the ONLY point where attached fire/smoke is cleared:
		# wrecks keep burning through the fall, impact, and time on the
		# ground.  (Inner class, so the detach is inline — AvatarData
		# cannot call the outer sync helpers.)
		if damage_fx:
			if EffectManager:
				EffectManager.detach_damage_fx(damage_fx)
			elif is_instance_valid(damage_fx):
				damage_fx.queue_free()
			damage_fx = null

		# Initialize plane model parameters
		update_model_params()
		bombs = model_params.get("max_bombs", 0)

## All live avatars, keyed by avatar id.
var _avatars: Dictionary[int, AvatarData] = {}

## Prevents the crash signal from firing more than once per entity.
var _crash_processed: Dictionary = {}

## Set once the wreck of a destroyed plane has reached the ground, so the
## respawn timer is queued exactly once (2s later) regardless of how the plane
## was destroyed.  Reset on respawn.
var _respawn_queued: Dictionary = {}

###############################################################################
# DAMAGE MODIFIERS
## Called whenever damage_percent changes. Updates the cached modifier fields
## so Aerodynamics.calculate_forces() reads a consistent table rather than branch-testing
## damage_percent repeatedly.
###############################################################################

func _refresh_damage_modifiers(avatar: AvatarData) -> void:
	var new_state := avatar.damage.get_damage_state()
	avatar.damage.damage_state = new_state

	var mods := avatar.damage.get_modifiers()
	avatar.reliability = mods["reliability"]
	avatar.drag_multiplier = mods["drag_multiplier"]
	avatar.thrust_multiplier = mods["thrust_multiplier"]

###############################################################################
# SIGNALS
###############################################################################

signal fired_bullet(position: Vector2, direction: Vector2, speed: float, owner: Node, range_percent: float)
signal dropped_bomb(position: Vector2, velocity: Vector2, owner: Node)
signal crashed(is_midair: bool)
signal crashed_landed(avatar_id: int)
signal damaged(impact_force: float, v_perp: float)

###############################################################################
# NODE STATE
###############################################################################

var game_active: bool = false
var _terrain: Node    = null   ## Cached in _ready(); null if terrain absent.
var _active_bombs: Array[Node] = []   ## Bombs this plane dropped, tracking for whistle.

var _pending_teleport: bool = false
var _teleport_position: Vector2 = Vector2.ZERO
var _teleport_rotation: float = 0.0

var velocity: Vector2:
	get: return linear_velocity
	set(v): linear_velocity = v

###############################################################################
# STATIC ACCESSOR
## Used by external nodes (bullets, enemy_ai) to reach avatar data without
## a direct node reference. Looks up the Biplane node from the scene tree.
###############################################################################

static func get_avatar(player_id: int) -> AvatarData:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	var biplane := tree.root.get_node_or_null("Main/Biplane") \
				   if tree.root.has_node("Main/Biplane") \
				   else tree.root.get_node_or_null("Biplane")
	if biplane and biplane.has_method("get_avatar_data"):
		return biplane.get_avatar_data(player_id)
	return null

func get_avatar_data(player_id: int) -> AvatarData:
	if not _avatars.has(player_id):
		var av       := AvatarData.new()
		av.id         = player_id
		_avatars[player_id] = av
		if av.damage.damage_state_changed.is_connected(_on_avatar_damage_state_changed):
			av.damage.damage_state_changed.disconnect(_on_avatar_damage_state_changed)
		av.damage.damage_state_changed.connect(_on_avatar_damage_state_changed.bind(av))
	return _avatars[player_id]

## Convenience accessor used by obstacle-collision code in other nodes.
func get_primary_entity() -> AvatarData:
	return get_avatar_data(0)

###############################################################################
# HOMEBASE MANAGEMENT
###############################################################################

func setup_homebase(id: int, x: float, width: float, spawn_pos: Vector2,
		spawn_rot: float, team: Team = Team.ALLIED) -> void:
	var hb              := HomebaseData.new()
	hb.id               = id
	hb.home_base_x      = x
	hb.home_base_width  = width
	hb.spawn_position   = spawn_pos
	hb.spawn_rotation   = spawn_rot
	hb.team             = team
	_homebases[id]      = hb

func assign_plane_model(avatar: AvatarData, model: String) -> void:
	avatar.plane_model = model
	avatar.update_model_params()

	var player_faction_str := GameManager.player_faction if GameManager else "British"
	var player_faction_enum := Faction.BRITISH
	match player_faction_str:
		"German": player_faction_enum = Faction.GERMAN
		"French": player_faction_enum = Faction.FRENCH
	match model:
		"fokker_d7":
			avatar.faction = Faction.GERMAN
			avatar.team = Team.ALLIED if avatar.faction == player_faction_enum else Team.ENEMY
		"spad_s13":
			avatar.faction = Faction.FRENCH
			avatar.team = Team.ALLIED if avatar.faction == player_faction_enum else Team.ENEMY
		"p-51d":
			avatar.faction = Faction.USA
			avatar.team = Team.ALLIED if avatar.faction == player_faction_enum else Team.ENEMY
		_:
			avatar.faction = Faction.BRITISH
			avatar.team = Team.ALLIED if avatar.faction == player_faction_enum else Team.ENEMY

	# Update visual representation
	if has_node("Visual/Sprite2D"):
		var sprite: Sprite2D = $Visual/Sprite2D
		sprite.texture = load(_get_svg_path_from_params(avatar.model_params))
		sprite.scale = avatar.get_model_param("visual_scale", Vector2.ONE)

func get_default_plane_model(faction: Faction) -> String:
	match faction:
		Faction.BRITISH:
			return "sopwith_camel"
		Faction.GERMAN:
			return "fokker_d7"
		Faction.FRENCH:
			return "spad_s13"
		Faction.USA:
			return "p-51d"
		_:
			return "sopwith_camel"

func _get_homebase(avatar: AvatarData) -> HomebaseData:
	return _homebases.get(avatar.homebase_id)

## Sync an existing homebase's faction in place WITHOUT relocating its spawn
## point or renumbering its id.  Used when an enemy re-arms its faction on the
## respawn path; the homebase keeps the spawn location set once at game start.
func refresh_homebase_faction(avatar: AvatarData, faction: Faction) -> void:
	var hb := _get_homebase(avatar)
	if hb:
		hb.faction = faction

func get_homebase_x(avatar: AvatarData) -> float:
	var hb := _get_homebase(avatar)
	return hb.home_base_x if hb else 6554.0

func get_homebase_width(avatar: AvatarData) -> float:
	var hb := _get_homebase(avatar)
	return hb.home_base_width if hb else 700.0

func get_homebase_spawn_position(avatar: AvatarData) -> Vector2:
	var hb := _get_homebase(avatar)
	return hb.spawn_position if hb else Vector2(7000.0, 500.0)

func get_homebase_spawn_rotation(avatar: AvatarData) -> float:
	var hb := _get_homebase(avatar)
	return hb.spawn_rotation if hb else 0.0

###############################################################################
# TERRAIN QUERIES
## Centralised so every caller uses the same cached node and the same fallback.
###############################################################################

func _ground_y(x: float) -> float:
	if _terrain and _terrain.has_method("get_ground_height_at"):
		return _terrain.get_ground_height_at(x)
	return 650.0

func _on_runway(x: float) -> bool:
	if _terrain and _terrain.has_method("is_on_runway"):
		return _terrain.is_on_runway(x)
	return false

###############################################################################
# DEBUG VISUALIZATION
###############################################################################

func _process(_delta: float) -> void:
	if not OS.is_debug_build():
		return
	if not GameManager or not GameManager.debug_hud:
		return
	queue_redraw()

func _draw() -> void:
	if not OS.is_debug_build():
		return
	if not GameManager or not GameManager.debug_hud:
		return

	for avatar_id in _avatars:
		var avatar: AvatarData = _avatars[avatar_id]
		if is_player_controlled:
			_draw_debug_lines(avatar)
		else:
			_draw_ai_debug_lines(avatar)

func _draw_debug_lines(avatar: AvatarData) -> void:
	const MAX_LEN := 200.0
	const ALPHA := 0.5

	# All lines are drawn from the plane origin (local Vector2.ZERO) in local
	# coordinates.  We convert world-space directions to local so lines stay
	# anchored to the plane but point in the correct world-relative direction.

	# 1. Forward / Pitch axis (white) — the nose always points along local +X
	draw_line(Vector2.ZERO, Vector2(MAX_LEN, 0.0), Color(1.0, 1.0, 1.0, ALPHA), 1.5)

	# 2. Velocity (green)
	if velocity.length_squared() > 1.0:
		var vel_local := to_local(global_position + velocity.normalized() * MAX_LEN)
		draw_line(Vector2.ZERO, vel_local, Color(0.0, 1.0, 0.0, ALPHA), 1.5)

	# 3. Gravity / Weight (yellow) — always world-down
	# var grav_local := to_local(global_position + Vector2(0.0, MAX_LEN))
	# draw_line(Vector2.ZERO, grav_local, Color(1.0, 1.0, 0.0, ALPHA), 1.5)

	# 4. Force vectors from the last physics frame (FlightOutput)
	var out := avatar.last_flight_output
	if out:
		var lift_local := to_local(global_position + out.lift_force.normalized() * MAX_LEN) \
				if out.lift_force.length_squared() > 0.01 else Vector2.ZERO
		if lift_local != Vector2.ZERO:
			draw_line(Vector2.ZERO, lift_local, Color(0.2, 0.5, 1.0, ALPHA), 1.5)

		var thrust_local := to_local(global_position + out.thrust_force.normalized() * MAX_LEN) \
				if out.thrust_force.length_squared() > 0.01 else Vector2.ZERO
		if thrust_local != Vector2.ZERO:
			draw_line(Vector2.ZERO, thrust_local, Color(1.0, 0.0, 0.0, ALPHA), 1.5)

		var drag_local := to_local(global_position + out.drag_force.normalized() * MAX_LEN) \
				if out.drag_force.length_squared() > 0.01 else Vector2.ZERO
		if drag_local != Vector2.ZERO:
			draw_line(Vector2.ZERO, drag_local, Color(1.0, 0.6, 0.0, ALPHA), 1.5)

		# var normal_local := to_local(global_position + out.normal_force.normalized() * MAX_LEN) \
		# 		if out.normal_force.length_squared() > 0.01 else Vector2.ZERO
		# if normal_local != Vector2.ZERO:
		# 	draw_line(Vector2.ZERO, normal_local, Color(0.6, 0.0, 0.8, ALPHA), 1.5)

		# var net_local := to_local(global_position + out.net_force.normalized() * MAX_LEN) \
		# 		if out.net_force.length_squared() > 0.01 else Vector2.ZERO
		# if net_local != Vector2.ZERO:
		# 	draw_line(Vector2.ZERO, net_local, Color(0.8, 0.2, 0.8, ALPHA), 1.5)

	# # 5. Ground normal (cyan) from terrain slope
	# var gc := _get_ground_contact(avatar)
	# if gc.is_grounded:
	# 	var gn_local := to_local(global_position + gc.ground_normal * MAX_LEN)
	# 	draw_line(Vector2.ZERO, gn_local, Color(0.0, 0.8, 0.8, ALPHA), 1.5)

	# 6. Ground ray (cyan, thinner) from RayCast2D collision point
	# var ground_ray := $GroundRay if has_node("GroundRay") else null
	# if ground_ray and ground_ray.is_colliding():
	# 	var hit_local := to_local(ground_ray.get_collision_point())
	# 	draw_line(Vector2.ZERO, hit_local, Color(0.0, 1.0, 1.0, ALPHA * 0.6), 1.0)

func _find_enemy_ai_for_avatar(_avatar: AvatarData) -> Node:
	if has_node("EnemyAI"):
		return get_node("EnemyAI")
	return null

func _draw_ai_debug_lines(avatar: AvatarData) -> void:
	const MAX_LEN := 200.0
	const ALPHA := 0.6

	var ai_node := _find_enemy_ai_for_avatar(avatar)
	if not ai_node:
		return

	var pilot = ai_node.pilots[0] if ai_node.pilots.size() > 0 else null
	if not pilot:
		return

	# --- Desired heading line (purple) ---
	var heading_rad: float = pilot.desired_heading as float
	var heading_dir := Vector2(cos(heading_rad), sin(heading_rad))
	var heading_local := to_local(global_position + heading_dir * MAX_LEN)
	draw_line(Vector2.ZERO, heading_local, Color(0.7, 0.2, 1.0, ALPHA), 2.0)

	# --- Pitch input indicator (magenta, shorter) ---
	var pitch_input: float = pilot.last_pitch_input as float
	var pitch_len := absf(pitch_input) * MAX_LEN * 0.6
	if pitch_len > 5.0:
		# Pitch input is gravity-relative (the AI command convention):
		# positive = dive toward the ground, negative = climb toward the sky.
		var pitch_angle: float = pitch_input * 0.5  # scale for visibility
		var pitch_dir := heading_dir.rotated(pitch_angle)
		var pitch_local := to_local(global_position + pitch_dir * pitch_len)
		draw_line(Vector2.ZERO, pitch_local, Color(1.0, 0.0, 1.0, ALPHA * 0.8), 1.5)

	# --- Throttle bar (horizontal, below the plane) ---
	var bar_width := 60.0
	var bar_y := 35.0
	var bar_bg_start := Vector2(-bar_width * 0.5, bar_y)
	var bar_bg_end := Vector2(bar_width * 0.5, bar_y)
	draw_line(bar_bg_start, bar_bg_end, Color(0.3, 0.3, 0.3, ALPHA * 0.5), 3.0)
	var throttle: float = pilot.last_throttle as float
	var fill_width := bar_width * clampf(throttle, 0.0, 1.0)
	var bar_fill_end := Vector2(-bar_width * 0.5 + fill_width, bar_y)
	var thr_color := Color(0.0, 1.0, 0.3, ALPHA) if throttle > 0.5 else Color(1.0, 0.8, 0.0, ALPHA)
	draw_line(bar_bg_start, bar_fill_end, thr_color, 3.0)

	# --- Target line (red, to tracked target) ---
	var target_node = ai_node.target if "target" in ai_node else null
	if target_node and is_instance_valid(target_node):
		var tgt_local := to_local(target_node.global_position)
		draw_line(Vector2.ZERO, tgt_local, Color(1.0, 0.15, 0.15, ALPHA * 0.4), 1.0)
		# Small diamond at target position
		var d := 5.0
		var diamond := PackedVector2Array([
			tgt_local + Vector2(0, -d),
			tgt_local + Vector2(d, 0),
			tgt_local + Vector2(0, d),
			tgt_local + Vector2(-d, 0),
			tgt_local + Vector2(0, -d),
		])
		draw_polyline(diamond, Color(1.0, 0.15, 0.15, ALPHA * 0.6), 1.5)

###############################################################################
# COLLISION INTERFACE
###############################################################################

class CollisionResult:
	var hit: bool = false
	var damage: float = 0.0
	var is_midair: bool = false
	var impact_speed: float = 0.0

## Center distance below which two aircraft count as colliding.  The fuselage
## capsule (r=32.5) first touches at ~65 px center distance and the solver
## never lets centers get closer than ~50 px (measured headless), so the old
## 40.0 gates could never fire for plane-vs-plane.
const PLANE_PROXIMITY_RADIUS := 45.0
## Mid-air closing speed (m/s) that destroys both aircraft outright.  Cruise
## is ~40–50 m/s, so any genuine head-on impact is catastrophic while
## formation kisses and overtake bumps merely damage.
const MIDAIR_CRASH_CLOSING_MS := 30.0
## Minimum closing speed (m/s) that counts as a mid-air hit at all.
const MIDAIR_MIN_CLOSING_MS := 2.0
## Gentle plane-plane touches (closing below this, m/s) spring apart with
## restitution instead of grinding: bounce, light damage, keep flying.
const MIDAIR_BOUNCE_LIMIT_MS := 12.0
const MIDAIR_BOUNCE_RESTITUTION := 0.12
const MIDAIR_BOUNCE_MIN_PUSH_PX := 15.0
## Sub-catastrophic impact hits apply at most this often per avatar, so a
## sustained grind deals damage over time instead of melting at 60 Hz.
const IMPACT_THROTTLE_MS := 250

## Natural-physics mid-air damage from dissipated collision energy.  Two
## bodies closing at v share E = ½·μ·v² (μ = reduced mass); each airframe
## absorbs that in inverse proportion to its own mass share, so a light
## scout ramming a heavy bomber comes off far worse — and barely scratches
## the bomber.  Calibrated: equal 447 kg masses at MIDAIR_CRASH_CLOSING_MS
## score exactly 100 (destruction); the restitution loss (1−e²) is folded
## into that anchor.  Returns 0–100 damage points (100 = destruction).
static func midair_impact_damage(closing_px_s: float, ppm: float,
		self_mass_kg: float, other_mass_kg: float) -> float:
	var closing_ms := closing_px_s / maxf(ppm, 1.0)
	if closing_ms < MIDAIR_MIN_CLOSING_MS:
		return 0.0
	var m_self := maxf(self_mass_kg, 1.0)
	var m_other := maxf(other_mass_kg, 1.0)
	# μ/m_self = other's mass share; ×2 anchors equal masses to the plain
	# (v/30)² curve at the calibration point.
	var f := closing_ms / MIDAIR_CRASH_CLOSING_MS
	return clampf(200.0 * (m_other / (m_self + m_other)) * f * f, 0.0, 100.0)

## Airframe mass for impact physics (kg), with a sane fallback.
static func impact_mass_kg(av: AvatarData) -> float:
	if av == null:
		return 447.0
	return maxf(float(av.model_params.get("mass_kg", 447.0)), 1.0)

## Flight intent velocity for impact math: what the model commanded last
## tick, falling back to the solver's body velocity before intent exists
## (fresh spawn) or when it decayed to rest.  Solver output reads ~0 for a
## body pressed into an obstacle while intent still says full speed — impact
## severity must use intent.
func _intent_velocity(body: RigidBody2D, av: AvatarData) -> Vector2:
	if av and av.commanded_vel.length_squared() > 0.01:
		return av.commanded_vel
	if body:
		return body.linear_velocity
	return Vector2.ZERO

## Single choke point for impact damage on self (+ symmetric counter-damage
## on the collider).  Sub-catastrophic hits are throttled per avatar;
## catastrophic hits (crash=true) always apply immediately.  Returns true
## when damage was applied.
func _apply_impact(avatar: AvatarData, self_damage: float, collider: Node,
		collider_damage: float, crash: bool) -> bool:
	if self_damage <= 0.0 and not crash:
		return false
	if not crash:
		var now := Time.get_ticks_msec()
		if now - avatar.last_impact_ms < IMPACT_THROTTLE_MS:
			return false
		avatar.last_impact_ms = now
	if self_damage > 0.0:
		take_damage(avatar, self_damage, collider)
	if collider_damage > 0.0 and collider and is_instance_valid(collider) \
			and collider.has_method("take_damage"):
		collider.take_damage(collider_damage, self)
	if crash:
		_on_avatar_crashed(avatar)
	return true

###############################################################################
# COLLISION RESPONSE (called by other biplanes via get_collision_response)
###############################################################################

func get_collision_response(other: Node, other_avatar: AvatarData, other_speed: float,
		_plane_soft_landing: float = 100.0, _plane_hard_landing: float = 200.0) -> CollisionResult:
	var result := CollisionResult.new()
	var dist := global_position.distance_to(other.global_position)
	result.impact_speed = other_speed

	if other is RigidBody2D and other.has_method("get_primary_entity"):
		var self_av := get_primary_entity()
		if self_av and other_avatar and not self_av.is_hostile_to(other_avatar):
			return result
		# Approaching component only, consistent with the contact loop.
		# Intent velocities (see commanded_vel): pressed-together bodies
		# report ~0 solver velocity while still flying into each other.
		var closing := other_speed + velocity.length()
		if dist > 0.01 and dist < PLANE_PROXIMITY_RADIUS and other_speed > 10.0:
			var axis: Vector2 = (other.global_position - global_position) / dist
			closing = maxf(0.0, (_intent_velocity(self, self_av) \
				- _intent_velocity(other as RigidBody2D, other_avatar)).dot(axis))
			var dmg := midair_impact_damage(closing, pixels_per_meter,
				impact_mass_kg(self_av), impact_mass_kg(other_avatar))
			if dmg > 0.0:
				result.hit = true
				result.damage = dmg
				result.is_midair = true
	return result

func _get_hit_radius_for_body(body: Node) -> float:
	if body.is_in_group("ground_target") or body.is_in_group("wreck"):
		var pbounds := _get_collider_poly_bounds(body)
		if pbounds["has_poly"]:
			var horizontal_extent := maxf(abs(pbounds["min_x"]), abs(pbounds["max_x"]))
			var vertical_extent := maxf(abs(pbounds["min_y"]), abs(pbounds["max_y"]))
			return maxf(horizontal_extent, vertical_extent) + 5.0
		return 85.0
	return 15.0

###############################################################################
# GROUND CONTACT
###############################################################################

class GroundContact:
	var ground_y:     float   = 650.0
	var slope_angle:  float   = 0.0
	var tilt_angle:   float   = 0.0
	var on_runway:    bool    = false
	var is_grounded:  bool    = false
	var ground_normal: Vector2 = Vector2(0.0, -1.0)

func _get_ground_contact(avatar: AvatarData) -> GroundContact:
	var gc    := GroundContact.new()
	var x     := global_position.x
	gc.ground_y    = _ground_y(x)
	gc.on_runway   = _on_runway(x)
	var ahead      := _ground_y(x + 10.0)
	var behind     := _ground_y(x - 10.0)
	gc.slope_angle = atan2(ahead - behind, 20.0)

	## Ground normal: perpendicular to slope, pointing away from terrain.
	## For flat ground this is (0, -1) in Godot Y-down. Slope tilts it.
	gc.ground_normal = Vector2(-sin(gc.slope_angle), -cos(gc.slope_angle))

	## Tilt: how far the plane heading deviates from lying flat on the slope.
	## level_rotation() folds the inverted (leftward) 180° offset into the
	## comparison so tilt reads identically in either travel direction.
	var eff_pitch  := avatar.pitch_angle + avatar.level_rotation()
	var rel_angle  := fposmod(eff_pitch - gc.slope_angle + PI, TAU) - PI
	gc.tilt_angle  = abs(rel_angle)

	## Positional ground contact with tolerance to absorb integration overshoot.
	gc.is_grounded = global_position.y >= gc.ground_y - GROUND_SURFACE_OFFSET - GROUND_TOLERANCE
	return gc

###############################################################################
# GODOT LIFECYCLE
###############################################################################

func _ready() -> void:
	mass = 422.0
	gravity_scale = 0.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = CCD_MODE_CAST_SHAPE

	for avatar_id in _avatars:
		var avatar: AvatarData = _avatars[avatar_id]
		avatar.plane_model = get_default_plane_model(avatar.faction)
		avatar.update_model_params()

	var primary_avatar = get_avatar_data(0)
	if primary_avatar:
		var model_params = primary_avatar.model_params
		mass = model_params.get("mass_kg", 447.0)

	reset_visual_transform()
	_terrain = get_parent().get_node_or_null("Terrain")

func _physics_process(delta: float) -> void:
	if not game_active:
		return

	for avatar_id in _avatars:
		var avatar: AvatarData = _avatars[avatar_id]
		if avatar.flight_state == FlightState.CRASHED:
			continue
		if avatar.flight_state == FlightState.FALLING:
			velocity.y += gravity * pixels_per_meter * delta
			_check_obstacle_collision(avatar)
			continue

		_handle_input(avatar, delta)
		_handle_weapons(avatar, delta)
		_check_altitude_engine_cutoff(avatar, delta)
		_check_obstacle_collision(avatar)
		_check_fuel_consumption(avatar, delta)
		_check_home_refuel(avatar, delta)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _pending_teleport:
		var pre_av := state.get_angular_velocity()
		var t := Transform2D(_teleport_rotation, _teleport_position)
		state.set_transform(t)
		state.set_linear_velocity(Vector2.ZERO)
		state.set_angular_velocity(0.0)
		_pending_teleport = false
		var avatar := get_avatar_data(0)
		if avatar:
			avatar.pitch_angle = _teleport_rotation
			avatar.is_barrel_rolled = AvatarData.rotation_is_leftward(_teleport_rotation)
			rotation = _teleport_rotation
			DLog.info("teleport", {
				"pre_angvel": snapped(pre_av, 4),
				"post_rot": snapped(rotation, 4),
				"post_pitch": snapped(avatar.pitch_angle, 4),
				"post_av": snapped(avatar.angular_velocity, 4),
				"game_active": game_active,
			})
		if not game_active:
			return

	if not game_active:
		state.set_linear_velocity(Vector2.ZERO)
		state.set_angular_velocity(0.0)
		return

	var step := state.get_step()
	var avatar = get_avatar_data(0)
	if not avatar:
		return

	# FORENSIC: Log any physics contacts detected this frame
	var contact_count := state.get_contact_count()
	if contact_count > 0:
		var contact_info: Array[Dictionary] = []
		for ci in range(contact_count):
			var collider := state.get_contact_collider_object(ci)
			contact_info.append({
				"idx": ci,
				"collider": collider.name if collider else "null",
				"local_pos": Vector2(
					snapped(state.get_contact_local_position(ci).x, 1.0),
					snapped(state.get_contact_local_position(ci).y, 1.0)
				),
				"normal": state.get_contact_local_normal(ci),
			})


	if avatar.flight_state == FlightState.CRASHED:
		_integrate_crash_forces(state, avatar, step)
		return

	if avatar.flight_state == FlightState.FALLING:
		avatar.angular_velocity = FALLING_SPIN_RATE
		avatar.pitch_angle += avatar.angular_velocity * step
		state.set_angular_velocity(avatar.angular_velocity)

	var inp := _build_flight_input(avatar, state)
	var out := Aerodynamics.calculate_forces(inp)
	avatar.last_flight_output = out

	# Supplement analytical ground detection with physics contact data.
	# The analytical model checks center position vs terrain surface (pos_y >= ground_y - 2),
	# missing contacts where only the collision shape's lower extent touches terrain.
	# Physics contacts from state.get_contact_count() provide the real collision state.
	#
	# Impact severity reads flight INTENT (see commanded_vel), not solver
	# output: pressing into a wall reports ~0 solver velocity while intent
	# still says full speed, and vehicle-vs-vehicle contacts exchange almost
	# no solver momentum at all (both bodies re-assert velocity every tick).
	var intent_vel := _intent_velocity(self, avatar)
	var cc := state.get_contact_count()
	# Restitution pending for gentle aircraft touches (set in the mid-air
	# branch, applied to the final velocity below).
	var bounce_n := Vector2.ZERO
	var bounce_push := 0.0
	for ci in range(cc):
		var collider := state.get_contact_collider_object(ci)
		if not collider:
			continue
		# Check if contact is terrain (has get_ground_height_at on itself or parent)
		var ground_source: Node = collider
		if not ground_source.has_method("get_ground_height_at"):
			ground_source = collider.get_parent()
		if ground_source and ground_source.has_method("get_ground_height_at"):
			if not inp.is_grounded:
				inp.is_grounded = true
				out.v_perp = maxf(0.0, -inp.velocity.dot(inp.ground_normal))
			continue
		var col_node := collider as Node2D
		if col_node == null:
			continue
		var other_av: AvatarData = null
		if collider is RigidBody2D and collider.has_method("get_primary_entity"):
			other_av = collider.get_primary_entity()
		# Approach speed along the collision axis, px/s.  Falls back to the
		# relative-speed magnitude for degenerate (coincident) centers.
		var other_vel := Vector2.ZERO
		if other_av != null:
			other_vel = _intent_velocity(collider, other_av)
		else:
			other_vel = state.get_contact_collider_velocity_at_position(ci)
		var to_other: Vector2 = col_node.global_position - global_position
		var closing := 0.0
		if to_other.length_squared() > 0.01:
			closing = maxf(0.0, (intent_vel - other_vel).dot(to_other.normalized()))
		else:
			closing = (intent_vel - other_vel).length()
		if closing <= 0.0:
			continue
		# Structures (static bodies) and ground vehicles (tanks: huge,
		# effectively static masses) share the soft/hard landing
		# classification — now fed by closing velocity instead of impulse.
		if (collider is StaticBody2D \
				or (other_av != null and not other_av.is_aerodynamic())) \
				and avatar.is_aerodynamic():
			var model_params = avatar.model_params
			var soft_landing: float = model_params.get("soft_landing_vperp", 80.0)
			var hard_landing: float = model_params.get("hard_landing_vperp", 200.0)
			_debug_forensic_log(avatar, "building_contact", {
				"frame": _debug_frame_count,
				"collider": (collider as Node).name,
				"closing": snapped(closing, 1.0),
				"soft": soft_landing,
				"hard": hard_landing,
			})
			if closing >= hard_landing:
				_apply_impact(avatar, 100.0, collider,
					closing / hard_landing * 400.0, true)
				return
			elif closing > soft_landing:
				var damage_pct: float = (closing - soft_landing) / (hard_landing - soft_landing)
				damage_pct = clampf(damage_pct, 0.0, 1.0)
				_apply_impact(avatar, damage_pct * 100.0, collider,
					damage_pct * 300.0, false)
			continue
		# Biplane-vs-biplane: RigidBody2D with a primary avatar (another plane).
		# Each body's _integrate_forces sees the same contact independently,
		# so damage is applied only to self (the other body damages itself
		# from its own callback) — counter-damage here covers the collider
		# only when IT cannot process contacts itself.
		#
		# Mid-air collisions have no shock absorption (unlike landing gear
		# cushioned by oleos and tyres), so the kinetic-energy ramp below
		# replaces the per-model landing thresholds: a high-speed impact is
		# catastrophic as a natural outcome of the closing speed.
		if other_av != null and other_av.is_aerodynamic() and avatar.is_aerodynamic():
			var self_kg := impact_mass_kg(avatar)
			var other_kg := impact_mass_kg(other_av)
			var dmg := midair_impact_damage(closing, pixels_per_meter, self_kg, other_kg)
			_debug_forensic_log(avatar, "midair_contact", {
				"frame": _debug_frame_count,
				"collider": (collider as Node).name,
				"closing": snapped(closing, 1.0),
				"damage": snapped(dmg, 1.0),
			})
			if dmg > 0.0:
				_apply_impact(avatar, dmg, collider, dmg * 0.5, dmg >= 100.0)
			# Gentle touches bounce: remember the strongest separation push
			# so the final velocity springs apart instead of re-asserting
			# aerodynamic velocity into the other aircraft (grind).  Scaled
			# by the elastic recoil share — the lighter aircraft recoils more.
			if dmg < 100.0 and to_other.length_squared() > 0.01 \
					and closing / maxf(pixels_per_meter, 1.0) < MIDAIR_BOUNCE_LIMIT_MS:
				var push := (closing * MIDAIR_BOUNCE_RESTITUTION + MIDAIR_BOUNCE_MIN_PUSH_PX) \
					* 2.0 * other_kg / (self_kg + other_kg)
				if push > bounce_push:
					bounce_push = push
					bounce_n = -to_other.normalized()
			continue

	if out.should_crash:
		DLog.crash_enter(avatar.id, out.crash_reason, {
			"px": snapped(global_position.x, 0.1),
			"py": snapped(global_position.y, 0.1),
			"vx": snapped(velocity.x, 0.1),
			"vy": snapped(velocity.y, 0.1),
			"ground_y": snapped(_ground_y(global_position.x), 0.1),
		})
		_on_avatar_crashed(avatar)
		return

	if inp.is_grounded and out.v_perp > 0.0:
		_process_landing_impact(avatar, out.v_perp, out.impact_force, inp.tilt_angle)
		if avatar.flight_state == FlightState.CRASHED:
			return
		if avatar.flight_state == FlightState.DAMAGED:
			pass
	if avatar.is_aerodynamic() and inp.is_grounded and inp.tilt_angle >= deg_to_rad(avatar.max_landing_tilt):
		_on_avatar_crashed(avatar)
		return

	var current_vel := state.get_linear_velocity()
	var mass: float = avatar.model_params.get("mass_kg", 447.0)
	current_vel += (out.net_force / mass) * pixels_per_meter * step
	state.set_linear_velocity(current_vel)

	var pre_gc := _get_ground_contact(avatar)
	_debug_check_ground_forensics(avatar, state, pre_gc, inp, out, "pre_clamp")

	var gc := _get_ground_contact(avatar)
	if gc.is_grounded:
		var transform := state.get_transform()
		var surf_y := gc.ground_y - GROUND_SURFACE_OFFSET
		if transform.origin.y > surf_y:
			transform.origin.y = surf_y
			state.set_transform(transform)
		var vel_into_ground := -current_vel.dot(gc.ground_normal)
		if vel_into_ground > 0.0:
			current_vel += gc.ground_normal * vel_into_ground
			state.set_linear_velocity(current_vel)

	# Restitution for gentle mid-air touches: guarantee separation along the
	# contact axis so aircraft bounce apart instead of grinding.  Skipped
	# once crashed (the wreck is ballistic) — the crash path returns earlier
	# in the catastrophic case; this covers the bounce-and-keep-flying case.
	if bounce_n != Vector2.ZERO and avatar.is_aerodynamic() \
			and avatar.flight_state != FlightState.CRASHED:
		var vn := current_vel.dot(bounce_n)
		if vn < bounce_push:
			current_vel += bounce_n * (bounce_push - vn)
			state.set_linear_velocity(current_vel)

	_debug_check_ground_forensics(avatar, state, gc, inp, out, "post_clamp")

	avatar.control_effectiveness = out.control_effectiveness
	avatar.is_airborne = not gc.is_grounded
	# Record flight intent AFTER all adjustments (clamp, bounce): this is the
	# velocity the model commanded, which impact math reads next tick.
	avatar.commanded_vel = current_vel

	_update_flight_state(avatar, gc, out.is_stalled, current_vel)

func _build_flight_input(avatar: AvatarData, state: PhysicsDirectBodyState2D) -> Aerodynamics.FlightInput:
	var gc := _get_ground_contact(avatar)
	var inp := Aerodynamics.FlightInput.new()
	inp.velocity = state.get_linear_velocity()
	inp.pitch_angle = avatar.pitch_angle
	inp.throttle = avatar.throttle
	inp.is_grounded = gc.is_grounded
	inp.ground_normal = gc.ground_normal
	inp.on_runway = gc.on_runway
	inp.tilt_angle = gc.tilt_angle
	inp.global_position_y = global_position.y
	inp.ground_y = gc.ground_y
	inp.is_barrel_rolled = avatar.travel_sign() < 0.0
	inp.engine_cutoff = avatar.engine_cutoff
	inp.mass_kg = avatar.mass_kg
	inp.model_params = avatar.model_params
	inp.damage_drag_mult = avatar.drag_multiplier
	inp.damage_thrust_mult = avatar.thrust_multiplier
	inp.stall_speed_ms = avatar.stall_speed_ms
	inp.pixels_per_meter = pixels_per_meter
	inp.air_density = air_density
	inp.gravity = gravity
	inp.arcade_multiplier = arcade_multiplier
	inp.bungee_time = avatar.bungee_time
	inp.is_destroyed = avatar.damage.damage_state == DamageData.DamageState.DESTROYED
	return inp

func _update_flight_state(avatar: AvatarData, gc: GroundContact, stalled: bool, ground_speed: Vector2 = Vector2.ZERO) -> void:
		var speed: float = ground_speed.length()

		if gc.is_grounded:
			# Destroyed / crashed / damaged planes keep their own (terminal) state.
			if avatar.flight_state == FlightState.DAMAGED or \
			   avatar.flight_state == FlightState.CRASHED or \
			   avatar.damage.damage_state == DamageData.DamageState.DESTROYED:
				return

			# Only treat the plane as LANDED once it has slowed to a taxi/rollout
			# speed.  A plane hugging the terrain at speed (low strafing pass, fast
			# ground rollout) is still flying — flagging it LANDED there strands the
			# flight FSM in LANDED and the AI wrongly keeps ENGAGING a plane that is
			# clearly airborne.  A fast grounded plane therefore stays FLYING and
			# rolls/skims until it decelerates below the threshold.
			if speed < LANDING_TAXI_SPEED:
				avatar.set_flight_state(FlightState.LANDED)
			else:
				avatar.set_flight_state(FlightState.FLYING)
			return

		if avatar.flight_state == FlightState.FALLING:
			if avatar.damage.damage_state == DamageData.DamageState.DESTROYED:
				# Destroyed wreck that has nearly stopped (resting on a
				# building, wreck, etc.) but not touching ground — crash it
				# so the respawn timer triggers.  Without this the wreck
				# stays FALLING forever and the plane never respawns.
				if velocity.length() < 5.0:
					_on_avatar_crashed(avatar)
			else:
				if stalled:
					avatar.set_flight_state(FlightState.STALLED)
				else:
					avatar.set_flight_state(FlightState.FLYING)
			return

		if stalled and avatar.damage.damage_state != DamageData.DamageState.DESTROYED:
			if avatar.flight_state == FlightState.FLYING or \
			   avatar.flight_state == FlightState.LANDED:
				avatar.set_flight_state(FlightState.STALLED)
			return

		if avatar.damage.damage_state != DamageData.DamageState.DESTROYED:
			if avatar.flight_state == FlightState.STALLED or \
			   avatar.flight_state == FlightState.LANDED:
				avatar.set_flight_state(FlightState.FLYING)

func _process_landing_impact(avatar: AvatarData, v_perp: float,
		impact_force: float, tilt_angle: float) -> void:
	# A plane that is already destroyed is a wreck — any terrain contact grounds
	# it as a crash, regardless of how gentle the impact is.  Without this a
	# destroyed plane landing CLEAN/HARD stayed in FALLING (spinning on the
	# ground) and never reached CRASHED, so it never scheduled a respawn.
	if avatar.damage.damage_state == DamageData.DamageState.DESTROYED:
		_on_avatar_crashed(avatar)
		return

	var model_params = avatar.model_params
	var max_landing_tilt: float = model_params.get("max_landing_tilt_deg", 40.0)
	var soft_landing: float = model_params.get("soft_landing_vperp", 80.0)
	var hard_landing: float = model_params.get("hard_landing_vperp", 200.0)

	var result := Aerodynamics.classify_landing_impact(
		v_perp, tilt_angle, max_landing_tilt, soft_landing, hard_landing)

	match result:
		Aerodynamics.LandingImpact.CLEAN:
			pass
		Aerodynamics.LandingImpact.HARD:
			var damage_pct: float = (v_perp - soft_landing) / (hard_landing - soft_landing)
			damage_pct = clampf(damage_pct, 0.0, 1.0)
			avatar.set_flight_state(FlightState.DAMAGED)
			avatar.damage.take_damage(damage_pct)
			_refresh_damage_modifiers(avatar)
			damaged.emit(impact_force, v_perp)
			if SoundManager:
				SoundManager.play_sfx(SoundManager.SoundEvent.BUMP)
		Aerodynamics.LandingImpact.CRASH:
			DLog.crash_enter(avatar.id, "hard_landing", {
				"v_perp": v_perp,
				"px": snapped(global_position.x, 0.1),
				"py": snapped(global_position.y, 0.1),
				"vx": snapped(velocity.x, 0.1),
				"vy": snapped(velocity.y, 0.1),
				"ground_y": snapped(_ground_y(global_position.x), 0.1),
			})
			_on_avatar_crashed(avatar)

func _integrate_crash_forces(state: PhysicsDirectBodyState2D, avatar: AvatarData, step: float) -> void:
	var current_vel := state.get_linear_velocity()
	var ground_ray: RayCast2D = $GroundRay if has_node("GroundRay") else null
	var gc := _get_ground_contact(avatar)

	# Respawn scheduling — runs every crash frame, BEFORE the at-rest early
	# return below.  A generous terrain-proximity margin (GROUND_REST_MARGIN =
	# 300 px, ~2× the tallest building height) catches wrecks resting on
	# buildings and obstacles as well as terrain — no contact scanning needed
	# because every structure sits on terrain.  Combined with the at-rest
	# velocity gate (<30 px/s) and angular-rest gate (<0.5 rad/s), this
	# ensures only wrecks that have truly settled trigger respawn: a falling
	# wreck can't be both near terrain AND stopped.
	var terrain_y := gc.ground_y - GROUND_SURFACE_OFFSET
	var near_terrain := global_position.y >= terrain_y - GROUND_REST_MARGIN
	var at_rest := current_vel.length() < RESPAWN_GROUND_SPEED
	var angular_rest := absf(state.get_angular_velocity()) < RESPAWN_ANGULAR_REST_SPEED
	if not _respawn_queued.has(avatar.id) and near_terrain and at_rest and angular_rest:
		_respawn_queued[avatar.id] = true
		crashed_landed.emit(avatar.id)

	if current_vel == Vector2.ZERO and avatar.has_hit_ground:
		state.set_linear_velocity(Vector2.ZERO)
		state.set_angular_velocity(0.0)
		avatar.commanded_vel = Vector2.ZERO
		return

	current_vel.y += gravity * pixels_per_meter * step
	var ang_vel = current_vel.x * 0.01
	state.set_linear_velocity(current_vel)
	state.set_angular_velocity(ang_vel)
	avatar.commanded_vel = current_vel

	if ground_ray and ground_ray.is_colliding() and not avatar.has_hit_ground:
		state.set_linear_velocity(Vector2.ZERO)
		state.set_angular_velocity(0.0)
		avatar.commanded_vel = Vector2.ZERO
		avatar.has_hit_ground = true
		damaged.emit(1.0, 0.0)
		DLog.crash_enter(avatar.id, "ground_ray", {
			"px": snapped(global_position.x, 0.1),
			"py": snapped(global_position.y, 0.1),
			"vx": snapped(velocity.x, 0.1),
			"vy": snapped(velocity.y, 0.1),
			"ground_y": snapped(_ground_y(global_position.x), 0.1),
		})
		_on_avatar_crashed(avatar)

	var transform := state.get_transform()
	var surf_y := _ground_y(global_position.x) - GROUND_SURFACE_OFFSET
	if transform.origin.y > surf_y:
		transform.origin.y = surf_y
		state.set_transform(transform)
		if current_vel.y > 0.0:
			current_vel.y = -current_vel.y * 0.1
			state.set_linear_velocity(current_vel)

###############################################################################
# ALTITUDE ENGINE CUTOFF
###############################################################################

func _check_altitude_engine_cutoff(avatar: AvatarData, delta: float) -> void:
	if avatar.unlimited_fuel_ammo:
		return
	var altitude := _ground_y(global_position.x) - global_position.y
	if not avatar.engine_cutoff:
		if altitude >= ENGINE_CUTOFF_ALTITUDE:
			avatar.engine_cutoff                 = true
			avatar.throttle                      = 0.0
			avatar.throttle_target               = 0.0
			avatar.engine_restart_hold_time      = 0.0
			avatar.engine_restart_required_time  = 4.0 + randf() * 4.0
			avatar.sputtering_timer             = 0.0
			if is_player_controlled and SoundManager:
				SoundManager.set_engine_rpm(randf() * 0.2)
	else:
		if is_player_controlled and SoundManager:
			avatar.sputtering_timer += delta
			if avatar.sputtering_timer >= 0.25:
				avatar.sputtering_timer = 0.0
				SoundManager.set_engine_rpm(randf() * 0.4)
		# Player restarts by holding the throttle-up action.  AI pilots keep
		# throttle at maximum (patrol/engage/evade), so their commanded
		# throttle_target is the equivalent "hold throttle to restart" intent:
		# the engine re-lights once they've held max throttle long enough.
		var restart_intent: bool = is_player_controlled and Input.is_action_pressed("throttle_up")
		if not is_player_controlled:
			restart_intent = avatar.throttle_target >= 0.5
		if restart_intent:
			avatar.engine_restart_hold_time += delta
			if avatar.engine_restart_hold_time >= avatar.engine_restart_required_time:
				avatar.engine_cutoff            = false
				avatar.engine_restart_hold_time = 0.0
				if is_player_controlled and SoundManager:
					SoundManager.start_engine()
					SoundManager.set_engine_rpm(0.0)

## Tilt-aware ground test for roll-input MODE SELECTION.  Uses the lowest
## point of the ACTUAL collision capsule rather than the body centre: a
## tilted capsule rests on its cap arc, which lifts the CENTRE a few pixels
## clear of the surface — a centre-height probe misreads that as airborne and
## picks the fatal airborne barrel-roll.  Capsule support-point geometry
## (radius r, half-length l, fuselage axis slope |u.y|):
##     hull_bottom = centre.y + r + l*|u.y|
## The margin grows with tilt, so a resting hull can never be missed.
func _is_on_ground_for_roll(avatar: AvatarData) -> bool:
	if avatar.flight_state == FlightState.LANDED:
		return true
	var gc := _get_ground_contact(avatar)
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs and cs.shape is CapsuleShape2D:
		var cap: CapsuleShape2D = cs.shape
		# Shape node is rotated onto the fuselage axis: the capsule's long
		# axis (height) runs along body-X, its radius across it.
		var half_len := cap.height * 0.5
		var fuselage_uy := absf(cos(rotation + cs.rotation))   # world |u.y| of long axis
		var hull_bottom := global_position.y + cap.radius + half_len * fuselage_uy
		return hull_bottom >= gc.ground_y - GROUND_TOLERANCE
	return is_grounded(avatar)

###############################################################################
# INPUT (human player)
###############################################################################

func _handle_input(avatar: AvatarData, delta: float) -> void:
	if not is_player_controlled:
		return

	# Player pitch commands are gravity-relative: pull_up = climb (negative),
	# pull_down = dive (positive).  Convert once into the rotation frame so an
	# inverted (leftward) plane rotates the correct way.
	var pitch_input := 0.0
	if Input.is_action_pressed("pull_up"):
		pitch_input = -1.0
	elif Input.is_action_pressed("pull_down"):
		pitch_input = 1.0
	pitch_input = avatar.pitch_command_to_rotation_input(pitch_input)
	pitch_input *= avatar.control_effectiveness

	if not avatar.engine_cutoff:
		var thr_up   := Input.is_action_pressed("throttle_up")
		var thr_down := Input.is_action_pressed("throttle_down")
		if thr_up or thr_down:
			avatar.throttle_repeat_timer -= delta
			if avatar.throttle_repeat_timer <= 0.0:
				if thr_up:
					avatar.throttle_target = minf(max_throttle, avatar.throttle_target + 0.15)
				else:
					avatar.throttle_target = maxf(min_throttle, avatar.throttle_target - 0.15)
				avatar.throttle_repeat_timer = 0.1
		else:
			avatar.throttle_repeat_timer = 0.0

	avatar.throttle = move_toward(avatar.throttle, avatar.throttle_target, 5.0 * delta)

	if Input.is_action_just_pressed("roll") and not avatar.is_flipping:
		if _is_on_ground_for_roll(avatar):
			_start_ground_reversal(avatar)
		else:
			_start_flip(avatar)
	elif Input.is_action_just_released("roll") and avatar.is_flipping:
		_release_flip(avatar)

	if not avatar.is_flipping:
		var model_params = avatar.model_params
		var eff_rot_speed: float = model_params.get("rotation_speed", 5.0) * (1.0 - avatar.damage.damage_percent * 0.4)
		var target_av: float = pitch_input * eff_rot_speed
		avatar.angular_velocity = move_toward(
			avatar.angular_velocity, target_av, model_params.get("rotation_inertia", 4.0) * delta)
		avatar.pitch_angle += avatar.angular_velocity * delta

	rotation = avatar.pitch_angle

func set_ai_input(pitch: float, throttle_amount: float) -> void:
	var dt = get_physics_process_delta_time()
	for avatar_id in _avatars:
		var avatar: AvatarData = _avatars[avatar_id]
		if is_player_controlled or avatar.flight_state == FlightState.CRASHED:
			continue
		avatar.throttle_target = clampf(throttle_amount, min_throttle, max_throttle)
		avatar.throttle = move_toward(avatar.throttle, avatar.throttle_target, 5.0 * dt)
		# `pitch` arrives gravity-relative (negative = climb, positive = dive —
		# the takeoff convention).  pitch_command_to_rotation_input() is the ONE
		# is_barrel_rolled sign flip, converting it into the rotation frame so a
		# leftward/inverted plane rotates toward the commanded attitude instead
		# of away from it.  Callers must NOT pre-flip the command (that
		# double-flip previously made leftward AI planes pitch into the ground).
		# Clamp first so every AI state's command is bounded to the same valid
		# pitch range regardless of travel direction, then apply the single
		# gravity→rotation conversion — pitch is treated relative to the horizon
		# (heading) identically for upright and inverted planes.
		var gp_pitch: float = clampf(pitch, -1.0, 1.0) * avatar.control_effectiveness
		var input_pitch: float = avatar.pitch_command_to_rotation_input(gp_pitch)
		var model_params = avatar.model_params
		var eff_rot_speed: float = model_params.get("rotation_speed", 5.0) * (1.0 - avatar.damage.damage_percent * 0.4)
		var pre_av := avatar.angular_velocity
		var pre_pitch := avatar.pitch_angle
		avatar.angular_velocity = move_toward(
			avatar.angular_velocity, input_pitch * eff_rot_speed, model_params.get("rotation_inertia", 4.0) * dt)
		avatar.pitch_angle += avatar.angular_velocity * dt
		rotation = avatar.pitch_angle
		# if absf(pre_av) > 0.01 or absf(avatar.angular_velocity) > 0.01 or absf(pre_pitch - avatar.pitch_angle) > 0.001:
		# 	DLog.info("ai_pitch_integrate", {
		# 		"avatar_id": avatar_id,
		# 		"pitch_in": snapped(pitch, 4),
		# 		"input_pitch": snapped(input_pitch, 4),
		# 		"pre_av": snapped(pre_av, 4),
		# 		"post_av": snapped(avatar.angular_velocity, 4),
		# 		"pre_pitch": snapped(pre_pitch, 4),
		# 		"post_pitch": snapped(avatar.pitch_angle, 4),
		# 		"delta_pitch": snapped(avatar.pitch_angle - pre_pitch, 4),
		# 		"dt": snapped(dt, 6),
		# 	})

###############################################################################
# FLIP / BARREL ROLL (visual tween)
###############################################################################

var _flip_tween: Tween = null

## Grounded roll input (original Sopwith behaviour): a plane on the ground
## cannot barrel-roll, so the roll key reverses its direction of travel.  The
## reversal reuses the airborne flip tween verbatim — same duration, easing,
## scale.y lerp and arc.  The only difference is the state handover: the
## physical direction change (velocity, heading, is_barrel_rolled) fires
## ATOMICALLY at the tween midpoint instead of the airborne flag-only toggle.
## Heading and flag must never disagree for even one frame: the tilt-crash
## check measures pitch_angle against level_rotation(), so a half-applied
## reversal reads as ~180° tilt and instantly destroys the plane.
func _start_ground_reversal(avatar: AvatarData) -> void:
	_start_flip(avatar)
	avatar.flip_is_ground_reversal = true

## Atomic midpoint handover for a grounded reversal.  Called exactly once from
## _set_flip_frame when the tween crosses t = 0.5.  Must NOT touch $Visual
## here — the tween owns it until completion.
func _apply_ground_reversal_state(avatar: AvatarData) -> void:
	velocity.x = -velocity.x
	# Carry the gravity-frame pitch across the mirror: a plane parked tilted
	# (nose-down on a slope, tipped back on its tail) keeps that tilt mirrored
	# in the new direction.  Snapping to perfectly level here would jump the
	# attitude and can exceed max_landing_tilt — destroying the very plane
	# this atomic handover exists to protect.
	var ts_old := avatar.travel_sign()
	var grav   := avatar.gravity_pitch()
	avatar.is_barrel_rolled = not avatar.is_barrel_rolled
	avatar.pitch_angle      = wrapf(avatar.level_rotation() - grav / ts_old, -PI, PI)
	avatar.angular_velocity = 0.0
	rotation                = avatar.pitch_angle
	_update_ground_ray(avatar)

## Shared reset of the per-flip bookkeeping fields.
func _reset_flip_state(avatar: AvatarData) -> void:
	avatar.is_flipping             = false
	avatar.flip_progress           = 0.0
	avatar.flip_is_ground_reversal = false
	avatar.flip_halfway_applied    = false

## Kill any in-flight flip tween AND restore the state it was mutating.
## Killing the tween alone leaves `is_flipping` stuck true and the Visual node
## frozen at an intermediate scale/arc offset; callers destroying, resetting,
## or teleporting the plane need a clean attitude immediately.  Idempotent.
func _cancel_flip(avatar: AvatarData) -> void:
	_kill_flip_tween()
	if avatar == null:
		return
	_reset_flip_state(avatar)
	avatar.flip_direction = 0
	reset_visual_transform(avatar)

func _start_flip(avatar: AvatarData) -> void:
	if _flip_tween and _flip_tween.is_valid():
		_flip_tween.kill()
	avatar.is_flipping   = true
	avatar.flip_progress = 0.0
	avatar.flip_direction = int(avatar.travel_sign())
	_flip_tween = create_tween()
	_flip_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_flip_tween.tween_method(_update_flip.bind(avatar), 0.0, 1.0, FLIP_DURATION)
	_flip_tween.finished.connect(_on_flip_completed.bind(avatar))

func _release_flip(avatar: AvatarData) -> void:
	if avatar.flip_progress < 0.5:
		var prog := avatar.flip_progress
		if _flip_tween and _flip_tween.is_valid():
			_flip_tween.kill()
		_flip_tween = create_tween()
		_flip_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		_flip_tween.tween_method(_update_flip.bind(avatar), prog, 0.0, FLIP_DURATION * prog)
		_flip_tween.finished.connect(_on_flip_cancelled.bind(avatar))
	else:
		if _flip_tween and _flip_tween.is_valid():
			_flip_tween.kill()
		_set_flip_frame(avatar, 1.0)
		_on_flip_completed(avatar)

func _update_flip(progress: float, avatar: AvatarData) -> void:
	avatar.flip_progress = progress
	_set_flip_frame(avatar, progress)

## One frame of the ACTIVE flip mode — visuals plus the midpoint state
## handover — shared by the tween, the early-release snap, and rewind so every
## path through a flip behaves identically.  Handover runs BEFORE the visual
## update so the t = 0.5 frame renders the post-handover pose.
func _set_flip_frame(avatar: AvatarData, t: float) -> void:
	if t >= 0.5 and not avatar.flip_halfway_applied:
		avatar.flip_halfway_applied = true
		if avatar.flip_is_ground_reversal:
			_apply_ground_reversal_state(avatar)
		elif _is_on_ground_for_roll(avatar):
			# SAFETY NET: an air-mode flip whose plane is actually ON the
			# ground at midpoint (tilted/bouncing rollout defeated the
			# keypress-time probes).  The airborne bare flag-toggle against
			# the stale heading reads as ~180° tilt and destroys the plane;
			# the atomic mirrored handover keeps heading and flag consistent.
			_apply_ground_reversal_state(avatar)
		else:
			avatar.is_barrel_rolled = (avatar.flip_direction == 1)
	if avatar.flip_is_ground_reversal:
		_apply_ground_reversal_transform(avatar, t)
	else:
		_apply_flip_transform(avatar, t)

## Airborne barrel roll: somersault on Y with a small hop arc.
func _apply_flip_transform(avatar: AvatarData, t: float) -> void:
	var visual    := $Visual
	var start     := 1.0 if avatar.flip_direction == 1 else -1.0
	visual.scale.y     = lerp(start, -start, t)
	visual.position.y  = -sin(t * PI) * FLIP_ARC_HEIGHT

## Grounded reversal: horizontal mirror.  First half squashes the sprite to
## zero width; at that invisible instant the midpoint handover rotates the
## BODY 180° and flips the vertical mirror, then the second half regrows the
## sprite already facing the new direction.  The mirror phase derives from
## flip_direction (+1 upright start, -1 inverted start) so the end pose is
## exactly what reset_visual_transform() produces for the new attitude.
## No hop arc: the plane pivots in place.
func _apply_ground_reversal_transform(avatar: AvatarData, t: float) -> void:
	var visual   := $Visual
	var s        := 1.0 if avatar.flip_direction == 1 else -1.0
	visual.scale.x    = absf(2.0 * t - 1.0)
	visual.scale.y    = s if t < 0.5 else -s
	visual.position.y = 0.0

func _on_flip_completed(avatar: AvatarData) -> void:
	_reset_flip_state(avatar)
	avatar.is_barrel_rolled   = (avatar.flip_direction == 1)
	_update_ground_ray(avatar)
	_flip_tween = null

func _on_flip_cancelled(avatar: AvatarData) -> void:
	_reset_flip_state(avatar)
	_flip_tween = null

###############################################################################
# OBSTACLE COLLISION
###############################################################################

func _get_collider_poly_bounds(collider: Node) -> Dictionary:
	var result := {"min_y": 0.0, "max_y": 0.0, "min_x": 0.0, "max_x": 0.0, "has_poly": false}
	if collider.has_method("get_polygon_bounds"):
		var bounds := collider.get_polygon_bounds() as Dictionary
		result["min_y"] = bounds["min_y"]
		result["max_y"] = bounds["max_y"]
		result["min_x"] = bounds["min_x"]
		result["max_x"] = bounds["max_x"]
		result["has_poly"] = true
		return result
	for ch in collider.get_children():
		if ch is CollisionPolygon2D:
			var p_min_y := INF
			var p_max_y := -INF
			var p_min_x := INF
			var p_max_x := -INF
			for pt in (ch as CollisionPolygon2D).polygon:
				p_min_y = min(p_min_y, pt.y)
				p_max_y = max(p_max_y, pt.y)
				p_min_x = min(p_min_x, pt.x)
				p_max_x = max(p_max_x, pt.x)
			result["min_y"] = p_min_y
			result["max_y"] = p_max_y
			result["min_x"] = p_min_x
			result["max_x"] = p_max_x
			result["has_poly"] = true
			return result
	return result

func _check_obstacle_collision(avatar: AvatarData) -> void:
	# NOTE: Do NOT gate this on a minimum speed.  A freshly-spawned or parked
	# plane sitting still is not invincible — collision processing still runs.
	# What keeps a correctly-spawned grounded plane from being destroyed is the
	# impact-speed classification below (and in each obstacle's
	# get_collision_response): a contact below the plane's soft-landing speed
	# deals zero damage, so a plane resting on the ground/runway is safe by
	# virtue of its low impact speed, not by an artificial "hasn't moved yet"
	# exemption that made planes indestructible until they started moving.
	# Intent speed, not solver output (see commanded_vel).
	var speed := _intent_velocity(self, avatar).length()
	var parent := get_parent()
	if not parent:
		return

	_debug_check_obstacle_forensics(avatar, speed, parent)

	var model_params = avatar.model_params
	var soft_landing: float = model_params.get("soft_landing_vperp", 100.0)
	var hard_landing: float = model_params.get("hard_landing_vperp", 200.0)

	for child in parent.get_children():
		if child == self:
			continue
		if child.has_method("get_collision_response"):
			# Ground vehicles (tanks, is_aerodynamic() == false) roll straight
			# through buildings and wrecks: no damage to the tank and none to
			# the structure.  They engage hostile buildings with their weapons.
			if not avatar.is_aerodynamic() and ("target_type" in child or child.is_in_group("wreck") or child.is_in_group("obstacle")):
				continue
			var collision_result = child.get_collision_response(self, avatar, speed, soft_landing, hard_landing)
			if collision_result.hit:
				var actual_damage: float = collision_result.damage * 100.0
				if collision_result.is_midair or avatar.flight_state == FlightState.FALLING:
					_apply_impact(avatar, actual_damage, child,
						actual_damage * 0.5, actual_damage >= 100.0)
				elif not collision_result.is_midair and avatar.flight_state != FlightState.FALLING:
					if child.has_method("take_damage"):
						child.take_damage(actual_damage * 0.5, self)
					if collision_result.damage >= 1.0:
						_on_avatar_crashed(avatar)
					else:
						take_damage(avatar, actual_damage, child)
				return
		if child is RigidBody2D and child.has_method("get_primary_entity") and not child.has_method("get_collision_response"):
			var dist := global_position.distance_to(child.global_position)
			if dist < PLANE_PROXIMITY_RADIUS and dist > 0.01:
				# Approaching component only: receding aircraft are bouncing
				# apart, not colliding.  Intent velocities, not solver output
				# (see commanded_vel): pressed-together bodies report ~0.
				var axis: Vector2 = (child.global_position - global_position) / dist
				var my_vel := _intent_velocity(self, avatar)
				var child_av: AvatarData = child.get_primary_entity()
				var other_vel := _intent_velocity(child, child_av)
				var closing: float = maxf(0.0, (my_vel - other_vel).dot(axis))
				var dmg := midair_impact_damage(closing, pixels_per_meter,
					impact_mass_kg(avatar), impact_mass_kg(child_av))
				if dmg > 0.0:
					_apply_impact(avatar, dmg, child, dmg * 0.5, dmg >= 100.0)
				return

###############################################################################
# WEAPONS
###############################################################################

func _handle_weapons(avatar: AvatarData, delta: float) -> void:
	avatar.gun_timer  = maxf(0.0, avatar.gun_timer  - delta)
	avatar.bomb_timer = maxf(0.0, avatar.bomb_timer - delta)

	if not is_player_controlled:
		return
	if Input.is_action_pressed("fire") and avatar.gun_timer <= 0.0:
		fire_gun(avatar)
	if Input.is_action_just_pressed("bomb") and avatar.bomb_timer <= 0.0:
		drop_bomb(avatar)

func fire_gun(avatar: AvatarData) -> void:
	if avatar.ammo <= 0:
		return
	avatar.gun_timer = gun_cooldown
	avatar.ammo     -= 1
	if GameManager and is_player_controlled:
		GameManager.ammo_changed.emit(avatar.id, avatar.ammo)

	var model_params = avatar.model_params
	var base_offset: Vector2 = avatar.bullet_spawn_offset
	base_offset.y *= avatar.travel_sign()   # flip the gun offset when inverted
	var spawn_off: Vector2 = base_offset.rotated(avatar.pitch_angle)
	var spawn_pos: Vector2 = global_position + spawn_off
	var direction: Vector2 = Vector2(cos(avatar.pitch_angle), sin(avatar.pitch_angle))

	var target = _find_nearest_enemy(avatar)
	var range_pct: float = 0.5
	if target:
		var dist: float = spawn_pos.distance_to(target.global_position)
		avatar.last_shot_range = minf(dist, avatar.max_bullet_range)
		range_pct = avatar.last_shot_range / avatar.max_bullet_range

	var bullet = BULLET_SCENE.instantiate()
	bullet.speed           = bullet_speed
	bullet.global_position = spawn_pos
	bullet.rotation        = avatar.pitch_angle
	bullet.assign_owner(self, range_pct)
	get_parent().add_child(bullet)
	fired_bullet.emit(spawn_pos, direction, bullet_speed, self, range_pct)
	if SoundManager:
		SoundManager.play_sfx(SoundManager.SoundEvent.GUN)

func drop_bomb(avatar: AvatarData) -> void:
	if avatar.bombs_disabled or avatar.bombs <= 0:
		return
	avatar.bomb_timer = bomb_cooldown
	avatar.bombs     -= 1
	if GameManager and is_player_controlled:
		GameManager.bombs_changed.emit(avatar.id, avatar.bombs)

	var model_params = avatar.model_params
	var base_offset: Vector2 = avatar.bomb_spawn_offset
	base_offset.y *= avatar.travel_sign()   # flip the bomb offset when inverted
	var spawn_off: Vector2 = base_offset.rotated(avatar.pitch_angle)
	var spawn_pos: Vector2 = global_position + spawn_off

	var bomb = BOMB_SCENE.instantiate()
	bomb.global_position = spawn_pos
	bomb.rotation        = avatar.pitch_angle
	bomb.initialize(self, velocity)
	get_parent().add_child(bomb)
	dropped_bomb.emit(spawn_pos, velocity, self)
	_active_bombs.append(bomb)
	bomb.tree_exited.connect(_on_dropped_bomb_exited.bind(bomb))


func _on_dropped_bomb_exited(bomb: Node) -> void:
	var idx := _active_bombs.find(bomb)
	if idx >= 0:
		_active_bombs.remove_at(idx)


func _find_nearest_enemy(avatar: AvatarData) -> Node:
	var nearest: Node = null
	var min_dist := INF
	for child in get_parent().get_children():
		if child == self:
			continue
		var other_av: AvatarData = child.get_primary_entity() \
		              if child.has_method("get_primary_entity") else null
		if other_av and avatar.is_hostile_to(other_av):
			var dist := global_position.distance_to(child.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest  = child
	return nearest

###############################################################################
# FUEL
###############################################################################

func _check_fuel_consumption(avatar: AvatarData, delta: float) -> void:
	if avatar.unlimited_fuel_ammo:
		return
	if avatar.fuel <= 0.0:
		avatar.throttle        = 0.0
		avatar.throttle_target = 0.0
		# Fuel-starvation plume shares the unified damage-FX builder (small
		# white smoke).  It morphs into real damage smoke via
		# _sync_damage_particles once damage arrives, and is cleared on
		# refuel-teleport / reset like all damage FX.
		if avatar.damage_fx == null and avatar.damage.damage_state == DamageData.DamageState.INTACT and EffectManager:
			avatar.damage_fx = EffectManager.attach_damage_fx(
				self, EffectManager.make_puff_profile(10, true, 1.0, Vector2(-15, 5)))
		return

	if avatar.throttle > 0.0 or avatar.damage.damage_state >= DamageData.DamageState.MODERATE:
		var loss := avatar.throttle * delta * 0.8
		match avatar.damage.damage_state:
			DamageData.DamageState.SEVERE:   loss *= 6.0
			DamageData.DamageState.MODERATE: loss *= 2.0
		avatar.fuel = maxf(0.0, avatar.fuel - loss)
		if GameManager and is_player_controlled:
			GameManager.fuel_changed.emit(avatar.id, avatar.fuel)

	if SoundManager and is_player_controlled:
		SoundManager.set_engine_rpm(avatar.throttle)

###############################################################################
# HOME BASE REFUEL & REPAIR
###############################################################################

func _check_home_refuel(avatar: AvatarData, delta: float) -> void:
	# Ground vehicles never refuel/repair at a base (and must not teleport to
	# the spawn point when they drive over their home strip).
	if not avatar.is_aerodynamic():
		return
	if velocity.length() > 50 or (not is_grounded(avatar)):
		return
	var hb := _get_homebase(avatar)
	if not hb:
		return
	## Team check: can only refuel at a friendly base.
	if avatar.team != hb.team:
		return
	if abs(global_position.x - hb.home_base_x) > hb.home_base_width:
		return

	## Cooldown prevents teleport loop when taxiing into homebase.
	if avatar.refuel_cooldown > 0.0:
		avatar.refuel_cooldown -= delta

	var max_bombs = avatar.model_params.get("max_bombs", 0)
	if avatar.ammo == MAX_AMMO and avatar.bombs == max_bombs and avatar.fuel == 100:
		return

	var randomi := randi() % 100
	## Base percentage chances for a repair/reload (spec).  A homebase
	## missing the relevant structure halves that chance: no hangar ->
	## slower repairs, no fuel depot -> slower refuel, no ammo depot
	## -> slower rearm.  The registry is the single source of truth for
	## which structures this homebase still has standing.
	var hb_id := avatar.homebase_id
	var has_hangar := true
	var has_fuel_depot := true
	var has_ammo_depot := true
	if BuildingRegistry:
		has_hangar = BuildingRegistry.has_hangar(hb_id)
		has_fuel_depot = BuildingRegistry.has_fuel_depot(hb_id)
		has_ammo_depot = BuildingRegistry.has_ammo_depot(hb_id)
	var hangar_factor := 30 if has_hangar else 15
	var fuel_factor := 70 if has_fuel_depot else 35
	var ammo_factor := 60 if has_ammo_depot else 30

	## Repair damage on landing at home.
	if randomi <= hangar_factor and avatar.damage.damage_state != DamageData.DamageState.INTACT:
		avatar.damage.repair(false, 0.01)
		_refresh_damage_modifiers(avatar)

	avatar.refuel_timer += delta
	if avatar.refuel_timer >= 0.5:
		var old_ammo  := avatar.ammo
		var old_bombs := avatar.bombs
		var old_fuel  := avatar.fuel
		avatar.refuel_timer = 0.0

		if randomi <= ammo_factor / 2:
			avatar.ammo = minf(MAX_AMMO, avatar.ammo + 12.0 + int(delta * 50.0))
		if randomi <= fuel_factor:
			avatar.fuel = minf(100.0, avatar.fuel + 6.0 + int(delta * 50.0))
		if randomi <= ammo_factor:
			avatar.bombs = mini(max_bombs, avatar.bombs + 1)

		if GameManager and is_player_controlled:
			if avatar.ammo  != old_ammo:  GameManager.ammo_changed.emit(avatar.id, avatar.ammo)
			if avatar.bombs != old_bombs: GameManager.bombs_changed.emit(avatar.id, avatar.bombs)
			if avatar.fuel  != old_fuel:  GameManager.fuel_changed.emit(avatar.id, avatar.fuel)

		## Teleport to spawn if there's no cooldown
		if avatar.throttle == 0.0 and (avatar.ammo > old_ammo or avatar.bombs > old_bombs or avatar.fuel > old_fuel):
			if avatar.refuel_cooldown <= 0.0:
				avatar.refuel_cooldown = 10.0
				_perform_teleport_landing(avatar)

###############################################################################
# DAMAGE
###############################################################################

func take_damage(avatar_or_amount, amount_or_attacker = null, _attacker = null) -> void:
	## Accepts both (avatar, amount, attacker) and legacy (amount, attacker) forms.
	var avatar: AvatarData
	var amount: float
	if avatar_or_amount is AvatarData:
		avatar = avatar_or_amount
		amount = float(amount_or_attacker)
	else:
		avatar = get_avatar_data(0)
		amount = float(avatar_or_amount)
		_attacker = amount_or_attacker

	if not avatar or avatar.flight_state == FlightState.CRASHED:
		return

	## Score: if a player caused the damage to a non-player plane, add score.
	## Scored in raw damage points (100 = a full plane).  Cap the award at the
	## remaining health so overkill — e.g. a single bomb dealing ~270 raw damage —
	## can never push a plane's total reward past 100 points.
	if _attacker and not _attacker is AvatarData and _attacker.is_in_group("player") \
			and not is_in_group("player"):
		if GameManager:
			var remaining: float = (1.0 - avatar.damage.damage_percent) * 100.0
			var award: int = int(minf(amount, remaining))
			if award > 0:
				GameManager.add_score(0, award)

	## DamageData.take_damage() already reassigns `damage_state` and emits
	## `damage_state_changed` — re-deriving it here is redundant.
	avatar.damage.take_damage(amount / 100.0)
	_refresh_damage_modifiers(avatar)

	if avatar.damage.damage_state == DamageData.DamageState.SEVERE:
		avatar.set_flight_state(FlightState.DAMAGED)

	if avatar.damage.damage_state == DamageData.DamageState.DESTROYED:
		avatar.set_flight_state(FlightState.FALLING)

###############################################################################
# PARTICLE HELPERS  (delegated to EffectManager)
###############################################################################

func _on_avatar_damage_state_changed(_from: DamageData.DamageState, _to: DamageData.DamageState, avatar: AvatarData) -> void:
	if _to == DamageData.DamageState.DESTROYED:
		SoundManager.set_engine_rpm(randf() * 0.2)
		## A destroyed plane must not keep animating a barrel roll through its
		## death tumble — cancel the tween and snap the visual to its attitude.
		_cancel_flip(avatar)
	_sync_damage_particles(avatar)

## Sync particle effects to current damage state.  Single call into the
## unified EffectManager mapping: smoke trails from the tail, wreck fire
## burns at the engine (identical to a fresh tank wreck).
func _sync_damage_particles(avatar: AvatarData) -> void:
	if not EffectManager:
		return
	var offset := Vector2(-15, 5)
	if avatar.damage.damage_state >= DamageData.DamageState.SEVERE:
		offset = Vector2(15, -5)
	avatar.damage_fx = EffectManager.sync_damage_fx(
		self, avatar.damage_fx, avatar.damage.damage_state,
		avatar.damage.damage_percent, 1.0, offset)

###############################################################################
# CRASH & SPIN-OUT
###############################################################################

func _start_spinning_out(avatar: AvatarData) -> void:
	avatar.throttle             = 0.0
	avatar.throttle_target      = 0.0
	avatar.set_flight_state(FlightState.FALLING)

func _on_avatar_crashed(avatar: AvatarData) -> void:
	## Stop any barrel-roll tween the moment we crash so it cannot corrupt the
	## respawned plane's inverted/visual state after the crash delay.
	_cancel_flip(avatar)

	if _crash_processed.has(avatar.id):
		return

	DLog.crash_guard(avatar.id, "_crash_processed", {
		"px": snapped(global_position.x, 0.1),
		"py": snapped(global_position.y, 0.1),
		"vx": snapped(velocity.x, 0.1),
		"vy": snapped(velocity.y, 0.1),
		"ground_y": snapped(_ground_y(global_position.x), 0.1),
	})

	_crash_processed[avatar.id] = true
	avatar.set_flight_state(FlightState.CRASHED)
	## Destruction-by-impact must force the damage band to DESTROYED regardless
	## of `damage_percent` (the setter only tracks the enum, not the band).
	avatar.damage.damage_state   = DamageData.DamageState.DESTROYED
	avatar.is_airborne           = false
	if GameManager and is_player_controlled:
		GameManager.destroy_player(avatar.id)
	if is_player_controlled and SoundManager:
		SoundManager.stop_engine()

	## Fire/smoke stays attached to the wreck through its fall, impact, and
	## time on the ground — it is cleared only on respawn (AvatarData.reset).
	## Sync to DESTROYED so even an undamaged plane burns as a wreck; the
	## lingering burn at the impact point is reinforced by the world-space
	## crash effects spawned just below.
	_sync_damage_particles(avatar)

	## Single, consolidated crash-effect path for EVERY destructive end-state
	## (mid-air shoot-down, terrain impact, obstacle/building collision,
	## force_crash).  Effects, sound and screen-shake all scale with the plane's
	## impact speed so a gentle cartwheel and a 200 km/h nose-dive read
	## differently and physically.  This is the one place destruction visuals
	## are produced — AI and player planes therefore look and sound identical.
	var gc := _get_ground_contact(avatar)
	var is_midair := not gc.is_grounded and avatar.flight_state != FlightState.LANDED
	_spawn_crash_effects(avatar, is_midair)

	## Emit the destruction event for any external bookkeeping.  Respawn timing
	## is decoupled and only starts once the wreck reaches the ground (see
	## _integrate_crash_forces -> crashed_landed), so a plane destroyed in
	## mid-air tumbles to the surface before any respawn is scheduled.
	crashed.emit(is_midair)

###############################################################################
# VISUAL HELPERS
###############################################################################

func reset_visual_transform(avatar: AvatarData = null) -> void:
	if avatar == null:
		avatar = get_primary_entity()
	var visual    := $Visual
	visual.scale    = Vector2.ONE
	visual.rotation = 0.0
	visual.position = Vector2.ZERO
	if avatar and avatar.travel_sign() < 0.0:
		visual.scale.y = -1.0
	if avatar:
		_update_ground_ray(avatar)

func update_visual_representation(avatar: AvatarData) -> void:
	if not has_node("Visual"):
		return

	var visual := $Visual

	# Update sprite based on model
	if visual.has_node("Sprite2D"):
		var sprite: Sprite2D = $Visual/Sprite2D
		var model_params = avatar.model_params
		sprite.texture = load(_get_svg_path_from_params(model_params))
		sprite.scale = model_params.get("visual_scale", Vector2.ONE)

	# Update visual elements based on damage state
	match avatar.damage.damage_state:
		DamageData.DamageState.DESTROYED, DamageData.DamageState.SEVERE:
			# Add fire effect for heavily damaged planes
			pass
		DamageData.DamageState.MODERATE:
			# Add smoke effect
			pass
		DamageData.DamageState.LIGHT:
			# Light smoke effect
			pass
		_:
			# Clear all effects
			pass

func _update_ground_ray(avatar: AvatarData) -> void:
	var ground_ray: RayCast2D = $GroundRay if has_node("GroundRay") else null
	if ground_ray:
		var base_offset: float = 26.0
		var dir_sign := avatar.travel_sign()
		if not avatar.is_aerodynamic():
			dir_sign = 1.0
		ground_ray.target_position = Vector2(0, base_offset * dir_sign)

## Derive a normalised impact intensity + effect energy from the plane's speed
## at the moment of destruction.  Force scales linearly with impact speed
## relative to the model's hard-landing threshold (px/s), clamped so even a
## gentle crash shows some effect while a high-speed impact saturates.  Using
## kinetic energy (½·m·v²) would over-saturate instantly, so we scale on speed
## against a meaningful reference — a real, physical proxy for how hard the
## airframe hits.
func _compute_crash_intensity(avatar: AvatarData) -> Dictionary:
	var speed: float = velocity.length()
	# Reference impact speed: a typical crash comes in well above the soft/hard
	# *vertical* landing thresholds, so scaling on those directly saturates every
	# real crash to max.  Use a reference near a normal impact (~3× the hard
	# vertical-landing threshold) so a gentle cartwheel and a full-speed dive
	# actually read differently while still being physically grounded.
	var hard: float = avatar.model_params.get("hard_landing_vperp", 80.0)
	var ref_speed: float = hard * 3.0
	var force_ratio: float = clampf(speed / ref_speed, 0.25, 3.0)
	var energy: float = clampf(40.0 + force_ratio * 80.0, 40.0, 280.0)
	return {"force_ratio": force_ratio, "energy": energy}

## Single consolidated crash-effect path for every destructive end-state.
## Sequence is physically motivated: a bright blast + initial burst of fire at
## the instant of impact, smoke boiling up in its wake, and debris flung only
## when the impact is forceful enough to shatter the airframe.  Grounded wrecks
## keep a lingering open fire + smoke until they burn out.  Sound and screen
## shake scale with the same impact force so the audio matches the visuals.
func _spawn_crash_effects(avatar: AvatarData, is_midair: bool) -> void:
	var intensity := _compute_crash_intensity(avatar)
	var force_ratio: float = intensity["force_ratio"]
	var energy: float = intensity["energy"]

	var pos := global_position
	if not is_midair:
		# Ground crash: keep the blast at the terrain surface so it reads like a
		# ground wreck rather than spawning buried under the collision shape.
		var surface_y := _ground_y(pos.x) - GROUND_SURFACE_OFFSET
		pos.y = min(pos.y, surface_y)

	var debris_color := get_dominant_color()
	var polygon := get_plane_polygon()

	if not EffectManager:
		return

	EffectManager.spawn_destruction_puff(pos)

	# 1. Flash + core blast, scaled with impact energy.
	var blast = EffectManager.spawn_explosion(pos, energy)
	if blast and is_instance_valid(blast):
		var s := clampf(force_ratio, 0.5, 3.0)
		blast.scale = Vector2(s, s)

	# 2. Initial burst of fire at the moment of impact (scaled with force).
	var fire_amount := int(clampf(15.0 + force_ratio * 35.0, 10, 90))
	var fire_lifetime := clampf(0.2 + force_ratio * 0.1, 0.2, 1.0)
	var fire = EffectManager.spawn_fire(pos, fire_amount, fire_lifetime)
	if fire and is_instance_valid(fire):
		var s := clampf(0.6 + force_ratio * 0.5, 0.6, 3.0)
		fire.scale = Vector2(s, s)

	# 3. Smoke boils up in the wake of the fire, then dissipates.
	var smoke_amount := int(clampf(15.0 + force_ratio * 30.0, 10, 80))
	var smoke_lifetime := clampf(0.5 + force_ratio * 0.3, 0.8, 2.0)
	EffectManager.spawn_black_smoke(pos, smoke_amount, smoke_lifetime)

	# 4. Debris — only thrown when the impact is forceful enough to shatter the
	#    airframe; count and spread scale with how hard it hit.
	if force_ratio >= 0.9:
		var debris_count := int(clampf((force_ratio - 0.6) * 14.0, 4, 30))
		EffectManager.spawn_explosion_debris(pos, energy, debris_count, debris_color, polygon)

	# 5. Grounded wrecks keep burning (open fire + smoke) until they burn out.
	if not is_midair:
		EffectManager.spawn_open_fire_with_smoke(pos, 6.0, fire_amount, smoke_amount)

	# 6. Explosion sound scales with the same impact force.  (Screen shake is
	#    already driven, scaled by energy, inside EffectManager.spawn_explosion,
	#    so we don't add a second one here.)
	if SoundManager:
		var vol_db := clampf(force_ratio * 5.0, -3.0, 9.0)
		SoundManager.play_sfx(SoundManager.SoundEvent.EXPLOSION, {"volume_db": vol_db})

## Public backward-compatible entry point.  _on_avatar_crashed is the real
## caller; this lets any external node request the same scaled crash effect.
func create_explosion(is_midair: bool = false) -> void:
	var avatar := get_primary_entity()
	if not avatar:
		return
	_spawn_crash_effects(avatar, is_midair)

func get_plane_polygon() -> PackedVector2Array:
	var model_params = get_primary_entity().model_params
	var scale = model_params.get("visual_scale", Vector2.ONE)
	return PackedVector2Array([
		Vector2(20 * scale.x, 0), Vector2(10 * scale.x, -4 * scale.y),
		Vector2(-15 * scale.x, -4 * scale.y), Vector2(-20 * scale.x, 0),
		Vector2(-15 * scale.x, 4 * scale.y), Vector2(10 * scale.x, 4 * scale.y)
	])

func get_dominant_color() -> Color:
	var avatar := get_primary_entity()
	if avatar:
		return avatar.model_params.get("color", Color(0.36, 0.32, 0.18))
	return Color(0.36, 0.32, 0.18)

###############################################################################
# ENTITY CREATION UTILITIES
###############################################################################

## Create a new entity with specified model and faction
func create_entity(faction: Faction, team: Team, model: String = "",
		position: Vector2 = Vector2.ZERO, rotation: float = 0.0) -> int:
	var entity_id = _avatars.keys().size() if _avatars.keys().size() > 0 else 0

	var avatar := AvatarData.new()
	avatar.id = entity_id
	avatar.faction = faction
	avatar.team = team
	avatar.homebase_id = 0
	if GameManager:
		GameManager.get_player_data(avatar.id).is_player = (entity_id == 0)

	# Set plane model - use faction default if not specified
	if model == "":
		model = get_default_plane_model(faction)
	avatar.plane_model = model
	avatar.update_model_params()

	# Set initial position and rotation
	avatar.pitch_angle = rotation
	if position != Vector2.ZERO:
		global_position = position
		rotation = rotation

	_avatars[entity_id] = avatar
	return entity_id

## Quick spawn for testing - creates a German Fokker or British Camel
func spawn_german_enemy(position: Vector2 = Vector2.ZERO, rotation: float = 0.0) -> int:
	return create_entity(Faction.GERMAN, Team.ENEMY, "fokker_d7", position, rotation)

func spawn_british_ally(position: Vector2 = Vector2.ZERO, rotation: float = 0.0) -> int:
	return create_entity(Faction.BRITISH, Team.ALLIED, "sopwith_camel", position, rotation)

## Configure a homebase with specific faction and model
func setup_faction_homebase(id: int, x: float, width: float, spawn_pos: Vector2,
		spawn_rot: float, faction: Faction) -> void:
	var player_faction_str := GameManager.player_faction if GameManager else "British"
	var player_faction_enum := Faction.BRITISH
	match player_faction_str:
		"German": player_faction_enum = Faction.GERMAN
		"French": player_faction_enum = Faction.FRENCH
	var team: Team = Team.ALLIED if faction == player_faction_enum else Team.ENEMY
	setup_homebase(id, x, width, spawn_pos, spawn_rot, team)
	_homebases[id].faction = faction

	# Set default model for any entities spawned at this homebase
	for avatar_id in _avatars:
		var avatar: AvatarData = _avatars[avatar_id]
		if avatar.homebase_id == id:
			avatar.plane_model = get_default_plane_model(faction)
			avatar.update_model_params()
			avatar.faction = faction
			avatar.team = team

## Re-apply plane model from the avatar's assigned homebase faction.
## Used on respawn so the homebase drives the model, faction, team, and sprite.
func apply_homebase_model(avatar: AvatarData) -> void:
	var hb := _get_homebase(avatar)
	if not hb:
		push_warning("apply_homebase_model: no homebase for avatar %d (homebase_id=%d)" % [avatar.id, avatar.homebase_id])
		return
	var default_model := get_default_plane_model(hb.faction)
	assign_plane_model(avatar, default_model)

###############################################################################
# RESET & RESPAWN
###############################################################################

func _kill_flip_tween() -> void:
	if _flip_tween and _flip_tween.is_valid():
		_flip_tween.kill()
	_flip_tween = null

func reset_flight_state(avatar_id: int = 0) -> void:
	var avatar := get_avatar_data(avatar_id)
	## Any in-flight barrel-roll tween must be cancelled before reset(), otherwise
	## its finished/cancelled callbacks fire after respawn and re-write
	## avatar.is_barrel_rolled / visual.scale.y, leaving the plane rotated off-axis.
	_cancel_flip(avatar)
	if avatar:
		avatar.reset()
		_crash_processed.erase(avatar_id)
		_respawn_queued.erase(avatar_id)
		_update_ground_ray(avatar)
		if is_player_controlled and SoundManager:
			SoundManager.start_engine()
			SoundManager.set_engine_rpm(0.0)
	reset_visual_transform()

func force_crash() -> void:
	var avatar: AvatarData = get_primary_entity()
	if not avatar:
		return
	if avatar.flight_state != FlightState.CRASHED:
		avatar.damage.take_damage(1.0)
		_refresh_damage_modifiers(avatar)
		_start_spinning_out(avatar)
		DLog.crash_enter(avatar.id, "force_crash", {
			"px": snapped(global_position.x, 0.1),
			"py": snapped(global_position.y, 0.1),
			"vx": snapped(velocity.x, 0.1),
			"vy": snapped(velocity.y, 0.1),
			"ground_y": snapped(_ground_y(global_position.x), 0.1),
		})
		_on_avatar_crashed(avatar)

func _perform_teleport_landing(avatar: AvatarData) -> void:
	_cancel_flip(avatar)
	avatar.is_barrel_rolled = false
	avatar.pitch_angle = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	var spawn_pos := get_homebase_spawn_position(avatar)
	var spawn_rot := get_homebase_spawn_rotation(avatar)
	rotation = spawn_rot
	avatar.pitch_angle = spawn_rot
	global_position = Vector2(spawn_pos.x, spawn_pos.y)
	_pending_teleport = true
	_teleport_position = spawn_pos
	_teleport_rotation = spawn_rot
	## Refuel teleport relocates the plane WITHOUT a full reset, so attached
	## damage FX rides to the spawn point with it — damage persists through
	## refuel, and repair clears the FX via the damage-state signal.
	reset_visual_transform(avatar)
	if GameManager and is_player_controlled:
		GameManager.fuel_changed.emit(avatar.id, avatar.fuel)
		GameManager.ammo_changed.emit(avatar.id, avatar.ammo)
		GameManager.bombs_changed.emit(avatar.id, avatar.bombs)
	if is_player_controlled and SoundManager:
		SoundManager.start_engine()
		SoundManager.set_engine_rpm(0.0)

###############################################################################
# FSM HELPER METHODS
## Public accessors for flight state scripts. These wrap the private methods
## so the FSM states can call them on the biplane node.
###############################################################################

func _is_stalled_check(avatar: AvatarData, gc: GroundContact) -> bool:
	return Aerodynamics.is_stalled(
		avatar.pitch_angle, velocity, gc.is_grounded,
		avatar.stall_speed_ms, pixels_per_meter, avatar.model_params)

func _is_on_homebase(avatar: AvatarData) -> bool:
	if not is_grounded(avatar):
		return false
	var hb := _get_homebase(avatar)
	if not hb:
		return false
	if avatar.team != hb.team:
		return false
	return abs(global_position.x - hb.home_base_x) <= hb.home_base_width

###############################################################################
# PUBLIC ACCESSORS
## Thin query functions. Callers should prefer reading AvatarData fields
## directly when they already hold the avatar reference.
###############################################################################

func is_grounded(avatar: AvatarData) -> bool:
	if avatar.flight_state == FlightState.LANDED:
		return true
	var ground_ray: RayCast2D = $GroundRay if has_node("GroundRay") else null
	return ground_ray.is_colliding() if ground_ray else false

func is_stalling(avatar: AvatarData) -> bool:
	return avatar.flight_state == FlightState.STALLED

func get_avatar_speed(avatar: AvatarData) -> float:
	return velocity.length()

func get_vertical_speed(_avatar: AvatarData) -> float:
	return velocity.y

func get_reliability(avatar: AvatarData) -> float:
	return avatar.reliability

func get_ammo(avatar: AvatarData) -> int:
	return avatar.ammo

func get_bombs(avatar: AvatarData) -> int:
	return avatar.bombs

func is_barrel_rolled(avatar: AvatarData) -> bool:
	return avatar.travel_sign() < 0.0 if avatar else false

func set_player(avatar: AvatarData, p: bool) -> void:
	if GameManager:
		GameManager.get_player_data(avatar.id).is_player = p

func set_game_active(active: bool) -> void:
	game_active = active

func teleport_to(pos: Vector2, rot: float = 0.0) -> void:
	global_position = pos
	rotation = rot
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_pending_teleport = true
	_teleport_position = pos
	_teleport_rotation = rot
	## Attached damage FX rides along (cleared only on respawn/reset).

func set_unlimited_fuel_ammo(avatar: AvatarData, val: bool) -> void:
	avatar.unlimited_fuel_ammo = val

func disable_bombs(avatar: AvatarData) -> void:
	avatar.bombs_disabled = true

func set_home_base(avatar: AvatarData, id: int) -> void:
	avatar.homebase_id = id

func respawn(avatar_id: int, camera_ref: Camera2D = null) -> bool:
	var avatar: AvatarData = _avatars.get(avatar_id)
	if not avatar:
		return false

	var spawn_pos := get_homebase_spawn_position(avatar)
	var spawn_rot := get_homebase_spawn_rotation(avatar)

	reset_flight_state(avatar_id)

	avatar.is_barrel_rolled = AvatarData.rotation_is_leftward(spawn_rot)
	avatar.pitch_angle = spawn_rot
	rotation = spawn_rot
	apply_homebase_model(avatar)
	reset_visual_transform(avatar)

	visible = true
	global_position = spawn_pos
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_pending_teleport = true
	_teleport_position = spawn_pos
	_teleport_rotation = spawn_rot

	game_active = true

	if is_player_controlled and camera_ref:
		camera_ref.position = Vector2(spawn_pos.x, spawn_pos.y - 250)

	return true

func do_flip(avatar: AvatarData) -> void:
	if avatar and not avatar.is_flipping:
		_start_flip(avatar)

###############################################################################
# DEBUG PHYSICS FORENSICS
###############################################################################

var _debug_frame_count: int = 0
var _debug_last_ground_contact: String = ""
var _debug_last_obstacle_key: String = ""
var _debug_ground_penetration_logged: bool = false
var _debug_printed_intro: bool = false

func _debug_forensic_log(avatar: AvatarData, tag: String, data: Dictionary) -> void:
	if not is_player_controlled:
		return
	
	if not (GameManager and GameManager.debug_hud):
		return

	if not _debug_printed_intro:
		_debug_printed_intro = true
		print("[FORENSICS] Enabled - dive crashes and obstacle hits will be logged")
	DLog.info("forensic_" + tag, data)

func _debug_check_ground_forensics(avatar: AvatarData, state: PhysicsDirectBodyState2D,
		gc: GroundContact, inp: Aerodynamics.FlightInput, out: Aerodynamics.FlightOutput,
		phase: String) -> void:
	_debug_frame_count += 1
	var velocity := state.get_linear_velocity()
	var speed := velocity.length()
	var v_perp: float = out.v_perp if out else 0.0
	var vert_speed := velocity.y

	var ground_y_at_x := _ground_y(global_position.x)
	var penetration_depth := ground_y_at_x - global_position.y

	var should_log := false
	var log_key := ""

	# H1: Penetrating terrain at speed without being marked grounded
	if penetration_depth > GROUND_TOLERANCE * 2 and speed > 50.0 and not _debug_ground_penetration_logged:
		should_log = true
		log_key = "ground_penetration"
		_debug_ground_penetration_logged = true
	elif penetration_depth <= 0.0:
		_debug_ground_penetration_logged = false

	# H1: High-speed approach to ground
	if vert_speed > 80.0 and not gc.is_grounded and penetration_depth > 0 and penetration_depth < 80.0:
		should_log = true
		log_key = "approaching_ground_fast"

	# H3: Tilt angle while grounded
	if gc.is_grounded and gc.tilt_angle > 0.0 and (gc.tilt_angle > 0.5 or _debug_frame_count % 60 == 0):
		should_log = true
		log_key = "ground_tilt"

	# Log every 300 frames while grounded for baseline
	if gc.is_grounded and _debug_frame_count % 300 == 0:
		should_log = true
		log_key = "ground_baseline"

	if should_log and log_key:
		var state_name := ""
		match avatar.flight_state:
			FlightState.FLYING: state_name = "FLYING"
			FlightState.STALLED: state_name = "STALLED"
			FlightState.FALLING: state_name = "FALLING"
			FlightState.LANDED: state_name = "LANDED"
			FlightState.DAMAGED: state_name = "DAMAGED"
			FlightState.CRASHED: state_name = "CRASHED"
			_: state_name = str(avatar.flight_state)
		_debug_forensic_log(avatar, log_key + "_" + phase, {
			"frame": _debug_frame_count,
			"phase": phase,
			"state": state_name,
			"pos_x": snapped(global_position.x, 1.0),
			"pos_y": snapped(global_position.y, 1.0),
			"ground_y": snapped(ground_y_at_x, 1.0),
			"penetration": snapped(penetration_depth, 1.0),
			"vel_x": snapped(velocity.x, 1.0),
			"vel_y": snapped(velocity.y, 1.0),
			"speed": snapped(speed, 1.0),
			"vert_speed": snapped(vert_speed, 1.0),
			"v_perp": snapped(v_perp, 1.0),
			"gc_grounded": gc.is_grounded,
			"gc_tilt_deg": snapped(rad_to_deg(gc.tilt_angle), 1.0),
			"gc_slope_deg": snapped(rad_to_deg(gc.slope_angle), 1.0),
			"pitch_deg": snapped(rad_to_deg(avatar.pitch_angle), 1.0),
			"is_barrel_rolled": avatar.travel_sign() < 0.0,
			"damage_pct": snapped(avatar.damage.damage_percent * 100.0, 1.0),
		})

func _debug_check_obstacle_forensics(avatar: AvatarData, speed: float, parent: Node) -> void:
	if speed < 5.0:
		return

	var key := "%s_%.0f" % [parent.name, speed]
	if key == _debug_last_obstacle_key:
		return
	_debug_last_obstacle_key = key

	var with_response: Array[String] = []
	var rigidbodies: Array[String] = []

	for child in parent.get_children():
		if child == self:
			continue
		if child.has_method("get_collision_response"):
			with_response.append(child.name)
		if child is RigidBody2D:
			rigidbodies.append(child.name)

# =============================================================================
# END DEBUG PHYSICS FORENSICS
# =============================================================================

# =============================================================================
# EXAMPLE USAGE
# =============================================================================

## Example of setting up different factions:
##
## func _ready():
##     # Setup British base
##     setup_faction_homebase(0, 1000, 200, Vector2(1000, 500), 0, Faction.BRITISH)
##
##     # Setup German base
##     setup_faction_homebase(1, 5000, 200, Vector2(5000, 500), PI, Faction.GERMAN)
##
##     # Spawn some enemies
##     var german_id = spawn_german_enemy(Vector2(3000, 400), 0)
##     var german2_id = spawn_german_enemy(Vector2(4000, 450), PI)
##
##     # Switch player to a different model (if available)
##     var player = get_primary_entity()
##     if switch_plane_model(player, "fokker_d7"):
##         print("Player switched to Fokker D.VII")

## Example of adding ground vehicles:
##
## func create_tank(position: Vector2, faction: Faction):
##     var avatar := AvatarData.new()
##     avatar.id = _avatars.size()
##     avatar.faction = faction
##     avatar.team = Team.ALLIED if faction == Faction.BRITISH else Team.ENEMY
##     avatar.plane_model = "tank_mark_v"  # Would need to add tank model config
##     avatar.update_model_params()  # tank model leaves wing_area == 0.0 (no lift)
##     avatar.pitch_angle = 0  # Ground vehicles don't pitch
##     global_position = position
##     _avatars[avatar.id] = avatar

func switch_plane_model(avatar: AvatarData, new_model: String) -> bool:
	if not get_plane_models().has(new_model):
		push_error("Unknown plane model: %s" % new_model)
		return false

	avatar.plane_model = new_model
	avatar.update_model_params()

	# Update visual representation
	if GameManager and is_player_controlled and has_node("Visual"):
		update_visual_representation(avatar)

	# Emit model changed event if needed
	if GameManager:
		GameManager.model_changed.emit(avatar.id, new_model)

	return true

func get_available_models() -> Array:
	var models = []
	var plane_models = Biplane.get_plane_models()
	for key in plane_models.keys():
		models.append({
			"id": key,
			"name": plane_models[key].get("name", key),
			"faction": plane_models[key].get("faction", "neutral")
		})
	return models

# =============================================================================
# PUBLIC API DOCUMENTATION
# =============================================================================

## Entity Creation:
##   create_entity(faction, team, model, position, rotation) - Creates new entity
##   spawn_german_enemy(position, rotation) - Quick German enemy spawn
##   spawn_british_ally(position, rotation) - Quick British ally spawn
##   setup_faction_homebase(id, x, width, spawn_pos, spawn_rot, faction) - Setup faction base
##
## Model Management:
##   assign_plane_model(avatar, model) - Assign specific model to entity
##   switch_plane_model(avatar, new_model) - Switch entity's model dynamically
##   get_default_plane_model(faction) - Get faction's default model
##   get_available_models() - List all available models
##
## Debug Functions (Debug Build Only):
##   _draw_debug_lines / _draw_ai_debug_lines - velocity/thrust/heading visualization
##   Real-time velocity/thrust visualization
##
## Physics Access:
##   All physics now uses model-specific parameters through avatar.model_params
##   Ground vehicles supported by leaving wing_area == 0.0 in AvatarData
