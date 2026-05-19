Essential knowledge for maintaining and extending this Godot 4.6.2 Sopwith recreation.  Covers architecture, core systems, debug patterns, and critical constants for contributors.

## Project Overview

Recreation of classic Sopwith in Godot 4.6.2 (GDScript). A 2D biplane combat game with physics-based flight, AI enemies, terrain, and objectives.

Key directories: scripts/, scenes/, shaders/

## Core Architecture

- Main Node Tree:
- Main (Node2D) - game coordinator, camera, terrain, UI
- Main/Biplane (CharacterBody2D) - player-controlled aircraft, flight physics
- Main/EnemyBiplane - AI-controlled planes
- Main/Terrain - procedural ground
- Main/Background - sky gradient shader, mountains, clouds

## Critical Classes:

Class	File	Purpose
Biplane	biplane.gd	Flight physics, weapons, collision, avatars
AvatarData	biplane.gd (inner class)	Per-player state (lives, fuel, ammo, damage)
GameManager	game_manager.gd	Score, lives, game state
EnemyAI	enemy_ai.gd	AI flight behavior
Terrain	terrain.gd	Ground generation, runway detection

## Key Systems

- Avatar System:
- AvatarData stores per-player state; player ID 0 = human, 1+ = AI
- Access via biplane.get_avatar_data(player_id)
- destroyed_this_crash flag prevents double life loss per crash (NOTE: this is a kludge)

Flight Physics (biplane.gd):

- _apply_aerodynamics() - lift, drag, thrust calculation
- _check_ground_collision() - landing/crash detection with tilt tolerance
- _apply_ground_forces() - ground movement, tilt checks on ALL ground
- stall_speed_ms - stall threshold (21.4 / 2.2 m/s)
- pixels_per_meter: 10.0 - world scale

Camera (main.gd:_update_camera):

Uses speed_coeff (based on velocity vs stall speed) to scale look-ahead distance
On crash (flight_state == CRASHED), camera centers on player
Y-axis look-ahead when diving

## Collision Layers:

Layer 1: Ground/terrain
Layer 2: Player biplane, Enemy biplanes  
Layer 4: Bullets
Layer 8: Bombs

## Particle Systems (biplane.gd):

_init_particle_materials() - white/black smoke, fire materials (static)
_ensure_smoke(avatar, smoke_type, amount) - smoke_type: 1=white, 2=black
_ensure_fire(avatar, amount) - fire particles

Must set process_material after creating GPUParticles2D node

## Common Fix Patterns

Adding new crash trigger: Check avatar.flight_state != CRASHED before setting, emit crashed.emit(), guard with not avatar.destroyed_this_crash before calling GameManager.destroy_player().
Smoke/fire not showing: Ensure process_material is assigned after creating particle node.
Camera issues: All camera logic in _update_camera() - modify speed_coeff, look_ahead_dist, or lerp_rate.
Sky gradient: shaders/sky_gradient.gdshader + background.gd:_create_sky_gradient() - uses camera_y uniform to darken sky with altitude.

## Debug Commands

make run    # launch game
godot --help|--version

## Important Constants

max_landing_tilt_deg: 34.0 - max safe landing angle
stall_speed_ms: 21.4 / 2.2 - stall threshold
GROUND_Y: 800.0 - default ground level
MAX_ALTITUDE: 2000.0 - max playable altitude
RESPAWN_DELAY: 3.0 - seconds before respawn

## Respawn Flow

1. _on_biplane_crashed() → sets is_respawning = true
2. _respawn_biplane() → calls biplane._perform_teleport_landing()
3. avatar.reset() → resets state, sets destroyed_this_crash = false

When adding new avatar fields, add them to AvatarData class and reset in reset().