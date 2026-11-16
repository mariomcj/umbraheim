// Partícula aditiva com textura (pacote de partículas da Kenney, CC0), sempre de frente para a câmera.
// A forma vem da textura (alfa x brilho); a cor vem da partícula (COLOR). Sem textura = disco macio,
// igual a particle_soft.gdshader.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float intensity = 2.0;
uniform sampler2D shape : source_color, filter_linear_mipmap;
uniform bool has_shape = false;
// gira a forma com o tempo (faíscas, estrelas); 0 = parada
uniform float spin = 0.0;

varying float start_angle;

void vertex() {
	start_angle = INSTANCE_CUSTOM.x;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float a;
	if (has_shape) {
		vec2 uv = UV - 0.5;
		float ang = spin * TIME + start_angle;
		uv = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * uv + 0.5;
		vec4 t = texture(shape, uv);
		a = t.a * max(t.r, max(t.g, t.b));
	} else {
		float d = length(UV - 0.5) * 2.0;
		a = 1.0 - smoothstep(0.0, 1.0, d);
		a *= a;
	}
	ALBEDO = COLOR.rgb * intensity;
	ALPHA = a * COLOR.a;
}
