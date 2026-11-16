// Dissolução de cima para baixo com borda brilhante, na altura do mundo (morte de monstros e jogadores).
// Adaptado de "Godot 4+ 3D Vertical Dissolve Shader" (jamscars, godotshaders.com, CC0; original em
// assets/vfx/shaders/godot_4_vertical_dissolve_shader.gdshader). Mudanças: a altura é a do mundo
// (base_y..top_y, para servir em modelos de qualquer escala e com pele), material opaco com discard
// (sem ordenação de transparência) e a cor/textura vêm do material original da superfície.
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool has_texture = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D noise_texture;
uniform float offset = 0.0; // 0 = inteiro, 1 = sumiu
uniform float base_y = 0.0;
uniform float top_y = 2.0;
uniform vec4 border_color : source_color = vec4(0.7, 0.3, 1.0, 1.0);
uniform float border_height = 0.08;
uniform float wave_amplitude = 0.03;
uniform float wave_frequency = 3.0;
uniform float emission_intensity = 3.0;
uniform float noise_speed = 0.1;
uniform float noise_influence = 0.12;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 color = base_color;
	if (has_texture) {
		color *= texture(albedo_texture, UV);
	}
	vec2 noise_uv = world_pos.xz * 0.6;
	noise_uv.y -= TIME * noise_speed;
	float noise = texture(noise_texture, noise_uv).r;
	// 1 no topo, 0 na base: some primeiro em cima
	float height = clamp((world_pos.y - base_y) / max(0.01, top_y - base_y), 0.0, 1.0);
	float wave = (sin(world_pos.x * wave_frequency) + sin(world_pos.z * wave_frequency * 1.7)) * wave_amplitude;
	float edge = 1.0 - height + wave + (noise - 0.5) * noise_influence;
	float distance = (offset >= 1.0) ? -1.0 : edge - offset;
	if (distance < 0.0) {
		discard;
	}
	float border = 1.0 - smoothstep(0.0, border_height, distance);
	if (offset <= 0.0) {
		border = 0.0;
	}
	ALBEDO = mix(color.rgb, border_color.rgb, border);
	EMISSION = border_color.rgb * border * emission_intensity;
}
