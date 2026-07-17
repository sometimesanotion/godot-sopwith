Essential knowledge for maintaining and extending this Godot 4.6.2 Sopwith recreation.  Covers architecture, core systems, debug patterns, and critical constants for contributors.

## Agent conventions

Use `@extract <a natural language query for what you're looking for>` as a first resort for reading local files.

## Project Overview

Recreation of classic Sopwith in Godot 4.6.2 (GDScript). A 2D biplane combat game with physics-based flight, AI enemies, terrain, and objectives.

Key directories: scripts/, scenes/, scenes/particles/, shaders/

## Architecture

- **Biplane** (`scripts/biplane.gd` extends RigidBody2D): Core flight controller. Uses `Aerodynamics` static module for all physics calculations via `_integrate_forces()`. Flight state is an **enum + signal** on `AvatarData.flight_state` (written only via `AvatarData.set_flight_state()`, which no-ops on same-value and emits `flight_state_changed(from, to)`). There is **no flight node-FSM** — the `scripts/states/flight/` directory was deleted in M2.
- **Aerodynamics** (`scripts/aerodynamics.gd`): Pure static module. `calculate_forces(FlightInput) → FlightOutput`. Contains all NASA-derived lift/drag/thrust/stall formulas. No node references.
- **EffectManager** (`scripts/effect_manager.gd`): Autoload singleton. Spawns GPUParticles2D effects (smoke, fire, debris) at world positions. `spawn_damage_effects()` maps DamageState to particle combos.
- **FSM** (`state.gd` / `state_machine.gd`): Reusable base classes. Used by the **AI** FSM (`scripts/states/ai/`) and the **Game** FSM (`scripts/states/game/`). Flight states are NOT FSM-backed (see Biplane above).
- **EnemyAI** (`scripts/enemy_ai.gd`): FSM-driven dogfighting AI. The controller is the **sole driver** of `AIStateMachine`: it accumulates real elapsed time and ticks the FSM at `decision_interval` (0.05 s ≈ 20 Hz), and applies control outputs (`_apply_input`) once per physics frame (≈60 Hz). State scripts compute decisions only; they never apply inputs themselves.
- **GameManager** (`scripts/game_manager.gd`): Autoload. Player data, score, lives. Uses `GameStateMachine`.

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
