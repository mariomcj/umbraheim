// Fumaça/névoa 2D da tela de entrada (docs/design/PROPOSTA_AMBIENTACAO.md, seção 5): ruído fbm andando
// na horizontal, mais denso embaixo e sumindo para cima. Dois retângulos com velocidades opostas.
shader_type canvas_item;

#include "res://assets/shaders/include/noise.gdshaderinc"

uniform vec4 smoke_color : source_color = vec4(0.23, 0.19, 0.28, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 0.35;
uniform float scale = 3.0;
uniform float speed = 0.02;
uniform float seed = 0.0;
// fração da altura (de baixo para cima) em que a fumaça some
uniform float fade_top : hint_range(0.05, 1.0) = 0.9;

void fragment() {
	vec2 p = vec2(UV.x * scale * 1.8, UV.y * scale) + vec2(TIME * speed + seed * 7.3, seed * 3.1);
	vec2 warp = vec2(fbm(p * 0.7 + TIME * 0.03), fbm(p * 0.7 - TIME * 0.025 + 2.7));
	float n = fbm(p + warp * 1.3);
	float height = 1.0 - UV.y; // 0 embaixo, 1 em cima
	float v = smoothstep(0.35, 0.8, n) * (1.0 - smoothstep(0.0, fade_top, height));
	COLOR = vec4(smoke_color.rgb, v * alpha);
}
