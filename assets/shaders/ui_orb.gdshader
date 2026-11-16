// Orbe de vida/mana: vidro escuro com líquido ondulante, moldura de metal e reflexo.
shader_type canvas_item;

#include "res://assets/shaders/include/noise.gdshaderinc"

uniform vec4 liquid : source_color = vec4(0.75, 0.08, 0.08, 1.0);
uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform vec4 metal : source_color = vec4(0.42, 0.35, 0.22, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float surface = 1.0 - fill * 2.0;
	float wave = sin(p.x * 6.0 + TIME * 2.0) * 0.035 + sin(p.x * 11.0 - TIME * 3.1) * 0.015;
	float inside = smoothstep(surface + wave - 0.01, surface + wave + 0.01, p.y) * step(0.001, fill);

	vec3 glass = vec3(0.03, 0.03, 0.04) + vec3(0.04) * (1.0 - r);
	float swirl = fbm(p * 2.2 + vec2(TIME * 0.15, -TIME * 0.25));
	float depth = clamp((p.y - surface) * 0.6, 0.0, 1.0);
	vec3 liq = liquid.rgb * (1.25 - depth * 0.7) * (0.75 + swirl * 0.5);
	liq += liquid.rgb * smoothstep(0.04, 0.0, abs(p.y - surface - wave)) * 0.9 * step(0.001, fill) * step(fill, 0.999);
	vec3 col = mix(glass, liq, inside);

	// reflexo do vidro
	float hl = smoothstep(0.45, 0.0, length(p - vec2(-0.32, -0.42)));
	col += vec3(0.9, 0.9, 1.0) * hl * 0.22;

	// moldura metálica
	float ring = smoothstep(0.84, 0.88, r);
	vec3 metal_col = metal.rgb * (0.7 + 0.6 * (0.5 - p.y * 0.5)) * (0.85 + 0.3 * value_noise(UV * 40.0));
	col = mix(col, metal_col, ring);
	col *= mix(1.0, 0.6, smoothstep(0.86, 0.9, r) * (1.0 - smoothstep(0.9, 0.97, r)));

	COLOR = vec4(col, 1.0 - smoothstep(0.97, 1.0, r));
}
