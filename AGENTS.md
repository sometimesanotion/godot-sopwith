Essential knowledge for maintaining and extending this Godot 4.6.2 Sopwith recreation.  Covers architecture, core systems, debug patterns, and critical constants for contributors.

## Agent conventions

Use `@extract <a natural language query for what you're looking for>` as a first resort for reading local files.

## Project Overview

Recreation of classic Sopwith in Godot 4.6.2 (GDScript). A 2D biplane combat game with physics-based flight, AI enemies, terrain, and objectives.

Key directories: scripts/, scenes/, scenes/particles/, shaders/

## Architecture

- **Biplane** (`scripts/biplane.gd` extends RigidBody2D): Core flight controller. Uses `Aerodynamics` static module for all physics calculations via `_integrate_forces()`. FSM-driven (`FlightStateMachine`) for flight states.
- **Aerodynamics** (`scripts/aerodynamics.gd`): Pure static module. `calculate_forces(FlightInput) → FlightOutput`. Contains all NASA-derived lift/drag/thrust/stall formulas. No node references.
- **EffectManager** (`scripts/effect_manager.gd`): Autoload singleton. Spawns GPUParticles2D effects (smoke, fire, debris) at world positions. `spawn_damage_effects()` maps DamageState to particle combos.
- **FSM**: `state.gd` / `state_machine.gd` base classes. Flight states in `scripts/states/flight/`, AI states in `scripts/states/ai/`, game states in `scripts/states/game/`.
- **EnemyAI** (`scripts/enemy_ai.gd`): FSM-driven dogfighting AI. Uses `AIStateMachine` for state transitions.
- **GameManager** (`scripts/game_manager.gd`): Autoload. Player data, score, lives. Uses `GameStateMachine`.

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
