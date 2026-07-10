extends Node

## Enemy AI for Sopwith biplanes
## Architecture: FSM State Machine -> Pursuit Calculator -> Reflex Layer
##
## The AI now uses the project's reusable FSM (StateMachine/State) instead of
## a manual enum + match pattern. State transitions are handled by individual
## state scripts in scripts/states/ai/. The _physics_process loop delegates
## to the FSM which in turn calls the appropriate state's update().
##
## PITCH CONTROL  (Options B + C)
##   B — State-aware damping profiles: ENGAGING uses a more aggressive budget
##       (lower floor, lower ceiling) than CRUISE (patrol / return / takeoff).
##       The AoA blend that re-raises damping during a turn is suppressed in
##       combat so dogfighting authority is never silently stolen back.
##   C — Angular-velocity damping is a flat decoupled coefficient, not folded
##       into the speed curve.  This gives immediate snap on dive pull-outs
##       without affecting the speed-based sensitivity scaling.
##
## WOBBLE FIXES
##   • Residual heading-damping term removed (was fighting ang-vel term).
##   • desired_heading lerped each tick instead of hard-set, filtering noise
##     from a moving target.
##   • Deadband widened to 0.10 rad (~6°) so the AI declares "on heading"
##     before micro-corrections trigger an opposite input.
##
## OTHER FIXES (carried from previous revision)
##   • Target liveness guard — engagement releases on CRASHED / FALLING.
##   • AoA-aware stall recovery — hard override toward velocity vector.
##   • Energy-state engagement — altitude + speed gate dive attacks.
##   • Runway pitch suppression — outputs reset on respawn; reflexes skipped
##     in GROUNDED / TAKING_OFF.

# ---------------------------------------------------------------------------
# STATE ENUM
# ---------------------------------------------------------------------------

enum AIState {
	GROUNDED,
	TAKING_OFF,
	PATROLLING,
	ENGAGING,
	EVADING,
	RETURNING,
}

# ---------------------------------------------------------------------------
# CONSTANTS  (shared, never written at runtime)
# ---------------------------------------------------------------------------

const TERRAIN_LENGTH := 16384.0

# Altitude thresholds (pixels above terrain)
const PATROL_ALTITUDE                := 250.0
const MIN_ALTITUDE_ABOVE_GROUND      := 80.0
const DANGER_ALTITUDE_ABOVE_GROUND   := 60.0
const CRITICAL_ALTITUDE_ABOVE_GROUND := 20.0
const PULL_UP_ALTITUDE               := 200.0
const MAX_ALTITUDE                   := 1600.0

# Detection / engagement geometry
const DETECTION_RANGE       := 9000.0
const ENGAGEMENT_RANGE      := 2000.0
const MAX_FIRE_RANGE        := 600.0
const MIN_FIRE_RANGE        := 30.0
const FIRE_CONE_ANGLE       := 0.3
const STALKING_THRESHOLD    := 400.0
const ADVANTAGE_THRESHOLD   := 50.0
const RETURN_REENGAGE_RANGE := 400.0
const HOME_PROXIMITY        := 100.0

# Energy-state thresholds
const ENERGY_ALTITUDE_ADVANTAGE := 120.0   # px altitude edge to press a dive
const ENERGY_SPEED_RATIO_GOOD   := 1.4     # speed / stall_speed for healthy energy

# Patrol
const ALTITUDE_OSCILLATION_SPEED := 1.5
const ALTITUDE_OSCILLATION_AMP   := 30.0

# Pitch control — ENGAGE profile (aggressive, combat authority)
# const PITCH_SENS_ENGAGE_BASE  := 2.2-3.0   # gain at cruise speed in combat
# const PITCH_SENS_ENGAGE_LOW   := 0.9-1.0   # gain near stall in combat
const PITCH_SENS_ENGAGE_BASE  := 2.8   # gain at cruise speed in combat
const PITCH_SENS_ENGAGE_LOW   := 1.0   # gain near stall in combat
const PITCH_DAMP_ENGAGE_MAX   := 2.2   # speed-damping at low speed in combat
const PITCH_DAMP_ENGAGE_MIN   := 0.4   # speed-damping at cruise in combat
# const ANG_VEL_DAMP_ENGAGE     := 0.25  # flat ang-vel coefficient in combat
const ANG_VEL_DAMP_ENGAGE     := 0.22  # flat ang-vel coefficient in combat

# Pitch control — CRUISE profile (conservative, patrol / return / takeoff)
# const PITCH_SENS_CRUISE_BASE  := 1.8-2.2
# const PITCH_SENS_CRUISE_LOW   := 0.7-0.8
const PITCH_SENS_CRUISE_BASE  := 2.0
const PITCH_SENS_CRUISE_LOW   := 0.8
const PITCH_DAMP_CRUISE_MAX   := 3.0
const PITCH_DAMP_CRUISE_MIN   := 0.6
# const ANG_VEL_DAMP_CRUISE     := 0.30-0.50
const ANG_VEL_DAMP_CRUISE     := 0.40

# Heading smoothing (lerp factor per decision tick)
# const HEADING_LERP_FACTOR     := 0.30-0.45  # 0 = never turns, 1 = instant snap
const HEADING_LERP_FACTOR     := 0.32  # 0 = never turns, 1 = instant snap
# Deadband: angle error below this is treated as "on heading"
const HEADING_DEADBAND        := 0.10  # radians (~6°)

# Ground attack
const GROUND_ATTACK_DIVE_ALT  := 300.0
const GROUND_ATTACK_PULL_ALT  := 150.0

# Evade
const EVADE_DURATION_MIN := 0.5
const EVADE_DURATION_MAX := 2.0

# Terrain look-ahead
const TERRAIN_LOOK_DISTANCES := [50.0, 100.0, 200.0]
const TERRAIN_RISE_THRESHOLD := 0.3

# Take-off
const TAKEOFF_BUILD_SPEED  := 90.0
const TAKEOFF_ROTATE_SPEED := 120.0
const TAKEOFF_PITCH        := -0.05
const TAKEOFF_CLIMB_PITCH  := -0.10

# Bombing
const GROUND_ATTACK_ALTITUDE    := 300.0
const BOMB_OVERHEAD_X_THRESHOLD := 200.0
const BOMB_ANGLE_TOLERANCE      := 0.175

# ---------------------------------------------------------------------------
# PILOT STATE  (all mutable runtime data for one AI pilot)
# ---------------------------------------------------------------------------

class AIData:
	# FSM
	var ai_state: int        = 0   # AIState.GROUNDED
	var previous_state: int  = 2   # AIState.PATROLLING

	# Control outputs carried between frames
	var last_pitch_input: float = 0.0
	var last_throttle: float    = 0.0
	var desired_heading: float  = 0.0

	# Timers
	var decision_timer: float        = 0.0
	var incoming_bullet_timer: float = 0.0
	var flip_cooldown: float         = 0.0
	var bomb_cooldown_timer: float   = 0.0
	var evade_timer: float           = 0.0
	var patrol_time: float           = 0.0
	var takeoff_timer: float         = 0.0

	# Flags
	var is_using_autopilot: bool        = false

	func reset_control_outputs() -> void:
		last_pitch_input = 0.0
		last_throttle    = 0.0
		desired_heading  = 0.0

# ---------------------------------------------------------------------------
# NODE-LEVEL FIELDS
# ---------------------------------------------------------------------------

@export var target: Node2D
@export var biplane: RigidBody2D

# Configuration (set by spawner before _ready)
@export var home_base_x: float  = 1400.0
@export var patrol_range: float = 2000.0
@export var takeoff_delay: float = 0.0
@export var unlimited_fuel_ammo: bool = false

var decision_interval: float = 0.05

var territory_left: float  = 0.0
var territory_right: float = 16384.0

var terrain_cache: Node2D = null

var ai_fsm: AIStateMachine = null

# The one pilot this node controls.
var pilots: Array[AIData] = [AIData.new()]

var _respawn_id: int = -1

## Set once per life so the ground-impact re-signal (see biplane.gd respawn
## timer shortening) does not spawn a second explosion.
var _crashed_exploded: bool = false

# ---------------------------------------------------------------------------
# LIFECYCLE
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("destructible")
	_respawn_id = get_instance_id()
	if biplane and biplane.has_signal("crashed"):
		biplane.crashed.connect(_on_enemy_crashed)
	if RespawnManager:
		if RespawnManager.respawn_ready.is_connected(_on_enemy_respawn_ready):
			RespawnManager.respawn_ready.disconnect(_on_enemy_respawn_ready)
		RespawnManager.respawn_ready.connect(_on_enemy_respawn_ready)
	_setup_territory()
	_init_ai_fsm()

func _setup_territory() -> void:
	var half := patrol_range * 0.5
	territory_left  = home_base_x - half
	territory_right = home_base_x + half

func _init_ai_fsm() -> void:
	var fsm_node := AIStateMachine.new()
	fsm_node.name = "AIStateMachine"

	var state_scripts := {
		"Grounded": load("res://scripts/states/ai/grounded_state.gd"),
		"TakingOff": load("res://scripts/states/ai/taking_off_state.gd"),
		"Patrolling": load("res://scripts/states/ai/patrolling_state.gd"),
		"Engaging": load("res://scripts/states/ai/engaging_state.gd"),
		"Evading": load("res://scripts/states/ai/evading_state.gd"),
		"Returning": load("res://scripts/states/ai/returning_state.gd"),
		"Destroyed": load("res://scripts/states/ai/destroyed_state.gd"),
		"Refueling": load("res://scripts/states/ai/refueling_state.gd"),
	}
	for state_name in state_scripts:
		var state_node := State.new()
		state_node.name = state_name
		state_node.set_script(state_scripts[state_name])
		fsm_node.add_child(state_node)

	fsm_node.set_ai_controller(self)
	add_child(fsm_node)
	fsm_node.start_state = fsm_node.get_node("Grounded").get_path()
	ai_fsm = fsm_node
	ai_fsm.initialize(ai_fsm.get_node("Grounded"))

func _is_on_homebase_for_ai() -> bool:
	if not biplane:
		return false
	var avatar = _get_avatar()
	if not avatar:
		return false
	if not biplane.is_grounded(avatar):
		return false
	return abs(biplane.global_position.x - home_base_x) < 200.0

# ---------------------------------------------------------------------------
# PHYSICS LOOP
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not target or not biplane:
		return

	if takeoff_delay > 0.0:
		pilots[0].takeoff_timer += delta
		if pilots[0].takeoff_timer < takeoff_delay:
			return

	pilots[0].incoming_bullet_timer = maxf(0.0, pilots[0].incoming_bullet_timer - delta)
	pilots[0].bomb_cooldown_timer   = maxf(0.0, pilots[0].bomb_cooldown_timer - delta)
	pilots[0].flip_cooldown         = maxf(0.0, pilots[0].flip_cooldown - delta)

	var avatar = _get_avatar()
	if avatar and (avatar.flight_state == biplane.FlightState.FALLING
			or avatar.flight_state == biplane.FlightState.CRASHED):
		pilots[0].reset_control_outputs()
		return

	_apply_input(pilots[0].last_pitch_input, pilots[0].last_throttle)

	_check_flip_needed()

	if ai_fsm and ai_fsm._active:
		pilots[0].decision_timer -= delta
		if pilots[0].decision_timer <= 0.0:
			pilots[0].decision_timer = decision_interval
			ai_fsm.current_state.update(delta)
		return

	pilots[0].decision_timer -= delta
	if pilots[0].decision_timer <= 0.0:
		pilots[0].decision_timer = decision_interval
		_make_decision()

# ---------------------------------------------------------------------------
# DECISION LOOP
# ---------------------------------------------------------------------------

func _make_decision() -> void:
	if not target or not biplane:
		return
	var avatar = _get_avatar()
	if not avatar:
		return

	_update_state_machine()

	match pilots[0].ai_state:
		AIState.GROUNDED:
			# Zero outputs; skip reflexes — plane sits still on the runway.
			pilots[0].last_pitch_input = 0.0
			pilots[0].last_throttle    = 0.0
			return

		AIState.TAKING_OFF:
			# Dedicated handler writes directly to pilot outputs.
			_decision_takeoff(avatar)
			return

		AIState.PATROLLING:
			var pitch    = _compute_patrol_pitch()
			var throttle = _compute_patrol_throttle(avatar)
			var reflexed = _apply_reflexes(pitch, throttle)
			pilots[0].last_pitch_input = reflexed[0]
			pilots[0].last_throttle    = reflexed[1]

		AIState.ENGAGING:
			var result   = _compute_engage(avatar)
			var reflexed = _apply_reflexes(result[0], result[1])
			pilots[0].last_pitch_input = reflexed[0]
			pilots[0].last_throttle    = reflexed[1]

		AIState.EVADING:
			var pitch    = _compute_evade_pitch()
			var throttle = _compute_evade_throttle()
			var reflexed = _apply_reflexes(pitch, throttle)
			pilots[0].last_pitch_input = reflexed[0]
			pilots[0].last_throttle    = reflexed[1]

		AIState.RETURNING:
			var pitch    = _compute_return_pitch()
			var throttle = _compute_return_throttle(avatar)
			var reflexed = _apply_reflexes(pitch, throttle)
			pilots[0].last_pitch_input = reflexed[0]
			pilots[0].last_throttle    = reflexed[1]

# ---------------------------------------------------------------------------
# STATE MACHINE
# ---------------------------------------------------------------------------

func _update_state_machine() -> void:
	if not biplane or not target:
		return

	var avatar        = _get_avatar()
	var damage        = avatar.damage.damage_percent if avatar else 0.0
	var my_dist_home  = _get_wrapped_distance(biplane.global_position.x, home_base_x)
	var dist_to_tgt   = _get_wrapped_distance(biplane.global_position.x, target.global_position.x)

	match pilots[0].ai_state:
		AIState.GROUNDED:
			if dist_to_tgt < DETECTION_RANGE and _is_player_in_territory():
				pilots[0].ai_state = AIState.TAKING_OFF

		AIState.TAKING_OFF:
			var alt = _get_altitude_above_ground()
			if alt > PATROL_ALTITUDE:
				pilots[0].ai_state   = AIState.PATROLLING
				pilots[0].patrol_time = 0.0
			elif dist_to_tgt < ENGAGEMENT_RANGE and alt > MIN_ALTITUDE_ABOVE_GROUND:
				pilots[0].ai_state = AIState.ENGAGING

		AIState.PATROLLING:
			if dist_to_tgt < ENGAGEMENT_RANGE and _is_player_in_territory():
				pilots[0].ai_state = AIState.ENGAGING

		AIState.ENGAGING:
			# Release immediately if the target is no longer a viable threat.
			if not _is_target_alive():
				pilots[0].ai_state    = AIState.PATROLLING
				pilots[0].patrol_time = 0.0
				return

			var alt = _get_altitude_above_ground()
			if alt < DANGER_ALTITUDE_ABOVE_GROUND or pilots[0].incoming_bullet_timer > 0.0:
				pilots[0].previous_state = pilots[0].ai_state
				pilots[0].ai_state       = AIState.EVADING
				pilots[0].evade_timer    = randf_range(EVADE_DURATION_MIN, EVADE_DURATION_MAX)
			elif damage >= 0.5:
				pilots[0].ai_state = AIState.RETURNING
			elif dist_to_tgt > ENGAGEMENT_RANGE * 1.2:
				pilots[0].ai_state    = AIState.PATROLLING
				pilots[0].patrol_time = 0.0

		AIState.EVADING:
			pilots[0].evade_timer -= decision_interval
			var alt         = _get_altitude_above_ground()
			var avdata      = _get_avatar()
			var is_stalled  = avdata and avdata.flight_state == 1
			if not is_stalled \
					and pilots[0].evade_timer <= 0.0 \
					and alt > MIN_ALTITUDE_ABOVE_GROUND \
					and pilots[0].incoming_bullet_timer <= 0.0:
				pilots[0].ai_state = pilots[0].previous_state

		AIState.RETURNING:
			if dist_to_tgt < RETURN_REENGAGE_RANGE and damage < 0.5 and _is_target_alive():
				pilots[0].ai_state = AIState.ENGAGING
			elif my_dist_home < HOME_PROXIMITY and _is_grounded():
				pilots[0].ai_state = AIState.GROUNDED
				if biplane.has_method("disable_autopilot"):
					biplane.disable_autopilot()
				pilots[0].is_using_autopilot = false

# ---------------------------------------------------------------------------
# TARGET VALIDITY
# ---------------------------------------------------------------------------

## False when the target is destroyed or in a terminal fall so the AI never
## chases a wreck.  Non-biplane targets (ground structures) pass as alive.
func _is_target_alive() -> bool:
	if not target:
		return false
	if not target.has_method("get_avatar_data"):
		return true   # ground structure — treat as alive
	var ta = target.get_avatar_data(0)
	if not ta:
		return false
	# FlightState: CRASHED == 5, FALLING == 2
	return ta.flight_state != 5 and ta.flight_state != 2

# ---------------------------------------------------------------------------
# ENGAGE — unified entry point
# ---------------------------------------------------------------------------

## Returns [pitch, throttle].  Bombing takes priority over air combat.
func _compute_engage(avatar) -> Array:
	# Ground target with bombs → bomb run, bypass air combat entirely.
	if _is_target_on_ground() and _has_bombs(avatar):
		_try_decide_bomb_drop()
		return [_compute_bomb_pitch(), _compute_engage_throttle(avatar)]

	# Ground target, no bombs → dive to strafe, then pull up.
	if _is_target_on_ground():
		_try_fire_weapon()
		return [_compute_ground_attack_pitch(), _compute_engage_throttle(avatar)]

	# Airborne target → energy-state air combat.
	_try_fire_weapon()
	return [_compute_engage_pitch(), _compute_engage_throttle(avatar)]

# ---------------------------------------------------------------------------
# PITCH COMPUTATION
# ---------------------------------------------------------------------------

func _compute_patrol_pitch() -> float:
	if not biplane:
		return 0.0
	var patrol_x  = clampf(home_base_x, TERRAIN_LENGTH * 0.33, TERRAIN_LENGTH * 0.67)
	var ground_y  = _get_ground_height(patrol_x)
	pilots[0].patrol_time += decision_interval
	var osc       = sin(pilots[0].patrol_time * ALTITUDE_OSCILLATION_SPEED) * ALTITUDE_OSCILLATION_AMP
	var aim       = Vector2(patrol_x, ground_y - PATROL_ALTITUDE + osc)
	_steer_toward(aim)
	return _compute_pitch_from_heading(false)

func _compute_engage_pitch() -> float:
	if not biplane or not target:
		return 0.0

	var my_pos     = biplane.global_position
	var target_pos = target.global_position
	var distance   = my_pos.distance_to(target_pos)
	var my_alt     = _get_altitude_above_ground()
	var target_alt = _get_altitude_above_ground_for(target)
	var alt_diff   = my_alt - target_alt

	var aim: Vector2
	if distance > STALKING_THRESHOLD:
		aim = _stalking_waypoint(target_pos)
	elif _has_energy_advantage():
		aim    = _lead_pursuit_point(target_pos, 0.6)
		aim.y += 30.0   # lean into the dive
	elif alt_diff < -ENERGY_ALTITUDE_ADVANTAGE:
		aim    = _lead_pursuit_point(target_pos, 0.4)
		aim.y -= 40.0   # nose down to build speed before looping up
	else:
		aim = _lead_pursuit_point(target_pos, 0.7)

	_steer_toward(aim)
	return _compute_pitch_from_heading(true)   # ENGAGE profile

func _compute_ground_attack_pitch() -> float:
	if not biplane or not target:
		return 0.0

	var my_pos     = biplane.global_position
	var tgt_pos    = target.global_position
	var alt        = _get_altitude_above_ground()
	var to_target  = tgt_pos - my_pos
	var x_dist     = absf(to_target.x)
	var rel_x      = to_target.x

	# Emergency pull up if critically low
	if alt < CRITICAL_ALTITUDE_ABOVE_GROUND:
		return -1.0

	# Pull up if below safe dive recovery altitude
	if alt < GROUND_ATTACK_PULL_ALT:
		return -0.8

	# Check if past the target (passed overhead)
	var going_past = (biplane.velocity.x > 0 and rel_x < -50.0) or \
	                 (biplane.velocity.x < 0 and rel_x > 50.0)
	if going_past:
		var climb_aim = Vector2(
			my_pos.x + sign(biplane.velocity.x) * 300.0,
			my_pos.y - 200.0
		)
		_steer_toward(climb_aim)
		return _compute_pitch_from_heading(true)

	# Overhead — shallow dive / level
	if x_dist < 100.0:
		var aim = Vector2(tgt_pos.x + rel_x, tgt_pos.y - 20.0)
		_steer_toward(aim)
		return _compute_pitch_from_heading(true)

	# Above dive altitude — steep dive toward target
	if alt > GROUND_ATTACK_DIVE_ALT:
		var aim := Vector2(tgt_pos.x, tgt_pos.y + 30.0)
		_steer_toward(aim)
		return _compute_pitch_from_heading(true)

	# Medium altitude — shallow dive
	var aim = Vector2(tgt_pos.x, my_pos.y + 80.0)
	_steer_toward(aim)
	return _compute_pitch_from_heading(true)

func _compute_bomb_pitch() -> float:
	if not biplane or not target:
		return 0.0

	var my_pos       = biplane.global_position
	var target_pos   = target.global_position
	var x_dist       = _get_wrapped_distance(my_pos.x, target_pos.x)
	var approach_dir = sign(target_pos.x - my_pos.x)

	if x_dist < BOMB_OVERHEAD_X_THRESHOLD * 0.5:
		var aim = Vector2(my_pos.x + approach_dir * 100.0, my_pos.y - 20.0)
		_steer_toward(aim)
		return _compute_pitch_from_heading(true)

	var overhead_x = target_pos.x - approach_dir * BOMB_OVERHEAD_X_THRESHOLD * 2.0
	_steer_toward(Vector2(overhead_x, my_pos.y))
	return _compute_pitch_from_heading(true)

func _compute_evade_pitch() -> float:
	if not biplane:
		return 0.0
	var alt = _get_altitude_above_ground()
	if alt < CRITICAL_ALTITUDE_ABOVE_GROUND:
		return -1.0
	elif alt < DANGER_ALTITUDE_ABOVE_GROUND:
		return -0.8
	elif pilots[0].incoming_bullet_timer > 0.0:
		return -0.3
	return -0.5

func _compute_return_pitch() -> float:
	if not biplane:
		return 0.0
	var ground_y  = _get_ground_height(home_base_x)
	var home_pos  = Vector2(home_base_x, ground_y - PATROL_ALTITUDE)
	var to_home   = home_pos - biplane.global_position
	var dist      = to_home.length()

	if dist < HOME_PROXIMITY * 2.0:
		var land_pos = Vector2(home_base_x, ground_y - 50.0)
		_steer_toward(land_pos)
		if dist < HOME_PROXIMITY and not pilots[0].is_using_autopilot:
			_enable_autopilot_for_landing()
		return _compute_pitch_from_heading(false)

	var aim   = _lead_pursuit_point(home_pos, 0.5)
	aim.y      = minf(aim.y, ground_y - PATROL_ALTITUDE)
	_steer_toward(aim)
	return _compute_pitch_from_heading(false)

# ---------------------------------------------------------------------------
# HEADING → PITCH  (Options B + C)
# ---------------------------------------------------------------------------

## is_engaging = true  → ENGAGE profile (aggressive, AoA blend suppressed)
## is_engaging = false → CRUISE profile (conservative, AoA blend active)
func _compute_pitch_from_heading(is_engaging: bool) -> float:
	if not biplane:
		return 0.0

	var angle_diff = wrapf(pilots[0].desired_heading - biplane.rotation, -PI, PI)
	if absf(angle_diff) < HEADING_DEADBAND:
		return 0.0

	var avatar = _get_avatar()

	# --- Speed ratio ---
	var stall_speed: float = 21.4
	if avatar:
		stall_speed = avatar.stall_speed_ms
	var ppm: float = 10.0
	if "pixels_per_meter" in biplane:
		ppm = biplane.get("pixels_per_meter")
	var speed_ms    = biplane.velocity.length() / ppm
	var speed_ratio = clampf(speed_ms / maxf(stall_speed, 1.0), 0.6, 3.0)
	# speed_t: 0.0 = near stall, 1.0 = cruise and above
	var speed_t     = clampf((speed_ratio - 0.6) / 2.4, 0.0, 1.0)

	# --- AoA (only blended in for CRUISE — Option B) ---
	var aoa_ratio := 0.0
	if not is_engaging and biplane.velocity.length() > 0.5:
		var max_aoa: float = 0.279
		if avatar:
			max_aoa = deg_to_rad(avatar.model_params.get("max_aoa", 16.0))
		var actual_aoa = absf(wrapf(biplane.rotation - biplane.velocity.angle(), -PI, PI))
		aoa_ratio = clampf(actual_aoa / maxf(max_aoa, 0.01), 0.0, 1.0)

	# --- Select profile (Option B) ---
	var sens_base: float
	var sens_low: float
	var damp_max: float
	var damp_min: float
	var ang_vel_damp: float

	if is_engaging:
		sens_base    = PITCH_SENS_ENGAGE_BASE
		sens_low     = PITCH_SENS_ENGAGE_LOW
		damp_max     = PITCH_DAMP_ENGAGE_MAX
		damp_min     = PITCH_DAMP_ENGAGE_MIN
		ang_vel_damp = ANG_VEL_DAMP_ENGAGE
	else:
		sens_base    = PITCH_SENS_CRUISE_BASE
		sens_low     = PITCH_SENS_CRUISE_LOW
		damp_max     = PITCH_DAMP_CRUISE_MAX
		damp_min     = PITCH_DAMP_CRUISE_MIN
		ang_vel_damp = ANG_VEL_DAMP_CRUISE

	# Speed-based damping, then blend in AoA correction (CRUISE only).
	var speed_damp      = lerpf(damp_max, damp_min, speed_t)
	var dynamic_damping = lerpf(speed_damp, damp_max, aoa_ratio)

	# Sensitivity scales with speed.
	var sensitivity = lerpf(sens_low, sens_base, speed_t)

	# Angular velocity damping — flat decoupled coefficient (Option C).
	# Carries the stabilisation load; no longer tangled with the speed curve.
	var angular_vel: float = avatar.angular_velocity if avatar else 0.0
	var ang_damp_term      = angular_vel * ang_vel_damp

	# Combine: sensitivity * error  minus  ang-vel term  minus  speed-scaled heading damp.
	# The heading damp here is a small residual (0.05, down from 0.5) whose only
	# job is to prevent overshoot on the final approach to the target heading.
	# At this level it cannot produce the oscillation the old value caused.
	var base_pitch = angle_diff * sensitivity
	base_pitch    -= ang_damp_term
	base_pitch    -= angle_diff * dynamic_damping * 0.05

	return clampf(base_pitch, -1.0, 1.0)

# ---------------------------------------------------------------------------
# HEADING HELPER
# ---------------------------------------------------------------------------

## Smoothly steers pilots[0].desired_heading toward aim_point each decision tick.
## Lerping rather than hard-setting filters single-frame jitter from a moving
## target and prevents the heading from flipping sign between ticks.
func _steer_toward(aim_point: Vector2) -> void:
	if not biplane:
		return
	var target_heading = (aim_point - biplane.global_position).angle()
	pilots[0].desired_heading = lerp_angle(pilots[0].desired_heading, target_heading, HEADING_LERP_FACTOR)

# ---------------------------------------------------------------------------
# STALL REFLEX  (AoA-aware hard override)
# ---------------------------------------------------------------------------

## While STALLED, steers the nose toward the velocity vector to reduce AoA,
## then applies full throttle.  Releases only once AoA drops below 70 % of
## max_aoa (hysteresis) to prevent re-stalling immediately after recovery.
## Returns true to signal that the normal heading path must be skipped.
func _stall_reflex() -> bool:
	var avatar = _get_avatar()
	if not avatar:
		return false
	# FlightState.STALLED == 1
	if avatar.flight_state != 1:
		return false

	var max_aoa = deg_to_rad(avatar.model_params.get("max_aoa", 16.0))
	var recovery_threshold = max_aoa * 0.7

	var actual_aoa := 0.0
	if biplane.velocity.length() > 0.5:
		actual_aoa = absf(wrapf(biplane.rotation - biplane.velocity.angle(), -PI, PI))

	if actual_aoa < recovery_threshold:
		return false   # recovered — release the override

	# Hard override: aim ~5° above the relative wind for a touch of lift.
	var recovery_heading      = biplane.velocity.angle() - deg_to_rad(5.0)
	pilots[0].desired_heading      = recovery_heading
	pilots[0].last_pitch_input     = _compute_pitch_from_heading(false)
	pilots[0].last_throttle        = 1.0
	return true

# ---------------------------------------------------------------------------
# THROTTLE COMPUTATION
# ---------------------------------------------------------------------------

func _compute_patrol_throttle(avatar) -> float:
	return 1.0

func _compute_engage_throttle(avatar) -> float:
	return 1.0

func _compute_evade_throttle() -> float:
	return 1.0

func _compute_return_throttle(avatar) -> float:
	return 0.8

# ---------------------------------------------------------------------------
# ENERGY STATE
# ---------------------------------------------------------------------------

func _has_energy_advantage() -> bool:
	if not biplane or not target:
		return false
	var alt_edge = _get_altitude_above_ground() - _get_altitude_above_ground_for(target) \
				   > ENERGY_ALTITUDE_ADVANTAGE
	var avatar   = _get_avatar()
	var stall    = avatar.stall_speed_ms if avatar else 21.4
	var ppm: float = biplane.get("pixels_per_meter") if "pixels_per_meter" in biplane else 10.0
	var speed_ok = biplane.velocity.length() / ppm / maxf(stall, 1.0) >= ENERGY_SPEED_RATIO_GOOD
	return alt_edge and speed_ok

func _is_low_energy() -> bool:
	if not biplane:
		return false
	var avatar = _get_avatar()
	var stall  = avatar.stall_speed_ms if avatar else 21.4
	var ppm: float = biplane.get("pixels_per_meter") if "pixels_per_meter" in biplane else 10.0
	return biplane.velocity.length() / ppm / maxf(stall, 1.0) < ENERGY_SPEED_RATIO_GOOD

# ---------------------------------------------------------------------------
# TAKE-OFF HANDLER
# ---------------------------------------------------------------------------

func _decision_takeoff(avatar) -> void:
	var stall_speed: float = 21.4
	if avatar:
		stall_speed = avatar.stall_speed_ms
	var speed = biplane.velocity.length()

	# Throttle — always full except on the ground to prevent over-speed.
	if _is_grounded():
		pilots[0].last_throttle = 1.0
	else:
		pilots[0].last_throttle = 1.0

	# Pitch — never pitch hard while on the ground
	if _is_grounded():
		pilots[0].last_pitch_input = 0.0 if speed < TAKEOFF_ROTATE_SPEED else TAKEOFF_PITCH
	else:
		var alt = _get_altitude_above_ground()
		if speed < stall_speed * 2.0:
			pilots[0].last_pitch_input = clampf(-0.03 * (speed / (stall_speed * 2.0)), -0.03, 0.0)
		elif alt < 100.0:
			pilots[0].last_pitch_input = -0.05
		elif alt < 200.0:
			pilots[0].last_pitch_input = -0.08
		else:
			pilots[0].last_pitch_input = TAKEOFF_CLIMB_PITCH

# ---------------------------------------------------------------------------
# REFLEX LAYER
# ---------------------------------------------------------------------------

## Applied after state pitch/throttle for PATROLLING / ENGAGING / EVADING /
## RETURNING.  Skipped for GROUNDED and TAKING_OFF (they manage own outputs).
func _apply_reflexes(pitch: float, throttle: float) -> Array:
	if _stall_reflex():
		return [pilots[0].last_pitch_input, pilots[0].last_throttle]

	var alt_fix = _altitude_reflex()
	if alt_fix != 0.0:
		pitch    = alt_fix
		throttle = maxf(throttle, 0.8)

	var ceil_fix = _altitude_ceiling_reflex()
	if ceil_fix != 0.0:
		pitch = maxf(pitch, ceil_fix)

	var terrain_fix = _terrain_projection_reflex()
	if terrain_fix != 0.0:
		pitch = minf(pitch, terrain_fix)

	var pullup_fix = _pull_up_reflex()
	if pullup_fix != 0.0:
		pitch = pullup_fix

	return [pitch, throttle]

func _pull_up_reflex() -> float:
	if not biplane or _get_altitude_above_ground() > PULL_UP_ALTITUDE:
		return 0.0
	return -0.5 if biplane.rotation > 0.1 else 0.0

func _altitude_reflex() -> float:
	if not biplane:
		return 0.0
	var alt = _get_altitude_above_ground()
	if alt < CRITICAL_ALTITUDE_ABOVE_GROUND:
		return -1.0
	elif alt < DANGER_ALTITUDE_ABOVE_GROUND:
		return -0.7
	elif alt < MIN_ALTITUDE_ABOVE_GROUND:
		return -0.3
	return 0.0

func _altitude_ceiling_reflex() -> float:
	if not biplane:
		return 0.0
	var alt = _get_altitude_above_ground()
	if alt > MAX_ALTITUDE:
		return 0.5
	elif alt > MAX_ALTITUDE - 50.0:
		return 0.2
	return 0.0

func _terrain_projection_reflex() -> float:
	if not biplane:
		return 0.0
	var cur_ground = _get_ground_height(biplane.global_position.x)
	var vel_x      = biplane.velocity.x
	for look_dist in TERRAIN_LOOK_DISTANCES:
		var future_x   = biplane.global_position.x + sign(vel_x) * look_dist
		var terrain_rise = cur_ground - _get_ground_height(future_x)
		if terrain_rise > look_dist * TERRAIN_RISE_THRESHOLD:
			return -0.5
	return 0.0

# ---------------------------------------------------------------------------
# PURSUIT GEOMETRY
# ---------------------------------------------------------------------------

func _lead_pursuit_point(target_pos: Vector2, lead_factor: float) -> Vector2:
	if not biplane or not target:
		return target_pos
	var dist       = biplane.global_position.distance_to(target_pos)
	var target_vel = target.velocity if "velocity" in target else Vector2.ZERO
	var my_speed   = maxf(biplane.velocity.length(), 1.0)
	var lead_time  = clampf(dist / my_speed * lead_factor, 0.2, 1.5)
	var predicted  = target_pos + target_vel * lead_time
	var my_alt     = _get_altitude_above_ground()
	var tgt_alt    = _get_altitude_above_ground_for(target)
	if my_alt < tgt_alt - ADVANTAGE_THRESHOLD:
		predicted.y -= 30.0
	elif my_alt > tgt_alt + ADVANTAGE_THRESHOLD:
		predicted.y += 15.0
	return predicted

func _stalking_waypoint(target_pos: Vector2) -> Vector2:
	if not biplane:
		return target_pos
	var my_pos = biplane.global_position
	var dx     = target_pos.x - my_pos.x
	if abs(dx) > STALKING_THRESHOLD:
		var wx        = my_pos.x + sign(dx) * 150.0
		var safe_ceil = _get_ground_height(wx) - MIN_ALTITUDE_ABOVE_GROUND
		return Vector2(wx, minf(my_pos.y - 100.0, safe_ceil))
	return target_pos

# ---------------------------------------------------------------------------
# WEAPONS
# ---------------------------------------------------------------------------

func _try_fire_weapon() -> void:
	if not biplane or not target or not _is_target_alive():
		return
	var avatar = _get_avatar()
	if not avatar or avatar.gun_timer > 0.0:
		return
	var my_pos    = biplane.global_position
	var tgt_pos   = target.global_position
	var dist      = my_pos.distance_to(tgt_pos)
	if dist > MAX_FIRE_RANGE or dist < MIN_FIRE_RANGE:
		return
	var tgt_vel      = target.velocity if "velocity" in target else Vector2.ZERO
	var lead_time    = dist / 1600.0
	var predicted    = tgt_pos + tgt_vel * lead_time
	var bullet_dir   = (predicted - my_pos).normalized()
	var my_hdg       = Vector2(cos(biplane.rotation), sin(biplane.rotation))
	var angle_diff   = bullet_dir.angle_to(my_hdg)
	var shot_quality = 1.0 - (absf(angle_diff) / FIRE_CONE_ANGLE)
	var threshold    = 0.3 if dist < 200.0 else 0.6
	if shot_quality >= threshold:
		_fire_weapon()

func _try_decide_bomb_drop() -> void:
	if _can_bomb_ground_target():
		_try_drop_bomb()

func _try_drop_bomb() -> void:
	if pilots[0].bomb_cooldown_timer > 0.0:
		return
	var avatar = _get_avatar()
	if not avatar or avatar.bombs <= 0:
		return
	if biplane.has_method("drop_bomb"):
		biplane.drop_bomb(avatar)
		pilots[0].bomb_cooldown_timer = 2.5

func _fire_weapon() -> void:
	if biplane.has_method("fire_gun") and biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			biplane.fire_gun(avatar)

# ---------------------------------------------------------------------------
# BOMBING PREDICATES
# ---------------------------------------------------------------------------

func _has_bombs(avatar) -> bool:
	if not avatar or avatar.bombs <= 0:
		return false
	return not (GameManager and not GameManager.enemy_bombs)

func _can_bomb_ground_target() -> bool:
	if GameManager and not GameManager.enemy_bombs:
		return false
	if not target or not biplane or pilots[0].bomb_cooldown_timer > 0.0:
		return false
	var avatar = _get_avatar()
	if not _has_bombs(avatar):
		return false
	if not _is_target_on_ground() or not _is_overhead_target():
		return false
	if _get_altitude_above_ground() < 100.0:
		return false
	var to_target         = target.global_position - biplane.global_position
	var angle_from_vert   = absf(atan2(to_target.x, -to_target.y))
	return angle_from_vert <= BOMB_ANGLE_TOLERANCE

# ---------------------------------------------------------------------------
# TERRITORY & POSITION QUERIES
# ---------------------------------------------------------------------------

func _is_player_in_territory() -> bool:
	if not target:
		return false
	var px = target.global_position.x
	return px >= territory_left and px <= territory_right

func _is_target_on_ground() -> bool:
	if not target:
		return false
	if target.has_method("is_grounded") and target.has_method("get_avatar_data"):
		var ta = target.get_avatar_data(0)
		if ta:
			return target.is_grounded(ta)
	return _get_altitude_above_ground_for(target) < 30.0

func _is_overhead_target() -> bool:
	if not biplane or not target:
		return false
	return _get_wrapped_distance(biplane.global_position.x, target.global_position.x) \
		< BOMB_OVERHEAD_X_THRESHOLD

# ---------------------------------------------------------------------------
# TERRAIN & ALTITUDE HELPERS
# ---------------------------------------------------------------------------

func _get_terrain() -> Node2D:
	if terrain_cache == null:
		terrain_cache = get_parent().get_node_or_null("Terrain")
	return terrain_cache

func _get_ground_height(x: float) -> float:
	var terrain = _get_terrain()
	if terrain and terrain.has_method("get_ground_height_at"):
		return terrain.get_ground_height_at(x)
	return 650.0

func _get_altitude_above_ground() -> float:
	if not biplane:
		return 0.0
	return _get_ground_height(biplane.global_position.x) - biplane.global_position.y

func _get_altitude_above_ground_for(node: Node2D) -> float:
	if not node:
		return 0.0
	return _get_ground_height(node.global_position.x) - node.global_position.y

func _get_wrapped_distance(x1: float, x2: float) -> float:
	var d = absf(x1 - x2)
	return TERRAIN_LENGTH - d if d > TERRAIN_LENGTH * 0.5 else d

func _is_grounded() -> bool:
	if biplane and biplane.has_method("is_grounded") and biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			return biplane.is_grounded(avatar)
	return false

func _get_avatar():
	if biplane and biplane.has_method("get_avatar_data"):
		return biplane.get_avatar_data(0)
	return null

# ---------------------------------------------------------------------------
# INPUT APPLICATION
# ---------------------------------------------------------------------------

func _apply_input(pitch: float, throttle_amount: float) -> void:
	if not biplane.has_method("set_ai_input"):
		return
	var avatar = _get_avatar()
	var effective_pitch = -pitch if (avatar and avatar.is_inverted) else pitch
	biplane.set_ai_input(effective_pitch, throttle_amount)

# ---------------------------------------------------------------------------
# AUTOPILOT / LANDING
# ---------------------------------------------------------------------------

func _enable_autopilot_for_landing() -> void:
	pilots[0].is_using_autopilot = true
	if biplane.has_method("enable_autopilot"):
		biplane.enable_autopilot()
	var ground_y = _get_ground_height(home_base_x)
	if biplane.has_method("setup_faction_homebase") and biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			# Use setup_faction_homebase (not setup_homebase): the latter leaves the
			# base at the default Faction.BRITISH, so a later respawn would re-apply
			# the wrong model (e.g. a Sopwith instead of a Fokker) while keeping the
			# enemy's AI/faction data.  Preserve this plane's own faction on the base.
			biplane.setup_faction_homebase(1, home_base_x, 200.0, Vector2(home_base_x, ground_y - 12), 0.0, avatar.faction)
			biplane.set_home_base(avatar, 1)

# ---------------------------------------------------------------------------
# CRASH / RESPAWN
# ---------------------------------------------------------------------------

func _on_enemy_crashed(is_midair: bool = false) -> void:
	if not _crashed_exploded and biplane and biplane.has_method("create_explosion"):
		biplane.create_explosion(is_midair)
		_crashed_exploded = true
	if RespawnManager:
		var delay := RespawnManager.MAX_RESPAWN_DELAY if is_midair else RespawnManager.RESPAWN_DELAY
		RespawnManager.queue_respawn(_respawn_id, delay)

func _on_enemy_respawn_ready(avatar_id: int) -> void:
	if avatar_id == _respawn_id:
		_do_respawn()

func _do_respawn() -> void:
	if not biplane:
		return

	# Reset all per-pilot mutable state so nothing leaks across lives.
	pilots[0] = AIData.new()
	_crashed_exploded = false

	if biplane.has_method("respawn"):
		biplane.respawn(0)
	else:
		# Fallback if respawn isn't available
		var avatar = biplane.get_avatar_data(0) if biplane.has_method("get_avatar_data") else null
		if avatar:
			var spawn_pos = biplane.get_homebase_spawn_position(avatar) if biplane.has_method("get_homebase_spawn_position") else Vector2(7000, 500)
			var spawn_rot = biplane.get_homebase_spawn_rotation(avatar) if biplane.has_method("get_homebase_spawn_rotation") else 0.0
			var ground_y := _get_ground_height(spawn_pos.x)
			biplane.global_position = Vector2(spawn_pos.x, ground_y - 12)
			biplane.rotation = spawn_rot
			biplane.linear_velocity = Vector2.ZERO
			biplane.angular_velocity = 0.0
			biplane.visible = true

	# Sync AI heading to the spawn orientation.
	if biplane.has_method("get_homebase_spawn_rotation") and biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			pilots[0].desired_heading = biplane.get_homebase_spawn_rotation(avatar)

	if ai_fsm and ai_fsm._active:
		ai_fsm.transition_to(&"grounded")

# ---------------------------------------------------------------------------
# EXTERNAL API
# ---------------------------------------------------------------------------

func notify_incoming_fire() -> void:
	pilots[0].incoming_bullet_timer = 0.5

func get_dodge_chance() -> float:
	var avatar = _get_avatar()
	return 0.5 if (avatar and avatar.is_flipping) else 0.0

func _check_flip_needed() -> void:
	var avatar = _get_avatar()
	if not avatar or avatar.is_flipping:
		return

	var x_speed = avatar.stall_speed_ms * 10.0
	var should_be_inverted = biplane.velocity.x <= -1 * x_speed
	if should_be_inverted != avatar.is_inverted and abs(biplane.velocity.x) >= x_speed:
			biplane.do_flip(avatar)

func take_damage(amount: float, attacker: Node) -> void:
	var owner: Node = null
	if attacker.has_method("get_bullet_owner"):
		owner = attacker.get_bullet_owner()
	elif attacker.has_method("get_bomb_owner"):
		owner = attacker.get_bomb_owner()
	if owner and owner.is_in_group("player"):
		notify_incoming_fire()
	if biplane and biplane.has_method("take_damage"):
		biplane.take_damage(amount, attacker)

func get_biplane() -> RigidBody2D:
	return biplane

func is_enemy() -> bool:
	return true
