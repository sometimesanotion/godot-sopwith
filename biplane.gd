## biplane.gd
## Sopwith Camel — unified aerodynamics controller with multi-model support.
##
## DESIGN PHILOSOPHY
##
## One class, one physics loop, zero abstraction layers.
##
## FlightState is the single finite-state machine that controls all behaviours.
## Every per-entity value lives in AvatarData. The node itself is the view layer.
## The physics loop _apply_physics() sums all forces in one pass every frame —
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
extends CharacterBody2D

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
		"soft_landing_vperp": 120.0,
		"hard_landing_vperp": 300.0,
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
		"soft_landing_vperp": 120.0,
		"hard_landing_vperp": 300.0,
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
		"rotation_inertia": 4.0,
		"bullet_spawn_offset": Vector2(34, -15),
		"bomb_spawn_offset": Vector2(0, 32),
		"max_bombs": 3,
		"visual_scale": Vector2.ONE,
		"bungee_time": 0.15,
		"soft_landing_vperp": 120.0,
		"hard_landing_vperp": 300.0,
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
		"soft_landing_vperp": 120.0,
		"hard_landing_vperp": 300.0,
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
		"soft_landing_vperp": 120.0,
		"hard_landing_vperp": 300.0,
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
		"soft_landing_vperp": 120.0,
		"hard_landing_vperp": 300.0,
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

###############################################################################
# MODEL-SPECIFIC CONSTANTS (no longer hardcoded)
##############################################################################

## Distance from plane origin to ground surface when at rest.
const GROUND_SURFACE_OFFSET := 12.0

## Grounded detection tolerance (px). Absorbs one-frame integration overshoot.
const GROUND_TOLERANCE := 2.0

const THROTTLE_STEP         := 0.15
const THROTTLE_REPEAT_DELAY := 0.1
const THROTTLE_RAMP_SPEED   := 5.0

const MAX_AMMO  := 250	# 500 rounds, twin guns

const FLIP_DURATION   := 0.35
const FLIP_ARC_HEIGHT := 15.0

## Altitude at which engine efficiency begins to taper off.
const ENGINE_EFFICIENCY_START_ALTITUDE := 1800.0
## Altitude at which the engine cuts out entirely.
const ENGINE_CUTOFF_ALTITUDE           := 2000.0

## Ground friction coefficients μ used in F_friction = μ × |F_normal|.
## Rolling = throttle applied; Braking = no throttle.
const FRICTION_RUNWAY_ROLLING  := 0.03
const FRICTION_RUNWAY_BRAKING  := 0.70
const FRICTION_TERRAIN_ROLLING := 0.07
const FRICTION_TERRAIN_BRAKING := 0.40

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
	DAMAGED = 3,   ## Rough-landed or hit; reduced performance, may still fly
	LANDED  = 4,   ## On the ground, stationary or taxiing
	CRASHED = 5    ## Destroyed; post-crash tumble physics only
}

## Damage severity bands. Drives physics modifiers via _refresh_damage_modifiers().
enum DamageState {
	INTACT    = 0,   ##   0–24 %  — full performance
	LIGHT     = 1,   ##  25–49 %  — white smoke, slight drag increase
	MODERATE  = 2,   ##  50–79 %  — black smoke, reduced speed cap
	SEVERE    = 3,   ##  80–99 %  — fire, losing control
	DESTROYED = 4    ## 100 %     — crash
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
	var is_player:    bool    = false
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
			# Fallback to default
			var plane_models = Biplane.get_plane_models()
			model_params = plane_models["sopwith_camel"]

	func get_plane_name() -> String:
		return model_params.get("name", "Unknown")

	# Flight state (FSM)
	var flight_state: FlightState = FlightState.FLYING

	# Damage
	var damage_percent:  float       = 0.0
	var damage_state:    DamageState = DamageState.INTACT
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

	# Weapons
	var ammo:             int   = MAX_AMMO
	var bombs:            int   = 0
	var fuel:             float = 100.0
	var gun_timer:        float = 0.0
	var bomb_timer:       float = 0.0
	var max_bullet_range: float = 1000.0
	var last_shot_range:  float = 0.0

	# View-layer particle handles
	var smoke_particles:    GPUParticles2D = null
	var fire_particles:     GPUParticles2D = null
	var current_smoke_type: int = 0   ## 0=none, 1=white, 2=black

	var max_landing_tilt: float = model_params.get("max_landing_tilt_deg", 34.0)
	var soft_landing: float = model_params.get("soft_landing_vperp", 80.0)
	var hard_landing: float = model_params.get("hard_landing_vperp", 200.0)
	var bungee_time: float = model_params.get("bungee_time", 0.15)
	var mass_kg: float = model_params.get("mass_kg", 447.0)

	var bullet_spawn_offset: Vector2 = model_params.get("bullet_spawn_offset", Vector2(34, -15))
	var bomb_spawn_offset: Vector2 = model_params.get("bomb_spawn_offset", Vector2(0, 32))

	func reset() -> void:
		flight_state = FlightState.FLYING
		damage_percent   = 0.0
		damage_state     = DamageState.INTACT
		reliability      = 1.0
		drag_multiplier  = 1.0
		thrust_multiplier = 1.0
		refuel_timer     = 0.0
		refuel_cooldown  = 0.0
		pitch_angle      = 0.0
		angular_velocity  = 0.0
		control_effectiveness = 1.0
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
		is_losing_control = false
		has_hit_ground    = false
		ammo  = MAX_AMMO
		fuel  = 100.0
		gun_timer  = 0.0
		bomb_timer = 0.0
		last_shot_range = 0.0
		if smoke_particles:
			smoke_particles.emitting = false
			smoke_particles.queue_free()
			smoke_particles = null
		if fire_particles:
			fire_particles.emitting = false
			fire_particles.queue_free()
			fire_particles = null
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
## so _apply_physics() reads a consistent table rather than branch-testing
## damage_percent repeatedly.
###############################################################################

func _refresh_damage_modifiers(avatar: AvatarData) -> void:
	var prev_state := avatar.damage_state
	if avatar.damage_percent >= 1.0:
		avatar.damage_state    = DamageState.DESTROYED
		avatar.reliability     = 0.0
		avatar.drag_multiplier   = 2.0
		avatar.thrust_multiplier = 0.0
	elif avatar.damage_percent >= 0.8:
		avatar.damage_state    = DamageState.SEVERE
		avatar.reliability     = 0.0
		avatar.drag_multiplier   = 1.6
		avatar.thrust_multiplier = 0.5
	elif avatar.damage_percent >= 0.5:
		avatar.damage_state    = DamageState.MODERATE
		avatar.reliability     = 0.5
		avatar.drag_multiplier   = 1.25
		avatar.thrust_multiplier = 0.7
	elif avatar.damage_percent >= 0.25:
		avatar.damage_state    = DamageState.LIGHT
		avatar.reliability     = 0.75
		avatar.drag_multiplier   = 1.05
		avatar.thrust_multiplier = 0.9
	else:
		avatar.damage_state    = DamageState.INTACT
		avatar.reliability     = 1.0
		avatar.drag_multiplier   = 1.0
		avatar.thrust_multiplier = 1.0

	# Sync particles whenever damage band changes.
	if avatar.damage_state != prev_state:
		_init_particle_materials()
		_sync_damage_particles(avatar)

###############################################################################
# PARTICLE MATERIALS (static, shared across all instances)
###############################################################################

static var _white_smoke_mat: ParticleProcessMaterial
static var _black_smoke_mat: ParticleProcessMaterial
static var _fire_mat:        ParticleProcessMaterial

static func _init_particle_materials() -> void:
	if _white_smoke_mat:
		return
	_white_smoke_mat = ParticleProcessMaterial.new()
	_white_smoke_mat.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_white_smoke_mat.emission_sphere_radius = 8.0
	_white_smoke_mat.gravity                = Vector3(0, 30, 0)
	_white_smoke_mat.spread                 = 30.0
	_white_smoke_mat.initial_velocity_min   = 30.0
	_white_smoke_mat.initial_velocity_max   = 60.0
	_white_smoke_mat.scale_min              = 4.0
	_white_smoke_mat.scale_max              = 10.0
	_white_smoke_mat.color                  = Color(0.8, 0.8, 0.8, 0.5)

	_black_smoke_mat = ParticleProcessMaterial.new()
	_black_smoke_mat.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_black_smoke_mat.emission_sphere_radius = 8.0
	_black_smoke_mat.gravity                = Vector3(0, 30, 0)
	_black_smoke_mat.spread                 = 30.0
	_black_smoke_mat.initial_velocity_min   = 30.0
	_black_smoke_mat.initial_velocity_max   = 60.0
	_black_smoke_mat.scale_min              = 4.0
	_black_smoke_mat.scale_max              = 10.0
	_black_smoke_mat.color                  = Color(0.05, 0.05, 0.05, 0.5)

	_fire_mat = ParticleProcessMaterial.new()
	_fire_mat.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_fire_mat.emission_sphere_radius = 5.0
	_fire_mat.gravity                = Vector3(0, 30, 0)
	_fire_mat.spread                 = 30.0
	_fire_mat.initial_velocity_min   = 60.0
	_fire_mat.initial_velocity_max   = 90.0
	_fire_mat.scale_min              = 3.0
	_fire_mat.scale_max              = 6.0
	_fire_mat.color                  = Color(0.95, 0.5, 0.2, 0.9)

###############################################################################
# SIGNALS
###############################################################################

signal fired_bullet(position: Vector2, direction: Vector2, speed: float, owner: Node, range_percent: float)
signal dropped_bomb(position: Vector2, velocity: Vector2, owner: Node)
signal crashed()
signal damaged(impact_force: float, v_perp: float)

###############################################################################
# NODE STATE
###############################################################################

var game_active: bool = false
var _terrain: Node    = null   ## Cached in _ready(); null if terrain absent.
var _active_bombs: Array[Node] = []   ## Bombs this plane dropped, tracking for whistle.

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
	debug_text += "Damage: %.1f%%\n" % (avatar.damage_percent * 100)
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
		if avatar.is_player:
			_draw_debug_info(avatar)
			break  # Only draw debug for primary player

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
	motion_mode = MotionMode.MOTION_MODE_FLOATING

	# Set default plane models based on faction for existing entities
	for avatar_id in _avatars:
		var avatar: AvatarData = _avatars[avatar_id]
		avatar.plane_model = get_default_plane_model(avatar.faction)
		avatar.update_model_params()

	# Set physics parameters based on primary entity's model
	var primary_avatar = get_avatar_data(0)
	if primary_avatar:
		var model_params = primary_avatar.model_params
		PhysicsServer2D.body_set_param(get_rid(), PhysicsServer2D.BODY_PARAM_MASS, model_params.get("mass_kg", 447.0))

	_init_particle_materials()
	reset_visual_transform()
	_terrain = get_parent().get_node_or_null("Terrain")

func _physics_process(delta: float) -> void:
	if not game_active:
		return

	for avatar_id in _avatars:
		var avatar: AvatarData = _avatars[avatar_id]

		match avatar.flight_state:
			FlightState.CRASHED:
				_apply_crash_physics(avatar, delta)
				_check_obstacle_collision(avatar)
				continue

			FlightState.FALLING:
				avatar.angular_velocity = 4.0
				avatar.pitch_angle += avatar.angular_velocity * delta
				rotation = avatar.pitch_angle
				_apply_physics(avatar, delta)
				_check_obstacle_collision(avatar)
				continue

		## All other states go through the normal pipeline.
		_handle_input(avatar, delta)
		_handle_weapons(avatar, delta)
		_check_altitude_engine_cutoff(avatar, delta)
		_apply_physics(avatar, delta)
		_check_obstacle_collision(avatar)
		_check_fuel_consumption(avatar, delta)
		_check_home_refuel(avatar, delta)

###############################################################################
# UNIFIED PHYSICS LOOP
##
## All forces are summed in one pass and integrated once. Ground contact is a
## positional constraint applied after integration — not a separate regime.
## This ensures buildings, vehicles, and planes all obey the same physics.
##
## Force budget (SI, Newtons):
##   weight_vec    — always down
##   thrust_vec    — along heading
##   lift_vec      — perpendicular to velocity (zero for ground vehicles)
##   drag_vec      — opposing velocity
##   normal_vec    — perpendicular to slope, prevents ground penetration
##   friction_vec  — opposing velocity, proportional to normal force
###############################################################################

func _apply_physics(avatar: AvatarData, delta: float) -> void:
	var gc     := _get_ground_contact(avatar)
	var model_params = avatar.model_params
	var forward := Vector2(cos(avatar.pitch_angle), sin(avatar.pitch_angle))
	## right = 90° CCW from forward = "up off the wings" for level right-flight.
	var right  := Vector2(forward.y, -forward.x)

	var vel_si   := velocity / pixels_per_meter
	var speed_si := vel_si.length()

	# 1. WEIGHT
	var weight_vec := Vector2(0.0, model_params.get("mass_kg", 447.0) * gravity)

	# 2. THRUST
	var thrust_vec := forward * _calc_thrust(avatar, speed_si, gc.ground_y)

	# 3. LIFT & AERODYNAMIC DRAG
	var lift_vec := Vector2.ZERO
	var drag_vec := Vector2.ZERO
	var stalled  := false

	var aoa: float = 0.0
	if speed_si > 0.5:
		aoa = forward.angle_to(vel_si.normalized())

	## Planes cannot stall aerodynamically while on the ground.
	stalled = (not gc.is_grounded) and (abs(aoa) > model_params.get("stall_aoa", 0.244) or speed_si < model_params.get("stall_speed_ms_ms", 21.4 / 2.2))

	var cl: float = clampf(aoa * 2.0 * PI, -model_params.get("max_lift_coeff", 1.4), model_params.get("max_lift_coeff", 1.4))
	if stalled:
		cl *= 0.3

	var altitude: float = maxf(0.0, gc.ground_y - global_position.y)
	var density_factor: float = exp(-altitude / 2500.0)
	var rho: float = air_density * density_factor

	if speed_si > 0.5:
		var lift_si: float = 0.5 * rho * speed_si * speed_si * model_params.get("wing_area", 21.46) * cl
		lift_vec = right * lift_si

	var para_drag: float = 0.5 * rho * speed_si * speed_si * model_params.get("zero_lift_drag_area", 0.811)
	var induced_drag: float = 0.5 * rho * speed_si * speed_si * model_params.get("wing_area", 21.46) * (cl * cl) / model_params.get("ar_efficiency", 11.0)

	## Speed-cap drag: exponential penalty above the effective max speed.
	var eff_max_speed_ms: float = model_params.get("max_speed_ms", 300.0)
	var speed_px: float = velocity.length()
	var speed_lim_drag: float = 0.0
	if speed_px > eff_max_speed_ms:
		var over: float = speed_px - eff_max_speed_ms
		speed_lim_drag = over * over * 0.5

	var total_drag: float = (para_drag + induced_drag + speed_lim_drag / pixels_per_meter) \
	                 * avatar.drag_multiplier
	if speed_si > 0.01:
		drag_vec = -vel_si.normalized() * total_drag

	# 4. GROUND NORMAL FORCE & FRICTION
	var normal_vec  := Vector2.ZERO
	var friction_vec := Vector2.ZERO

	if gc.is_grounded:
		## Tilt crash: nose dug into ground at an angle.
		if gc.tilt_angle >= deg_to_rad(model_params.get("max_landing_tilt_deg", 40.0)):
			_on_avatar_crashed(avatar)
			return

		## Impact detection uses pre-integration velocity so we measure actual
		## approach speed rather than speed after this frame's forces.
		var v_perp := maxf(0.0, -velocity.dot(gc.ground_normal))
		var impact_force_calc: float = avatar.mass_kg * (v_perp / pixels_per_meter) / avatar.bungee_time
		_process_landing_impact(avatar, v_perp, impact_force_calc, gc.tilt_angle)
		if avatar.flight_state == FlightState.CRASHED:
			return

		## Normal force: exactly opposes the net into-ground aero force.
		var net_aero  := weight_vec + thrust_vec + lift_vec + drag_vec
		var into_gnd  := -net_aero.dot(gc.ground_normal)
		if into_gnd > 0.0:
			normal_vec = gc.ground_normal * into_gnd

		## Ground friction: F = μ × |F_normal|, opposing the velocity.
		if speed_si > 0.01:
			var mu       := _friction_coeff(gc.on_runway, avatar.throttle)
			friction_vec  = -vel_si.normalized() * (maxf(0.0, into_gnd) * mu)

	# 5. INTEGRATE
	var net_force := weight_vec + thrust_vec + lift_vec + drag_vec + normal_vec + friction_vec
	velocity      += (net_force / model_params.get("mass_kg", 447.0)) * pixels_per_meter * delta
	global_position += velocity * delta

	# 6. GROUND PENETRATION CLAMP
	## The normal force prevents most penetration; this catches discrete overshoot.
	if gc.is_grounded:
		var surf_y := gc.ground_y - GROUND_SURFACE_OFFSET
		if global_position.y > surf_y:
			global_position.y = surf_y
		## Cancel the into-ground component of velocity (slope-aware).
		var into_v := velocity.dot(gc.ground_normal)
		if into_v > 0.0:
			velocity -= gc.ground_normal * into_v

	# 7. CONTROL EFFECTIVENESS (scales with dynamic pressure)
	var sp_si := velocity.length() / pixels_per_meter
	var stall_speed_ms = model_params.get("stall_speed_ms_ms", 21.4 / 2.2)
	avatar.control_effectiveness = clampf(
		(sp_si * sp_si) / (stall_speed_ms * stall_speed_ms * 50.0), 0.6, 1.8)

	# 8. FLIGHT STATE TRANSITIONS
	if gc.is_grounded:
		if avatar.flight_state != FlightState.DAMAGED and \
		   avatar.flight_state != FlightState.CRASHED:
			avatar.flight_state = FlightState.LANDED
	elif stalled:
		if avatar.flight_state == FlightState.FLYING or \
		   avatar.flight_state == FlightState.LANDED:
			avatar.flight_state = FlightState.STALLED
	else:
		if avatar.flight_state == FlightState.STALLED or \
		   avatar.flight_state == FlightState.LANDED:
			avatar.flight_state = FlightState.FLYING

###############################################################################
# LANDING IMPACT
###############################################################################

func _process_landing_impact(avatar: AvatarData, v_perp: float,
		impact_force: float, tilt_angle: float) -> void:
	var model_params = avatar.model_params
	var max_landing_tilt: float = model_params.get("max_landing_tilt_deg", 40.0)
	var soft_landing: float = model_params.get("soft_landing_vperp", 80.0)
	var hard_landing: float = model_params.get("hard_landing_vperp", 200.0)
	var bungee_time: float = model_params.get("bungee_time", 0.15)
	var mass_kg: float = model_params.get("mass_kg", 447.0)
	var impact_force_calc: float = mass_kg * (v_perp / pixels_per_meter) / bungee_time

	if tilt_angle >= deg_to_rad(max_landing_tilt) and v_perp > 40.0:
		_on_avatar_crashed(avatar)
		return

	if v_perp <= soft_landing:
		pass   ## Clean touch-down; flight state handled by the transition block.

	elif v_perp <= hard_landing:
		## Rough landing: add damage, slow the plane, emit feedback.
		avatar.flight_state = FlightState.DAMAGED
		avatar.damage_percent = minf(1.0, avatar.damage_percent + 0.2)
		_refresh_damage_modifiers(avatar)
		velocity.x *= 0.5
		damaged.emit(impact_force_calc, v_perp)
		if SoundManager:
			SoundManager.play_sfx(SoundManager.SoundEvent.BUMP)

	else:
		_on_avatar_crashed(avatar)

###############################################################################
# THRUST
###############################################################################

func _calc_thrust(avatar: AvatarData, speed_si: float, ground_y: float) -> float:
	if avatar.engine_cutoff:
		return 0.0

	var altitude    := ground_y - global_position.y
	var alt_eff     := 1.0
	if altitude > ENGINE_EFFICIENCY_START_ALTITUDE:
		alt_eff = 1.0 - clampf(
			(altitude - ENGINE_EFFICIENCY_START_ALTITUDE) /
			(ENGINE_CUTOFF_ALTITUDE - ENGINE_EFFICIENCY_START_ALTITUDE),
			0.0, 1.0)

	var thr := avatar.throttle * avatar.thrust_multiplier * arcade_multiplier
	var model_params = avatar.model_params

	## Below 0.5 m/s the P×η/v formula diverges; use a static thrust value.
	if speed_si < 0.5:
		return 2000.0 * thr * alt_eff

	var eta := maxf(0.0, 0.8 * (1.0 - pow((speed_si - 40.0) / 40.0, 2)))
	return model_params.get("engine_power_watts", 96941.0) * eta / speed_si * thr * alt_eff

###############################################################################
# GROUND FRICTION LOOKUP
###############################################################################

func _friction_coeff(on_runway: bool, throttle: float) -> float:
	if on_runway:
		return FRICTION_RUNWAY_ROLLING if throttle >= THROTTLE_STEP else FRICTION_RUNWAY_BRAKING
	return FRICTION_TERRAIN_ROLLING if throttle >= THROTTLE_STEP else FRICTION_TERRAIN_BRAKING

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
			if avatar.is_player and SoundManager:
				SoundManager.stop_engine()
	else:
		## Sputtering sound while engine is cut off.
		if avatar.is_player and SoundManager:
			avatar.sputtering_timer += delta
			if avatar.sputtering_timer >= 0.25:
				avatar.sputtering_timer = 0.0
				SoundManager.set_engine_rpm(randf() * 0.4)
		## Hold throttle-up to restart the engine after descending.
		if avatar.is_player and Input.is_action_pressed("throttle_up"):
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
	if not avatar.is_player:
		return

	## Pitch input: inverted flight reverses the control sense.
	var pitch_input := 0.0
	if Input.is_action_pressed("pull_up"):
		pitch_input = -1.0
	elif Input.is_action_pressed("pull_down"):
		pitch_input = 1.0
	if avatar.is_inverted:
		pitch_input = -pitch_input
	pitch_input *= avatar.control_effectiveness

	## Throttle: step on key-repeat.
	if not avatar.engine_cutoff:
		var thr_up   := Input.is_action_pressed("throttle_up")
		var thr_down := Input.is_action_pressed("throttle_down")
		if thr_up or thr_down:
			avatar.throttle_repeat_timer -= delta
			if avatar.throttle_repeat_timer <= 0.0:
				if thr_up:
					avatar.throttle_target = minf(max_throttle, avatar.throttle_target + THROTTLE_STEP)
				else:
					avatar.throttle_target = maxf(min_throttle, avatar.throttle_target - THROTTLE_STEP)
				avatar.throttle_repeat_timer = THROTTLE_REPEAT_DELAY
		else:
			avatar.throttle_repeat_timer = 0.0

	avatar.throttle = move_toward(avatar.throttle, avatar.throttle_target, THROTTLE_RAMP_SPEED * delta)

	## Roll / flip.
	if Input.is_action_just_pressed("roll") and not avatar.is_flipping and not is_grounded(avatar):
		_start_flip(avatar)
	elif Input.is_action_just_released("roll") and avatar.is_flipping:
		_release_flip(avatar)

	## Rotation: smooth angular velocity with inertia.
	if not avatar.is_flipping:
		var model_params = avatar.model_params
		var eff_rot_speed: float = model_params.get("rotation_speed", 5.0) * (1.0 - avatar.damage_percent * 0.4)
		var target_av: float = pitch_input * eff_rot_speed
		avatar.angular_velocity = move_toward(
			avatar.angular_velocity, target_av, model_params.get("rotation_inertia", 4.0) * delta)
		avatar.pitch_angle += avatar.angular_velocity * delta

	rotation = avatar.pitch_angle

## Called by AI systems. Translates a pitch/throttle pair into the same
## angular velocity integration used by the human-input path.
func set_ai_input(pitch: float, throttle_amount: float) -> void:
	for avatar_id in _avatars:
		var avatar: AvatarData = _avatars[avatar_id]
		if avatar.is_player or avatar.flight_state == FlightState.CRASHED:
			continue
		avatar.throttle_target = clampf(throttle_amount, min_throttle, max_throttle)
		avatar.throttle = move_toward(avatar.throttle, avatar.throttle_target, THROTTLE_RAMP_SPEED * 0.016)
		var input_pitch: float = pitch * avatar.control_effectiveness
		if avatar.is_inverted:
			input_pitch = -input_pitch
		var model_params = avatar.model_params
		var eff_rot_speed: float = model_params.get("rotation_speed", 5.0) * (1.0 - avatar.damage_percent * 0.4)
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
		## Not past halfway — spring back.
		var prog := avatar.flip_progress
		if _flip_tween and _flip_tween.is_valid():
			_flip_tween.kill()
		_flip_tween = create_tween()
		_flip_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		_flip_tween.tween_method(_update_flip.bind(avatar), prog, 0.0, FLIP_DURATION * prog)
		_flip_tween.finished.connect(_on_flip_cancelled.bind(avatar))
	else:
		## Past halfway — commit to completion.
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
# CRASH PHYSICS
## After entering CRASHED, the plane tumbles under gravity until the
## RayCast2D detects ground contact, then stops.
###############################################################################

func _apply_crash_physics(avatar: AvatarData, delta: float) -> void:
	if velocity == Vector2.ZERO:
		return
	velocity.y += gravity * pixels_per_meter * delta
	rotation   += velocity.x * 0.01 * delta
	move_and_slide()

	var ground_ray: RayCast2D = $GroundRay if has_node("GroundRay") else null
	if ground_ray and ground_ray.is_colliding():
		velocity           = Vector2.ZERO
		avatar.has_hit_ground = true
		damaged.emit(1.0, 0.0)
		_on_avatar_crashed(avatar)
		return

	var surf_y := _ground_y(global_position.x) - GROUND_SURFACE_OFFSET
	if global_position.y > surf_y:
		global_position.y = surf_y
		if velocity.y > 0.0:
			velocity.y = -velocity.y * 0.1

###############################################################################
# OBSTACLE COLLISION
###############################################################################

func _check_obstacle_collision(avatar: AvatarData) -> void:
	var speed := velocity.length()
	if speed < 5.0:
		return
	var parent := get_parent()
	if not parent:
		return

	for child in parent.get_children():
		if child == self:
			continue

		if child is StaticBody2D and (child.is_in_group("ground_target") or
		   child.is_in_group("wreck") or child.is_in_group("obstacle")):
			var dist   := global_position.distance_to(child.global_position)
			var hit_r  := 35.0 if (child.is_in_group("ground_target") or
			              child.is_in_group("wreck")) else 25.0
			if dist < hit_r:
				if child.has_method("take_damage"):
					child.take_damage(100.0, self)
				_on_avatar_crashed(avatar)
				return

		elif child is CharacterBody2D and child.has_method("get_primary_entity") and speed > 10.0:
			var dist := global_position.distance_to(child.global_position)
			if dist < 40.0:
				take_damage(avatar, 100.0, child)
				_on_avatar_crashed(avatar)
				if child.has_method("force_crash"):
					child.force_crash()
					if is_in_group("player") and GameManager:
						GameManager.add_score(0, 100)
				elif child.has_method("take_damage"):
					child.take_damage(100.0, self)
				return

		elif child.is_in_group("bird") and speed > 5.0:
			var dist := global_position.distance_to(child.global_position)
			if dist < 20.0:
				var bird_damage := randi_range(10, 50)
				take_damage(avatar, bird_damage, child)
				if child.has_method("take_damage"):
					child.take_damage(100.0, self)
				return

###############################################################################
# WEAPONS
###############################################################################

func _handle_weapons(avatar: AvatarData, delta: float) -> void:
	avatar.gun_timer  = maxf(0.0, avatar.gun_timer  - delta)
	avatar.bomb_timer = maxf(0.0, avatar.bomb_timer - delta)

	if not avatar.is_player:
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
	if avatar.is_player and GameManager:
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
	if avatar.is_player and GameManager:
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
		if avatar.current_smoke_type == 0:
			_ensure_smoke(avatar, 1, 10)
		return

	if avatar.throttle > 0.0 or avatar.damage_state >= DamageState.MODERATE:
		var loss := avatar.throttle * delta * 0.8
		match avatar.damage_state:
			DamageState.SEVERE:   loss *= 6.0
			DamageState.MODERATE: loss *= 2.0
		avatar.fuel = maxf(0.0, avatar.fuel - loss)
		if avatar.is_player and GameManager:
			GameManager.fuel_changed.emit(avatar.id, avatar.fuel)

	if SoundManager and avatar.is_player:
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
	if avatar.damage_state != DamageState.INTACT:
		avatar.damage_percent = 0.0
		_refresh_damage_modifiers(avatar)
		avatar.flight_state = FlightState.FLYING

	avatar.refuel_timer += delta
	if avatar.refuel_timer >= 1.5:
		var old_ammo  := avatar.ammo
		var old_bombs := avatar.bombs
		var old_fuel  := avatar.fuel

		avatar.ammo = minf(MAX_AMMO, avatar.ammo + 3.0 + int(2 + delta * 10.0))
		avatar.fuel = minf(100.0, avatar.fuel + 10.0 + int(5 + delta * 10.0))
		avatar.bombs = mini(max_bombs, avatar.bombs + 1)
		avatar.refuel_timer = 0.0

		if avatar.is_player and GameManager:
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

	avatar.damage_percent = minf(1.0, avatar.damage_percent + amount / 100.0)
	_refresh_damage_modifiers(avatar)

	if avatar.damage_state == DamageState.SEVERE and not avatar.is_losing_control:
		_start_spinning_out(avatar)

	if avatar.damage_state == DamageState.DESTROYED:
		## Don't emit crashed yet — wait until hitting ground in FALLING state.
		avatar.flight_state = FlightState.FALLING

###############################################################################
# PARTICLE HELPERS
###############################################################################

## Sync particle effects to current damage state. Called by _refresh_damage_modifiers.
func _sync_damage_particles(avatar: AvatarData) -> void:
	match avatar.damage_state:
		DamageState.DESTROYED, DamageState.SEVERE:
			_ensure_fire(avatar, int(30.0 * avatar.damage_percent))
			_ensure_smoke(avatar, 2, int(30.0 * avatar.damage_percent))
		DamageState.MODERATE:
			_disable_fire(avatar)
			_ensure_smoke(avatar, 2, int(60.0 * avatar.damage_percent))
		DamageState.LIGHT:
			_disable_fire(avatar)
			_ensure_smoke(avatar, 1, int(20.0 * avatar.damage_percent))
		_:
			_disable_fire(avatar)
			_disable_smoke(avatar)

func _ensure_smoke(avatar: AvatarData, smoke_type: int, amount: int) -> void:
	if not avatar.smoke_particles:
		avatar.smoke_particles         = GPUParticles2D.new()
		avatar.smoke_particles.name    = "SmokeParticles_%d" % avatar.id
		avatar.smoke_particles.emitting = true
		avatar.smoke_particles.lifetime = 1.5
		add_child(avatar.smoke_particles)
	avatar.smoke_particles.process_material = \
		_white_smoke_mat if smoke_type == 1 else _black_smoke_mat
	avatar.smoke_particles.amount     = amount
	avatar.current_smoke_type         = smoke_type

func _disable_smoke(avatar: AvatarData) -> void:
	if avatar.smoke_particles:
		avatar.smoke_particles.emitting = false
		avatar.current_smoke_type       = 0

func _ensure_fire(avatar: AvatarData, amount: int) -> void:
	if not avatar.fire_particles:
		avatar.fire_particles                  = GPUParticles2D.new()
		avatar.fire_particles.name             = "FireParticles_%d" % avatar.id
		avatar.fire_particles.emitting         = true
		avatar.fire_particles.lifetime         = 0.3
		avatar.fire_particles.process_material = _fire_mat
		add_child(avatar.fire_particles)
	avatar.fire_particles.amount   = amount
	avatar.fire_particles.emitting = true

func _disable_fire(avatar: AvatarData) -> void:
	if avatar.fire_particles:
		avatar.fire_particles.emitting = false

###############################################################################
# CRASH & SPIN-OUT
###############################################################################

func _start_spinning_out(avatar: AvatarData) -> void:
	avatar.is_losing_control   = true
	avatar.throttle             = 0.0
	avatar.throttle_target      = 0.0
	avatar.flight_state         = FlightState.FALLING

func _on_avatar_crashed(avatar: AvatarData) -> void:
	if _crash_processed.has(avatar.id):
		return
	_crash_processed[avatar.id] = true
	avatar.flight_state          = FlightState.CRASHED
	crashed.emit()
	if avatar.is_player and GameManager:
		GameManager.destroy_player(avatar.id)

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
	match avatar.damage_state:
		DamageState.DESTROYED, DamageState.SEVERE:
			# Add fire effect for heavily damaged planes
			pass
		DamageState.MODERATE:
			# Add smoke effect
			pass
		DamageState.LIGHT:
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

func create_explosion() -> void:
	var pos := global_position
	var explosion_scene := load("res://scenes/explosion.tscn")
	if explosion_scene:
		var explosion: Node = explosion_scene.instantiate()
		explosion.global_position = pos
		get_parent().add_child(explosion)
	var shatter_scene := load("res://scenes/shatter_effect.tscn")
	if shatter_scene:
		var shatter: Node = shatter_scene.instantiate()
		shatter.setup(get_plane_polygon(), Color(0.5, 0.55, 0.5), pos, 20.0)
		get_parent().add_child(shatter)

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
	avatar.is_player = (entity_id == 0)  # First entity is player by default

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

func reset_flight_state() -> void:
	var avatar := get_avatar_data(0)
	if avatar:
		avatar.reset()
		_crash_processed.erase(0)
		_update_ground_ray(avatar)
		if avatar.is_player and SoundManager:
			SoundManager.start_engine()
			SoundManager.set_engine_rpm(0.0)
	reset_visual_transform()

func force_crash() -> void:
	for avatar_id in _avatars:
		var avatar: AvatarData = _avatars[avatar_id]
		if avatar.flight_state != FlightState.CRASHED:
			avatar.damage_percent = 1.0
			_refresh_damage_modifiers(avatar)
			_start_spinning_out(avatar)
			_on_avatar_crashed(avatar)

func _perform_teleport_landing(avatar: AvatarData) -> void:
	avatar.is_inverted = false
	avatar.is_flipping = false
	avatar.flip_progress = 0.0
	avatar.flip_direction = 0
	avatar.pitch_angle = 0.0
	velocity = Vector2.ZERO
	var spawn_pos := get_homebase_spawn_position(avatar)
	var spawn_rot := get_homebase_spawn_rotation(avatar)
	rotation = spawn_rot
	avatar.pitch_angle = spawn_rot
	global_position = Vector2(spawn_pos.x, spawn_pos.y)
	reset_visual_transform(avatar)
	if avatar.is_player and GameManager:
		GameManager.fuel_changed.emit(avatar.id, avatar.fuel)
		GameManager.ammo_changed.emit(avatar.id, avatar.ammo)
		GameManager.bombs_changed.emit(avatar.id, avatar.bombs)
	if avatar.is_player and SoundManager:
		SoundManager.start_engine()
		SoundManager.set_engine_rpm(0.0)

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

func is_player_plane(avatar: AvatarData) -> bool:
	return avatar.is_player

func is_enemy_plane(avatar: AvatarData) -> bool:
	return not avatar.is_player

func is_inverted(avatar: AvatarData) -> bool:
	return avatar.is_inverted if avatar else false

func set_player(avatar: AvatarData, p: bool) -> void:
	avatar.is_player = p

func set_game_active(active: bool) -> void:
	game_active = active

func set_unlimited_fuel_ammo(avatar: AvatarData, val: bool) -> void:
	avatar.unlimited_fuel_ammo = val

func disable_bombs(avatar: AvatarData) -> void:
	avatar.bombs_disabled = true

func set_home_base(avatar: AvatarData, id: int) -> void:
	avatar.homebase_id = id

func do_flip(avatar: AvatarData) -> void:
	if avatar and not avatar.is_flipping:
		_start_flip(avatar)

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
	if avatar.is_player and has_node("Visual"):
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
