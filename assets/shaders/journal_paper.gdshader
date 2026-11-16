// Folha do diário: papel envelhecido procedural + grafite da textura de tinta.
// A tinta vem de uma SubViewport acumulativa (só o alfa importa: é a "quantidade de grafite").
// O grão do papel "segura" o grafite: o traço fica granulado, como lápis de verdade.
shader_type canvas_item;

#include "res://assets/shaders/include/noise.gdshaderinc"

uniform sampler2D ink_tex : filter_linear, repeat_disable;
uniform vec2 view_origin = vec2(0.0); // canto da área visível, em UV da folha
uniform vec2 view_size = vec2(1.0);   // tamanho da área visível, em UV da folha
uniform float paper_px = 1024.0;

uniform vec3 paper_light : source_color = vec3(0.86, 0.80, 0.66);
uniform vec3 paper_dark : source_color = vec3(0.64, 0.55, 0.40);
uniform vec3 graphite : source_color = vec3(0.16, 0.15, 0.15);
uniform float grain_strength : hint_range(0.0, 1.0) = 0.55;
uniform float ink_gain = 1.15;
uniform float vignette = 0.55;
uniform float edge_wear = 0.05;

void fragment() {
	vec2 puv = view_origin + UV * view_size;
	vec2 pp = puv * paper_px;

	// papel: manchas grandes, fibras, pintas de idade
	float stains = fbm(pp * 0.0045);
	float fibers = value_noise(vec2(pp.x * 0.55, pp.y * 0.04));
	vec3 paper = mix(paper_dark, paper_light, smoothstep(0.2, 0.8, stains));
	paper *= 0.94 + 0.06 * fibers;
	float spot = smoothstep(0.74, 0.82, fbm(pp * 0.012 + 5.0));
	paper = mix(paper, paper_dark * 0.75, spot * 0.3);

	// grafite granulado
	float ink = texture(ink_tex, puv).a * ink_gain;
	float tooth = value_noise(pp * 0.95) * 0.6 + value_noise(pp * 2.4 + 7.0) * 0.4;
	ink *= mix(1.0, smoothstep(0.1, 0.8, tooth) * 1.35, grain_strength);
	ink = clamp(ink, 0.0, 1.0);
	vec3 col = mix(paper, graphite, ink * 0.92);

	// vinheta e bordas gastas (relativas ao recorte mostrado)
	vec2 c = UV - 0.5;
	col *= 1.0 - dot(c, c) * vignette;
	vec2 e = min(UV, 1.0 - UV);
	float edge = min(e.x, e.y);
	float ragged = value_noise(UV * 38.0) * edge_wear * 0.35;
	col *= mix(0.72, 1.0, smoothstep(0.0, edge_wear, edge));
	float a = smoothstep(0.0, 0.006, edge - ragged);

	COLOR = vec4(col, a);
}
