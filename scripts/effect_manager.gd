extends Node
## EffectManager — centralized scene-spawner for all visual effects.
## Autoload singleton. Other nodes call EffectManager.spawn_*() at world positions.
##
## Damage state mapping:
##   LIGHT    → white smoke (light damage)
##   MODERATE → black smoke (heavy damage)
##   SEVERE   → black smoke + fire (heavy damage + fire)
##   DESTROYED→ fire + explosion debris + open fire/smoke
##
## Explosion style types (ExplosionStyle enum):
##   NORMAL          — single explosion + shatter, brief screen shake
##   FUEL_DEPOT      — multi-burst (5x), waning INTENSE burns, huge shake
##   VIOLENT_BURST   — fast high-energy one-shot, intense velocity, brief
##   CRASH           — standard crash: explosion + debris + open fire/smoke

signal effect_spawned(effect_name: String, position: Vector2)

const WHITE_SMOKE_SCENE := preload("res://scenes/particles/white_smoke_light_damage.tscn")
const BLACK_SMOKE_SCENE := preload("res://scenes/particles/black_smoke_heavy_damage.tscn")
const FIRE_SCENE         := preload("res://scenes/particles/fire_particles.tscn")
const OPEN_FIRE_SCENE    := preload("res://scenes/particles/open_fire_with_smoke.tscn")
const EXPLOSION_SCENE    := preload("res://scenes/explosion.tscn")
const DEBRIS_SCENE      := preload("res://scenes/particles/explosion_debris.tscn")

## Energy→damage conversion: debris damage = energy * ENERGY_DAMAGE_SCALE
const ENERGY_DAMAGE_SCALE: float = 0.1

## Unified damage-FX: ONE profile table maps DamageData.DamageState →
## visuals for biplanes, tanks, and buildings alike.  Entity differences
## (scale, particle size, duration, anchor offset) are pure parameters on
## DamageFXProfile — see make_damage_profile().
##
## State mapping (single source of truth; replaces the old per-entity tables):
##   LIGHT     → white smoke, amount grows with damage_percent
##   MODERATE  → black smoke, amount grows with damage_percent
##   SEVERE / DESTROYED → wreck fire (open fire + black smoke) at FIXED
##     WRECK_FIRE_AMOUNT / WRECK_SMOKE_AMOUNT — so a SEVERE biplane, a fresh
##     tank wreck, and a burning building wreck all carry the identical fire.
const WRECK_FIRE_DURATION := 8.0
const WRECK_FIRE_AMOUNT := 10
const WRECK_SMOKE_AMOUNT := 8

## Destroyed buildings burn with fire and smoke that both steadily wane and
## go out together as they lose intensity (BUILDING_WANE_TIME to burn down).
## Fuel-depot blasts use the same waning burn (hotter preset, longer wane)
## instead of bespoke mound emitters.  Wanes are kept short on purpose: every
## lingering node occupies effect budget until deleted, and long burns were
## saturating the cap and starving fresh wreck fires (leaving only the
## half-second puffs visible).
const BUILDING_WANE_TIME := 6.0
const DEPOT_WANE_TIME := 12.0

## Smoke reads ~50% denser than the raw profile amounts everywhere.  Single
## multiplier, applied centrally in _smoke_amount() / the spawn wrappers.
const SMOKE_ABUNDANCE := 1.2

## Damage FX always draws above structures/wrecks (buildings z=0, tank
## wrecks z=-10, tanks z=1).  Set on the DamageFX root; children inherit.
const DAMAGE_FX_Z_INDEX := 5

## Smoke/fire color presets shared by the unified builder.
const SMOKE_WHITE := Color(0.8, 0.8, 0.8, 0.5)
const SMOKE_BLACK := Color(0.05, 0.05, 0.05, 0.5)

## Damage-FX node kinds. NONE carries no emitters (INTACT).
enum DamageFXKind { NONE, SMOKE, FIRE_SMOKE }

## Parameter bag for one damage-FX instance.  `size` scales amount, particle
## size, and emission radius together (1.0 = biplane/tank, larger for
## buildings); `offset` anchors the node on the entity; duration is a
## placement concern (attached = burns until detached, world = burn-out timer).
class DamageFXProfile extends RefCounted:
	var kind: int = 1
	var smoke_amount: int = 0
	var fire_amount: int = 0
	var fire_preset: int = 0  ## FireColorPreset (STANDARD default; depots burn INTENSE)
	var smoke_color: Color = Color(0.05, 0.05, 0.05, 0.5)
	var smoke_lifetime: float = 2.0
	var scale: float = 1.0
	var offset: Vector2 = Vector2.ZERO

## Single mapping table: damage state + percent + entity size → profile.
static func make_damage_profile(state: int, percent: float, size := 1.0, offset := Vector2.ZERO) -> DamageFXProfile:
	var p := DamageFXProfile.new()
	p.scale = size
	p.offset = offset
	match state:
		DamageData.DamageState.LIGHT:
			p.kind = DamageFXKind.SMOKE
			p.smoke_color = SMOKE_WHITE
			p.smoke_lifetime = 2.0
			p.smoke_amount = int(round((10.0 + 20.0 * percent) * size))
		DamageData.DamageState.MODERATE:
			p.kind = DamageFXKind.SMOKE
			p.smoke_color = SMOKE_BLACK
			p.smoke_lifetime = 2.5
			p.smoke_amount = int(round((14.0 + 28.0 * percent) * size))
		DamageData.DamageState.SEVERE, DamageData.DamageState.DESTROYED:
			p.kind = DamageFXKind.FIRE_SMOKE
			p.smoke_color = SMOKE_BLACK
			p.smoke_lifetime = 2.5
			p.fire_amount = int(round(WRECK_FIRE_AMOUNT * size))
			p.smoke_amount = int(round(WRECK_SMOKE_AMOUNT * size))
		_:
			p.kind = DamageFXKind.NONE
	return p

## Small standalone smoke plume (fuel starvation): same builder, no damage.
static func make_puff_profile(amount: int, white := true, size := 1.0, offset := Vector2.ZERO) -> DamageFXProfile:
	var p := DamageFXProfile.new()
	p.kind = DamageFXKind.SMOKE
	p.smoke_color = SMOKE_WHITE if white else SMOKE_BLACK
	p.smoke_lifetime = 1.5 if white else 2.0
	p.smoke_amount = maxi(1, amount)
	p.scale = size
	p.offset = offset
	return p

## Explosion visual styles
enum ExplosionStyle {
	NORMAL,          ## Single explosion + shatter, brief screen shake
	FUEL_DEPOT,       ## Multi-burst (5x), waning INTENSE burns, huge shake
	VIOLENT_BURST,   ## Fast high-energy one-shot, intense velocity, brief
}
## Fire color gradient presets
enum FireColorPreset {
	STANDARD,   ## Yellow-white → orange → reddish ash (default)
	INTENSE,    ## Brighter peak, more saturated orange mid
	COOL,       ## More white/blue-white to pale orange
}

## Maximum concurrent effects to keep performance stable.  Sized with headroom
## above worst-case battle load (lingering wreck/depot burns + attached damage
## smoke + bursts): if the cap saturates, fresh wreck fires are dropped
## outright while only half-second puffs remain visible.
@export var max_concurrent_effects: int = 64

var _active_effects: Array[Node] = []
var _effect_count: int = 0

func _process(_delta: float) -> void:
	_active_effects = _active_effects.filter(func(e): return is_instance_valid(e))
	_effect_count = _active_effects.size()

func _physics_process(delta: float) -> void:
	# Wane runs on fixed physics steps, not idle frames: idle rate varies
	# (and can stall entirely headless), but intensity expiry must advance
	# on a steady clock.  Snapshot: retiring a node mid-loop must not skip
	# the siblings behind it.
	for e in _active_effects.duplicate():
		if is_instance_valid(e):
			_tick_wane(e, delta)

func _exit_tree() -> void:
	for e in _active_effects:
		if is_instance_valid(e):
			e.queue_free()
	_active_effects.clear()
	_effect_count = 0

func spawn_white_smoke(pos: Vector2, amount: int = 20, lifetime: float = 0.0) -> Node2D:
	if _effect_count >= max_concurrent_effects:
		return null
	var instance: Node2D = WHITE_SMOKE_SCENE.instantiate()
	instance.global_position = pos
	instance.smoke_amount = int(round(amount * SMOKE_ABUNDANCE))
	_get_world().add_child(instance)
	_active_effects.append(instance)
	effect_spawned.emit("white_smoke", pos)
	_free_after(instance, lifetime)
	return instance

func spawn_black_smoke(pos: Vector2, amount: int = 30, lifetime: float = 0.0) -> Node2D:
	if _effect_count >= max_concurrent_effects:
		return null
	var instance: Node2D = BLACK_SMOKE_SCENE.instantiate()
	instance.global_position = pos
	instance.smoke_amount = int(round(amount * SMOKE_ABUNDANCE))
	_get_world().add_child(instance)
	_active_effects.append(instance)
	effect_spawned.emit("black_smoke", pos)
	_free_after(instance, lifetime)
	return instance

func spawn_fire(pos: Vector2, amount: int = 30, lifetime: float = 0.0) -> Node2D:
	if _effect_count >= max_concurrent_effects:
		return null
	var instance: Node2D = FIRE_SCENE.instantiate()
	instance.global_position = pos
	instance.fire_amount = amount
	_get_world().add_child(instance)
	_active_effects.append(instance)
	effect_spawned.emit("fire", pos)
	_free_after(instance, lifetime)
	return instance

## Schedule an effect node to free itself once its particles have finished, so
## one-shot / burst effects (explosions, crash fire, crash smoke) don't pile up
## at crash sites forever.  A `lifetime` of 0 (default) expires with the
## longest emitter instead of living forever — every effect deletes itself
## when its intensity is spent.
func _free_after(instance: Node2D, lifetime: float) -> void:
	if not is_instance_valid(instance):
		return
	if lifetime <= 0.0:
		lifetime = 0.2
		for child in instance.find_children("*", "GPUParticles2D", true, false):
			lifetime = maxf(lifetime, (child as GPUParticles2D).lifetime + 0.2)
	var t := instance.get_tree().create_timer(lifetime)
	t.timeout.connect(instance.queue_free)

func spawn_open_fire_with_smoke(pos: Vector2, duration: float = 8.0, fire_amount: int = 40, smoke_amount: int = 45) -> Node2D:
	if _effect_count >= max_concurrent_effects:
		return null
	var instance: Node2D = OPEN_FIRE_SCENE.instantiate()
	instance.global_position = pos
	instance.fire_amount = fire_amount
	instance.smoke_amount = smoke_amount
	_get_world().add_child(instance)
	instance.start.call_deferred(duration)
	_active_effects.append(instance)
	effect_spawned.emit("open_fire_with_smoke", pos)
	return instance

## Lingering fire on a freshly destroyed wreck (world-space: the wreck never
## moves, so the effect is spawned once and burns out on its own).  Profile-
## backed: identical fire to a SEVERE biplane at size 1.0; pass a larger size
## for building wrecks.
func spawn_wreck_fire(pos: Vector2, size := 1.0) -> Node2D:
	return spawn_damage_fx(pos, make_damage_profile(DamageData.DamageState.DESTROYED, 1.0, size, Vector2.ZERO))

## Identical wreck fire, parented to a moving node so it travels with a highly
## damaged biplane.  Burns indefinitely (duration INF) until detached — a
## still-flying plane must not have its fire self-extinguish mid-flight while
## the damage persists.
func attach_wreck_fire(parent: Node, offset: Vector2 = Vector2(15, -5), size := 1.0) -> Node2D:
	return attach_damage_fx(parent, make_damage_profile(DamageData.DamageState.SEVERE, 1.0, size, offset))

## Stop and free a wreck-fire node created by spawn/attach_wreck_fire().
func detach_wreck_fire(instance: Node2D) -> void:
	detach_damage_fx(instance)

## Waning burn for a destroyed building wreck: fire and black smoke that
## steadily lose intensity together and go out as one.  One node, so the
## plume never jumps position.
func spawn_building_wreck_fire(pos: Vector2, size := 1.0) -> Node2D:
	return spawn_waning_fire(pos, size, FireColorPreset.STANDARD, BUILDING_WANE_TIME)

## Waning burn: world-space fire + smoke whose emitters both lose `amount`
## linearly over `wane_time` and go out together at zero — smoke wanes and
## fades exactly like fire.  Fuel-depot blasts use this (INTENSE, long wane)
## instead of the old bespoke mound emitters.
func spawn_waning_fire(pos: Vector2, size := 1.0, preset: FireColorPreset = FireColorPreset.STANDARD, wane_time := BUILDING_WANE_TIME) -> Node2D:
	var profile := make_damage_profile(DamageData.DamageState.DESTROYED, 1.0, size, Vector2.ZERO)
	profile.fire_preset = preset
	var node := spawn_damage_fx(pos, profile, INF)
	if node:
		var fire := node.get_node_or_null("Fire") as GPUParticles2D
		var smoke := node.get_node_or_null("Smoke") as GPUParticles2D
		node.set_meta("wane_total", wane_time)
		node.set_meta("wane_left", wane_time)
		node.set_meta("wane_from", fire.amount if fire else 0)
		node.set_meta("wane_smoke_from", smoke.amount if smoke else 0)
	return node

func _tick_wane(node: Node, delta: float) -> void:
	if not node.has_meta("wane_left"):
		return
	var node2d := node as Node2D
	if node2d == null:
		return
	var left := float(node.get_meta("wane_left")) - delta
	node.set_meta("wane_left", left)
	if left <= 0.0:
		# Burned out: cease emission and let the last particles fade before
		# the node frees itself (same graceful retirement as detach).
		detach_damage_fx(node2d)
		return
	var frac := left / float(node.get_meta("wane_total"))
	# Floor at 1: the engine rejects amount 0 ("Amount of particles cannot
	# be smaller than 1").  The last sliver burns at a single particle
	# until `left` expires and detach retires the node.
	var fire := node2d.get_node_or_null("Fire") as GPUParticles2D
	if fire:
		fire.amount = maxi(1, int(round(int(node.get_meta("wane_from")) * frac)))
	var smoke := node2d.get_node_or_null("Smoke") as GPUParticles2D
	if smoke:
		smoke.amount = maxi(1, int(round(int(node.get_meta("wane_smoke_from")) * frac)))

## Single builder for all continuous damage-FX.  One Node2D carrying a smoke
## emitter plus (FIRE_SMOKE only) a fire emitter in the STANDARD palette, both
## with local_coords=false so attached trails read correctly on moving
## entities and identically on static ones.  Amounts live-update via
## _retune_damage_fx(); the node is rebuilt only when its kind/size changes.
func _build_damage_fx(profile: DamageFXProfile) -> Node2D:
	var root := Node2D.new()
	root.name = "DamageFX"
	root.z_index = DAMAGE_FX_Z_INDEX
	root.set_meta("fx_kind", profile.kind)
	root.set_meta("fx_size", profile.scale)

	var smoke := GPUParticles2D.new()
	smoke.name = "Smoke"
	smoke.emitting = true
	smoke.one_shot = false
	smoke.amount = _smoke_amount(profile)
	smoke.lifetime = profile.smoke_lifetime
	smoke.position = Vector2.ZERO
	smoke.local_coords = false
	var smoke_mat := ParticleProcessMaterial.new()
	smoke_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke_mat.emission_sphere_radius = 10.0 * profile.scale
	# Larger burns drive stronger thermals: smoke rise scales with size, so
	# building plumes (1.5–3.0) climb faster while planes/tanks (1.0) are
	# bit-identical to before.
	var rise := 0.5 + 0.5 * profile.scale
	smoke_mat.gravity = Vector3(0, -30.0 * rise, 0)
	smoke_mat.spread = 30.0
	smoke_mat.initial_velocity_min = 30.0 * rise
	smoke_mat.initial_velocity_max = 60.0 * rise
	smoke_mat.scale_min = 6.0 * profile.scale
	smoke_mat.scale_max = 14.0 * profile.scale
	smoke_mat.color_ramp = make_smoke_ramp(profile.smoke_color)
	smoke.process_material = smoke_mat
	root.add_child(smoke)

	if profile.kind == DamageFXKind.FIRE_SMOKE:
		var colors := _get_fire_colors(profile.fire_preset)
		var fire := GPUParticles2D.new()
		fire.name = "Fire"
		fire.emitting = true
		fire.one_shot = false
		fire.amount = maxi(1, profile.fire_amount)
		fire.lifetime = 0.35
		fire.explosiveness = 0.35
		fire.position = Vector2.ZERO
		fire.local_coords = false
		var fire_mat := ParticleProcessMaterial.new()
		fire_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		fire_mat.emission_sphere_radius = 5.0 * profile.scale
		fire_mat.gravity = Vector3(0, -40, 0)
		fire_mat.spread = 30.0
		fire_mat.initial_velocity_min = 60.0
		fire_mat.initial_velocity_max = 90.0
		fire_mat.scale_min = 4.0 * profile.scale
		fire_mat.scale_max = 8.0 * profile.scale
		fire_mat.color_ramp = make_fire_ramp(colors["peak"], colors["mid"], colors["ash"])
		fire.process_material = fire_mat
		root.add_child(fire)

	return root

## Live-update emitter amounts on an existing damage-FX node (same kind/size).
func _retune_damage_fx(node: Node2D, profile: DamageFXProfile) -> void:
	var smoke := node.get_node_or_null("Smoke") as GPUParticles2D
	if smoke:
		smoke.amount = _smoke_amount(profile)
		smoke.emitting = true
	var fire := node.get_node_or_null("Fire") as GPUParticles2D
	if fire and profile.kind == DamageFXKind.FIRE_SMOKE:
		fire.amount = maxi(1, profile.fire_amount)
		fire.emitting = true

## Attached damage-FX: follows the entity until detached.  Used for biplanes,
## tanks (via the biplane sync), and buildings (static, so equivalent to a
## spawn but with automatic cleanup on destroy).
func attach_damage_fx(parent: Node, profile: DamageFXProfile) -> Node2D:
	if _effect_count >= max_concurrent_effects:
		return null
	var node := _build_damage_fx(profile)
	node.set_meta("fx_kind", profile.kind)
	node.set_meta("fx_size", profile.scale)
	node.set_meta("fx_color", profile.smoke_color.to_rgba32())
	node.position = profile.offset
	parent.add_child(node)
	_active_effects.append(node)
	effect_spawned.emit("damage_fx", node.global_position)
	return node

## World-space damage-FX with a burn-out timer.  Used for wreck sites.
func spawn_damage_fx(pos: Vector2, profile: DamageFXProfile, duration := WRECK_FIRE_DURATION) -> Node2D:
	if _effect_count >= max_concurrent_effects:
		return null
	var node := _build_damage_fx(profile)
	node.global_position = pos
	_get_world().add_child(node)
	_active_effects.append(node)
	effect_spawned.emit("damage_fx", pos)
	_free_damage_fx_after(node, duration)
	return node

func _free_damage_fx_after(node: Node2D, duration: float) -> void:
	if duration == INF or duration <= 0.0 or not is_instance_valid(node):
		return
	var t := node.get_tree().create_timer(duration)
	# Guarded closure, NOT .bind(node): a bound freed object fails typed
	# conversion at emit time ("Cannot convert argument 1 from Object to
	# Object") when the node dies first (level change, early detach).  The
	# closure checks validity before touching it.
	t.timeout.connect(func(): if is_instance_valid(node): detach_damage_fx(node))

## Idempotent sync: the ONE entry point for lingering damage visuals.
## Returns the live node (or null for INTACT).  Rebuilds only when kind or
## size changes; otherwise retunes amounts in place and re-anchors the offset.
## `size` 1.0 = biplane/tank; buildings pass a footprint-derived factor.
func sync_damage_fx(parent: Node, current: Node2D, state: int, percent: float, size := 1.0, offset := Vector2.ZERO) -> Node2D:
	var want := make_damage_profile(state, percent, size, offset)
	if want.kind == DamageFXKind.NONE:
		detach_damage_fx(current)
		return null
	if current != null and is_instance_valid(current) \
			and int(current.get_meta("fx_kind", -1)) == want.kind \
			and is_equal_approx(float(current.get_meta("fx_size", 0.0)), size) \
			and int(current.get_meta("fx_color", 0)) == int(want.smoke_color.to_rgba32()):
		_retune_damage_fx(current, want)
		current.position = offset
		return current
	detach_damage_fx(current)
	return attach_damage_fx(parent, want)

## Stop and release a node created by attach/spawn/sync_damage_fx (or the
## wreck helpers).  Safe on null/freed nodes.  Emission ceases at once but
## the node is freed only after its longest particle lifetime expires, so
## state switches dissolve instead of popping.  It is reparented to the
## world first so a dying parent (destroyed building, respawning plane)
## cannot cut the fade short.
func detach_damage_fx(node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	_active_effects.erase(node)
	var longest := 0.0
	for child in node.get_children():
		if child is GPUParticles2D:
			child.emitting = false
			longest = maxf(longest, child.lifetime)
	var world := _get_world()
	if node.get_parent() != world:
		var gp := node.global_position
		var parent := node.get_parent()
		if parent:
			parent.remove_child(node)
		world.add_child(node)
		node.global_position = gp
	var t := get_tree().create_timer(longest + 0.2)
	t.timeout.connect(node.queue_free)

func spawn_explosion(pos: Vector2, energy: float) -> Node2D:
	var instance: Node2D = EXPLOSION_SCENE.instantiate()
	instance.global_position = pos
	_get_world().add_child(instance)
	_active_effects.append(instance)
	effect_spawned.emit("explosion", pos)
	if GameManager:
		GameManager.request_screen_shake(energy / 3.0)
	# One-shot flash with no script of its own — free the (emitter-less) node
	# once its particles have finished so explosions don't accumulate in the tree.
	_free_after(instance, 0.6)
	return instance

func spawn_explosion_debris(pos: Vector2, energy: float, count: int, color: Color, polygon: PackedVector2Array = PackedVector2Array()) -> Node2D:
	if _effect_count >= max_concurrent_effects:
		return null
	var instance: Node2D = DEBRIS_SCENE.instantiate()
	instance.global_position = pos
	_get_world().add_child(instance)
	var dmg: float = energy * ENERGY_DAMAGE_SCALE
	instance.setup(pos, color, count, dmg)
	_active_effects.append(instance)
	effect_spawned.emit("explosion_debris", pos)
	return instance

func spawn_explosion_style(pos: Vector2, energy: float, style: ExplosionStyle, debris_count: int = 0, debris_color: Color = Color(0.2, 0.3, 0.2), fire_preset: FireColorPreset = FireColorPreset.STANDARD, polygon: PackedVector2Array = PackedVector2Array()) -> void:
	match style:
		ExplosionStyle.FUEL_DEPOT:
			for i in range(5):
				spawn_explosion(pos + Vector2(randf_range(-12, 12), randf_range(-15, 2)), energy * 0.3)
			# Waning extreme-damage burns: same effect as building wreck
			# fires, hotter preset and longer wane for a fuel blast.
			for i in range(3):
				spawn_waning_fire(
					pos + Vector2(randf_range(-20, 20), randf_range(-20, 0)),
					2.0, FireColorPreset.INTENSE, DEPOT_WANE_TIME)
			# Flak-like area explosion puff
			spawn_fire_puff(pos, 250.0, 0.5)

		ExplosionStyle.VIOLENT_BURST:
			spawn_explosion(pos, energy)
			var fire := _spawn_violent_fire(pos, fire_preset)
			if fire:
				_active_effects.append(fire)
			var smoke := _spawn_violent_smoke(pos)
			if smoke:
				_active_effects.append(smoke)

		_:
			spawn_explosion(pos, energy)

	if debris_count > 0:
		spawn_explosion_debris(pos, energy, debris_count, debris_color, polygon)

	if GameManager:
		GameManager.request_screen_shake(energy / 3.0)


func _get_fire_colors(preset: FireColorPreset) -> Dictionary:
	match preset:
		FireColorPreset.INTENSE:
			return {
				"peak": Color(1.0, 1.0, 0.9, 1.0),
				"mid": Color(1.0, 0.6, 0.1, 0.95),
				"ash": Color(0.5, 0.15, 0.05, 0.4)
			}
		FireColorPreset.COOL:
			return {
				"peak": Color(0.9, 0.95, 1.0, 1.0),
				"mid": Color(1.0, 0.7, 0.3, 0.9),
				"ash": Color(0.5, 0.2, 0.1, 0.3)
			}
		_:
			return {
				"peak": Color(1.0, 0.95, 0.7, 1.0),
				"mid": Color(1.0, 0.5, 0.1, 0.9),
				"ash": Color(0.4, 0.1, 0.05, 0.3)
			}

## Single builder for every procedural particle color ramp.  Gradient.new()
## ships with black@0 / white@1 defaults that add_point() does NOT remove, so
## the naive new()+add_point pattern births black particles that die white —
## the reverse of a fire ramp.  Reusing the two default slots keeps exactly
## one point per stop: offset 0 samples stops[0], offset 1 the last stop.
## `stops`: Array of [offset: float, color: Color], ascending, at least two.
static func make_color_ramp(stops: Array) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.set_offset(0, float(stops[0][0]))
	grad.set_color(0, stops[0][1])
	grad.set_offset(1, float(stops[stops.size() - 1][0]))
	grad.set_color(1, stops[stops.size() - 1][1])
	for i in range(1, stops.size() - 1):
		grad.add_point(float(stops[i][0]), stops[i][1])
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex

## Standard fire ramp: yellow-white birth → orange mid-life → transparent
## orange-red death.  Shared by all fire emitters (damage FX, depot fires,
## violent bursts, and the fire/open-fire particle scenes).
static func make_fire_ramp(peak: Color, mid: Color, ash: Color) -> GradientTexture1D:
	return make_color_ramp([[0.0, peak], [0.3, mid], [1.0, ash]])

## Smoke ramp: full-strength birth holding most of its life, then fading to
## transparency so puffs dissolve instead of popping out.  Shared by white
## and black smoke everywhere (unified builder + standalone smoke scenes).
static func make_smoke_ramp(color: Color) -> GradientTexture1D:
	var clear := color
	clear.a = 0.0
	return make_color_ramp([[0.0, color], [0.65, color], [1.0, clear]])

## Central smoke abundance: every smoke emitter draws ~50% more particles
## than its raw profile amount.
static func _smoke_amount(profile: DamageFXProfile) -> int:
	return maxi(1, int(round(profile.smoke_amount * SMOKE_ABUNDANCE)))

## Preset-keyed convenience wrapper for EffectManager-internal emitters.
func _fire_ramp(preset: FireColorPreset) -> GradientTexture1D:
	var colors := _get_fire_colors(preset)
	return make_fire_ramp(colors["peak"], colors["mid"], colors["ash"])

func _spawn_violent_fire(base_pos: Vector2, preset: FireColorPreset) -> Node2D:
	if _effect_count >= max_concurrent_effects:
		return null
	var fire := GPUParticles2D.new()
	fire.name = "ViolentFire"
	fire.emitting = true
	fire.one_shot = true
	fire.explosiveness = 1.0
	fire.amount = 40
	fire.lifetime = 0.8
	fire.position = Vector2.ZERO
	fire.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 20.0
	mat.gravity = Vector3(0, -80, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 100.0
	mat.initial_velocity_max = 250.0
	mat.scale_min = 4.0
	mat.scale_max = 10.0

	var colors := _get_fire_colors(preset)
	mat.color_ramp = make_fire_ramp(colors["peak"], colors["mid"], colors["ash"])
	fire.process_material = mat
	_get_world().add_child(fire)
	effect_spawned.emit("violent_fire", base_pos)
	return fire

func _spawn_violent_smoke(base_pos: Vector2) -> Node2D:
	if _effect_count >= max_concurrent_effects:
		return null
	var smoke := GPUParticles2D.new()
	smoke.name = "ViolentSmoke"
	smoke.emitting = true
	smoke.one_shot = true
	smoke.explosiveness = 0.8
	smoke.amount = int(round(30.0 * SMOKE_ABUNDANCE))
	smoke.lifetime = 1.5
	smoke.position = Vector2.ZERO
	smoke.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 25.0
	mat.gravity = Vector3(0, -20, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 50.0
	mat.initial_velocity_max = 120.0
	mat.scale_min = 5.0
	mat.scale_max = 12.0
	mat.color_ramp = make_smoke_ramp(Color(0.1, 0.1, 0.1, 1.0))
	smoke.process_material = mat
	_get_world().add_child(smoke)
	effect_spawned.emit("violent_smoke", base_pos)
	return smoke

func stop_effect(effect: Node2D) -> void:
	if effect and is_instance_valid(effect):
		if effect.has_method("stop"):
			effect.stop()
		if effect.has_method("queue_free"):
			effect.queue_free()
		_active_effects.erase(effect)

## Spawn a fire-toned puffy circle (bomb/flak explosion) that fades from
## yellow-white to transparent orange-red within `duration` seconds.
## Replaces the old white shock ring with a natural fire-toned puff that
## scales with `radius` and uses the same color palette as fire effects.
func spawn_fire_puff(pos: Vector2, radius: float = 200.0, duration: float = 0.3) -> GPUParticles2D:
	if _effect_count >= max_concurrent_effects:
		return null
	var puff := GPUParticles2D.new()
	puff.name = "FirePuff"
	puff.global_position = pos
	puff.emitting = true
	puff.one_shot = true
	puff.amount = maxi(20, int(radius * 0.3))
	puff.lifetime = duration
	puff.explosiveness = 0.6
	puff.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = radius * 0.15
	mat.gravity = Vector3(0, -10, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = radius / duration * 0.3
	mat.initial_velocity_max = radius / duration * 0.8
	mat.scale_min = 4.0
	mat.scale_max = 12.0
	mat.color_ramp = make_color_ramp([
		[0.0, Color(1.0, 0.95, 0.6, 0.9)],
		[0.2, Color(1.0, 0.6, 0.1, 0.7)],
		[0.5, Color(0.9, 0.3, 0.05, 0.4)],
		[1.0, Color(0.6, 0.1, 0.02, 0.0)],
	])
	puff.process_material = mat
	_get_world().add_child(puff)
	_active_effects.append(puff)
	effect_spawned.emit("fire_puff", pos)
	_free_after(puff, duration + 0.1)
	return puff

func spawn_destruction_puff(pos: Vector2) -> void:
	spawn_fire(pos, 15, 0.5)
	spawn_black_smoke(pos, 20, 0.5)

func _get_world() -> Node:
	var tree := get_tree()
	if tree and tree.root and tree.root.has_node("Main"):
		return tree.root.get_node("Main")
	return self