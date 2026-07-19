Essential knowledge for maintaining and extending this Godot 4.6.2 Sopwith recreation.  Covers architecture, core systems, debug patterns, and critical constants for contributors.

## Agent conventions

Use `@extract <a natural language query for what you're looking for>` as a first resort for reading local files.

## Project Overview

Recreation of classic Sopwith in Godot 4.6.2 (GDScript). A 2D biplane combat game with physics-based flight, AI enemies, terrain, and objectives.

Key directories: scripts/, scenes/, scenes/particles/, shaders/

## Architecture

- **Biplane** (`scripts/biplane.gd` extends RigidBody2D): Core flight controller. Uses `Aerodynamics` static module for all physics calculations via `_integrate_forces()`. Flight state is an **enum + signal** on `AvatarData.flight_state` (written only via `AvatarData.set_flight_state()`, which no-ops on same-value and emits `flight_state_changed(from, to)`). There is **no flight node-FSM** — the `scripts/states/flight/` directory was deleted in M2.
- **Aerodynamics** (`scripts/aerodynamics.gd`): Pure static module. `calculate_forces(FlightInput) → FlightOutput`. Contains all NASA-derived lift/drag/thrust/stall formulas. No node references.
- **Terrain** (`scripts/terrain.gd` extends Node2D, `class_name Terrain`): Gameplay surface. Owns `ground_points`, `StaticBody2D` collision, 3 tiled `Polygon2D` copies, and 3 tiled `Line2D` trim lines. Multi-frequency synthesis (D4): `_sample_height(x)` layers a **macro** noise (sweeping plains/mountains) with a **micro** noise whose amplitude is modulated by macro ruggedness. The macro/micro instances are built via `TerrainNoise.make_noise` with `derive_seed(resolved_seed, SALT_*)`; `_runway_flatness(x)` returns 0 exactly on any registered runway span and smoothsteps to 1 over `RUNWAY_BLEND_WIDTH` (D5) so off-runway taxiing has no collision cliffs. **Public API** (all consumers must keep working): `generate()`, `add_runway(x)`, `get_ground_height_at(x)`, `is_on_runway(x)`, `get_ground_points()`, `get_terrain_info_at(x)`, `get_visual_line()`. `resolved_seed` is the world seed (set in `_initialize_noise` from `GameManager.terrain_seed` else `randi()`).
- **TerrainNoise** (`scripts/terrain_noise.gd`, `class_name TerrainNoise`): Shared static noise module. `make_noise(seed, frequency, octaves, gain)`, `sample_periodic(noise, x, period)` (D3: 1D periodic sampling via circle-of-radius-`period/TAU` in 2D noise space — preserves wavelength and gives a C∞-continuous wrap, no height OR slope seam), `derive_seed(base, salt)` (deterministic per-purpose seed split via `(base + salt*747796405) & 0x7FFFFFFF`), `smoothstep01(t)`. Used by **both** `terrain.gd` and `background.gd` — single source of periodic noise in the project.
- **ParallaxScenery** (`scripts/parallax_scenery.gd`, `class_name ParallaxScenery`): Static builders for the 3-layer vector parallax (D6/D9). `build_ridge_points(seed, period, baseline, amplitude, frequency, seg)` (one-sided silhouette: `baseline - (v*0.5+0.5)*amplitude`), `make_ridge_polygon(points, period, floor_y, color)`, `make_trim_line(points, color)`, `build_clouds(seed, period, count)` (14 clusters × 3–7 ellipse puffs, 12 verts, y∈[100, 420], alpha∈[0.35, 0.55]). No stored state, no node references.
- **Background** (`scripts/background.gd` extends Node2D): Owns the sky gradient (unchanged, `CanvasLayer.layer = -20`) and assembles the deterministic, seed-driven 3-layer vector parallax via `generate(seed)` (called by `main.gd` after `terrain.generate()`). The legacy per-frame `_draw` mountains/clouds path (randomized, 4 000+ circles/frame) was deleted in M5.3. All scenery is now static — zero per-frame `_draw` in `background.gd`. 3 ridge `ParallaxLayer`s at `motion_mirroring = TERRAIN_LENGTH * scale` (D6 math) + the cloud cluster on the 0.6-scale layer. The `ParallaxBackground` is at `CanvasLayer.layer = -15`.
- **EffectManager** (`scripts/effect_manager.gd`): Autoload singleton. Spawns GPUParticles2D effects (smoke, fire, debris) at world positions. `spawn_damage_effects()` maps DamageState to particle combos.
- **FSM** (`state.gd` / `state_machine.gd`): Reusable base classes. Used by the **AI** FSM (`scripts/states/ai/`) and the **Game** FSM (`scripts/states/game/`). Flight states are NOT FSM-backed (see Biplane above).
- **EnemyAI** (`scripts/enemy_ai.gd`): FSM-driven dogfighting AI. The controller is the **sole driver** of `AIStateMachine`: it accumulates real elapsed time and ticks the FSM at `decision_interval` (0.05 s ≈ 20 Hz), and applies control outputs (`_apply_input`) once per physics frame (≈60 Hz). State scripts compute decisions only; they never apply inputs themselves.
- **GameManager** (`scripts/game_manager.gd`): Autoload. Player data, score, lives. Uses `GameStateMachine`.

## World layout (M6)

- `Terrain.RUNWAY_START = 5300.0`, `Terrain.RUNWAY_END = 5800.0` (player runway, exactly `BASE_Y` across the span — physics contract, D5).
- `Main.PLAYER_SPAWN_X = 5330.0`, `Main.HOME_BASE = Vector2(5300, 650)` (minimap home marker follows the runway).
- `Main.possible_bases = [2400, 8000, 10500, 13000, 15500]` — 1 base west of the player (`faces_left = false`, rightward launch), 4 east (`faces_left = true`, `spawn_rot = PI`, leftward launch).
- `Main.MIN_ENEMY_DISTANCE = 2458.0` (wrap-aware; every base pair clears it — asserted by `tools/verify_base_layout.gd`).
- Inverted east-side enemies come for free: `biplane.respawn()` derives `is_barrel_rolled = absf(spawn_rot) > PI/2` from the homebase `spawn_rotation`; the initial spawn path explicitly sets `enemy.rotation`, `enemy_avatar.is_barrel_rolled`, `reset_visual_transform`, and `EnemyAI.pilots[0].desired_heading` to match so the first death doesn't visually flip.

## FSM Contract (state_machine.gd)

- Owners call `initialize(start_key: StringName)` **explicitly** after references are set — the base class auto-registers `State` children in `_ready` (key = `child.name.to_snake_case()`), so hand-written `states_map` literals are gone.
- `self_driven: bool` — `true` means the FSM ticks itself in `_physics_process`; the AI FSM sets it to `false` (the controller ticks it via `tick(delta)`).
- Public API: `tick(delta)`, `transition_to(key)`, `is_active()`, `set_active(value)`, `current_key`, `previous_key`. The internal `_active` flag is **off-limits** to external code (use `is_active()`).
- `_change_state(key)` is idempotent (no-op if `key == current_key`) and calls `push_warning` + aborts on an unknown key. `previous_key` is recorded by the base class (replaces any hand-tracked previous state).
- State scripts expose reserved extension hooks `handle_input(event)` and `_on_animation_finished(anim)` (currently unused — do not drive behavior from them).

## Debug Pointers

- `Biplane._draw_debug_lines()` / `_draw_ai_debug_lines()`: drawn only in debug builds (`OS.is_debug_build()`); show flight state, velocity/thrust vectors, heading, throttle bar, and AI target line.
- In-editor: Run → "Debug with External Editor" or launch a debug build to see the overlay.

## Physics Flow

1. `_integrate_forces()` builds `Aerodynamics.FlightInput` from avatar + physics state
2. `Aerodynamics.calculate_forces()` computes all forces (weight, thrust, lift, drag, ground normal, friction)
3. Forces applied via `state.set_linear_velocity()`
4. Ground penetration clamp applied via `state.set_transform()`
5. Flight state transitions handled by `_update_flight_state()`
6. Crash/destroyed: gravity-only fall via `_integrate_crash_forces()`

## Key Patterns

- `AvatarData.is_airborne`: set in `_integrate_forces`; `true` when not grounded
- `AvatarData.damage_state`: drives particle effects via `EffectManager.spawn_damage_effects()`
- Landing impact: `Aerodynamics.classify_landing_impact()` returns CLEAN/HARD/CRASH
- Stall check: `Aerodynamics.is_stalled()` static method

## Debug Commands

make run    # launch game
godot --help|--version
