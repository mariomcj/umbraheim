// Círculo rúnico procedural (quad no chão — NÃO usar decal, ver GUIA_DE_ARTE).
// Base da "antecipação" das magias. Aditivo e emissivo: é fonte de cor no mundo escuro.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(0.62, 0.28, 1.0, 1.0);
uniform float intensity = 1.6;
uniform float spin_speed = 0.15;
uniform float pulse_speed = 2.0;
uniform int rune_count = 24;

const float TAU_C = 6.28318530718;

float ring(float r, float center, float width) {
	return 1.0 - smoothstep(0.0, width, abs(r - center));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float spin = TIME * spin_speed;

	float rings = ring(r, 0.94, 0.02) + ring(r, 0.80, 0.012) + ring(r, 0.42, 0.012);

	// marcas "rúnicas" entre os dois anéis externos, girando
	float seg = fract((a + spin) / TAU_C * float(rune_count));
	float band = step(0.83, r) * step(r, 0.91);
	float glyph = band * (1.0 - smoothstep(0.0, 0.12, abs(seg - 0.5)))
		* step(0.3, fract(seg * 3.7 + floor((a + spin) / TAU_C * float(rune_count)) * 0.37));

	// estrela de 6 pontas girando no sentido contrário
	float star = 0.0;
	for (int i = 0; i < 3; i++) {
		float ang = float(i) * TAU_C / 6.0 - spin * 0.6;
		vec2 d = vec2(cos(ang), sin(ang));
		float dist = abs(p.x * d.y - p.y * d.x);
		star += (1.0 - smoothstep(0.0, 0.01, dist)) * step(r, 0.8);
	}

	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed);
	float mask = clamp(rings + glyph + star * 0.55, 0.0, 1.0) * step(r, 1.0);
	float glow = exp(-abs(r - 0.94) * 18.0) * 0.25;

	ALBEDO = color.rgb * intensity * pulse;
	ALPHA = clamp(mask + glow, 0.0, 1.0);
}
