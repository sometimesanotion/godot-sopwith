shader_type canvas_item;

uniform vec4 color_sky_hi: source_color = vec4(0.05, 0.35, 0.7, 1.0);
uniform vec4 color_sky_lo: source_color = vec4(0.20, 0.50, 0.8, 1.0);
uniform float camera_y = 650.0;
uniform float ground_y = 800.0;
uniform float max_altitude = 2000.0;

void fragment() {
	float altitude = max(0.0, ground_y - camera_y);
	float altitude_factor = clamp(altitude / max_altitude, 0.0, 1.0);

	float t = UV.y;
	t = clamp(t, 0.0, 1.0);
	t = smoothstep(0.0, 1.0, t);

	vec4 sky_color = mix(color_sky_hi, color_sky_lo, t);

	float darken = altitude_factor;
	vec4 dark_blue = vec4(0.0, 0.15, 0.5, 1.0);
	sky_color = mix(sky_color, dark_blue, darken);

	COLOR = sky_color;
}