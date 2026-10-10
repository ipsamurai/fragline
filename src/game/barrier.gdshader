shader_type canvas_item;
// Spawn-door energy field: players walk through, shots don't.

uniform vec4 color : source_color = vec4(0.2, 0.9, 1.0, 1.0);
instance uniform float tiles = 4.0;

void fragment() {
	float y = UV.y * tiles;
	float scan = 0.5 + 0.5 * sin(y * 9.0 - TIME * 6.0);
	float d = abs(UV.x - 0.5);
	float core = smoothstep(0.1, 0.0, d);
	float body = smoothstep(0.5, 0.15, d);
	float flicker = 0.85 + 0.15 * sin(TIME * 23.0 + y);
	float hex = step(0.82, fract(y * 2.0 + UV.x * 1.5)) * 0.25;
	float a = ((0.22 + 0.25 * scan + hex) * body + 0.7 * core) * flicker;
	COLOR = vec4(mix(color.rgb, vec3(1.0), 0.3 * scan + 0.5 * core), clamp(a, 0.0, 0.9));
}
