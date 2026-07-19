extends Node

## Enemy AI for Sopwith biplanes
## Architecture: Controller (sole driver) -> FSM State Machine -> Pursuit Calculator -> Reflex Layer
##
## The AI uses the project's reusable FSM (StateMachine/State) instead of a
## manual enum + match pattern. State scripts in scripts/states/ai/ compute
## decisions only — they never apply inputs or mutate pilot outputs directly.
##
## CADENCE MODEL (single-driver, D2/D3)
##   • The controller (`enemy_ai`) is the SOLE driver of `AIStateMachine`.
##     `self_driven` is false; the FSM never ticks itself.
##   • Decisions: the controller accumulates real elapsed time and calls
##     `ai_fsm.tick(elapsed)` once every `decision_interval` (0.05 s ≈ 20 Hz).
##   • Application: control outputs (`_apply_input`) are applied once per
##     physics frame (≈60 Hz), decoupled from the decision cadence.
##   • State timers (`evade_timer`, patrol oscillation) therefore track wall
##     time exactly, and `HEADING_LERP_FACTOR` filters jitter at its designed
##     20 Hz (B3/B4).
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
## ATTITUDE FRAMES & HELPER API  (Biplane.AvatarData — direction-agnostic)
## ---------------------------------------------------------------------------
## Every pitch quantity the AI produces or consumes is expressed in the
## GRAVITY FRAME: 0 = level with the horizon, positive = nose-down toward the
## ground, negative = nose-up toward the sky.  A level plane flying leftward
## inverted and one flying rightward upright read IDENTICALLY, and a given
## command produces the same climb/dive for both.  This gravity frame is the
## ONLY frame behaviour code is allowed to reason about — raw world-space
## rotations and pre-flipped signs were the source of every inverted-plane
## bug in this file's history.
##
## THE HELPERS  (all on Biplane.AvatarData)
##   travel_sign()                          +1.0 rightward nose, -1.0 leftward
##   level_rotation()                       0.0 rightward, PI leftward (world)
##   gravity_pitch()                        pitch relative to the horizon
##   gravity_pitch_rate()                   pitch rate, sign-corrected
##   gravity_angle(world_heading)           world heading → gravity frame
##   world_angle(gravity_pitch_value)       gravity frame → world heading
##   pitch_command_to_rotation_input(cmd)   gravity command → rotation input
##   rotation_is_leftward(world_rotation)   static: true when nose aims left
##
## VITAL RULES  (every one of these was a real bug; obey them all)
##   1. NEVER read or branch on `avatar.is_barrel_rolled` in this file.
##      Use `travel_sign()` for direction-sensitive branches, `gravity_pitch()`
##      for "is the nose above/below the horizon", `level_rotation()` for a
##      world-frame rotation reference, and `rotation_is_leftward()` to
##      derive inverted state from a world rotation.
##   2. `desired_heading` is a WORLD-SPACE angle (Vector2.angle()).  Convert
##      it via `gravity_angle()` only at the point of comparison (inside
##      `_compute_pitch_from_heading`); never pre-convert and store.  The
##      frame conversion is the pitch controller's responsibility, not the
##      steer's.
##   3. Forward pitch commands to `Biplane.set_ai_input()` VERBATIM.  The
##      single `is_barrel_rolled` sign flip lives in
##      `pitch_command_to_rotation_input()` inside `set_ai_input`.  Pre-flipping
##      here double-converts and cancels it out — that previously made
##      leftward-spawned, inverted AI planes pitch into the ground on
##      takeoff instead of climbing.
##   4. Raw pitch overrides (takeoff ladder, panic pull-ups, stall dive,
##      Immelmann aim) are ALREADY gravity-frame commands: negative = climb,
##      positive = dive.  Write them directly; the integrator flips them.
##   5. `set_ai_input()` is the only entry point for AI pitch.  Never
##      mutate `biplane.rotation` or `avatar.pitch_angle` from the AI.
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
##
## ENERGY-MODE ENGAGEMENT  (boom & zoom)
##   Air combat runs a small mode machine (Pilots.engage_mode) with hysteresis:
##   • PURSUE — the default: turn toward the target, lead-pursuit, fire when
##     in cone.  Turn rate scales with energy (high alt OR high speed →
##     tighter turn) so a healthy plane snaps hard while a wounded one can
##     only swing wide.
##   • RECOVER_DIVE / RECOVER_CLIMB — the only break-offs.  High altitude
##     with low airspeed triggers RECOVER_DIVE (trade altitude for speed);
##     low altitude triggers RECOVER_CLIMB (gain altitude).  Either exits to
##     PURSUE once airspeed recovers (RECOVER_EXIT_SPEED_RATIO) or after a
##     hard time limit.
##
## PREDICTIVE TERRAIN AVOIDANCE
##   `_terrain_impact_time()` samples the velocity vector for a terrain
##   intersection; when impact is inside a speed-scaled window the reflex
##   layer pulls the nose up early (scaled by urgency) instead of relying on
##   the old fixed-altitude panic lines — this is what stops dive-attack
##   crashes.  Slow planes get a shallow pull (they cannot zoom).
##
## DEFENSIVE REACTIONS & AGGRESSION
##   `_should_evade_defensively()` detects a player locked onto the AI's six
##   (rear cone + tracking nose) and breaks.  Incoming fire only triggers an
##   evade when the AI is slow or already hurt — healthy, fast planes press
##   head-on attacks instead of flinching at every round.
##
## ALTITUDE-ADVANTAGE PATROL
##   While the player is airborne, PATROLLING cruises above the player's
##   altitude (clamped to the [PATROL_CRUISE_MIN, PATROL_MAX_ALTITUDE] band)
##   so it always holds potential energy to dive with.  The band is capped
##   below the 1800 px engine-taper line as required.


# ---------------------------------------------------------------------------
# CONSTANTS  (shared, never written at runtime)
# ---------------------------------------------------------------------------

const TERRAIN_LENGTH := 16384.0

# Altitude thresholds (pixels above terrain)
const PATROL_ALTITUDE                := 250.0
# Patrol cruise band while the player is airborne: the AI holds an altitude
# advantage over the player so it always has potential energy to dive with.
# PATROL_MAX_ALTITUDE is capped below the 1800 px engine-taper line
# (Biplane.ENGINE_EFFICIENCY_START_ALTITUDE) — the required "no more than
# 1800 m off the ground" ceiling — and below the MAX_ALTITUDE ceiling reflex
# so patrol never fights the push-down reflexes.
const PATROL_CRUISE_MIN              := 800.0
const PATROL_ALTITUDE_ADVANTAGE      := 300.0
const PATROL_MAX_ALTITUDE            := 1500.0
const MIN_ALTITUDE_ABOVE_GROUND      := 100.0
const DANGER_ALTITUDE_ABOVE_GROUND   := 60.0
const CRITICAL_ALTITUDE_ABOVE_GROUND := 20.0
const PULL_UP_ALTITUDE               := 200.0
# Hard ceiling on cruise altitude.  1600 px = 0.8 × Biplane.ENGINE_CUTOFF_ALTITUDE
# (2000 px): AI planes can still climb to gather potential energy but the
# ceiling reflex pushes the nose down before they reach the 1800 px
# thrust-taper band or the cutoff itself, where they would stall and die.
const MAX_ALTITUDE_FRACTION          := 0.4
const MAX_ALTITUDE                   := 1600.0
# Fraction of Biplane.ENGINE_CUTOFF_ALTITUDE above which the AI treats the engine
# as about to quit and forces the nose down (independent hard safety, holds even
# if some other logic commands a high climb).
const ENGINE_CUTOFF_AVOID_FRACTION   := 0.8
# Seconds-to-impact below which a descent is treated as an imminent crash.
# Used by _terrain_impact_time(): the actual pull-up window scales up with
# speed (see _impact_window) since a faster plane covers more ground per second.
const PULL_UP_TIME_TO_GROUND         := 1.2
# Trajectory sample times (s) for the predictive terrain-impact check.
const IMPACT_SAMPLE_TIMES: Array[float] = [0.25, 0.5, 0.8, 1.2, 1.7, 2.2, 2.8]
# Clearance margin (px) kept above the terrain when sampling the trajectory.
const IMPACT_ALT_MARGIN              := 30.0

# Detection / engagement geometry.  ENGAGEMENT_RANGE is the distance (wrapped, so
# it spans the whole torus) at which PATROL commits to ENGAGE.  It must be large
# enough that an enemy will fly out to strike a player who is on the ground at
# the far end of the map, not just orbit its own base.  9000 px exceeds the
# maximum wrapped separation (TERRAIN_LENGTH/2 = 8192) so any alive target is
# engageable; the territory gate still restricts *airborne* targets to the
# enemy's own side, while a grounded player is a valid target anywhere.
const DETECTION_RANGE       := 40000.0
const ENGAGEMENT_RANGE      := 24000.0
const MAX_FIRE_RANGE        := 700.0
const MIN_FIRE_RANGE        := 30.0
const FIRE_CONE_ANGLE       := 0.42
const ADVANTAGE_THRESHOLD   := 50.0
const RETURN_REENGAGE_RANGE := 400.0
const HOME_PROXIMITY        := 100.0

# Return-to-base landing approach (designed to land gently, not crash)
# Continuous glide slope: desired altitude above the base = horizontal_distance
# * GLIDE_SLOPE, capped at PATROL_ALTITUDE.  This lets the plane bleed altitude
# steadily all the way home instead of cruising level then diving at the last
# moment.  ~9° descent (1:6) keeps the sink rate within the soft-landing vperp.
const RETURN_GLIDE_SLOPE       := 0.16
# Once the plane is this close horizontally it is committed to the final: the
# climb-forcing ground-avoidance reflexes are suppressed so it can descend the
# rest of the way to the runway and flare.
const RETURN_FINAL_DIST        := 520.0
# Below this altitude on final the plane flares (levels the nose and cuts the
# throttle) to arrest the sink rate for a soft touchdown.
const RETURN_FLARE_ALT         := 90.0
const RETURN_CRUISE_THROTTLE   := 0.7   # en-route, maintain speed
const RETURN_FINAL_THROTTLE    := 0.3   # short final, slow down
const RETURN_FLARE_THROTTLE    := 0.0   # idle on the flare

# Energy-state thresholds
const ENERGY_ALTITUDE_ADVANTAGE := 120.0   # px altitude edge to press a dive
const ENERGY_SPEED_RATIO_GOOD   := 1.5     # speed / stall_speed for healthy energy

# Engagement energy threshold — below this speed/stall ratio the AI cannot
# safely press an attack (it would mush into a stall).  Above the safe-dive
# altitude (RECOVER_DIVE_MIN_ALT) this triggers RECOVER_DIVE; below it, the
# altitude check wins and the plane climbs instead.
const EXTEND_ENTER_SPEED_RATIO  := 1.35

# High-energy turnaround — when the AI is genuinely flying *away* from its
# target (velocity points broadly opposite the line to target) yet has altitude
# or airspeed in reserve, it reverses course back toward the target on the X
# axis instead of sailing off the edge of the map.  This is the boom-zoom
# energy-management that keeps a fast/high plane in the fight.
const FLYAWAY_TURNAROUND_ALTITUDE    := 600.0   # px above ground
const FLYAWAY_TURNAROUND_SPEED_RATIO := 1.7     # speed / stall_speed

# Immelmann fly-away turnaround: build the reversal aim as a point PAST the
# player (along the approach axis) and HIGH above the plane.  In the gravity
# frame the relative vector resolves to a large NEGATIVE angle_diff (climb)
# for BOTH travel directions, so a rightward upright plane and a leftward
# inverted plane both pitch UP and arc over the target to reverse heading.
# (Pointing the aim directly at the player produced a 180° gap in world
# space; the controller picked the positive half of that gap and dove —
# flying straight down, perpendicular to the player's horizontal path.)
# Sized for a 20-30 m/s Sopwith: enough climb to reverse heading without
# bleeding so much speed that the apex stall traps the plane below it.
const IMMELMANN_PAST_DIST: float     = 600.0   # px past the player, along the approach axis
const IMMELMANN_CLIMB_ALT: float     = 800.0   # px above current altitude (climb ceiling)

# RECOVER — the only break-off paths from PURSUE.  The default engage state is
# to turn and fire; we only break off when the energy state makes a fight
# impossible.  Two cases, exactly as the player would expect a skilled
# opponent to behave:
#   • high altitude + low airspeed → RECOVER_DIVE (nose down, trade altitude
#     for speed to get back into the fight); unsafe below RECOVER_DIVE_MIN_ALT.
#   • low altitude                 → RECOVER_CLIMB (nose up, gain altitude so
#     the next pass has energy to spend).
# Above the safe-dive altitude and at healthy speed, the AI is in PURSUE and
# just snaps its nose onto the target.
const RECOVER_LEG_LENGTH        := 800.0   # px — how far behind us the recovery waypoint sits
const RECOVER_DIVE_MIN_ALT      := 500.0   # px — below this altitude a dive is unsafe
const RECOVER_DIVE_DY           := 200.0   # px — nose-down target offset (y down: positive = down)
const RECOVER_CLIMB_DY          := 300.0   # px — nose-up target offset (y down: negative = up)
const RECOVER_MIN_CLEARANCE     := 200.0   # px — recovery waypoint never aims below this
const RECOVER_EXIT_SPEED_RATIO  := 1.5     # speed/stall above which RECOVER exits to PURSUE
const RECOVER_MIN_TIME          := 0.6     # s — hysteresis floor, prevents mode flapping
const RECOVER_MAX_TIME          := 4.0     # s — never recover forever, force a re-attempt
# Turn-rate scaling.  The base HEADING_LERP_FACTOR (cruise) is the default
# lerp factor.  ENGAGE scales it from ENGAGE_TURN_LO (low-energy) up to
# ENGAGE_TURN_HI (high-energy), so a healthy fast/high plane snaps harder
# than a slow/low one.  RECOVER uses a fixed slow rate (the waypoint is
# already behind us; little yaw is needed).
const ENGAGE_TURN_LO            := 0.30    # low-energy: lazy turn, save what we have
const ENGAGE_TURN_HI            := 0.75    # high-energy: aggressive snap
const ENGAGE_CHOP_THROTTLE      := 0.35    # only when a steep, fast dive is about to crash

# Defensive reactions — a live target inside this rear cone, close and with
# its nose tracking us, means the player has our six: break.
const DEFENSIVE_RANGE       := 600.0
const DEFENSIVE_REAR_ANGLE  := 1.92   # rad (~110°) — |angle to target| beyond this = behind us
const DEFENSIVE_TRACK_ANGLE := 0.52   # rad (~30°) — target nose within this of us = tracking

# Stall-avoidance / energy management
# While pulling the nose up, the AI refuses to stall: below STALL_AVOID_SPEED_RATIO
# it noses down to rebuild airspeed instead of attempting a dramatic pull-up.
const STALL_AVOID_SPEED_RATIO   := 1.3    # speed / stall_speed below which it won't climb
const STALL_RECOVERY_PITCH      := 0.4     # nose-down command used to regain speed
# Minimum altitude (px, ~800 m) the plane must be above before the stall reflex is
# allowed to dive (positive pitch) to gain speed.  Below this it may only level
# out the climb — never push the nose down, to avoid diving into the ground.
const STALL_DIVE_MIN_ALTITUDE   := 800.0
# Sharp combat pull-ups (hard climbs/turns) are only permitted once the AI has at
# least COMBAT_ENERGY_MARGIN above stall in reserve; below it the pull-up is
# progressively softened toward level so the plane keeps building speed first.
const COMBAT_ENERGY_MARGIN      := 1.6     # speed / stall_speed required for hard maneuvers

# Patrol
const ALTITUDE_OSCILLATION_SPEED := 1.5
const ALTITUDE_OSCILLATION_AMP   := 30.0

# Pitch control — ENGAGE profile (aggressive, combat authority)
const PITCH_SENS_ENGAGE_BASE  := 2.8   # gain at cruise speed in combat
const PITCH_SENS_ENGAGE_LOW   := 1.0   # gain near stall in combat
const PITCH_DAMP_ENGAGE_MAX   := 2.2   # speed-damping at low speed in combat
const PITCH_DAMP_ENGAGE_MIN   := 0.4   # speed-damping at cruise in combat
const ANG_VEL_DAMP_ENGAGE     := 0.22  # flat ang-vel coefficient in combat

# Pitch control — CRUISE profile (conservative, patrol / return / takeoff)
const PITCH_SENS_CRUISE_BASE  := 2.0
const PITCH_SENS_CRUISE_LOW   := 0.8
const PITCH_DAMP_CRUISE_MAX   := 3.0
const PITCH_DAMP_CRUISE_MIN   := 0.6
const ANG_VEL_DAMP_CRUISE     := 0.40

# Heading smoothing (lerp factor per decision tick)
const HEADING_LERP_FACTOR     := 0.6  # 0 = never turns, 1 = instant snap
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

## Air-combat mode machine.  PURSUE is the default — turn toward the target
## and shoot, with turn rate scaling with energy.  RECOVER_DIVE / RECOVER_CLIMB
## are the only break-offs, taken when the energy state makes a fight
## impossible (high+slow → dive, low → climb).
enum EngageMode { PURSUE, RECOVER_DIVE, RECOVER_CLIMB }

class AIData:
	# Control outputs carried between frames
	var last_pitch_input: float = 0.0
	var last_throttle: float    = 0.0
	var desired_heading: float  = 0.0

	# Timers
	var incoming_bullet_timer: float = 0.0
	var flip_cooldown: float         = 0.0
	var bomb_cooldown_timer: float   = 0.0
	var patrol_time: float           = 0.0
	var takeoff_timer: float         = 0.0

	# Air-combat mode (boom & zoom) — see EngageMode.  0 = EngageMode.PURSUE.
	var engage_mode: int        = 0
	var engage_mode_timer: float = 0.0

	# Flags
	var is_using_autopilot: bool        = false

	func reset_control_outputs() -> void:
		last_pitch_input = 0.0
		last_throttle    = 0.0
		desired_heading  = 0.0
		engage_mode      = 0   # EngageMode.PURSUE
		engage_mode_timer = 0.0

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

var decision_interval: float = 0.02
var decision_accum: float = 0.0

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
	if biplane and biplane.has_signal("crashed_landed"):
		if biplane.crashed_landed.is_connected(_on_enemy_landed):
			biplane.crashed_landed.disconnect(_on_enemy_landed)
		biplane.crashed_landed.connect(_on_enemy_landed)
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
	}
	for state_name in state_scripts:
		var state_node := State.new()
		state_node.name = state_name
		state_node.set_script(state_scripts[state_name])
		fsm_node.add_child(state_node)

	fsm_node.set_ai_controller(self)
	add_child(fsm_node)
	ai_fsm = fsm_node
	ai_fsm.initialize(&"grounded")
	# The controller is the only driver: it ticks the FSM at decision_interval
	# (D2/D3), so the FSM must not self-drive.
	ai_fsm.self_driven = false



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
		# Single destruction path: reflect the wreck in the FSM (idempotent) and
		# stop driving control outputs. Respawn later returns it to GROUNDED.
		if ai_fsm and ai_fsm.is_active():
			ai_fsm.transition_to(&"destroyed")
		pilots[0].reset_control_outputs()
		return

	# Apply the pilot's control outputs once per physics frame. State scripts
	# only *compute* outputs (at the 20 Hz decision cadence); the controller owns
	# application so there is exactly one application path (D4).
	_apply_input(pilots[0].last_pitch_input, pilots[0].last_throttle)
	_check_flip_needed()

	# Drive the FSM at the decision cadence using accumulated real elapsed time,
	# so state timers track wall time exactly (D8).
	decision_accum += delta
	if decision_accum >= decision_interval:
		var step := decision_accum
		decision_accum = 0.0
		if ai_fsm and ai_fsm.is_active():
			ai_fsm.tick(step)


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
	return ta.flight_state != biplane.FlightState.CRASHED \
			and ta.flight_state != biplane.FlightState.FALLING

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
	# While the player is airborne, cruise above their altitude so the patrol
	# always holds potential energy to dive with (capped ≤ PATROL_MAX_ALTITUDE,
	# itself below the 1800 px engine-taper line).  With the player on the
	# ground, keep the legacy low orbit ready to pounce on takeoff.
	var cruise_alt := PATROL_ALTITUDE
	if _is_player_airborne():
		var player_alt := _get_altitude_above_ground_for(target)
		cruise_alt = clampf(player_alt + PATROL_ALTITUDE_ADVANTAGE,
			PATROL_CRUISE_MIN, PATROL_MAX_ALTITUDE)
	var aim       = Vector2(patrol_x, ground_y - cruise_alt + osc)
	_steer_toward(aim)
	return _compute_pitch_from_heading(false)

func _compute_engage_pitch() -> float:
	if not biplane or not target:
		return 0.0

	var target_pos = target.global_position
	var dx         = wrapf(target_pos.x - biplane.global_position.x, -TERRAIN_LENGTH * 0.5, TERRAIN_LENGTH * 0.5)
	var dy         = target_pos.y - biplane.global_position.y
	var distance   = sqrt(dx * dx + dy * dy)

	_update_engage_mode(distance)

	# Turn rate scales with energy: a healthy, fast, high-altitude plane pulls
	# a tighter turn than a low, slow one.  Both axes contribute, and the
	# plane is only as loose as its weakest axis.  RECOVER modes use a fixed
	# slow rate — the waypoint is already behind us, so a snap is wasted.
	var turn_rate := HEADING_LERP_FACTOR
	match pilots[0].engage_mode:
		EngageMode.PURSUE:
			turn_rate = _engage_turn_rate()
			var aim = _lead_pursuit_point(target_pos, 0.85)
			# High-energy overshoot: if we are actually moving away from the
			# target yet have altitude or airspeed to spend, hard-reverse the
			# heading back toward it (full lead + max snap) rather than flying
			# off the map in the wrong X direction.
			if _is_flying_away() \
					and (_get_altitude_above_ground() > FLYAWAY_TURNAROUND_ALTITUDE \
					     or _speed_ratio() > FLYAWAY_TURNAROUND_SPEED_RATIO):
				# Immelmann turnaround: aim PAST the player and HIGH above.
				# The relative vector (toward-player + past, and up) maps in
				# the gravity frame to a large negative angle_diff (climb) for
				# BOTH travel directions — a rightward upright plane and a
				# leftward inverted plane both pitch up and arc over the
				# target.  See IMMELMANN_* constants above for the rationale.
				var dir_to_player := signf(dx)
				if dir_to_player == 0.0:
					dir_to_player = 1.0
				aim = Vector2(
					biplane.global_position.x + dx + dir_to_player * IMMELMANN_PAST_DIST,
					biplane.global_position.y - IMMELMANN_CLIMB_ALT
				)
				turn_rate = ENGAGE_TURN_HI
			_steer_toward(aim, turn_rate)
		_:
			_steer_toward(_recover_waypoint(pilots[0].engage_mode), ENGAGE_TURN_LO)

	return _compute_pitch_from_heading(true)   # ENGAGE profile

## True when the AI is genuinely moving away from its target (velocity vector
## points broadly opposite to the line to target).
func _is_flying_away() -> bool:
	if not biplane or not target:
		return false
	var to_tgt := target.global_position - biplane.global_position
	if to_tgt.length_squared() < 1.0:
		return false
	var speed: float = biplane.velocity.length()
	if speed < 1.0:
		return false
	return (biplane.velocity / speed).dot(to_tgt.normalized()) < -0.2

# ---------------------------------------------------------------------------
# ENGAGEMENT ENERGY MODES  (turn + fire vs. recover)
# ---------------------------------------------------------------------------

## Mode selection with hysteresis, called once per decision tick from
## _compute_engage_pitch.  The default is PURSUE — turn toward the target
## and fire.  The only break-offs are when the energy state makes a fight
## impossible:
##   • low altitude        → RECOVER_CLIMB (gain altitude before re-engaging)
##   • high + slow         → RECOVER_DIVE  (trade altitude for speed)
## Either recovery exits to PURSUE when speed is restored, after a hysteresis
## floor, or after a hard time limit.
func _update_engage_mode(_distance: float) -> void:
	var p := pilots[0]
	p.engage_mode_timer += decision_interval
	var sr  := _speed_ratio()
	var alt := _get_altitude_above_ground()

	# Currently recovering — check exit conditions before re-evaluating.
	if p.engage_mode == EngageMode.RECOVER_DIVE or p.engage_mode == EngageMode.RECOVER_CLIMB:
		var speed_ok := sr >= RECOVER_EXIT_SPEED_RATIO \
				or p.engage_mode_timer >= RECOVER_MAX_TIME
		if (speed_ok and p.engage_mode_timer >= RECOVER_MIN_TIME) \
				or p.engage_mode_timer >= RECOVER_MAX_TIME:
			p.engage_mode = EngageMode.PURSUE
			p.engage_mode_timer = 0.0
		return

	# Altitude is the dominant axis: a low plane cannot safely dive, so it
	# must climb regardless of its airspeed.  Only above RECOVER_DIVE_MIN_ALT
	# do we consider trading altitude for speed.
	if alt < RECOVER_DIVE_MIN_ALT:
		p.engage_mode = EngageMode.RECOVER_CLIMB
		p.engage_mode_timer = 0.0
	elif sr < EXTEND_ENTER_SPEED_RATIO:
		p.engage_mode = EngageMode.RECOVER_DIVE
		p.engage_mode_timer = 0.0
	else:
		p.engage_mode = EngageMode.PURSUE
		p.engage_mode_timer = 0.0

## Turn rate for PURSUE: scale HEADING_LERP_FACTOR with the plane's energy so
## a high/fast plane snaps harder than a low/slow one.  The energy measure is
## `max(speed_t, alt_t)` — the user said "tighter the higher in altitude OR
## higher airspeed they have", so whichever axis has the most room dominates.
func _engage_turn_rate() -> float:
	var sr  := _speed_ratio()
	var alt := _get_altitude_above_ground()
	# speed_t: 0 at ~stall, 1 at the prop-efficiency peak (~1.9× stall) and above.
	var speed_t := clampf((sr - 0.6) / 1.3, 0.0, 1.0)
	# alt_t: 0 at ground, 1 at the typical combat ceiling.
	var alt_t   := clampf(alt / 1200.0, 0.0, 1.0)
	var energy  := maxf(speed_t, alt_t)
	return lerpf(ENGAGE_TURN_LO, ENGAGE_TURN_HI, energy)

## Recovery waypoint: directly behind the AI, with a vertical bias matching
## the recovery reason.  RECOVER_DIVE → nose down (y +) to trade altitude
## for speed; RECOVER_CLIMB → nose up (y -) to gain altitude.  The waypoint
## is never aimed below the terrain.
func _recover_waypoint(mode: int) -> Vector2:
	var my_pos = biplane.global_position
	var dx := wrapf(target.global_position.x - my_pos.x, -TERRAIN_LENGTH * 0.5, TERRAIN_LENGTH * 0.5)
	var away := -signf(dx)
	if away == 0.0:
		away = signf(biplane.velocity.x)
		if away == 0.0:
			away = 1.0
	var dy: float
	if mode == EngageMode.RECOVER_DIVE:
		dy = RECOVER_DIVE_DY   # y down: positive dy = lower on screen = nose down
	else:
		dy = -RECOVER_CLIMB_DY # y down: negative dy = higher on screen = nose up
	var wx: float = my_pos.x + away * RECOVER_LEG_LENGTH
	# Climb waypoint: never below the current altitude (climbing); the climb
	# offset is already small.  Dive waypoint: clamp to terrain clearance.
	var wy: float
	if mode == EngageMode.RECOVER_DIVE:
		wy = minf(my_pos.y + dy, _get_ground_height(wx) - RECOVER_MIN_CLEARANCE)
	else:
		wy = my_pos.y + dy
	return Vector2(wx, wy)

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
		return -0.6

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
	# Panic pull-ups close to the terrain stay as raw pitch overrides.
	if alt < CRITICAL_ALTITUDE_ABOVE_GROUND:
		return -1.0
	elif alt < DANGER_ALTITUDE_ABOVE_GROUND:
		return -0.6

	# Break turn, steered through the heading controller so the maneuver is a
	# clean climbing/diving turn away from the attacker rather than the old
	# flat raw-pitch jink.  Fast planes zoom — a climbing target is the hardest
	# to track in 2D; slow planes dive shallowly for speed when there is
	# height to spare (the impact reflex guards the ground), else hold level.
	var my_pos := biplane.global_position
	var away := 1.0
	if target:
		away = -signf(wrapf(target.global_position.x - my_pos.x,
			-TERRAIN_LENGTH * 0.5, TERRAIN_LENGTH * 0.5))
	if away == 0.0:
		away = signf(biplane.velocity.x) if biplane.velocity.x != 0.0 else 1.0

	var sr := _speed_ratio()
	var dy := -400.0
	if sr < STALL_AVOID_SPEED_RATIO:
		dy = 150.0 if alt > STALL_DIVE_MIN_ALTITUDE * 0.5 else 0.0
	elif pilots[0].incoming_bullet_timer > 0.0:
		dy = -500.0   # under fire with energy to spend: break harder
	_steer_toward(Vector2(my_pos.x + away * 500.0, my_pos.y + dy))
	return _compute_pitch_from_heading(true)

func _compute_return_pitch() -> float:
	if not biplane:
		return 0.0

	# Signed shortest horizontal offset to the home base (handles world wrap).
	var dx         = wrapf(home_base_x - biplane.global_position.x, -TERRAIN_LENGTH * 0.5, TERRAIN_LENGTH * 0.5)
	var dist_x     = absf(dx)
	var alt        = _get_altitude_above_ground()
	var ground_y   = _get_ground_height(home_base_x)
	# Direction we are travelling toward the base (used to place the flare aim).
	var approach_dir = sign(dx) if absf(dx) > 1.0 else sign(biplane.velocity.x)

	# Committed final approach — descend the rest of the way and flare.
	if dist_x < RETURN_FINAL_DIST:
		# Establish the landing home base reference once, on short final.
		if dist_x < HOME_PROXIMITY and not pilots[0].is_using_autopilot:
			_enable_autopilot_for_landing()

		if alt < RETURN_FLARE_ALT:
			# Flare: aim a point well ahead at our CURRENT altitude so the nose
			# levels out and the sink rate is bled off instead of being driven
			# into the runway.  Gentle, level-ish attitude = soft touchdown.
			var aim = Vector2(biplane.global_position.x + approach_dir * 300.0, biplane.global_position.y)
			_steer_toward(aim)
			return _compute_pitch_from_heading(false)

		# Follow the glide slope down to the numbers at the home base.
		var glide_alt = maxf(0.0, dist_x * RETURN_GLIDE_SLOPE)
		var aim = Vector2(home_base_x, ground_y - glide_alt)
		_steer_toward(aim)
		return _compute_pitch_from_heading(false)

	# En-route: ride the glide slope from cruise altitude down toward the base.
	# (No lead-pursuit here — the base is stationary, so steering straight at it
	# is correct.  The old code offset the aim by the *player's* velocity and
	# therefore never homed on the actual spawn point.)
	var desired_alt = minf(PATROL_ALTITUDE, dist_x * RETURN_GLIDE_SLOPE)
	var aim = Vector2(home_base_x, ground_y - desired_alt)
	_steer_toward(aim)
	return _compute_pitch_from_heading(false)

# ---------------------------------------------------------------------------
# HEADING → PITCH  (Options B + C)
# ---------------------------------------------------------------------------

## is_engaging = true  → ENGAGE profile (aggressive, AoA blend suppressed)
## is_engaging = false → CRUISE profile (conservative, AoA blend active)
##
## The heading error is computed in the GRAVITY FRAME (see ATTITUDE FRAMES
## above): desired_heading (world-space) and the plane's current pitch are
## both converted before being compared, so the same error commands the same
## climb/dive whether the plane is flying rightward upright or leftward
## inverted.  (The old rotation-space diff read with the opposite sign for
## inverted planes, steering every heading-guided behaviour away from its
## target attitude whenever is_barrel_rolled was true.)
func _compute_pitch_from_heading(is_engaging: bool) -> float:
	if not biplane:
		return 0.0

	var avatar = _get_avatar()

	var angle_diff: float
	if avatar:
		angle_diff = wrapf(avatar.gravity_angle(pilots[0].desired_heading) \
			- avatar.gravity_pitch(), -PI, PI)
	else:
		angle_diff = wrapf(pilots[0].desired_heading - biplane.rotation, -PI, PI)
	if absf(angle_diff) < HEADING_DEADBAND:
		return 0.0

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
	# Read in the gravity frame so it DAMPS for both travel directions (in the
	# rotation frame an inverted plane's climb/dive rates have flipped signs,
	# which previously turned this term into anti-damping when inverted).
	var angular_vel: float = avatar.gravity_pitch_rate() if avatar else 0.0
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
## desired_heading stays a WORLD-SPACE angle (Vector2.angle()); the conversion
## into the gravity frame happens only when it is consumed in
## _compute_pitch_from_heading(), so steering never branches on direction.
## Lerping rather than hard-setting filters single-frame jitter from a moving
## target and prevents the heading from flipping sign between ticks.
## Pass turn_rate < 0 to use the default HEADING_LERP_FACTOR; otherwise the
## caller overrides the lerp factor for this tick (e.g. ENGAGE scales it with
## energy so a fast/high plane snaps harder than a slow/low one).
func _steer_toward(aim_point: Vector2, turn_rate: float = -1.0) -> void:
	if not biplane:
		return
	var target_heading = (aim_point - biplane.global_position).angle()
	var rate := HEADING_LERP_FACTOR if turn_rate < 0.0 else turn_rate
	pilots[0].desired_heading = lerp_angle(pilots[0].desired_heading, target_heading, rate)

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
	if avatar.flight_state != biplane.FlightState.STALLED:
		return false

	var max_aoa = deg_to_rad(avatar.model_params.get("max_aoa", 16.0))
	var recovery_threshold = max_aoa * 0.7

	var actual_aoa := 0.0
	if biplane.velocity.length() > 0.5:
		actual_aoa = absf(wrapf(biplane.rotation - biplane.velocity.angle(), -PI, PI))

	if actual_aoa < recovery_threshold:
		return false   # recovered — release the override

	# Hard override: aim ~5° above the relative wind for a touch of lift.
	# Computed in the gravity frame so "above" means toward the sky in either
	# travel direction — in world space a leftward/inverted plane's "above"
	# has the opposite angle sign, so the old raw-angle math aimed it BELOW
	# the wind and deepened the stall instead of recovering.
	var wind_gp      = avatar.gravity_angle(biplane.velocity.angle())
	var recovery_heading = avatar.world_angle(wind_gp - deg_to_rad(5.0))
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
	if not biplane:
		return 1.0
	# Default policy: full throttle.  A high-energy AI needs every erg of thrust
	# to press the attack, close on the target, and recover from a maneuver.
	# Chop the throttle ONLY when the predictive terrain-impact check reports
	# a crash inside the speed-scaled window AND we are at high speed AND
	# pointed at the ground — i.e. an unrecoverable steep dive.  The other
	# cases (controlled dive, low alt, fast but level) all keep full throttle
	# so the AI keeps the energy it has and stays aggressive.
	var ppm: float = biplane.get("pixels_per_meter") if "pixels_per_meter" in biplane else 16.0
	var max_speed_px: float = avatar.model_params.get("max_speed_ms", 50.6) * ppm
	if biplane.velocity.y > 250.0 \
			and biplane.velocity.length() > max_speed_px * 0.85 \
			and _terrain_impact_time() < _impact_window():
		return ENGAGE_CHOP_THROTTLE
	return 1.0

func _compute_evade_throttle() -> float:
	return 1.0

func _compute_return_throttle(avatar) -> float:
	var dx     = wrapf(home_base_x - biplane.global_position.x, -TERRAIN_LENGTH * 0.5, TERRAIN_LENGTH * 0.5)
	var dist_x = absf(dx)
	var alt    = _get_altitude_above_ground()
	if dist_x < RETURN_FINAL_DIST:
		if alt < RETURN_FLARE_ALT:
			return RETURN_FLARE_THROTTLE   # idle on the flare
		return RETURN_FINAL_THROTTLE      # short final, slow down
	return RETURN_CRUISE_THROTTLE        # en-route, hold speed

# ---------------------------------------------------------------------------
# ENERGY STATE
# ---------------------------------------------------------------------------

## Current speed as a multiple of the plane's stall speed — the AI's single
## energy gauge.  ~1.9 ≈ the prop-efficiency peak (max thrust at ~40 m/s).
func _speed_ratio() -> float:
	if not biplane:
		return 1.0
	var avatar = _get_avatar()
	var stall: float = avatar.stall_speed_ms if avatar else 21.4
	var ppm: float = biplane.get("pixels_per_meter") if "pixels_per_meter" in biplane else 10.0
	return biplane.velocity.length() / ppm / maxf(stall, 1.0)

func _has_energy_advantage() -> bool:
	if not biplane or not target:
		return false
	var alt_edge = _get_altitude_above_ground() - _get_altitude_above_ground_for(target) \
				   > ENERGY_ALTITUDE_ADVANTAGE
	return alt_edge and _speed_ratio() >= ENERGY_SPEED_RATIO_GOOD

func _is_low_energy() -> bool:
	if not biplane:
		return false
	return _speed_ratio() < ENERGY_SPEED_RATIO_GOOD

## True when a live target sits inside our rear cone, close, with its nose
## tracking us — i.e. the player has our six.  The engaging state breaks into
## an evade when this trips; without it you could sit on their tail forever.
func _should_evade_defensively() -> bool:
	if not biplane or not target or not _is_target_alive():
		return false
	var to_tgt := target.global_position - biplane.global_position
	to_tgt.x = wrapf(to_tgt.x, -TERRAIN_LENGTH * 0.5, TERRAIN_LENGTH * 0.5)
	var dist := to_tgt.length()
	if dist > DEFENSIVE_RANGE or dist < 1.0:
		return false
	var my_fwd := Vector2(cos(biplane.rotation), sin(biplane.rotation))
	# Target in the rear cone...
	if absf(my_fwd.angle_to(to_tgt.normalized())) < DEFENSIVE_REAR_ANGLE:
		return false
	# ...and with its nose pointed near us (tracking, not merely passing).
	var tgt_fwd := Vector2(cos(target.rotation), sin(target.rotation))
	return absf(tgt_fwd.angle_to(-to_tgt.normalized())) <= DEFENSIVE_TRACK_ANGLE

# ---------------------------------------------------------------------------
# TAKE-OFF HANDLER
# ---------------------------------------------------------------------------

func _decision_takeoff(avatar) -> void:
	var stall_speed: float = 21.4
	if avatar:
		stall_speed = avatar.stall_speed_ms
	var ppm: float = biplane.get("pixels_per_meter") if "pixels_per_meter" in biplane else 16.0
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
		# Hold the nose level until ~2× stall (px/s) to build flying speed
		# before the climb — comparison is in px/s, not the raw m/s stall value.
		var rotate_speed_px: float = stall_speed * ppm * 2.0
		if speed < rotate_speed_px:
			pilots[0].last_pitch_input = clampf(-0.03 * (speed / rotate_speed_px), -0.03, 0.0)
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
func _apply_reflexes(pitch: float, throttle: float, allow_ground_avoid := true, allow_ceiling := true) -> Array:
	if _stall_reflex():
		return [pilots[0].last_pitch_input, pilots[0].last_throttle]

	# On the committed final approach of a RETURNING plane we must let it descend
	# the rest of the way to the runway, so the climb-forcing ground-avoidance
	# reflexes (altitude + pull-up) are suppressed — otherwise they pitch the nose
	# up below ~80 px and the plane can never actually touch down.
	var ground_avoid := allow_ground_avoid
	if ai_fsm.current_key == &"returning":
		var dx = wrapf(home_base_x - biplane.global_position.x, -TERRAIN_LENGTH * 0.5, TERRAIN_LENGTH * 0.5)
		if absf(dx) < RETURN_FINAL_DIST:
			ground_avoid = false

	var alt_fix = 0.0
	var pullup_fix = 0.0
	var impact_t := INF
	if ground_avoid:
		alt_fix = _altitude_reflex()
		pullup_fix = _pull_up_reflex()
		impact_t = _terrain_impact_time()

	if alt_fix != 0.0:
		pitch = alt_fix
		# The engage state owns its own throttle policy (1.0 by default, chop
		# only on a steep+fast+imminent-crash triple).  Don't override it here
		# — the alt reflex's only job in engage is to pull the nose up.
		# For other states (patrol/evade/return) the low-altitude pull-up is
		# paired with a power surge so the engine can climb the plane out of
		# trouble; the previous maxf is kept for those paths.
		if ai_fsm.current_key != &"engaging":
			throttle = maxf(throttle, 0.8)

	var ceil_fix = _altitude_ceiling_reflex() if allow_ceiling else 0.0
	if ceil_fix != 0.0:
		pitch = maxf(pitch, ceil_fix)

	var cutoff_fix = _engine_cutoff_avoid_reflex() if allow_ceiling else 0.0
	if cutoff_fix != 0.0:
		pitch = maxf(pitch, cutoff_fix)

	var terrain_fix = _terrain_projection_reflex()
	if terrain_fix != 0.0:
		pitch = minf(pitch, terrain_fix)

	if pullup_fix != 0.0:
		pitch = pullup_fix

	var energy = _energy_stall_reflex(pitch, throttle)
	pitch = energy[0]
	throttle = energy[1]

	# Predictive terrain avoidance, applied LAST so it overrides even the
	# energy gate: samples the velocity vector for a terrain intersection and
	# pulls up early, scaled by urgency — this is what stops dive-attack
	# crashes.  A slow plane gets only a shallow pull: it cannot zoom, and
	# yanking the nose up near stall would just drop it out of the sky.
	# Throttle is intentionally NOT raised here: the engage throttle policy
	# (1.0 by default, chopped only on a steep+fast+imminent-crash triple) is
	# the one knob that controls engine power.  This reflex only ever touches
	# pitch.
	if impact_t < _impact_window():
		var urgency := 1.0 - clampf(impact_t / _impact_window(), 0.0, 1.0)
		var pull := lerpf(-0.35, -1.0, urgency)
		if _speed_ratio() < STALL_AVOID_SPEED_RATIO:
			pull = maxf(pull, -0.45)
		pitch = minf(pitch, pull)

	return [pitch, throttle]

## Seconds until the current velocity vector intersects the terrain (INF when
## the trajectory is clear).  Samples future positions, so rising ground ahead
## is caught as well as a straight descent.  This is the predictive layer that
## lets the AI pull up BEFORE the fixed low-altitude panic reflexes would fire.
func _terrain_impact_time() -> float:
	if not biplane:
		return INF
	var pos := biplane.global_position
	var vel: Vector2 = biplane.velocity
	if vel.length_squared() < 100.0:
		return INF
	for t in IMPACT_SAMPLE_TIMES:
		var future: Vector2 = pos + vel * t
		if future.y >= _get_ground_height(future.x) - IMPACT_ALT_MARGIN:
			return t
	return INF

## Pull-up window in seconds: the base time-to-impact scaled up with speed,
## since a faster plane needs more sky (and more lead time) to arc out of a dive.
func _impact_window() -> float:
	if not biplane:
		return PULL_UP_TIME_TO_GROUND
	return PULL_UP_TIME_TO_GROUND * clampf(biplane.velocity.length() / 400.0, 1.0, 2.0)

## Stall-avoidance / energy management.  When the AI wants to pull the nose up
## (negative pitch = climb in this convention) while close to stall speed, it
## instead noses down to rebuild airspeed rather than attempting a dramatic
## low-speed pull-up that would stall it out.  Sharp combat climb commands are
## also gated behind an energy margin: below COMBAT_ENERGY_MARGIN the pull-up is
## progressively softened toward level so the plane keeps accelerating first.
func _energy_stall_reflex(pitch: float, throttle: float) -> Array:
	var avatar = _get_avatar()
	if not avatar or not biplane:
		return [pitch, throttle]
	if _is_grounded() \
			or avatar.flight_state == biplane.FlightState.CRASHED \
			or avatar.flight_state == biplane.FlightState.FALLING:
		return [pitch, throttle]

	var stall_speed: float = avatar.stall_speed_ms if avatar.stall_speed_ms else 21.4
	var ppm: float = biplane.get("pixels_per_meter") if "pixels_per_meter" in biplane else 10.0
	var speed_ms: float = biplane.velocity.length() / ppm
	var speed_ratio: float = speed_ms / maxf(stall_speed, 1.0)

	# Wants to pull the nose up (climb) — the input that risks a low-speed stall.
	var wants_climb := pitch < -0.05

	# 1) Near-stall: never pull up.  Only ever reduce the climb — level the nose
	#    out at most.  A dive (nose-down) is only permitted when the plane is
	#    above STALL_DIVE_MIN_ALTITUDE, where it has height to trade for speed.
	if wants_climb and speed_ratio < STALL_AVOID_SPEED_RATIO:
		throttle = 1.0
		if _get_altitude_above_ground() > STALL_DIVE_MIN_ALTITUDE:
			pitch = STALL_RECOVERY_PITCH   # dive to rebuild speed
		else:
			pitch = 0.0                    # level out only — never dive

	# 2) Combat energy gate: hard pull-ups require an energy margin. Below the
	#    margin, scale the climb command down toward level as energy drops so the
	#    plane keeps building speed instead of bleeding it in a sharp maneuver.
	#    This only ever reduces the climb toward level — it never dives.
	elif wants_climb and speed_ratio < COMBAT_ENERGY_MARGIN:
		var margin_t := clampf(
			(speed_ratio - STALL_AVOID_SPEED_RATIO) /
			(COMBAT_ENERGY_MARGIN - STALL_AVOID_SPEED_RATIO), 0.0, 1.0)
		pitch = lerpf(0.0, pitch, margin_t)

	return [pitch, throttle]

func _pull_up_reflex() -> float:
	if not biplane or _get_altitude_above_ground() > PULL_UP_ALTITUDE:
		return 0.0
	# Nose below the horizon → pull up.  gravity_pitch() reads identically in
	# either travel direction (the old raw `rotation > 0.1` check was always
	# true for an inverted plane, firing even when it was already climbing).
	var avatar = _get_avatar()
	if not avatar:
		return 0.0
	return -0.5 if avatar.gravity_pitch() > 0.1 else 0.0

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
		return 0.7
	elif alt > MAX_ALTITUDE - 150.0:
		return 0.35
	return 0.0

## Hard safety against the engine-cutoff altitude.  Biplane.ENGINE_CUTOFF_ALTITUDE
## is where the engine quits (thrust already tapers from ~1800 px).  If the plane
## climbs within ENGINE_CUTOFF_AVOID_FRACTION of that altitude, force the nose
## down proportionally so it never reaches the dead zone where it would stall.
func _engine_cutoff_avoid_reflex() -> float:
	if not biplane:
		return 0.0
	var cutoff: float = Biplane.ENGINE_CUTOFF_ALTITUDE
	var threshold := cutoff * ENGINE_CUTOFF_AVOID_FRACTION
	var alt := _get_altitude_above_ground()
	if alt < threshold:
		return 0.0
	var urgency := clampf((alt - threshold) / maxf(cutoff - threshold, 1.0), 0.0, 1.0)
	return lerpf(0.3, 0.7, urgency)   # positive = nose down

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
	var dx         = wrapf(target_pos.x - biplane.global_position.x, -TERRAIN_LENGTH * 0.5, TERRAIN_LENGTH * 0.5)
	var dy         = target_pos.y - biplane.global_position.y
	var dist       = sqrt(dx * dx + dy * dy)
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
	var dx        = wrapf(tgt_pos.x - my_pos.x, -TERRAIN_LENGTH * 0.5, TERRAIN_LENGTH * 0.5)
	var dy        = tgt_pos.y - my_pos.y
	var dist      = sqrt(dx * dx + dy * dy)
	if dist > MAX_FIRE_RANGE or dist < MIN_FIRE_RANGE:
		return
	var tgt_vel      = target.velocity if "velocity" in target else Vector2.ZERO
	var lead_time    = dist / 1600.0
	var predicted    = tgt_pos + tgt_vel * lead_time
	var bullet_dir   = (predicted - my_pos).normalized()
	var my_hdg       = Vector2(cos(biplane.rotation), sin(biplane.rotation))
	var angle_diff   = bullet_dir.angle_to(my_hdg)
	var shot_quality = 1.0 - (absf(angle_diff) / FIRE_CONE_ANGLE)
	# Aggressive fire discipline: open up earlier at all ranges to keep the
	# player under pressure, not just when the solution is near-perfect.
	var threshold    = 0.25 if dist < 200.0 else 0.35
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

## True when the target is a biplane that is currently airborne (FLYING or
## STALLED).  Ground-structure targets count as "not airborne".
func _is_player_airborne() -> bool:
	if not target or not target.has_method("get_avatar_data"):
		return false
	var ta = target.get_avatar_data(0)
	if not ta:
		return false
	return ta.flight_state == biplane.FlightState.FLYING \
			or ta.flight_state == biplane.FlightState.STALLED

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

func _is_fuel_low() -> bool:
	var avatar = _get_avatar()
	return avatar and avatar.fuel < 20.0

# ---------------------------------------------------------------------------
# INPUT APPLICATION
# ---------------------------------------------------------------------------

func _apply_input(pitch: float, throttle_amount: float) -> void:
	## `pitch` is a gravity-frame command (negative = climb, positive = dive)
	## and is forwarded verbatim: the single is_barrel_rolled conversion lives
	## inside Biplane.set_ai_input() via AvatarData.pitch_command_to_rotation_input().
	## Never flip the sign here — double-flipping cancels the conversion out
	## (which previously made leftward-spawned, is_barrel_rolled=true AI planes
	## pitch into the ground on takeoff instead of climbing).
	if not biplane.has_method("set_ai_input"):
		return
	biplane.set_ai_input(pitch, throttle_amount)

# ---------------------------------------------------------------------------
# AUTOPILOT / LANDING
# ---------------------------------------------------------------------------

func _enable_autopilot_for_landing() -> void:
	pilots[0].is_using_autopilot = true
	if biplane.has_method("enable_autopilot"):
		biplane.enable_autopilot()
	# Keep this plane's own faction on its existing homebase so a later respawn
	# re-applies the correct model.  IMPORTANT: do NOT recreate the homebase here.
	# The homebase was created once at the plane's real spawn location in
	# main.gd (_spawn_enemies_and_targets) using ENEMY_SPAWN_RUNWAY_OFFSET.  A
	# previous version rewrote it via setup_faction_homebase(1, home_base_x, …)
	# on every autopilot landing, which relocated the spawn point to the runway
	# centre (dropping the +80 offset and using ground_y - 12) and renumbered
	# the homebase id to 1 — so every respawn after the first landing happened
	# at the wrong place.  refresh_homebase_faction updates only the faction,
	# preserving the spawn position and id.
	if biplane.has_method("refresh_homebase_faction") and biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			biplane.refresh_homebase_faction(avatar, avatar.faction)

# ---------------------------------------------------------------------------
# CRASH / RESPAWN
# ---------------------------------------------------------------------------

func _on_enemy_crashed(is_midair: bool = false) -> void:
	## The crash explosion, debris, fire, smoke, screen-shake and explosion
	## sound are produced once inside Biplane._on_avatar_crashed (the single
	## funnel every destructive end-state reaches), so AI planes now look and
	## sound identical to the player.  Kept only for the respawn bookkeeping flag.
	_crashed_exploded = true

func _on_enemy_landed(avatar_id: int) -> void:
	## The wreck has hit the ground — queue the fixed 2s respawn.
	if RespawnManager:
		RespawnManager.queue_respawn(_respawn_id, RespawnManager.RESPAWN_DELAY)

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

	if ai_fsm and 	ai_fsm.is_active():
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

	# Flip when the world travel direction (sign of velocity.x) disagrees with
	# the nose's travel direction (+1 rightward / -1 leftward).  The speed
	# gate keeps the plane from flipping while parked or taxiing slowly.
	var x_speed = avatar.stall_speed_ms * 10.0
	if absf(biplane.velocity.x) < x_speed:
		return
	if signf(biplane.velocity.x) != avatar.travel_sign():
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
