// Gelo dos blocos e espinhos da Geleira (parte 5 da ambientação): miolo escuro com veios de ruído,
// rachaduras finas, brilho interno fraco e recorte (fresnel) azul na silhueta. Sem texturas, WebGL 2.
// Valores em ambience.json -> materials.ice (aplicados por RegionScenery no cliente).
shader_type spatial;

#include "res://assets/shaders/include/noise.gdshaderinc"

uniform vec4 ice_color : source_color = vec4(0.42, 0.58, 0.74, 1.0);
uniform vec4 deep_color : source_color = vec4(0.1, 0.18, 0.32, 1.0);
uniform vec4 rim_color : source_color = vec4(0.55, 0.82, 1.0, 1.0);
uniform float rim_power = 3.0;
uniform float rim_strength = 0.55;
uniform float glow = 0.3;
uniform float vein_scale = 1.4;
uniform float crack_amount = 0.5;
uniform float ice_roughness = 0.18;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 p = world_pos * vein_scale;
	float veins = fbm(p.xz + p.y * 0.6);
	float crack_n = value_noise(vec2(p.x + p.z, p.y) * 2.3);
	float cracks = (1.0 - smoothstep(0.0, 0.04, abs(crack_n - 0.5))) * crack_amount;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	vec3 col = mix(deep_color.rgb, ice_color.rgb, veins);
	ALBEDO = col + vec3(cracks * 0.25);
	ROUGHNESS = ice_roughness + cracks * 0.5;
	SPECULAR = 0.65;
	EMISSION = deep_color.rgb * glow * (0.5 + veins) + rim_color.rgb * fres * rim_strength;
}
