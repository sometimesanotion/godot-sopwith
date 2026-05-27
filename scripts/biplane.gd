## biplane.gd
## Sopwith Camel — unified aerodynamics controller with multi-model support.
##
## DESIGN PHILOSOPHY
##
## One class, one physics loop, zero abstraction layers.
##
## FlightState is the single finite-state machine that controls all behaviours.
## Every per-entity value lives in AvatarData. The node itself is the view layer.
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
## • Ground vehicle support via has_aerodynamics flag
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
		"bullet_spawn_offset": Vector2(34, -15),
		"bomb_spawn_offset": Vector2(0, 32),
		"max_bombs": 6,
		"visual_scale": Vector2.ONE,
		"bungee_time": 0.15,
		"max_landing_tilt_deg": 34.0,
		"soft_landing_vperp": 10.0,
		"hard_landing_vperp": 20.0,
		"svg_sprite_name": "sopwith_camel"
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
		"bullet_spawn_offset": Vector2(34, -15),
		"bomb_spawn_offset": Vector2(0, 32),
		"max_bombs": 4,
		"visual_scale": Vector2.ONE,
		"bungee_time": 0.15,
		"max_landing_tilt_deg": 34.0,
		"soft_landing_vperp": 10.0,
		"hard_landing_vperp": 20.0,
		"svg_sprite_name": "se5a"
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
		"bullet_spawn_offset": Vector2(34, -15),
		"bomb_spawn_offset": Vector2(0, 32),
		"max_bombs": 3,
		"visual_scale": Vector2.ONE,
		"bungee_time": 0.15,
		"max_landing_tilt_deg": 34.0,
		"soft_landing_vperp": 10.0,
		"hard_landing_vperp": 20.0,
		"svg_sprite_name": "bristol_f2b"
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
		"bullet_spawn_offset": Vector2(34, -15),
		"bomb_spawn_offset": Vector2(0, 32),
		"max_bombs": 6,
		"visual_scale": Vector2.ONE,
		"bungee_time": 0.15,
		"max_landing_tilt_deg": 34.0,
		"soft_landing_vperp": 10.0,
		"hard_landing_vperp": 20.0,
		"svg_sprite_name": "p-51"
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
		"bullet_spawn_offset": Vector2(34, -15),
		"bomb_spawn_offset": Vector2(0, 32),
		"max_bombs": 6,
		"visual_scale": Vector2.ONE,
		"bungee_time": 0.15,
		"max_landing_tilt_deg": 34.0,
		"soft_landing_vperp": 10.0,
		"hard_landing_vperp": 20.0,
		"svg_sprite_name": "spad_s13"
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
		"bullet_spawn_offset": Vector2(32, -14),
		"bomb_spawn_offset": Vector2(0, 32),
		"max_bombs": 0,
		"visual_scale": Vector2(1.1, 1.1),
		"bungee_time": 0.15,
		"max_landing_tilt_deg": 34.0,
		"soft_landing_vperp": 10.0,
		"hard_landing_vperp": 20.0,
		"svg_sprite_name": "fokker_d7"
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

@export_group("Flight Parameters (SI Units)")
@export var arcade_multiplier: float = 2.4
@export var gravity:            float = 9.81

@export_group("Scale & Arcade Tuning")
@export var pixels_per_meter: float = 10.0

@export_group("Aerodynamics")
@export var air_density:         float = 1.225 * arcade_multiplier
@export var stall_aoa:           float = 0.244

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
enum Faction { BRITISH = 0, GERMAN = 1, FRENCH = 2, NEUTRAL = 3 }
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

	# Damage
	var damage:          DamageData  = DamageData.new()
	var reliability:     float       = 1.0
	var refuel_timer:    float       = 0.0
	var refuel_cooldown: float       = 0.0
	## Cached physics modifiers; recomputed by _refresh_damage_modifiers().
	var drag_multiplier:   float = 1.0
	var thrust_multiplier: float = 1.0

	# Kinematics
	var pitch_angle:         float = 0.0
	var angular_velocity:    float = 0.0
	var control_effectiveness: float = 1.0
	var is_airborne:         bool  = true

	# Throttle & engine
	var throttle:               float = 0.0
	var throttle_target:        float = 0.0
	var throttle_repeat_timer:  float = 0.0
	var engine_cutoff:          bool  = false
	var engine_restart_hold_time:     float = 0.0
	var engine_restart_required_time: float = 0.0
	var sputtering_timer:              float = 0.0

	# Flip / roll
	var is_inverted:    bool  = false
	var is_flipping:    bool  = false
	var flip_progress:  float = 0.0
	var flip_direction: int   = 0   ## 1 = upright→inverted, -1 = inverted→upright

	# Control flags
	var is_losing_control: bool = false
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

	# View-layer particle handles (managed via EffectManager)
	var continuous_fire_handles: Dictionary = {}  ## keys "core","glow","smoke" or empty
	var continuous_smoke:       GPUParticles2D = null
	var current_smoke_type:     int = 0         ## 0=none, 1=white, 2=black

	var max_landing_tilt: float = model_params.get("max_landing_tilt_deg", 34.0)
	var soft_landing: float = model_params.get("soft_landing_vperp", 80.0)
	var hard_landing: float = model_params.get("hard_landing_vperp", 200.0)
	var bungee_time: float = model_params.get("bungee_time", 0.15)
	var mass_kg: float = model_params.get("mass_kg", 447.0)

	var bullet_spawn_offset: Vector2 = model_params.get("bullet_spawn_offset", Vector2(48, -12))
	var bomb_spawn_offset: Vector2 = model_params.get("bomb_spawn_offset", Vector2(0, 32))

	func reset() -> void:
		flight_state = FlightState.FLYING
		damage.reset()
		reliability      = 1.0
		drag_multiplier  = 1.0
		thrust_multiplier = 1.0
		refuel_timer     = 0.0
		refuel_cooldown  = 0.0
		pitch_angle      = 0.0
		angular_velocity  = 0.0
		control_effectiveness = 1.0
		is_airborne           = true
		throttle         = 0.0
		throttle_target  = 0.0
		throttle_repeat_timer = 0.0
		engine_cutoff    = false
		engine_restart_hold_time    = 0.0
		engine_restart_required_time = 0.0
		is_inverted      = false
		is_flipping      = false
		flip_progress    = 0.0
		flip_direction   = 0
		is_airborne           = true
		is_losing_control     = false
		has_hit_ground    = false
		ammo  = MAX_AMMO
		fuel  = 100.0
		gun_timer  = 0.0
		bomb_timer = 0.0
		last_shot_range = 0.0
		if continuous_fire_handles.size() > 0:
			if EffectManager:
				EffectManager.detach_continuous_fire(continuous_fire_handles)
			continuous_fire_handles.clear()
		if continuous_smoke:
			if EffectManager:
				EffectManager.detach_continuous_smoke(continuous_smoke)
			continuous_smoke = null
		current_smoke_type = 0

		# Initialize plane model parameters
		update_model_params()
		bombs = model_params.get("max_bombs", 0)

## All live avatars, keyed by avatar id.
var _avatars: Dictionary[int, AvatarData] = {}

## Prevents the crash signal from firing more than once per entity.
var _crash_processed: Dictionary = {}

###############################################################################
# DAMAGE MODIFIERS
## Called whenever damage_percent changes. Updates the cached modifier fields
## so Aerodynamics.calculate_forces() reads a consistent table rather than branch-testing
## damage_percent repeatedly.
###############################################################################

func _refresh_damage_modifiers(avatar: AvatarData) -> void:
	var new_state := avatar.damage.get_damage_state()
	var prev_state := avatar.damage.damage_state
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
signal damaged(impact_force: float, v_perp: float)

###############################################################################
# NODE STATE
###############################################################################

@export var current_flight_state_name: String = "Flying"

var game_active: bool = false
var _terrain: Node    = null   ## Cached in _ready(); null if terrain absent.
var _active_bombs: Array[Node] = []   ## Bombs this plane dropped, tracking for whistle.
var flight_fsm: FlightStateMachine = null

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

	match model:
		"fokker_d7":
			avatar.faction = Faction.GERMAN
			avatar.team = Team.ENEMY
		"spad_s13":
			avatar.faction = Faction.FRENCH
			avatar.team = Team.ALLIED
		_:
			avatar.faction = Faction.BRITISH
			avatar.team = Team.ALLIED

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
		_:
			return "sopwith_camel"

func _get_homebase(avatar: AvatarData) -> HomebaseData:
	return _homebases.get(avatar.homebase_id)

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

func _draw_debug_info(avatar: AvatarData) -> void:
	if not OS.is_debug_build():
		return

	# Draw debug info overlay
	var font = Control.new().get_font("font")

	# Flight state and model info
	var debug_text = "Model: %s\n" % avatar.get_plane_name()
	debug_text += "Faction: %s\n" % ["British", "German", "Neutral"][avatar.faction]
	debug_text += "Team: %s\n" % ["Allied", "Enemy", "Neutral"][avatar.team]
	debug_text += "Flight State: %s\n" % ["Flying", "Stalled", "Falling", "Damaged", "Landed", "Crashed"][avatar.flight_state]
	debug_text += "Damage: %.1f%%\n" % (avatar.damage.damage_percent * 100)
	debug_text += "Speed: %.1f px/s\n" % velocity.length()
	debug_text += "Throttle: %.1f%%\n" % (avatar.throttle * 100)

	# Draw in top-left corner
	draw_string(font, Vector2(10, 25), debug_text, HORIZONTAL_ALIGNMENT_LEFT)

	# Draw velocity vector
	var vel_normalized = velocity.normalized() * 30
	draw_line(global_position, global_position + vel_normalized, Color.GREEN, 2)

	# Draw thrust vector
	var model_params = avatar.model_params
	if avatar.throttle > 0 and not avatar.engine_cutoff:
		var thrust_dir = Vector2(cos(avatar.pitch_angle), sin(avatar.pitch_angle))
		var thrust_vec = thrust_dir * (avatar.throttle * 40)
		draw_line(global_position, global_position + thrust_vec, Color.RED, 2)

	# Draw ground contact point
	var gc := _get_ground_contact(avatar)
	if gc.is_grounded:
		draw_line(global_position, Vector2(global_position.x, gc.ground_y), Color.YELLOW, 1)

func _update_debug_overlay(delta: float) -> void:
	# Draw debug info for all avatars
	for avatar_id in _avatars:
		var avatar: AvatarData = _avatars[avatar_id]
		if is_player_controlled:
			_draw_debug_info(avatar)
			break  # Only draw debug for primary player

###############################################################################
# COLLISION INTERFACE
###############################################################################

class CollisionResult:
	var hit: bool = false
	var damage: float = 0.0
	var is_midair: bool = false
	var impact_speed: float = 0.0

###############################################################################
# COLLISION RESPONSE (called by other biplanes via get_collision_response)
###############################################################################

func get_collision_response(other: Node, other_avatar: AvatarData, other_speed: float,
		_plane_soft_landing: float = 100.0, _plane_hard_landing: float = 200.0) -> CollisionResult:
	var result := CollisionResult.new()
	var dist := global_position.distance_to(other.global_position)
	result.impact_speed = other_speed

	if other is RigidBody2D and other.has_method("get_primary_entity"):
		var relative_speed := velocity.length() + other_speed
		var stall_speed: float = other_avatar.stall_speed_ms if other_avatar else 21.4
		var damage_ratio: float = clampf(relative_speed / stall_speed, 0.0, 2.0)
		if dist < 40.0 and other_speed > 10.0:
			result.hit = true
			result.damage = clampf(damage_ratio, 0.5, 1.0)
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
	return 25.0

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
	var inv_offset := PI if avatar.is_inverted else 0.0
	var eff_pitch  := avatar.pitch_angle + inv_offset
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

	_init_flight_fsm()

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

func _init_flight_fsm() -> void:
	var fsm_node = get_node_or_null("FlightStateMachine")
	if not fsm_node:
		fsm_node = _create_flight_fsm_nodes()
	if fsm_node and fsm_node is FlightStateMachine:
		flight_fsm = fsm_node
		flight_fsm.set_biplane(self)
		if flight_fsm.state_changed.is_connected(_on_flight_state_changed):
			flight_fsm.state_changed.disconnect(_on_flight_state_changed)
		flight_fsm.state_changed.connect(_on_flight_state_changed)
		if get_avatar_data(0):
			flight_fsm.transition_to(&"flying")

func _create_flight_fsm_nodes() -> FlightStateMachine:
	var fsm := FlightStateMachine.new()
	fsm.name = "FlightStateMachine"

	var state_scripts := {
		"Flying": load("res://scripts/states/flight/flying_state.gd"),
		"Stalling": load("res://scripts/states/flight/stalling_state.gd"),
		"Falling": load("res://scripts/states/flight/falling_state.gd"),
		"Damaged": load("res://scripts/states/flight/damaged_state.gd"),
		"Landed": load("res://scripts/states/flight/landed_state.gd"),
		"Crashed": load("res://scripts/states/flight/crashed_state.gd"),
		"Refueling": load("res://scripts/states/flight/refueling_state.gd"),
	}
	for state_name in state_scripts:
		var state_node := State.new()
		state_node.name = state_name
		state_node.set_script(state_scripts[state_name])
		fsm.add_child(state_node)
	add_child(fsm)
	fsm.start_state = fsm.get_node("Flying").get_path()
	return fsm

func _on_flight_state_changed(new_state: State) -> void:
	if new_state:
		current_flight_state_name = new_state.name
		var avatar = get_avatar_data(0)
		if avatar:
			avatar.flight_state = flight_fsm.get_flight_state_enum()

func _physics_process(delta: float) -> void:
	if not game_active:
		return

	if flight_fsm and flight_fsm._active:
		for avatar_id in _avatars:
			var avatar: AvatarData = _avatars[avatar_id]
			if avatar.damage.damage_state == DamageData.DamageState.DESTROYED and \
			   avatar.flight_state != FlightState.CRASHED and \
			   current_flight_state_name != "Crashed":
				_on_avatar_crashed(avatar)
		return

	for avatar_id in _avatars:
		var avatar: AvatarData = _avatars[avatar_id]
		if avatar.flight_state == FlightState.CRASHED:
			continue
		if avatar.flight_state == FlightState.FALLING:
			avatar.is_airborne = true
			avatar.velocity.y += gravity * pixels_per_meter * delta
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
		var t := Transform2D(_teleport_rotation, _teleport_position)
		state.set_transform(t)
		state.set_linear_velocity(Vector2.ZERO)
		state.set_angular_velocity(0.0)
		_pending_teleport = false
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
		_debug_forensic_log(avatar, "physics_contact", {
			"frame": _debug_frame_count,
			"contact_count": contact_count,
			"contacts": contact_info,
			"pos_y": snapped(global_position.y, 1.0),
			"ground_y": snapped(_ground_y(global_position.x), 1.0),
			"flight_state": avatar.flight_state,
			"speed": snapped(velocity.length(), 1.0),
		})

	if avatar.flight_state == FlightState.CRASHED:
		_integrate_crash_forces(state, avatar, step)
		return

	if avatar.flight_state == FlightState.FALLING:
		avatar.angular_velocity = 4.0
		avatar.pitch_angle += avatar.angular_velocity * step
		state.set_angular_velocity(avatar.angular_velocity)

	var inp := _build_flight_input(avatar, state)
	var out := Aerodynamics.calculate_forces(inp)

	# Supplement analytical ground detection with physics contact data.
	# The analytical model checks center position vs terrain surface (pos_y >= ground_y - 2),
	# missing contacts where only the collision shape's lower extent touches terrain.
	# Physics contacts from state.get_contact_count() provide the real collision state.
	if not inp.is_grounded:
		var cc := state.get_contact_count()
		for ci in range(cc):
			var collider := state.get_contact_collider_object(ci)
			if collider and collider.has_method("get_ground_height_at"):
				inp.is_grounded = true
				out.v_perp = maxf(0.0, -inp.velocity.dot(inp.ground_normal))
				break

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
			var current_vel := state.get_linear_velocity()
			current_vel.x *= 0.5
			state.set_linear_velocity(current_vel)
	if inp.is_grounded and inp.tilt_angle >= deg_to_rad(avatar.max_landing_tilt):
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

	_debug_check_ground_forensics(avatar, state, gc, inp, out, "post_clamp")

	avatar.control_effectiveness = out.control_effectiveness
	avatar.is_airborne = not gc.is_grounded

	_update_flight_state(avatar, gc, out.is_stalled)

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
	inp.is_inverted = avatar.is_inverted
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

func _update_flight_state(avatar: AvatarData, gc: GroundContact, stalled: bool) -> void:
	if gc.is_grounded:
		if avatar.flight_state != FlightState.DAMAGED and \
		   avatar.flight_state != FlightState.CRASHED and \
		   avatar.damage.damage_state != DamageData.DamageState.DESTROYED:
			avatar.flight_state = FlightState.LANDED
			if flight_fsm and flight_fsm._active and current_flight_state_name != "Landed":
				flight_fsm.transition_to(&"landed")
	elif stalled and avatar.damage.damage_state != DamageData.DamageState.DESTROYED:
		if avatar.flight_state == FlightState.FLYING or \
		   avatar.flight_state == FlightState.LANDED:
			avatar.flight_state = FlightState.STALLED
			if flight_fsm and flight_fsm._active and current_flight_state_name != "Stalling":
				flight_fsm.transition_to(&"stalling")
	elif avatar.damage.damage_state != DamageData.DamageState.DESTROYED:
		if avatar.flight_state == FlightState.STALLED or \
		   avatar.flight_state == FlightState.LANDED:
			avatar.flight_state = FlightState.FLYING
			if flight_fsm and flight_fsm._active and current_flight_state_name != "Flying":
				flight_fsm.transition_to(&"flying")

func _process_landing_impact(avatar: AvatarData, v_perp: float,
		impact_force: float, tilt_angle: float) -> void:
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
			avatar.flight_state = FlightState.DAMAGED
			if flight_fsm and flight_fsm._active:
				flight_fsm.transition_to(&"damaged")
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
	if current_vel == Vector2.ZERO and avatar.has_hit_ground:
		state.set_linear_velocity(Vector2.ZERO)
		state.set_angular_velocity(0.0)
		return

	current_vel.y += gravity * pixels_per_meter * step
	var ang_vel = current_vel.x * 0.01
	state.set_linear_velocity(current_vel)
	state.set_angular_velocity(ang_vel)

	var ground_ray: RayCast2D = $GroundRay if has_node("GroundRay") else null
	if ground_ray and ground_ray.is_colliding():
		state.set_linear_velocity(Vector2.ZERO)
		state.set_angular_velocity(0.0)
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
		if is_player_controlled and Input.is_action_pressed("throttle_up"):
			avatar.engine_restart_hold_time += delta
			if avatar.engine_restart_hold_time >= avatar.engine_restart_required_time:
				avatar.engine_cutoff            = false
				avatar.engine_restart_hold_time = 0.0
				if SoundManager:
					SoundManager.start_engine()
					SoundManager.set_engine_rpm(0.0)

###############################################################################
# INPUT (human player)
###############################################################################

func _handle_input(avatar: AvatarData, delta: float) -> void:
	if not is_player_controlled:
		return

	var pitch_input := 0.0
	if Input.is_action_pressed("pull_up"):
		pitch_input = -1.0
	elif Input.is_action_pressed("pull_down"):
		pitch_input = 1.0
	if avatar.is_inverted:
		pitch_input = -pitch_input
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

	if Input.is_action_just_pressed("roll") and not avatar.is_flipping and not is_grounded(avatar):
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
	for avatar_id in _avatars:
		var avatar: AvatarData = _avatars[avatar_id]
		if is_player_controlled or avatar.flight_state == FlightState.CRASHED:
			continue
		avatar.throttle_target = clampf(throttle_amount, min_throttle, max_throttle)
		avatar.throttle = move_toward(avatar.throttle, avatar.throttle_target, 5.0 * 0.016)
		var input_pitch: float = pitch * avatar.control_effectiveness
		if avatar.is_inverted:
			input_pitch = -input_pitch
		var model_params = avatar.model_params
		var eff_rot_speed: float = model_params.get("rotation_speed", 5.0) * (1.0 - avatar.damage.damage_percent * 0.4)
		avatar.angular_velocity = move_toward(
			avatar.angular_velocity, input_pitch * eff_rot_speed, model_params.get("rotation_inertia", 4.0) * 0.016)
		avatar.pitch_angle += avatar.angular_velocity * 0.016
		rotation = avatar.pitch_angle

###############################################################################
# FLIP / BARREL ROLL (visual tween)
###############################################################################

var _flip_tween: Tween = null

func _start_flip(avatar: AvatarData) -> void:
	if _flip_tween and _flip_tween.is_valid():
		_flip_tween.kill()
	avatar.is_flipping   = true
	avatar.flip_progress = 0.0
	avatar.flip_direction = 1 if not avatar.is_inverted else -1
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
		_apply_flip_transform(avatar, 1.0)
		_on_flip_completed(avatar)

func _update_flip(progress: float, avatar: AvatarData) -> void:
	avatar.flip_progress = progress
	_apply_flip_transform(avatar, progress)

func _apply_flip_transform(avatar: AvatarData, t: float) -> void:
	var visual    := $Visual
	var start     := 1.0 if avatar.flip_direction == 1 else -1.0
	visual.scale.y     = lerp(start, -start, t)
	visual.position.y  = -sin(t * PI) * FLIP_ARC_HEIGHT
	if t >= 0.5:
		avatar.is_inverted = (avatar.flip_direction == 1)

func _on_flip_completed(avatar: AvatarData) -> void:
	avatar.is_flipping   = false
	avatar.flip_progress = 0.0
	avatar.is_inverted   = (avatar.flip_direction == 1)
	_update_ground_ray(avatar)
	_flip_tween = null

func _on_flip_cancelled(avatar: AvatarData) -> void:
	avatar.is_flipping   = false
	avatar.flip_progress = 0.0
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
	var speed := velocity.length()
	if speed < 5.0:
		return
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
			var collision_result = child.get_collision_response(self, avatar, speed, soft_landing, hard_landing)
			if collision_result.hit:
				var actual_damage: float = collision_result.damage * 100.0
				if collision_result.is_midair or avatar.flight_state == FlightState.FALLING:
					if child.has_method("take_damage"):
						child.take_damage(actual_damage * 0.5, self)
					take_damage(avatar, actual_damage, child)
					if actual_damage >= 100.0:
						_on_avatar_crashed(avatar)
				elif not collision_result.is_midair and avatar.flight_state != FlightState.FALLING:
					if child.has_method("take_damage"):
						child.take_damage(actual_damage * 0.5, self)
					if collision_result.damage >= 1.0:
						_on_avatar_crashed(avatar)
					else:
						take_damage(avatar, actual_damage, child)
				return
		if child is RigidBody2D and child.has_method("get_primary_entity") and not child.has_method("get_collision_response"):
			var other_speed: float = child.velocity.length()
			var dist := global_position.distance_to(child.global_position)
			if dist < 40.0 and speed > 10.0 and other_speed > 10.0:
				var stall_speed: float = avatar.stall_speed_ms
				var relative_speed: float = speed + other_speed
				var damage_ratio: float = clampf(relative_speed / stall_speed * 0.5, 0.5, 1.0)
				var actual_damage: float = damage_ratio * 100.0
				take_damage(avatar, actual_damage, child)
				if child.has_method("take_damage"):
					child.take_damage(damage_ratio * 50.0, self)
				if actual_damage >= 100.0:
					_on_avatar_crashed(avatar)
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

	var inv: bool = avatar.is_inverted
	var model_params = avatar.model_params
	var base_offset: Vector2 = avatar.bullet_spawn_offset
	if inv:
		base_offset.y *= -1
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

	var inv: bool = avatar.is_inverted
	var model_params = avatar.model_params
	var base_offset: Vector2 = avatar.bomb_spawn_offset
	if inv:
		base_offset.y *= -1
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
		if avatar.current_smoke_type == 0 and EffectManager:
			avatar.continuous_smoke = EffectManager.attach_continuous_smoke(self, Vector2(-15, 5), 1, 10)
			avatar.current_smoke_type = 1
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
	if not is_grounded(avatar):
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

	## Repair damage instantly on landing at home.
	if avatar.damage.damage_state != DamageData.DamageState.INTACT:
		avatar.damage.repair(true)
		_refresh_damage_modifiers(avatar)
		avatar.flight_state = FlightState.FLYING
		if flight_fsm and flight_fsm._active:
			flight_fsm.transition_to(&"flying")

	avatar.refuel_timer += delta
	if avatar.refuel_timer >= 0.5:
		var old_ammo  := avatar.ammo
		var old_bombs := avatar.bombs
		var old_fuel  := avatar.fuel

		avatar.ammo = minf(MAX_AMMO, avatar.ammo + 5.0 + int(delta * 50.0))
		avatar.fuel = minf(100.0, avatar.fuel + 3.0 + int(delta * 50.0))
		avatar.bombs = mini(max_bombs, avatar.bombs + 1)
		avatar.refuel_timer = 0.0

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

	if not avatar or avatar.flight_state == FlightState.CRASHED:
		return

	## Score: if a player caused the damage to a non-player plane, add score.
	if _attacker and not _attacker is AvatarData and _attacker.is_in_group("player") \
			and not is_in_group("player"):
		if GameManager:
			GameManager.add_score(0, int(amount))

	avatar.damage.take_damage(amount / 100.0)
	avatar.damage.damage_state = avatar.damage.get_damage_state()
	_refresh_damage_modifiers(avatar)

	if avatar.damage.damage_state == DamageData.DamageState.SEVERE and not avatar.is_losing_control:
		_start_spinning_out(avatar)

	if avatar.damage.damage_state == DamageData.DamageState.DESTROYED:
		avatar.flight_state = FlightState.FALLING
		if flight_fsm and flight_fsm._active:
			flight_fsm.transition_to(&"falling")

###############################################################################
# PARTICLE HELPERS  (delegated to EffectManager)
###############################################################################

func _on_avatar_damage_state_changed(_from: DamageData.DamageState, _to: DamageData.DamageState, avatar: AvatarData) -> void:
	_sync_damage_particles(avatar)

## Sync particle effects to current damage state using EffectManager continuous effects.
func _sync_damage_particles(avatar: AvatarData) -> void:
	if not EffectManager:
		return

	match avatar.damage.damage_state:
		DamageData.DamageState.DESTROYED, DamageData.DamageState.SEVERE:
			if avatar.continuous_fire_handles.is_empty():
				avatar.continuous_fire_handles = EffectManager.attach_continuous_fire(self, Vector2(15, -5), int(30.0 * avatar.damage.damage_percent))
			else:
				EffectManager.update_continuous_fire(avatar.continuous_fire_handles, int(30.0 * avatar.damage.damage_percent))

			if not avatar.continuous_smoke or avatar.current_smoke_type != 2:
				_detach_smoke(avatar)
				avatar.continuous_smoke = EffectManager.attach_continuous_smoke(self, Vector2(-15, 5), 2, int(30.0 * avatar.damage.damage_percent))
				avatar.current_smoke_type = 2
			else:
				EffectManager.update_continuous_smoke(avatar.continuous_smoke, int(30.0 * avatar.damage.damage_percent))

		DamageData.DamageState.MODERATE:
			_detach_fire(avatar)

			if not avatar.continuous_smoke or avatar.current_smoke_type != 2:
				_detach_smoke(avatar)
				avatar.continuous_smoke = EffectManager.attach_continuous_smoke(self, Vector2(-15, 5), 2, int(60.0 * avatar.damage.damage_percent))
				avatar.current_smoke_type = 2
			else:
				EffectManager.update_continuous_smoke(avatar.continuous_smoke, int(60.0 * avatar.damage.damage_percent))

		DamageData.DamageState.LIGHT:
			_detach_fire(avatar)

			if not avatar.continuous_smoke or avatar.current_smoke_type != 1:
				_detach_smoke(avatar)
				avatar.continuous_smoke = EffectManager.attach_continuous_smoke(self, Vector2(-15, 5), 1, int(20.0 * avatar.damage.damage_percent))
				avatar.current_smoke_type = 1
			else:
				EffectManager.update_continuous_smoke(avatar.continuous_smoke, int(20.0 * avatar.damage.damage_percent))

		_:
			_detach_fire(avatar)
			_detach_smoke(avatar)

func _detach_fire(avatar: AvatarData) -> void:
	if not avatar.continuous_fire_handles.is_empty():
		if EffectManager:
			EffectManager.detach_continuous_fire(avatar.continuous_fire_handles)
		avatar.continuous_fire_handles.clear()

func _detach_smoke(avatar: AvatarData) -> void:
	if avatar.continuous_smoke:
		if EffectManager:
			EffectManager.detach_continuous_smoke(avatar.continuous_smoke)
		avatar.continuous_smoke = null
	avatar.current_smoke_type = 0

###############################################################################
# CRASH & SPIN-OUT
###############################################################################

func _start_spinning_out(avatar: AvatarData) -> void:
	avatar.is_losing_control   = true
	avatar.throttle             = 0.0
	avatar.throttle_target      = 0.0
	avatar.flight_state         = FlightState.FALLING
	if flight_fsm and flight_fsm._active:
		flight_fsm.transition_to(&"falling")

func _on_avatar_crashed(avatar: AvatarData) -> void:
	if _crash_processed.has(avatar.id):
		return
	else:
		DLog.crash_guard(avatar.id, "_crash_processed", {
			"px": snapped(global_position.x, 0.1),
			"py": snapped(global_position.y, 0.1),
			"vx": snapped(velocity.x, 0.1),
			"vy": snapped(velocity.y, 0.1),
			"ground_y": snapped(_ground_y(global_position.x), 0.1),
		})

	_crash_processed[avatar.id] = true
	var is_midair := avatar.is_airborne and avatar.flight_state != FlightState.LANDED and avatar.flight_state != FlightState.CRASHED
	avatar.flight_state          = FlightState.CRASHED
	avatar.damage.damage_state   = DamageData.DamageState.DESTROYED
	avatar.is_airborne           = false
	if flight_fsm and flight_fsm._active:
		flight_fsm.transition_to(&"crashed")
	if GameManager and is_player_controlled:
		GameManager.destroy_player(avatar.id)
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
	if avatar and avatar.is_inverted:
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
		ground_ray.target_position = Vector2(0, -base_offset if avatar.is_inverted else base_offset)

func create_explosion(is_midair: bool = false) -> void:
	var pos := global_position
	if EffectManager:
		if is_midair:
			EffectManager.spawn_explosion(pos, 100.0)
			EffectManager.spawn_explosion_debris(pos, Color(0.5, 0.55, 0.5), 8, 10.0, get_plane_polygon())
		else:
			EffectManager.spawn_crash_effects(pos, get_plane_polygon(), Color(0.5, 0.55, 0.5))

func get_plane_polygon() -> PackedVector2Array:
	var model_params = get_primary_entity().model_params
	var scale = model_params.get("visual_scale", Vector2.ONE)
	return PackedVector2Array([
		Vector2(20 * scale.x, 0), Vector2(10 * scale.x, -4 * scale.y),
		Vector2(-15 * scale.x, -4 * scale.y), Vector2(-20 * scale.x, 0),
		Vector2(-15 * scale.x, 4 * scale.y), Vector2(10 * scale.x, 4 * scale.y)
	])

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
	var team = Team.ALLIED if faction == Faction.BRITISH else Team.ENEMY
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
		return
	var default_model := get_default_plane_model(hb.faction)
	assign_plane_model(avatar, default_model)

###############################################################################
# RESET & RESPAWN
###############################################################################

func reset_flight_state(avatar_id: int = 0) -> void:
	var avatar := get_avatar_data(avatar_id)
	if avatar:
		avatar.reset()
		_crash_processed.erase(avatar_id)
		_update_ground_ray(avatar)
		if is_player_controlled and SoundManager:
			SoundManager.start_engine()
			SoundManager.set_engine_rpm(0.0)
	if flight_fsm:
		if not flight_fsm._active:
			flight_fsm._active = true
		flight_fsm.transition_to(&"flying")
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
	avatar.is_inverted = false
	avatar.is_flipping = false
	avatar.flip_progress = 0.0
	avatar.flip_direction = 0
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

func transition_flight_state(state_name: String) -> void:
	if flight_fsm and flight_fsm._active:
		flight_fsm.transition_to(StringName(state_name))

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

func is_inverted(avatar: AvatarData) -> bool:
	return avatar.is_inverted if avatar else false

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

	visible = true
	global_position = spawn_pos
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_pending_teleport = true
	_teleport_position = spawn_pos
	_teleport_rotation = spawn_rot

	reset_flight_state(avatar_id)

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

	# Log every 30 frames while grounded for baseline
	if gc.is_grounded and _debug_frame_count % 30 == 0:
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
			"is_inverted": avatar.is_inverted,
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
##     avatar.update_model_params()
##     avatar.has_aerodynamics = false  # Disable aerodynamics for ground vehicles
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
##   _draw_debug_info(avatar) - Shows flight state, model info, vectors
##   Real-time velocity/thrust visualization
##
## Physics Access:
##   All physics now uses model-specific parameters through avatar.model_params
##   Ground vehicles supported by setting has_aerodynamics = false in AvatarData
