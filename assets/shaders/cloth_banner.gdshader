// Estandarte de pano (parte 5 da ambientação): balança com o vento (mais embaixo, preso em cima),
// dobras sombreadas, faixa e losango na cor do debrum e ponta em rabo de andorinha.
// Malha: PlaneMesh virado para Z com subdivisões (AmbienceDirector._apply_banners).
// Valores em ambience.json -> regions.<id>.banners.
shader_type spatial;
render_mode cull_disabled;

uniform vec4 cloth_color : source_color = vec4(0.54, 0.1, 0.13, 1.0);
uniform vec4 trim_color : source_color = vec4(0.79, 0.63, 0.29, 1.0);
uniform float height = 2.0;
uniform float sway = 0.14;
uniform float speed = 1.2;
uniform float folds = 3.0;
uniform float glow = 0.12;

varying float drop;

void vertex() {
	drop = clamp((height * 0.5 - VERTEX.y) / height, 0.0, 1.0); // 0 no topo, 1 na ponta
	float t = TIME * speed + (MODEL_MATRIX[3].x + MODEL_MATRIX[3].z) * 0.7;
	VERTEX.z += sin(t + VERTEX.y * 1.6) * sway * drop + sin(VERTEX.x * folds * 6.2831) * 0.025;
	VERTEX.x += sin(t * 0.7 + VERTEX.y) * sway * 0.25 * drop;
}

void fragment() {
	// rabo de andorinha: corta um V no meio da ponta
	if (UV.y > 0.86 + 0.14 * abs(UV.x - 0.5) * 2.0) {
		discard;
	}
	float fold = 0.72 + 0.28 * sin(UV.x * folds * 6.2831);
	vec3 col = cloth_color.rgb * fold;
	float band = step(UV.y, 0.07) + step(abs(UV.x - 0.5), 0.5) * step(0.47, abs(UV.x - 0.5));
	float diamond = step(abs(UV.x - 0.5) + abs(UV.y - 0.42) * 0.6, 0.16) - step(abs(UV.x - 0.5) + abs(UV.y - 0.42) * 0.6, 0.11);
	float trim = clamp(band + diamond, 0.0, 1.0);
	col = mix(col, trim_color.rgb * (0.8 + 0.2 * fold), trim);
	ALBEDO = col;
	ROUGHNESS = 0.92 - trim * 0.4;
	SPECULAR = 0.2 + trim * 0.3;
	EMISSION = cloth_color.rgb * glow * fold;
}
