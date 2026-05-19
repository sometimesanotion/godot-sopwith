shader_type canvas_item;

uniform vec4 color_sky_hi: source_color = vec4(0.05, 0.30, 0.6, 1.0);
uniform vec4 color_sky_lo: source_color = vec4(0.20, 0.50, 0.8, 1.0);
uniform float camera_y = 650.0;
uniform float min_altitude = 400.0;
uniform float max_altitude = 2000.0;

void fragment() {
	float altitude_factor = clamp((camera_y - min_altitude) / (max_altitude - min_altitude), 0.0, 1.0);

	float t = UV.y;
	t = clamp(t, 0.0, 1.0);
	t = smoothstep(0.0, 1.0, t);

	vec4 sky_low_alt = color_sky_lo;
	vec4 sky_high_alt = color_sky_hi;
	vec4 dark_blue = vec4(0.0, 0.05, 0.2, 1.0);

	vec4 base_color = mix(sky_high_alt, sky_low_alt, t);
	base_color = mix(base_color, dark_blue, altitude_factor * (1.0 - t));

	COLOR = base_color;
}