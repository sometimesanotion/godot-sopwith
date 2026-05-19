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
- _on_avatar_crashed() in biplane.gd centralises all per-crash logic (lives, signal) with idempotent _crash_processed guard (replaces old destroyed_this_crash kludge)

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

## Debug Commands

make run    # launch game
godot --help|--version
