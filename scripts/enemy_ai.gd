extends Node

# ============================================================================
# AI pilot for enemy biplanes.
#
# DESIGN — FSM-DRIVEN, AIM-BASED STEERING
# ----------------------------------------
# Each state script writes three things onto the AIStateMachine (see
# scripts/states/ai/ai_state_machine.gd):
#
#   current_aim_point      Vector2  where to steer; INF = hold last heading
#   current_pitch_override float     gravity-frame pitch; INF = use heading
#   current_throttle       float     0..1 throttle
#
# Plus a stickiness floor (min_state_time) to commit to a maneuver before
# allowing any transition. The controller's `_physics_process` reads
# those fields, steers the heading toward the aim (or applies the pitch
# override), derives pitch from the heading via the AvatarData gravity-
# frame helpers, and applies reflexes (terrain / energy / stall).
#
# Specialized helpers (takeoff, climb-to-patrol, evade, return, stall
# recovery) live in this file and are called by their respective states;
# the rest of the AI is just "set aim, set throttle".
#
# The previous system had one `_compute_*_pitch()` / `_compute_*_throttle()`
# pair per state plus an internal recovery sub-mode enum; that complexity
# has been collapsed onto the FSM's intent fields plus a few aim
# helpers.
# ============================================================================

# ---------------------------------------------------------------------------
# CONSTANTS  (shared, never written at runtime)
# ---------------------------------------------------------------------------

# Terrain wrap length is owned by Biplane — reference Biplane.TERRAIN_LENGTH
# everywhere so wrap math can never silently diverge from the world size.

# Altitude thresholds (pixels above terrain)
const PATROL_ALTITUDE                := 250.0
const PATROL_CRUISE_MIN              := 800.0
const PATROL_ALTITUDE_ADVANTAGE      := 300.0
const PATROL_MAX_ALTITUDE            := 1500.0
const MIN_ALTITUDE_ABOVE_GROUND      := 100.0
const DANGER_ALTITUDE_ABOVE_GROUND   := 60.0
const CRITICAL_ALTITUDE_ABOVE_GROUND := 20.0
const PULL_UP_ALTITUDE               := 200.0
const MAX_ALTITUDE_FRACTION          := 0.4
const MAX_ALTITUDE                   := 1600.0
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
# the far end of the map, not just orbit its own base.
const DETECTION_RANGE       := 8000.0
const ENGAGEMENT_RANGE      := 5000.0
const MAX_FIRE_RANGE        := 700.0
const MIN_FIRE_RANGE        := 30.0
const FIRE_CONE_ANGLE       := 0.36
const ADVANTAGE_THRESHOLD   := 50.0
const RETURN_REENGAGE_RANGE := 400.0
const HOME_PROXIMITY        := 100.0

# Fuel floor (percent of avatar.fuel, 0..100) at or below which a patrolling
# or evading plane gives up and returns to base to refuel.  The task spec
# requires a 30% floor; the legacy code used a hardcoded 20.0.
const FUEL_RETURN_THRESHOLD := 30.0

# Return-to-base landing approach (designed to land gently, not crash)
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
# safely press an attack (it would mush into a stall).
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

# RECOVER — sub-state of engaging.  PURSUE is the default — turn toward the
# target and shoot.  RECOVER_DIVE / RECOVER_CLIMB are the only break-offs,
# taken when the energy state makes a fight impossible (high+slow → dive,
# low → climb).  Above the safe-dive altitude and at healthy speed, the AI
# is in PURSUE and just snaps its nose onto the target.
const RECOVERY_NONE            := 0
const RECOVERY_DIVE            := 1
const RECOVERY_CLIMB           := 2
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
# Below this AGL the climb tilt is capped to 90% of the plane's max landing
# tilt (see _takeoff_pitch) so AI pilots don't loop themselves into a crash
# during the initial climb-out.  Covers the whole takeoff (the state hands off
# to patrolling above PATROL_ALTITUDE).
const TAKEOFF_TILT_LIMIT_ALT := 250.0

# Bombing
const GROUND_ATTACK_ALTITUDE    := 300.0
const BOMB_OVERHEAD_X_THRESHOLD := 200.0
const BOMB_ANGLE_TOLERANCE      := 0.175

# ---------------------------------------------------------------------------
# PILOT STATE  (all mutable runtime data for one AI pilot)
# ---------------------------------------------------------------------------

class AIData:
	# Control outputs carried between frames
	var last_pitch_input: float = 0.0
	var last_throttle: float    = 0.0
	var desired_heading: float  = 0.0
	# -1.0 = use HEADING_LERP_FACTOR; >= 0 = override (energy-scaled turn rate
	# for engaging).  The engaging state writes a real value when it wants a
	# non-default snap rate; all other states leave it at -1.0.
	var steer_turn_rate: float  = -1.0
	# Last FSM key we observed.  The controller compares this to the live
	# `ai_fsm.current_key` each frame; a mismatch means the FSM just
	# transitioned and the new state's `enter()` reset the per-state
	# fields — we therefore snap `desired_heading` to the current rotation
	# so the plane holds heading until the new state sets an aim.  This is
	# the heading-reset behaviour that prevents a previous state's aim
	# from leaking into the new state and flapping it.
	var last_state_key: StringName = &""

	# Timers
	var incoming_bullet_timer: float = 0.0
	var flip_cooldown: float         = 0.0
	var bomb_cooldown_timer: float   = 0.0
	var takeoff_timer: float         = 0.0

	# Air-combat sub-mode (PURSUE / RECOVER_DIVE / RECOVER_CLIMB) — see
	# RECOVERY_* constants.  Lives on the pilot, not on the FSM, so a state
	# transition doesn't clobber the recovery timer mid-maneuver.
	var recovery_mode: int        = 0
	var recovery_mode_timer: float = 0.0

	# Patrol sweep direction: +1.0 = heading toward territory_right,
	# -1.0 = heading toward territory_left.  Persists on the pilot (not the
	# FSM) so the back-and-forth sweep continues seamlessly across the
	# transient states (evade / engage) a patrol may dip into and return
	# from.  _patrol_aim_point() flips it when the plane reaches the edge
	# it is aiming for.
	var patrol_dir: float = 1.0

	func reset_control_outputs() -> void:
		last_pitch_input = 0.0
		last_throttle    = 0.0
		desired_heading  = 0.0
		steer_turn_rate  = -1.0
		recovery_mode    = RECOVERY_NONE
		recovery_mode_timer = 0.0

# ---------------------------------------------------------------------------
# NODE-LEVEL FIELDS
# ---------------------------------------------------------------------------

@export var target: Node2D
@export var biplane: RigidBody2D

# Configuration (set by spawner before _ready)
@export var home_base_x: float  = 1400.0
## Registry homebase id (BuildingRegistry key) this AI flies for.  Set
## by main.gd to `base_idx + 1` so it is globally unique and
## matches the id its homebase's structures were registered with.
## Used by the respawn gate: a base with no surviving hangar
## can no longer put planes back in the air.
var homebase_id: int = -1
@export var patrol_range: float = 5000.0
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
	# Initial state key so the heading-reset path fires on the first physics
	# frame and the FSM's own `_change_state` reset doesn't double-up.
	pilots[0].last_state_key = ai_fsm.current_key

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

	# State transition detection: when the FSM moves to a new state, the FSM
	# has already cleared current_aim_point / current_pitch_override (see
	# AIStateMachine._change_state).  We additionally snap desired_heading
	# to the current rotation so the new state starts from "fly straight"
	# rather than the old state's last heading — the previous state would
	# otherwise leak its target heading into the new one and flap the
	# transition.
	if ai_fsm and pilots[0].last_state_key != ai_fsm.current_key:
		pilots[0].last_state_key = ai_fsm.current_key
		pilots[0].desired_heading = biplane.rotation
		pilots[0].steer_turn_rate = -1.0

	# Convert the FSM's intent (aim / pitch override / throttle) into the
	# pitch + throttle we send to the biplane.  This is the ONE place that
	# knows how to read the FSM output, so every state can stay simple
	# ("set aim, set throttle") without repeating heading-tracking code.
	var state_pitch := _apply_state_output()
	var state_throttle := ai_fsm.current_throttle if ai_fsm else 1.0

	# Reflexes (terrain pull-up, energy gate, stall recovery) run AFTER
	# the state has set its intent, so safety overrides still apply to
	# direct-pitch states like takeoff and stall recovery.  EXCEPTION: a
	# plane parked in the GROUNDED state must be left completely idle.  A
	# spawned plane sits at ~12 px above the terrain, which trips the
	# low-altitude ground-avoidance reflex — that forces the nose up AND
	# bumps the throttle to 0.8, an unbidden launch pathway that fires
	# even when the launch gate (_is_player_in_territory) is closed.  While
	# grounded, honour the state's idle intent verbatim; the taking_off
	# state re-enables reflexes the moment we actually scramble.
	var reflexed: Array
	if ai_fsm and ai_fsm.current_key == &"grounded":
		reflexed = [state_pitch, state_throttle]
	else:
		reflexed = _apply_reflexes(state_pitch, state_throttle, true, true)
	pilots[0].last_pitch_input = reflexed[0]
	pilots[0].last_throttle    = reflexed[1]

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
# STATE OUTPUT → PITCH/THROTTLE
# ---------------------------------------------------------------------------

## Reads the AIStateMachine's per-frame intent and converts it into a pitch
## command.  Two modes are supported:
##
##   1. Direct-pitch mode (current_pitch_override != INF)
##      Used by specialized states (takeoff, stall recovery).  The pitch
##      is taken verbatim; the aim is ignored.
##
##   2. Steering mode (current_aim_point != Vector2.INF, no override)
##      The controller steers the heading toward the aim, then derives
##      a pitch command from the heading error (the same heading
##      controller that the player uses, so behavior is uniform).
##
## If neither is set (e.g. the destroyed state), the plane holds the
## last heading with zero pitch — the controller's `last_pitch_input`
## is read by the biplane unchanged.
func _apply_state_output() -> float:
	if not biplane or not ai_fsm:
		return 0.0

	# 1) Direct-pitch mode — takeoff, stall recovery, urgent pull-up.
	if ai_fsm.current_pitch_override != INF:
		# Snap the heading to the current rotation so the heading controller
		# doesn't try to "catch up" to an aim the state isn't using.
		pilots[0].desired_heading = biplane.rotation
		pilots[0].steer_turn_rate = -1.0
		return ai_fsm.current_pitch_override

	# 2) Steering mode — track the state's aim, derive pitch from heading.
	#    The gain profile is whatever the active state last set on the FSM
	#    (ATTACK while pursuing, CRUISE otherwise).
	if ai_fsm.current_aim_point != Vector2.INF:
		_steer_to_aim(ai_fsm.current_aim_point)
		return _pitch_from_heading(ai_fsm.current_pitch_profile)

	# 3) No intent (e.g. just-entered state, destroyed).  Hold heading,
	#    zero pitch.  The reflexes will still apply.
	return 0.0

## Steer pilots[0].desired_heading toward an aim point.  Uses the world-wrap
## delta so an aim on the opposite side of the torus picks the short way.
## The lerp rate defaults to HEADING_LERP_FACTOR but the engaging state can
## override it via pilots[0].steer_turn_rate (energy-scaled snap).
func _steer_to_aim(aim_point: Vector2) -> void:
	if not biplane:
		return
	var my_pos := biplane.global_position
	var dx := wrapf(aim_point.x - my_pos.x, -Biplane.TERRAIN_LENGTH * 0.5, Biplane.TERRAIN_LENGTH * 0.5)
	var dy := aim_point.y - my_pos.y
	var target_heading := atan2(dy, dx)
	var rate := HEADING_LERP_FACTOR
	if pilots[0].steer_turn_rate >= 0.0:
		rate = pilots[0].steer_turn_rate
	pilots[0].desired_heading = lerp_angle(
		pilots[0].desired_heading, target_heading, rate)

## Convert the current heading error into a gravity-frame pitch command.
## This is the same heading → pitch controller the legacy code used; the
## crucial difference is that the error is read in the GRAVITY FRAME so
## the same heading error produces the same pitch command for an upright
## rightward plane and an inverted leftward plane.  `profile` selects the
## gain set: ATTACK (aggressive combat gains, used while pursuing) or
## CRUISE (conservative, used for patrol / return / recovery).
func _pitch_from_heading(profile: int = AIStateMachine.PitchProfile.CRUISE) -> float:
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
	var ppm: float = biplane.pixels_per_meter if biplane else 13.0
	var speed_ms    = biplane.velocity.length() / ppm
	var speed_ratio = clampf(speed_ms / maxf(stall_speed, 1.0), 0.6, 3.0)
	# speed_t: 0.0 = near stall, 1.0 = cruise and above
	var speed_t     = clampf((speed_ratio - 0.6) / 2.4, 0.0, 1.0)

	# --- AoA (blended in only for the CRUISE profile) ---
	var aoa_ratio := 0.0
	if profile != AIStateMachine.PitchProfile.ATTACK and biplane.velocity.length() > 0.5:
		var max_aoa: float = 0.279
		if avatar:
			max_aoa = deg_to_rad(avatar.model_params.get("max_aoa", 16.0))
		var actual_aoa = absf(wrapf(biplane.rotation - biplane.velocity.angle(), -PI, PI))
		aoa_ratio = clampf(actual_aoa / maxf(max_aoa, 0.01), 0.0, 1.0)

	# --- Select profile ---
	var sens_base: float
	var sens_low: float
	var damp_max: float
	var damp_min: float
	var ang_vel_damp: float

	if profile == AIStateMachine.PitchProfile.ATTACK:
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
# SPECIALIZED HELPERS — called by the corresponding state scripts
# ---------------------------------------------------------------------------

## Take-off pitch curve.  Speed-dependent: stay level on the ground until
## rotate speed, then progressively pull up as the airspeed builds, then
## commit to a steady climb pitch once above ~200 px.  Returns a
## gravity-frame pitch (negative = climb).  Throttle is fixed at 1.0 by
## the taking_off state itself.
func _takeoff_pitch(avatar) -> float:
	if not biplane:
		return 0.0
	var speed = biplane.velocity.length()
	var ppm: float = biplane.pixels_per_meter if biplane else 16.0
	var stall_speed: float = avatar.stall_speed_ms if avatar else 21.4

	# On the ground: hold level until rotate speed, then a tiny nose-up
	# bias to lift the tail.
	if _is_grounded():
		return 0.0 if speed < TAKEOFF_ROTATE_SPEED else TAKEOFF_PITCH

	# In the air: hold the nose level until ~2× stall (px/s) to build
	# flying speed before the climb — comparison is in px/s, not the
	# raw m/s stall value.
	var alt = _get_altitude_above_ground()
	var rotate_speed_px: float = stall_speed * ppm * 2.0
	var command: float
	if speed < rotate_speed_px:
		command = clampf(-0.03 * (speed / rotate_speed_px), -0.03, 0.0)
	elif alt < 100.0:
		command = -0.05
	elif alt < 200.0:
		command = -0.08
	else:
		command = TAKEOFF_CLIMB_PITCH

	# Near the ground, keep the nose-up tilt within 90% of the plane's max
	# landing tilt so AI pilots can't pitch themselves into a crash on the
	# initial climb.  gravity_pitch() is negative for nose-up; the limiter
	# eases the climb command toward zero as the tilt nears the cap (soft, so
	# it asymptotes to the limit instead of slamming the airframe into it).
	if alt < TAKEOFF_TILT_LIMIT_ALT and command < 0.0 and avatar:
		var max_tilt_rad := deg_to_rad(avatar.max_landing_tilt * 0.7)
		var climb_tilt := maxf(0.0, -avatar.gravity_pitch())
		var headroom := max_tilt_rad - climb_tilt
		if headroom <= 0.0:
			command = 0.0
		else:
			command = command * clampf(headroom / max_tilt_rad, 0.0, 1.0)
	return command

## Patrolling aim point.  Sweeps the full patrol zone between its two
## territory edges (home_base_x ± patrol_range/2, see _setup_territory) and
## reverses course when the plane reaches the edge it is heading toward, so
## it patrols back across to the other side of its territory.  A slow
## altitude oscillation varies the cruise height by ±ALTITUDE_OSCILLATION_AMP
## px, and when the player is airborne the plane rides a higher cruise altitude
## so the patrol always holds energy to dive with.
func _patrol_aim_point(patrol_time: float) -> Vector2:
	if not biplane:
		return Vector2.INF
	var my_x := biplane.global_position.x
	# The patrol zone spans home_base_x ± patrol_range/2.  Aim at the far
	# edge we are currently sweeping toward; once the plane reaches that edge
	# (within a small margin so it doesn't jitter on the boundary) reverse
	# course so it sweeps back to the opposite side — this is the
	# "more than patrol_range away from home base" turnaround.
	var edge_margin := 250.0
	var aim_x: float
	if pilots[0].patrol_dir > 0.0:
		aim_x = territory_right - edge_margin
		if my_x >= territory_right - edge_margin:
			pilots[0].patrol_dir = -1.0
	else:
		aim_x = territory_left + edge_margin
		if my_x <= territory_left + edge_margin:
			pilots[0].patrol_dir = 1.0

	var ground_y  = _get_ground_height(aim_x)
	var osc       = sin(patrol_time * ALTITUDE_OSCILLATION_SPEED) * ALTITUDE_OSCILLATION_AMP
	# While the player is airborne, cruise above their altitude so the patrol
	# always holds potential energy to dive with (capped ≤ PATROL_MAX_ALTITUDE,
	# itself below the 1800 px engine-taper line).  With the player on the
	# ground, keep the legacy low orbit ready to pounce on takeoff.
	var cruise_alt := PATROL_ALTITUDE
	if _is_player_airborne():
		var player_alt := _get_altitude_above_ground_for(target)
		cruise_alt = clampf(player_alt + PATROL_ALTITUDE_ADVANTAGE,
			PATROL_CRUISE_MIN, PATROL_MAX_ALTITUDE)
	return Vector2(aim_x, ground_y - cruise_alt + osc)

## Evade waypoint.  Pick a horizontal direction AWAY from the attacker (or
## from our own velocity if no threat is in range) and combine with a
## vertical bias driven by energy: climb when we have speed to spend,
## dive (only if we have altitude) when we don't.
func _evade_aim_point() -> Vector2:
	if not biplane:
		return Vector2.INF
	var my_pos := biplane.global_position
	var away := 1.0
	if target:
		var dx := wrapf(target.global_position.x - my_pos.x,
			-Biplane.TERRAIN_LENGTH * 0.5, Biplane.TERRAIN_LENGTH * 0.5)
		away = -signf(dx)
		if away == 0.0:
			away = 1.0
	elif biplane.velocity.x != 0.0:
		away = signf(biplane.velocity.x)

	var sr := _speed_ratio()
	var alt := _get_altitude_above_ground()
	# Default: a strong climb.  A climbing target is the hardest thing to
	# track in 2D so a fast plane zooms up.
	var dy := -400.0
	if sr < STALL_AVOID_SPEED_RATIO:
		# Low energy: trade altitude for speed if we have height to spend.
		dy = 150.0 if alt > STALL_DIVE_MIN_ALTITUDE * 0.5 else 0.0
	elif pilots[0].incoming_bullet_timer > 0.0:
		# Under fire with energy to spend: break harder.
		dy = -500.0

	return Vector2(my_pos.x + away * 500.0, my_pos.y + dy)

## Return-to-base aim + throttle pair.  Three regimes: en-route glide,
## committed final, and flare.  Throttle drops with each regime so the
## plane arrives at the runway at a controllable speed.
func _return_aim_and_throttle() -> Array:
	if not biplane:
		return [Vector2.INF, 1.0]

	var dx         = wrapf(home_base_x - biplane.global_position.x,
		-Biplane.TERRAIN_LENGTH * 0.5, Biplane.TERRAIN_LENGTH * 0.5)
	var dist_x     = absf(dx)
	var alt        = _get_altitude_above_ground()
	var ground_y   = _get_ground_height(home_base_x)
	# Direction we are travelling toward the base (used to place the flare aim).
	var approach_dir = sign(dx) if absf(dx) > 1.0 else sign(biplane.velocity.x)

	# Committed final approach — descend the rest of the way and flare.
	if dist_x < RETURN_FINAL_DIST:
		if alt < RETURN_FLARE_ALT:
			# Flare: aim a point well ahead at our CURRENT altitude so the
			# nose levels out and the sink rate is bled off instead of
			# being driven into the runway.  Gentle, level-ish attitude =
			# soft touchdown.
			var aim := Vector2(biplane.global_position.x + approach_dir * 300.0,
				biplane.global_position.y)
			return [aim, RETURN_FLARE_THROTTLE]
		# Follow the glide slope down to the numbers at the home base.
		var glide_alt = maxf(0.0, dist_x * RETURN_GLIDE_SLOPE)
		return [Vector2(home_base_x, ground_y - glide_alt), RETURN_FINAL_THROTTLE]

	# En-route: ride the glide slope from cruise altitude down toward the
	# base.  (No lead-pursuit here — the base is stationary, so steering
	# straight at it is correct.)
	var desired_alt = minf(PATROL_ALTITUDE, dist_x * RETURN_GLIDE_SLOPE)
	return [Vector2(home_base_x, ground_y - desired_alt), RETURN_CRUISE_THROTTLE]

## Engaging aim + throttle pair.  Dispatches to the right sub-aim based on
## the target type (air / ground / bomb) and the recovery sub-mode.
## Throttle is full by default; the chop-on-imminent-crash triple is
## handled by the engage-specific energy override at the bottom.
func _engaging_aim_and_throttle() -> Array:
	if not biplane or not target:
		return [Vector2.INF, 1.0]

	# Update the recovery sub-mode (hysteresis-bounded).
	_update_recovery_mode()

	var aim := Vector2.INF
	var turn_rate := HEADING_LERP_FACTOR

	match pilots[0].recovery_mode:
		RECOVERY_DIVE, RECOVERY_CLIMB:
			# Recovery waypoint: behind the AI with a vertical bias.
			# Turn rate is slow (the waypoint is already behind us;
			# little yaw is needed).
			aim = _recover_waypoint(pilots[0].recovery_mode)
			turn_rate = ENGAGE_TURN_LO
		_:
			# PURSUE — pick the air / ground / bomb aim, with Immelmann
			# override for high-energy fly-aways.
			if _is_target_on_ground():
				if _has_bombs(_get_avatar()):
					aim = _bomb_run_aim()
				else:
					aim = _ground_attack_aim()
			else:
				aim = _lead_pursuit_point(target.global_position, 0.85)
			if _is_flying_away() \
					and (_get_altitude_above_ground() > FLYAWAY_TURNAROUND_ALTITUDE \
					     or _speed_ratio() > FLYAWAY_TURNAROUND_SPEED_RATIO):
				# Immelmann turnaround: aim PAST the player and HIGH
				# above.  The relative vector maps in the gravity frame
				# to a large negative angle_diff (climb) for BOTH travel
				# directions — a rightward upright plane and a leftward
				# inverted plane both pitch up and arc over the target.
				var dir_to_player := signf(wrapf(target.global_position.x - biplane.global_position.x,
					-Biplane.TERRAIN_LENGTH * 0.5, Biplane.TERRAIN_LENGTH * 0.5))
				if dir_to_player == 0.0:
					dir_to_player = 1.0
				aim = Vector2(
					biplane.global_position.x
						+ wrapf(target.global_position.x - biplane.global_position.x,
							-Biplane.TERRAIN_LENGTH * 0.5, Biplane.TERRAIN_LENGTH * 0.5)
						+ dir_to_player * IMMELMANN_PAST_DIST,
					biplane.global_position.y - IMMELMANN_CLIMB_ALT)
				turn_rate = ENGAGE_TURN_HI
			else:
				turn_rate = _engage_turn_rate()

	# Stash the energy-scaled turn rate for _steer_to_aim to pick up.
	pilots[0].steer_turn_rate = turn_rate

	# Throttle: full by default.  Chop ONLY on a steep+fast+imminent-crash
	# triple — a controlled dive at altitude keeps full throttle so the
	# plane keeps the energy it has and stays aggressive.
	var throttle := _compute_engage_throttle()
	return [aim, throttle]

## True when the AI is genuinely moving away from its target (velocity
## vector points broadly opposite to the line to target).
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
# ENGAGE — GROUND ATTACK & BOMB-RUN AIMS
# ---------------------------------------------------------------------------

## Ground-attack aim point.  Phases:
##   * critically low → point straight up (the controller converts to a
##     max pull-up pitch via the heading error)
##   * pull-up altitude → point up and forward (abort the run)
##   * passed the target → climb away up-and-forward
##   * overhead → shallow dive / level at the target
##   * above dive altitude → steep dive on the target
##   * medium altitude → shallow dive on the target
func _ground_attack_aim() -> Vector2:
	if not biplane or not target:
		return Vector2.INF

	var my_pos     = biplane.global_position
	var tgt_pos    = target.global_position
	var alt        = _get_altitude_above_ground()
	var to_target  = tgt_pos - my_pos
	var x_dist     = absf(to_target.x)
	var rel_x      = to_target.x

	# Emergency pull up if critically low — point straight up; the
	# heading controller will saturate pitch at -1.0.
	if alt < CRITICAL_ALTITUDE_ABOVE_GROUND:
		return Vector2(my_pos.x, my_pos.y - 1000.0)

	# Pull up if below safe dive recovery altitude — strong pull up.
	if alt < GROUND_ATTACK_PULL_ALT:
		return Vector2(my_pos.x, my_pos.y - 600.0)

	# Check if past the target (passed overhead) — climb away.
	var going_past = (biplane.velocity.x > 0 and rel_x < -50.0) or \
	                 (biplane.velocity.x < 0 and rel_x > 50.0)
	if going_past:
		var climb_dir = sign(biplane.velocity.x) if biplane.velocity.x != 0.0 else 1.0
		return Vector2(my_pos.x + climb_dir * 300.0, my_pos.y - 200.0)

	# Overhead — shallow dive / level.
	if x_dist < 100.0:
		return Vector2(tgt_pos.x + rel_x, tgt_pos.y - 20.0)

	# Above dive altitude — steep dive toward target.
	if alt > GROUND_ATTACK_DIVE_ALT:
		return Vector2(tgt_pos.x, tgt_pos.y + 30.0)

	# Medium altitude — shallow dive.
	return Vector2(tgt_pos.x, my_pos.y + 80.0)

## Bomb-run aim point.  Two phases:
##   * overhead (close) → small forward step at current altitude so the
##     drop geometry is straight down
##   * approach (far) → aim at a point 2× the overhead threshold before
##     the target on the approach axis, so the plane flies over the
##     target and the bomb drops along the approach line
func _bomb_run_aim() -> Vector2:
	if not biplane or not target:
		return Vector2.INF

	var my_pos       = biplane.global_position
	var target_pos   = target.global_position
	var x_dist       = _get_wrapped_distance(my_pos.x, target_pos.x)
	var approach_dir = signf(target_pos.x - my_pos.x)
	if approach_dir == 0.0:
		approach_dir = 1.0

	if x_dist < BOMB_OVERHEAD_X_THRESHOLD * 0.5:
		return Vector2(my_pos.x + approach_dir * 100.0, my_pos.y - 20.0)

	var overhead_x = target_pos.x - approach_dir * BOMB_OVERHEAD_X_THRESHOLD * 2.0
	return Vector2(overhead_x, my_pos.y)

# ---------------------------------------------------------------------------
# ENGAGEMENT RECOVERY SUB-MODE  (turn + fire vs. recover)
# ---------------------------------------------------------------------------

## Mode selection with hysteresis, called once per decision tick.  When
## the AI is in a recovery sub-mode, it must commit for at least
## RECOVER_MIN_TIME (and at most RECOVER_MAX_TIME) so a brief dip in
## airspeed does not flap it in and out of recovery.
func _update_recovery_mode() -> void:
	var p := pilots[0]
	p.recovery_mode_timer += decision_interval
	var sr  := _speed_ratio()
	var alt := _get_altitude_above_ground()

	# Currently recovering — check exit conditions before re-evaluating.
	if p.recovery_mode == RECOVERY_DIVE or p.recovery_mode == RECOVERY_CLIMB:
		var speed_ok := sr >= RECOVER_EXIT_SPEED_RATIO \
				or p.recovery_mode_timer >= RECOVER_MAX_TIME
		if (speed_ok and p.recovery_mode_timer >= RECOVER_MIN_TIME) \
				or p.recovery_mode_timer >= RECOVER_MAX_TIME:
			p.recovery_mode = RECOVERY_NONE
			p.recovery_mode_timer = 0.0
		return

	# Altitude is the dominant axis: a low plane cannot safely dive, so
	# it must climb regardless of its airspeed.  Only above
	# RECOVER_DIVE_MIN_ALT do we consider trading altitude for speed.
	if alt < RECOVER_DIVE_MIN_ALT:
		p.recovery_mode = RECOVERY_CLIMB
		p.recovery_mode_timer = 0.0
	elif sr < EXTEND_ENTER_SPEED_RATIO:
		# Low energy: break away to rebuild it.  Dive to trade altitude for
		# speed when close (extend away from the fight), or climb to build
		# potential energy when already far from the target — exactly the
		# energy state the next attack will draw on.
		var dist := _get_wrapped_distance(biplane.global_position.x,
			target.global_position.x) if target else INF
		if dist < ENGAGEMENT_RANGE * 0.5:
			p.recovery_mode = RECOVERY_DIVE
		else:
			p.recovery_mode = RECOVERY_CLIMB
		p.recovery_mode_timer = 0.0
	else:
		p.recovery_mode = RECOVERY_NONE
		p.recovery_mode_timer = 0.0

## Turn rate for PURSUE: scale HEADING_LERP_FACTOR with the plane's
## energy so a high/fast plane snaps harder than a low/slow one.
func _engage_turn_rate() -> float:
	var sr  := _speed_ratio()
	var alt := _get_altitude_above_ground()
	# speed_t: 0 at ~stall, 1 at the prop-efficiency peak (~1.9× stall) and above.
	var speed_t := clampf((sr - 0.6) / 1.3, 0.0, 1.0)
	# alt_t: 0 at ground, 1 at the typical combat ceiling.
	var alt_t   := clampf(alt / 1200.0, 0.0, 1.0)
	var energy  := maxf(speed_t, alt_t)
	return lerpf(ENGAGE_TURN_LO, ENGAGE_TURN_HI, energy)

## Recovery waypoint: directly behind the AI, with a vertical bias
## matching the recovery reason.  RECOVER_DIVE → nose down (y +) to
## trade altitude for speed; RECOVER_CLIMB → nose up (y -) to gain
## altitude.  The waypoint is never aimed below the terrain.
func _recover_waypoint(mode: int) -> Vector2:
	var my_pos = biplane.global_position
	var dx := wrapf(target.global_position.x - my_pos.x, -Biplane.TERRAIN_LENGTH * 0.5, Biplane.TERRAIN_LENGTH * 0.5)
	var away := -signf(dx)
	if away == 0.0:
		away = signf(biplane.velocity.x)
		if away == 0.0:
			away = 1.0
	var dy: float
	if mode == RECOVERY_DIVE:
		dy = RECOVER_DIVE_DY   # y down: positive dy = lower on screen = nose down
	else:
		dy = -RECOVER_CLIMB_DY # y down: negative dy = higher on screen = nose up
	var wx: float = my_pos.x + away * RECOVER_LEG_LENGTH
	# Climb waypoint: never below the current altitude (climbing); the climb
	# offset is already small.  Dive waypoint: clamp to terrain clearance.
	var wy: float
	if mode == RECOVERY_DIVE:
		wy = minf(my_pos.y + dy, _get_ground_height(wx) - RECOVER_MIN_CLEARANCE)
	else:
		wy = my_pos.y + dy
	return Vector2(wx, wy)

# ---------------------------------------------------------------------------
# TARGET VALIDITY
# ---------------------------------------------------------------------------

## False when the target is destroyed or in a terminal fall so the AI
## never chases a wreck.  Non-biplane targets (ground structures) pass
## as alive.
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
# ENERGY STATE
# ---------------------------------------------------------------------------

## Current speed as a multiple of the plane's stall speed — the AI's
## single energy gauge.  ~1.9 ≈ the prop-efficiency peak (max thrust at
## ~40 m/s).
func _speed_ratio() -> float:
	if not biplane:
		return 1.0
	var avatar = _get_avatar()
	var stall: float = avatar.stall_speed_ms if avatar else 21.4
	var ppm: float = biplane.pixels_per_meter if biplane else 10.0
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

## True when a live target sits inside our rear cone, close, with its
## nose tracking us — i.e. the player has our six.  The engaging state
## breaks into an evade when this trips; without it you could sit on
## their tail forever.
func _should_evade_defensively() -> bool:
	if not biplane or not target or not _is_target_alive():
		return false
	var to_tgt := target.global_position - biplane.global_position
	to_tgt.x = wrapf(to_tgt.x, -Biplane.TERRAIN_LENGTH * 0.5, Biplane.TERRAIN_LENGTH * 0.5)
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
# STALL REFLEX  (AoA-aware hard override)
# ---------------------------------------------------------------------------

## While STALLED, steers the nose toward the velocity vector to reduce
## AoA, then applies full throttle.  Releases only once AoA drops below
## 70 % of max_aoa (hysteresis) to prevent re-stalling immediately
## after recovery.  Returns the [pitch, throttle] pair to apply, or null
## when no override is needed and the normal heading path should run.
##
## Computed in the gravity frame so "above" means toward the sky in
## either travel direction — in world space a leftward/inverted plane's
## "above" has the opposite angle sign, so the old raw-angle math aimed
## it BELOW the wind and deepened the stall instead of recovering.
func _stall_recovery() -> Array:
	var avatar = _get_avatar()
	if not avatar:
		return []
	if avatar.flight_state != biplane.FlightState.STALLED:
		return []

	var max_aoa = deg_to_rad(avatar.model_params.get("max_aoa", 16.0))
	var recovery_threshold = max_aoa * 0.7

	var actual_aoa := 0.0
	if biplane.velocity.length() > 0.5:
		actual_aoa = absf(wrapf(biplane.rotation - biplane.velocity.angle(), -PI, PI))

	if actual_aoa < recovery_threshold:
		return []   # recovered — release the override

	# Hard override: aim ~5° above the relative wind for a touch of lift.
	var wind_gp      = avatar.gravity_angle(biplane.velocity.angle())
	var recovery_heading = avatar.world_angle(wind_gp - deg_to_rad(5.0))
	# Steer toward the recovery heading in the gravity frame.
	pilots[0].desired_heading      = recovery_heading
	pilots[0].steer_turn_rate      = -1.0
	var pitch := _pitch_from_heading(AIStateMachine.PitchProfile.CRUISE)
	return [pitch, 1.0]

# ---------------------------------------------------------------------------
# ENGAGE THROTTLE
# ---------------------------------------------------------------------------

## Default policy: full throttle.  A high-energy AI needs every erg of
## thrust to press the attack, close on the target, and recover from a
## maneuver.  Chop the throttle ONLY when the predictive terrain-impact
## check reports a crash inside the speed-scaled window AND we are at
## high speed AND pointed at the ground — i.e. an unrecoverable steep
## dive.  The other cases (controlled dive, low alt, fast but level) all
## keep full throttle so the AI keeps the energy it has and stays
## aggressive.
func _compute_engage_throttle() -> float:
	if not biplane:
		return 1.0
	var avatar = _get_avatar()
	if not avatar:
		return 1.0
	var ppm: float = biplane.pixels_per_meter if biplane else 16.0
	var max_speed_px: float = avatar.model_params.get("max_speed_ms", 50.6) * ppm
	if biplane.velocity.y > 250.0 \
			and biplane.velocity.length() > max_speed_px * 0.85 \
			and _terrain_impact_time() < _impact_window():
		return ENGAGE_CHOP_THROTTLE
	return 1.0

# ---------------------------------------------------------------------------
# REFLEX LAYER
# ---------------------------------------------------------------------------

## Applied after state pitch/throttle for PATROLLING / ENGAGING / EVADING /
## RETURNING / TAKING_OFF.  Reflexes are state-agnostic safety overrides:
## terrain avoidance, energy gate, stall recovery.  They run AFTER the
## state's pitch/throttle so a state can deliberately set a pitch
## (takeoff, stall recovery) and the reflex still nudges it for safety.
func _apply_reflexes(pitch: float, throttle: float, allow_ground_avoid := true, allow_ceiling := true) -> Array:
	# Stall recovery takes priority: it overrides the heading AND sets its
	# own throttle.  Released on its own hysteresis (AoA < 70 % max).
	var stall := _stall_recovery()
	if stall.size() == 2:
		return [stall[0], stall[1]]

	# On the committed final approach of a RETURNING plane we must let it
	# descend the rest of the way to the runway, so the climb-forcing
	# ground-avoidance reflexes are suppressed — otherwise they pitch
	# the nose up below ~80 px and the plane can never actually touch
	# down.
	var ground_avoid := allow_ground_avoid
	if ai_fsm.current_key == &"returning":
		var dx = wrapf(home_base_x - biplane.global_position.x, -Biplane.TERRAIN_LENGTH * 0.5, Biplane.TERRAIN_LENGTH * 0.5)
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
		# The engage state owns its own throttle policy (1.0 by default,
		# chop only on a steep+fast+imminent-crash triple).
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
	# energy gate: samples the velocity vector for a terrain intersection
	# and pulls up early, scaled by urgency — this is what stops dive-
	# attack crashes.  A slow plane gets only a shallow pull: it cannot
	# zoom, and yanking the nose up near stall would just drop it out
	# of the sky.
	if impact_t < _impact_window():
		var urgency := 1.0 - clampf(impact_t / _impact_window(), 0.0, 1.0)
		var pull := lerpf(-0.35, -1.0, urgency)
		if _speed_ratio() < STALL_AVOID_SPEED_RATIO:
			pull = maxf(pull, -0.45)
		pitch = minf(pitch, pull)

	return [pitch, throttle]

## Seconds until the current velocity vector intersects the terrain
## (INF when the trajectory is clear).  Samples future positions, so
## rising ground ahead is caught as well as a straight descent.  This is
## the predictive layer that lets the AI pull up BEFORE the fixed low-
## altitude panic reflexes would fire.
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

## Pull-up window in seconds: the base time-to-impact scaled up with
## speed, since a faster plane needs more sky (and more lead time) to
## arc out of a dive.
func _impact_window() -> float:
	if not biplane:
		return PULL_UP_TIME_TO_GROUND
	return PULL_UP_TIME_TO_GROUND * clampf(biplane.velocity.length() / 400.0, 1.0, 2.0)

## Stall-avoidance / energy management.  When the AI wants to pull the
## nose up (negative pitch = climb in this convention) while close to
## stall speed, it instead noses down to rebuild airspeed rather than
## attempting a dramatic low-speed pull-up that would stall it out.
func _energy_stall_reflex(pitch: float, throttle: float) -> Array:
	var avatar = _get_avatar()
	if not avatar or not biplane:
		return [pitch, throttle]
	if _is_grounded() \
			or avatar.flight_state == biplane.FlightState.CRASHED \
			or avatar.flight_state == biplane.FlightState.FALLING:
		return [pitch, throttle]

	var stall_speed: float = avatar.stall_speed_ms if avatar.stall_speed_ms else 21.4
	var ppm: float = biplane.pixels_per_meter if biplane else 10.0
	var speed_ms: float = biplane.velocity.length() / ppm
	var speed_ratio: float = speed_ms / maxf(stall_speed, 1.0)

	# Wants to pull the nose up (climb) — the input that risks a low-speed stall.
	var wants_climb := pitch < -0.05

	# 1) Near-stall: never pull up.  Only ever reduce the climb — level
	#    the nose out at most.  A dive (nose-down) is only permitted when
	#    the plane is above STALL_DIVE_MIN_ALTITUDE, where it has height
	#    to trade for speed.
	if wants_climb and speed_ratio < STALL_AVOID_SPEED_RATIO:
		throttle = 1.0
		if _get_altitude_above_ground() > STALL_DIVE_MIN_ALTITUDE:
			pitch = STALL_RECOVERY_PITCH   # dive to rebuild speed
		else:
			pitch = 0.0                    # level out only — never dive

	# 2) Combat energy gate: hard pull-ups require an energy margin.
	#    Below the margin, scale the climb command down toward level as
	#    energy drops so the plane keeps building speed instead of
	#    bleeding it in a sharp maneuver.  This only ever reduces the
	#    climb toward level — it never dives.
	elif wants_climb and speed_ratio < COMBAT_ENERGY_MARGIN:
		var margin_t := clampf(
			(speed_ratio - STALL_AVOID_SPEED_RATIO) /
			(COMBAT_ENERGY_MARGIN - STALL_AVOID_SPEED_RATIO), 0.0, 1.0)
		pitch = lerpf(0.0, pitch, margin_t)

	return [pitch, throttle]

func _pull_up_reflex() -> float:
	if not biplane or _get_altitude_above_ground() > PULL_UP_ALTITUDE:
		return 0.0
	# Nose below the horizon → pull up.  gravity_pitch() reads identically
	# in either travel direction (the old raw `rotation > 0.1` check was
	# always true for an inverted plane, firing even when it was already
	# climbing).
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
## is where the engine quits (thrust already tapers from ~1800 px).  If
## the plane climbs within ENGINE_CUTOFF_AVOID_FRACTION of that altitude,
## force the nose down proportionally so it never reaches the dead zone
## where it would stall.
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
	var dx         = wrapf(target_pos.x - biplane.global_position.x, -Biplane.TERRAIN_LENGTH * 0.5, Biplane.TERRAIN_LENGTH * 0.5)
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
	var dx        = wrapf(tgt_pos.x - my_pos.x, -Biplane.TERRAIN_LENGTH * 0.5, Biplane.TERRAIN_LENGTH * 0.5)
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
	# Aggressive fire discipline: open up earlier at all ranges to keep
	# the player under pressure, not just when the solution is near-perfect.
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

## True when the target is a biplane that is currently airborne
## (FLYING or STALLED).  Ground-structure targets count as "not
## airborne".
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
	return Biplane.TERRAIN_LENGTH - d if d > Biplane.TERRAIN_LENGTH * 0.5 else d

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
	# Unlimited fuel never runs low — short-circuit so a "free fuel" skirmish
	# plane never abandons its patrol to land.
	if unlimited_fuel_ammo:
		return false
	var avatar = _get_avatar()
	return avatar and avatar.fuel < FUEL_RETURN_THRESHOLD

# ---------------------------------------------------------------------------
# INPUT APPLICATION
# ---------------------------------------------------------------------------

func _apply_input(pitch: float, throttle_amount: float) -> void:
	## `pitch` is a gravity-frame command (negative = climb, positive =
	## dive) and is forwarded verbatim: the single is_barrel_rolled
	## conversion lives inside Biplane.set_ai_input() via
	## AvatarData.pitch_command_to_rotation_input().  Never flip the sign
	## here — double-flipping cancels the conversion out (which
	## previously made leftward-spawned, is_barrel_rolled=true AI planes
	## pitch into the ground on takeoff instead of climbing).
	if not biplane.has_method("set_ai_input"):
		return
	biplane.set_ai_input(pitch, throttle_amount)

# ---------------------------------------------------------------------------
# CRASH / RESPAWN
# ---------------------------------------------------------------------------

func _on_enemy_crashed(is_midair: bool = false) -> void:
	_crashed_exploded = true

func _on_enemy_landed(avatar_id: int) -> void:
	## A homebase with no surviving hangar can no longer put planes
	## back in the air: skip the respawn entirely so the base is
	## permanently grounded once its last hangar is destroyed.
	if homebase_id >= 0 and BuildingRegistry and not BuildingRegistry.has_hangar(homebase_id):
		return
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

	# Sync AI heading to the spawn orientation and prime the state-key
	# tracker so the heading-reset path in _physics_process does not fire
	# spuriously on the first frame of a new life.
	if biplane.has_method("get_homebase_spawn_rotation") and biplane.has_method("get_avatar_data"):
		var avatar = biplane.get_avatar_data(0)
		if avatar:
			pilots[0].desired_heading = biplane.get_homebase_spawn_rotation(avatar)

	if ai_fsm and ai_fsm.is_active():
		ai_fsm.transition_to(&"grounded")
		pilots[0].last_state_key = ai_fsm.current_key

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
	# Cooldown after a flip so the orientation/velocity mismatch at the
	# tail end of a roll can't immediately re-trigger another flip.
	if pilots[0].flip_cooldown > 0.0:
		return

	# Flip when the world travel direction (sign of velocity.x) disagrees
	# with the nose's travel direction (+1 rightward / -1 leftward).  The
	# speed gate keeps the plane from flipping while parked or taxiing
	# slowly.
	var x_speed = avatar.stall_speed_ms * 10.0
	if absf(biplane.velocity.x) < x_speed:
		return
	if signf(biplane.velocity.x) != avatar.travel_sign():
		biplane.do_flip(avatar)
		pilots[0].flip_cooldown = 0.8

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
