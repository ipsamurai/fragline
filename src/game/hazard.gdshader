shader_type canvas_item;
// Animated lava / energy-void surface. One quad per hazard run, so it's very cheap.

uniform vec4 color : source_color = vec4(1.0, 0.4, 0.1, 1.0);
instance uniform float tiles = 4.0;

void fragment() {
	float x = UV.x * tiles;
	float wave = sin(x * 2.6 + TIME * 2.2) * 0.035 + sin(x * 0.9 - TIME * 1.3) * 0.045;
	float top = 0.16 + wave;
	float body = smoothstep(top - 0.03, top + 0.01, UV.y);
	float crest = 1.0 - smoothstep(top, top + 0.3, UV.y);
	float ripple = sin(x * 7.0 + TIME * 3.0) * sin(UV.y * 22.0 - TIME * 2.4);
	vec3 c = mix(color.rgb * 0.45, color.rgb * 1.7, crest) + ripple * 0.06;
	COLOR = vec4(c, body);
}
