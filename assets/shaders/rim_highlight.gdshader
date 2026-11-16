// Contorno (fresnel/rim) aditivo usado como material_overlay: destaca o alvo sob o mouse
// e dá leitura de silhueta ao personagem. Compatível com WebGL 2.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 rim_color : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float intensity = 1.2;
uniform float power = 2.5;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), power);
	ALBEDO = rim_color.rgb * intensity * fresnel;
}
