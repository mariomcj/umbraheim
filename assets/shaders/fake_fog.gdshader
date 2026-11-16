// Névoa "falsa" em camadas: plano translúcido com ruído animado.
// Substitui a névoa volumétrica (indisponível no renderer Compatibility / WebGL 2).
// Use 2–4 planos empilhados em alturas diferentes, cada um com layer_seed próprio.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://assets/shaders/include/noise.gdshaderinc"

uniform vec4 fog_color : source_color = vec4(0.42, 0.47, 0.45, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.35;
uniform float noise_scale = 0.07;
uniform vec2 wind = vec2(0.035, 0.015);
uniform float coverage : hint_range(0.0, 1.0) = 0.45;
uniform float edge_fade : hint_range(0.01, 1.0) = 0.3;
uniform float layer_seed = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * noise_scale + vec2(layer_seed * 13.7, layer_seed * 5.3);
	vec2 warp = vec2(fbm(p * 0.6 + TIME * 0.02), fbm(p * 0.6 - TIME * 0.015 + 3.1));
	float n = fbm(p + warp * 1.5 + wind * TIME);
	float mask = smoothstep(coverage, 1.0, n + 0.25);

	vec2 centered = abs(UV - 0.5) * 2.0;
	float edge = 1.0 - smoothstep(1.0 - edge_fade, 1.0, max(centered.x, centered.y));

	ALBEDO = fog_color.rgb;
	ALPHA = clamp(mask * density * edge, 0.0, 1.0);
}
