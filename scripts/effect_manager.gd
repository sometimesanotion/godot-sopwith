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
##   FUEL_DEPOT      — multi-burst (5x), persistent fire/smoke mounds, huge shake
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

## Explosion visual styles
enum ExplosionStyle {
	NORMAL,          ## Single explosion + shatter, brief screen shake
	FUEL_DEPOT,       ## Multi-burst (5x), persistent fire/smoke mounds, huge shake
	VIOLENT_BURST,   ## Fast high-energy one-shot, intense velocity, brief
}
## Fire color gradient presets
enum FireColorPreset {
	STANDARD,   ## Yellow-white → orange → reddish ash (default)
	INTENSE,    ## Brighter peak, more saturated orange mid
	COOL,       ## More white/blue-white to pale orange
}

## Maximum concurrent effects to keep performance stable.
@export var max_concurrent_effects: int = 32

var _active_effects: Array[Node] = []
var _effect_count: int = 0

func _process(_delta: float) -> void:
	_active_effects = _active_effects.filter(func(e): return is_instance_valid(e))
	_effect_count = _active_effects.size()

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
	instance.smoke_amount = amount
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
	instance.smoke_amount = amount
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
## at crash sites forever.  A `lifetime` of 0 (default) leaves the node alive
## indefinitely — used by persistent damage effects on static wreckage.
func _free_after(instance: Node2D, lifetime: float) -> void:
	if lifetime <= 0.0 or not is_instance_valid(instance):
		return
	var t := instance.get_tree().create_timer(lifetime)
	t.timeout.connect(instance.queue_free)

func spawn_open_fire_with_smoke(pos: Vector2, duration: float = 8.0, fire_amount: int = 40, smoke_amount: int = 30) -> Node2D:
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
	_free_after(instance, 1.5)
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

func spawn_crash_effects(pos: Vector2, energy: float, debris_count: int, debris_color: Color, polygon: PackedVector2Array = PackedVector2Array()) -> void:
	spawn_explosion(pos, energy)
	spawn_explosion_debris(pos, energy, debris_count, debris_color, polygon)
	spawn_open_fire_with_smoke(pos, 6.0, 30, 20)

func spawn_damage_effects(pos: Vector2, damage_state: int, damage_percent: float) -> void:
	match damage_state:
		1:  ## LIGHT
			var smoke := spawn_white_smoke(pos, int(40.0 * damage_percent))
		2:  ## MODERATE
			spawn_black_smoke(pos, int(60.0 * damage_percent))
		3:  ## SEVERE
			spawn_black_smoke(pos, int(30.0 * damage_percent))
			spawn_fire(pos, int(30.0 * damage_percent))
		4:  ## DESTROYED
			spawn_open_fire_with_smoke(pos, 6.0, 30, 20)

func spawn_explosion_style(pos: Vector2, energy: float, style: ExplosionStyle, debris_count: int = 0, debris_color: Color = Color(0.2, 0.3, 0.2), fire_preset: FireColorPreset = FireColorPreset.STANDARD, polygon: PackedVector2Array = PackedVector2Array()) -> void:
	match style:
		ExplosionStyle.FUEL_DEPOT:
			for i in range(5):
				spawn_explosion(pos + Vector2(randf_range(-12, 12), randf_range(-15, 2)), energy * 0.3)
			for i in range(5):
				var fire := _spawn_fuel_depot_fire(pos, fire_preset)
				if fire:
					_active_effects.append(fire)
			for i in range(3):
				var smoke := _spawn_fuel_depot_smoke(pos)
				if smoke:
					_active_effects.append(smoke)

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

func _spawn_fuel_depot_fire(base_pos: Vector2, preset: FireColorPreset) -> Node2D:
	if _effect_count >= max_concurrent_effects:
		return null
	var fire := GPUParticles2D.new()
	fire.name = "FuelDepotFire"
	fire.emitting = true
	fire.one_shot = false
	fire.explosiveness = 0.0
	fire.amount = 30
	fire.lifetime = 4.0
	fire.position = base_pos + Vector2(randf_range(-20, 20), randf_range(-20, 0))
	fire.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 15.0
	mat.gravity = Vector3(0, -50, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 30.0
	mat.initial_velocity_max = 80.0
	mat.scale_min = 3.0
	mat.scale_max = 8.0

	var colors := _get_fire_colors(preset)
	var gradient := Gradient.new()
	gradient.add_point(0.0, colors["peak"])
	gradient.add_point(0.3, colors["mid"])
	gradient.add_point(1.0, colors["ash"])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = gradient
	mat.color_ramp = grad_tex
	fire.process_material = mat
	_get_world().add_child(fire)
	effect_spawned.emit("fuel_depot_fire", base_pos)
	return fire

func _spawn_fuel_depot_smoke(base_pos: Vector2) -> Node2D:
	if _effect_count >= max_concurrent_effects:
		return null
	var smoke := GPUParticles2D.new()
	smoke.name = "FuelDepotSmoke"
	smoke.emitting = true
	smoke.one_shot = false
	smoke.amount = 20
	smoke.lifetime = 6.0
	smoke.position = base_pos + Vector2(randf_range(-15, 15), randf_range(-15, 0))
	smoke.local_coords = false

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 20.0
	mat.gravity = Vector3(0, -15, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 20.0
	mat.initial_velocity_max = 50.0
	mat.scale_min = 4.0
	mat.scale_max = 10.0
	mat.color = Color(0.1, 0.1, 0.1, 0.8)
	smoke.process_material = mat
	_get_world().add_child(smoke)
	effect_spawned.emit("fuel_depot_smoke", base_pos)
	return smoke

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
	var gradient := Gradient.new()
	gradient.add_point(0.0, colors["peak"])
	gradient.add_point(0.3, colors["mid"])
	gradient.add_point(1.0, colors["ash"])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = gradient
	mat.color_ramp = grad_tex
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
	smoke.amount = 30
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
	mat.color = Color(0.1, 0.1, 0.1, 1.0)
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

## Create continuous 3-layer fire attached to a parent node (for planes, etc.).
## Returns {"core": GPUParticles2D, "glow": GPUParticles2D, "smoke": GPUParticles2D}.
func attach_continuous_fire(parent: Node, offset: Vector2 = Vector2(15, -5), amount: int = 30, preset: FireColorPreset = FireColorPreset.STANDARD) -> Dictionary:
	var colors := _get_fire_colors(preset)
	var handles := {}

	# Layer 1: Fast, small, short-lived yellow-white core particles
	var core := GPUParticles2D.new()
	core.name = "ContinuousFireCore"
	core.emitting = true
	core.one_shot = false
	core.amount = max(1, amount)
	core.lifetime = 0.12
	core.explosiveness = 0.3
	core.position = offset
	core.local_coords = false
	var core_mat := ParticleProcessMaterial.new()
	core_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	core_mat.emission_sphere_radius = 3.0
	core_mat.gravity = Vector3(0, -20, 0)
	core_mat.spread = 40.0
	core_mat.initial_velocity_min = 80.0
	core_mat.initial_velocity_max = 120.0
	core_mat.scale_min = 1.5
	core_mat.scale_max = 3.0
	var core_grad := Gradient.new()
	core_grad.add_point(0.0, colors["peak"])
	core_grad.add_point(0.6, colors["mid"])
	core_grad.add_point(1.0, Color(colors["ash"].r, colors["ash"].g, colors["ash"].b, 0.0))
	var core_tex := GradientTexture1D.new()
	core_tex.gradient = core_grad
	core_mat.color_ramp = core_tex
	core.process_material = core_mat
	parent.add_child(core)
	handles["core"] = core

	# Layer 2: Slower, larger, translucent orange glow
	var glow := GPUParticles2D.new()
	glow.name = "ContinuousFireGlow"
	glow.emitting = true
	glow.one_shot = false
	glow.amount = max(1, amount / 2)
	glow.lifetime = 0.4
	glow.explosiveness = 0.2
	glow.position = offset
	glow.local_coords = false
	var glow_mat := ParticleProcessMaterial.new()
	glow_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	glow_mat.emission_sphere_radius = 5.0
	glow_mat.gravity = Vector3(0, -30, 0)
	glow_mat.spread = 35.0
	glow_mat.initial_velocity_min = 40.0
	glow_mat.initial_velocity_max = 70.0
	glow_mat.scale_min = 3.0
	glow_mat.scale_max = 6.0
	var glow_grad := Gradient.new()
	glow_grad.add_point(0.0, colors["mid"])
	glow_grad.add_point(0.5, Color(colors["ash"].r, colors["ash"].g, colors["ash"].b, colors["ash"].a * 0.6))
	glow_grad.add_point(1.0, Color(colors["ash"].r, colors["ash"].g, colors["ash"].b, 0.0))
	var glow_tex := GradientTexture1D.new()
	glow_tex.gradient = glow_grad
	glow_mat.color_ramp = glow_tex
	glow.process_material = glow_mat
	parent.add_child(glow)
	handles["glow"] = glow

	# Layer 3: Large, slow, translucent black smoke
	var smoke := GPUParticles2D.new()
	smoke.name = "ContinuousFireSmoke"
	smoke.emitting = true
	smoke.one_shot = false
	smoke.amount = max(1, amount / 3)
	smoke.lifetime = 1.5
	smoke.explosiveness = 0.0
	smoke.position = offset
	smoke.local_coords = false
	var smoke_mat := ParticleProcessMaterial.new()
	smoke_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke_mat.emission_sphere_radius = 8.0
	smoke_mat.gravity = Vector3(0, -15, 0)
	smoke_mat.spread = 30.0
	smoke_mat.initial_velocity_min = 15.0
	smoke_mat.initial_velocity_max = 35.0
	smoke_mat.scale_min = 6.0
	smoke_mat.scale_max = 12.0
	smoke_mat.color = Color(0.05, 0.05, 0.05, 0.35)
	smoke.process_material = smoke_mat
	parent.add_child(smoke)
	handles["smoke"] = smoke

	return handles

## Update amount on all layers of a continuous fire effect.
func update_continuous_fire(handles: Dictionary, amount: int) -> void:
	if handles.has("core") and handles["core"] and is_instance_valid(handles["core"]):
		handles["core"].amount = max(1, amount)
		handles["core"].emitting = true
	if handles.has("glow") and handles["glow"] and is_instance_valid(handles["glow"]):
		handles["glow"].amount = max(1, amount / 2)
		handles["glow"].emitting = true
	if handles.has("smoke") and handles["smoke"] and is_instance_valid(handles["smoke"]):
		handles["smoke"].amount = max(1, amount / 3)
		handles["smoke"].emitting = true

## Stop and free all layers of a continuous fire effect.
func detach_continuous_fire(handles: Dictionary) -> void:
	for key in ["core", "glow", "smoke"]:
		if handles.has(key) and handles[key] and is_instance_valid(handles[key]):
			handles[key].emitting = false
			handles[key].queue_free()
			handles[key] = null

## Attach continuous smoke to a parent node (white for LIGHT, black for MODERATE+).
## Returns the GPUParticles2D node, or null on failure.
func attach_continuous_smoke(parent: Node, offset: Vector2 = Vector2(-15, 5), smoke_type: int = 1, amount: int = 20) -> GPUParticles2D:
	var smoke := GPUParticles2D.new()
	smoke.name = "ContinuousSmoke_%s" % ("white" if smoke_type == 1 else "black")
	smoke.emitting = true
	smoke.one_shot = false
	smoke.amount = amount
	smoke.lifetime = 1.5
	smoke.position = offset
	smoke.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 8.0
	mat.gravity = Vector3(0, 30, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = 30.0
	mat.initial_velocity_max = 60.0
	mat.scale_min = 4.0
	mat.scale_max = 10.0
	mat.color = Color(0.8, 0.8, 0.8, 0.5) if smoke_type == 1 else Color(0.05, 0.05, 0.05, 0.5)
	smoke.process_material = mat
	parent.add_child(smoke)
	return smoke

## Update continuous smoke particle amount.
func update_continuous_smoke(particle_node: GPUParticles2D, amount: int) -> void:
	if particle_node and is_instance_valid(particle_node):
		particle_node.amount = amount
		particle_node.emitting = true

## Stop and free continuous smoke particles.
func detach_continuous_smoke(particle_node: GPUParticles2D) -> void:
	if particle_node and is_instance_valid(particle_node):
		particle_node.emitting = false
		particle_node.queue_free()

## Spawn a rapidly expanding translucent white ring (bomb explosion) that
## grows to `radius` pixels over `duration` seconds.
func spawn_bomb_explosion_ring(pos: Vector2, radius: float = 200.0, duration: float = 0.1) -> GPUParticles2D:
	if _effect_count >= max_concurrent_effects:
		return null
	var ring := GPUParticles2D.new()
	ring.name = "BombExplosionRing"
	ring.global_position = pos
	ring.emitting = true
	ring.one_shot = true
	ring.amount = 80
	ring.lifetime = duration
	ring.explosiveness = 1.0
	ring.local_coords = false
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.0
	mat.gravity = Vector3.ZERO
	mat.spread = 0.0
	mat.initial_velocity_min = radius / duration * 0.8
	mat.initial_velocity_max = radius / duration * 1.2
	mat.scale_min = 2.0
	mat.scale_max = 5.0
	var grad := Gradient.new()
	grad.add_point(0.0, Color(1, 1, 1, 0.5))
	grad.add_point(0.3, Color(1, 1, 1, 0.3))
	grad.add_point(1.0, Color(1, 1, 1, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	mat.color_ramp = tex
	ring.process_material = mat
	_get_world().add_child(ring)
	_active_effects.append(ring)
	effect_spawned.emit("bomb_explosion_ring", pos)
	return ring

func _get_world() -> Node:
	var tree := get_tree()
	if tree and tree.root and tree.root.has_node("Main"):
		return tree.root.get_node("Main")
	return self