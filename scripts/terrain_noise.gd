## terrain_noise.gd
## Shared static noise infrastructure for terrain and parallax scenery.
## Pure functions only — no node references (same pattern as aerodynamics.gd).
class_name TerrainNoise

const _SEED_MASK := 0x7FFFFFFF

## One factory for every FastNoiseLite in the project.
static func make_noise(seed_value: int, frequency: float,
		octaves: int = 4, gain: float = 0.5) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.seed = seed_value
	n.frequency = frequency
	n.fractal_octaves = octaves
	n.fractal_gain = gain
	return n

## Periodic 1D sampling: walk a circle in 2D noise space.  radius = period/TAU
## preserves linear wavelength, so existing frequency tunings carry over, and
## the loop is C∞-continuous — no height OR slope seam at the wrap boundary.
static func sample_periodic(noise: FastNoiseLite, x: float, period: float,
		circle_offset: Vector2 = Vector2(7919.31, 3133.73)) -> float:
	var angle := TAU * fposmod(x, period) / period
	var radius := period / TAU
	return noise.get_noise_2d(
		circle_offset.x + cos(angle) * radius,
		circle_offset.y + sin(angle) * radius)

## Deterministic per-purpose seed splitting: one world seed, uncorrelated layers.
static func derive_seed(base_seed: int, salt: int) -> int:
	return (base_seed + salt * 747796405) & _SEED_MASK

static func smoothstep01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
