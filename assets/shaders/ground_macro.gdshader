// Chão com textura e quebra de repetição (docs/design/PROPOSTA_AMBIENTACAO.md, parte 5).
// Monta-se a partir do StandardMaterial3D da cena (AmbienceDirector._macro_material): mesma textura,
// mais uma segunda amostra girada misturada por ruído (anti-tiling), manchas grandes que escurecem
// e uma cor de mancha (terra, musgo, fuligem). Valores por região em ambience.json -> regions.<id>.ground.macro.
shader_type spatial;

#include "res://assets/shaders/include/noise.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(18.0, 18.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float roughness = 0.9;
uniform float specular = 0.3;
uniform float normal_scale = 0.8;
uniform float anti_tile = 0.6;     // 0 = só a amostra original
uniform float macro_scale = 0.045; // manchas grandes (ciclos por metro)
uniform float macro_dark = 0.3;    // quanto as manchas escurecem
uniform vec4 stain_color : source_color = vec4(0.2, 0.17, 0.13, 1.0);
uniform float stain_amount = 0.3;
uniform float desaturate = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale + uv_offset;
	// segunda amostra: escala e giro diferentes, para a grade da textura não alinhar
	vec2 uv2 = mat2(vec2(0.62, -0.78), vec2(0.78, 0.62)) * uv * 0.73 + vec2(0.37, 0.71);
	float blend = smoothstep(0.42, 0.58, value_noise(world_pos.xz * 0.16 + 3.1)) * anti_tile;
	vec3 col = mix(texture(albedo_tex, uv).rgb, texture(albedo_tex, uv2).rgb, blend) * albedo_color.rgb;
	float macro = fbm(world_pos.xz * macro_scale);
	col *= mix(1.0 - macro_dark, 1.0, smoothstep(0.25, 0.7, macro));
	float stain = smoothstep(0.55, 0.8, value_noise(world_pos.xz * macro_scale * 2.7 + 7.0) * 0.6 + macro * 0.4);
	col = mix(col, stain_color.rgb * (0.6 + 0.4 * macro), stain * stain_amount);
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(col, vec3(luma), desaturate);
	ROUGHNESS = roughness;
	SPECULAR = specular;
	if (use_normal) {
		NORMAL_MAP = mix(texture(normal_tex, uv).rgb, texture(normal_tex, uv2).rgb, blend);
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
