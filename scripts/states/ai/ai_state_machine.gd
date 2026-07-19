class_name AIStateMachine
extends StateMachine

var ai_controller: Node = null

## Pitch-gain profile the controller should use when deriving pitch from
## the heading error.  CRUISE = conservative gains (patrol / return /
## takeoff / recovery); ATTACK = aggressive combat gains (pressing an
## attack).  The engaging state raises this to ATTACK only while it is
## actually pursuing (energy sufficient); recovery / other states leave
## it at CRUISE so energy is preserved.  Reset on every transition so a
## new state starts from the conservative default.
enum PitchProfile { CRUISE, ATTACK }

## ---------------------------------------------------------------------
## STATE OUTPUT FIELDS
## ---------------------------------------------------------------------
##
## A state writes these on every decision tick.  The controller
## (scripts/enemy_ai.gd) reads them in `_physics_process` and converts
## the intent into pitch / throttle applied to the biplane.
##
## All three fields are RESET on every state transition (see
## `_change_state` below) so a new state always establishes its own
## intent — this is the mechanism that prevents the previous state's
## aim from being carried forward and causing flapping.

## Where the AI is steering toward.  Vector2.INF means "no aim set" —
## the owning state must populate this, otherwise the controller holds
## the last heading.  Most states (patrolling, engaging, evading,
## returning) write a real aim here.
var current_aim_point: Vector2 = Vector2.INF

## Direct pitch override (gravity frame: negative = climb, positive =
## dive).  INF means "no override, derive pitch from the heading".  Used
## by specialized states (takeoff, stall recovery) that need a fixed
## pitch command rather than tracking an aim point.
var current_pitch_override: float = INF

## Throttle the AI is requesting.  Defaults to 1.0; the state may lower
## it (e.g. the return-path flare) without touching anything else.
var current_throttle: float = 1.0

## Pitch-gain profile currently in effect (see PitchProfile).  Written by
## the engaging state; read by enemy_ai._pitch_from_heading().
var current_pitch_profile: int = PitchProfile.CRUISE

## ---------------------------------------------------------------------
## STICKINESS / HYSTERESIS
## ---------------------------------------------------------------------

## Minimum wall-time (s) the FSM must stay in the current state before
## any transition_to() is honoured.  A state sets this in enter() to
## commit to its maneuver — e.g. evading uses this to require a full
## break turn before reverting to engaging.  Defaults to 0 (no floor).
var min_state_time: float = 0.0

## Wall-time elapsed in the current state.  Reset on every transition.
## The base tick() advances this; the controller can then gate exits
## through can_transition().
var state_elapsed: float = 0.0

## True when the state has been in long enough to exit.  States
## gate their `finished.emit()` calls on this so a state can never
## flap into / out of itself on a single decision tick.
func can_transition() -> bool:
	return state_elapsed >= min_state_time

# ---------------------------------------------------------------------------
# LIFECYCLE
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()

func set_ai_controller(controller: Node) -> void:
	ai_controller = controller

## Override the base transition to RESET the per-state output fields
## (aim, pitch override, throttle, stickiness).  The previous_key is
## captured before exit() so a state's enter() can branch on it.  The
## base semantics (idempotency, unknown-key warning, active gate) are
## preserved verbatim from state_machine.gd.
func _change_state(state_name: StringName) -> void:
	if not _active:
		return
	if not current_state:
		return
	# Idempotent: re-entering the current state is a no-op.
	if state_name == current_key:
		return
	if not states_map.has(state_name):
		push_warning("AIStateMachine._change_state: unknown state '%s'" % state_name)
		return
	previous_key = current_key
	current_state.exit()
	current_state = states_map[state_name]
	current_key = state_name
	# Reset per-state output so the new state establishes its own
	# intent rather than inheriting the old state's values.
	state_elapsed = 0.0
	min_state_time = 0.0
	current_aim_point = Vector2.INF
	current_pitch_override = INF
	current_throttle = 1.0
	current_pitch_profile = PitchProfile.CRUISE
	current_state.enter()
	state_changed.emit(current_state)

## Advance the FSM by `delta`.  We accumulate `state_elapsed` here so
## any state can gate its exit on min_state_time without having to
## track wall time itself.
func tick(delta: float) -> void:
	state_elapsed += delta
	super.tick(delta)

# ---------------------------------------------------------------------------
# STATE ORDER (single source of truth for ordinals)
# ---------------------------------------------------------------------------

## Single source of truth for AI state ordinals. Order matches the FSM children;
## `get_ai_state_enum()` is just a key -> ordinal lookup over this array.
const AI_STATE_ORDER := [
	&"grounded",
	&"taking_off",
	&"patrolling",
	&"engaging",
	&"evading",
	&"returning",
	&"destroyed",
]

func get_ai_state_enum() -> int:
	return AI_STATE_ORDER.find(current_key)
