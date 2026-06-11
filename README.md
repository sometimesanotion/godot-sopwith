# Godot Sopwith

A modern vector-graphics tribute to the 1984 classic Sopwith, built with Godot 4.x using vector aesthetics and realistic physics.

## Controls

| Key | Action |
|-----|--------|
| , | Pitch Up |
| / | Pitch Down |
| X | Throttle Up |
| Z | Throttle Down |
| SPACE | Fire Machine Gun |
| B | Drop Bomb |
| . | Flip |
| P | Pause |

## Gameplay

The features of the original Sopwith, with touches of physics simulation.

- Fly a biplane through a large procedural world
- Destroy ground targets (buildings, fuel tanks hangars, tanks)
- Avoid stalling at low speeds - watch for the warning!
- Land on the runway to refuel and rearm
- You have 5 lives - don't crash!
- There's no autopilot.  Can you safely land at your airbase?

## Features

- Realistic vector aerodynamics with lift and drag
- Stall mechanic based on speed threshold
- Weapon systems: machine gun and bombs
- Enemy AI biplanes and ground targets with AA fire
- Screen shake on explosions
- Pause menu (press P)

## Test Run

To take it for a spin:
```bash
make clean
make run
```

## Building

To build the project:
```bash
godot --headless --export-release "Linux" build/linux/godot-sopwith.x86_64
```

## License

Original Sopwith is a classic.  This is a modern tribute under the LGPL v2.1.
