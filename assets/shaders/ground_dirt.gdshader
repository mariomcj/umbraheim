// Chão de terra morta com manchas de musgo doentio — placeholder procedural.
shader_type spatial;

#include "res://assets/shaders/include/noise.gdshaderinc"

uniform vec3 dirt_dark : source_color = vec3(0.09, 0.085, 0.07);
uniform vec3 dirt_light : source_color = vec3(0.22, 0.19, 0.15);
uniform vec3 moss : source_color = vec3(0.13, 0.17, 0.08);
uniform float scale = 0.12;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.6;
uniform float bump = 0.0; // relevo pelo ruído (0 = liso); AmbienceDirector põe por região (ground.bump)
uniform float bump_scale = 0.6;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float base = fbm(world_pos.xz * scale);
	float detail = value_noise(world_pos.xz * 2.5);
	float moss_mask = smoothstep(0.52, 0.72, fbm(world_pos.xz * scale * 2.7 + 11.0));
	vec3 color = mix(dirt_dark, dirt_light, base * 0.8 + detail * 0.2);
	color = mix(color, moss, moss_mask * moss_amount);
	ALBEDO = color;
	if (bump > 0.0) { // o chão é plano: normal em espaço de mundo pelas diferenças do ruído
		vec2 q = world_pos.xz * bump_scale;
		float h0 = fbm(q);
		float hx = fbm(q + vec2(0.08, 0.0));
		float hz = fbm(q + vec2(0.0, 0.08));
		vec3 n = normalize(vec3((h0 - hx) * bump, 1.0, (h0 - hz) * bump));
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	}
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
