class_name PortalView
extends Node3D
## Portal entre regiões (só visual; a passagem é decidida pelo servidor quando o
## jogador entra no raio). Anel de pedra em pé, véu girando, luz e o nome do destino.
## Montado em código a partir dos dados da região (portals).

const PORTAL_SHADER := preload("res://assets/shaders/portal_dither.gdshader")

var _veil: MeshInstance3D
var _light: OmniLight3D
var _t: float = 0.0


func setup(data: Dictionary, color: Color) -> void:
	position = Vector3(float(data["pos"][0]), 0.0, float(data["pos"][1]))
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.2, 0.19, 0.21)
	stone.roughness = 0.95
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.25
	torus.outer_radius = 1.6
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	ring.material_override = stone
	ring.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	ring.position = Vector3(0.0, 1.6, 0.0)
	add_child(ring)
	# véu: buracos em camadas com dithering (assets/shaders/portal_dither.gdshader, de Dither Portals, CC0)
	var cfg: Dictionary = GameConfig.get_value("vfx", "portal")
	var veil_mat := ShaderMaterial.new()
	veil_mat.shader = PORTAL_SHADER
	veil_mat.set_shader_parameter("color_one", Color(color.lightened(0.25), 1.0))
	var edge := GameConfig.color_of(cfg.get("edge"), Color.BLACK)
	veil_mat.set_shader_parameter("color_two", Color(edge, float(cfg.get("edge_alpha", 0.9))))
	veil_mat.set_shader_parameter("layers", int(cfg.get("layers", 10)))
	veil_mat.set_shader_parameter("depth_amount", float(cfg.get("depth", 0.9)))
	veil_mat.set_shader_parameter("radius", float(cfg.get("radius", 0.42)))
	veil_mat.set_shader_parameter("pixel_size", float(cfg.get("pixel_size", 6.0)))
	_veil = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 2.6)
	_veil.mesh = quad
	_veil.material_override = veil_mat
	_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_veil.position = Vector3(0.0, 1.6, 0.0)
	add_child(_veil)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 1.6
	_light.omni_range = 6.0
	_light.position = Vector3(0.0, 1.6, 0.6)
	add_child(_light)
	var label := Label3D.new()
	label.text = "→ " + str(data.get("label", ""))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.005
	label.font_size = 40
	label.outline_size = 12
	label.modulate = Color(0.92, 0.8, 0.55)
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.position = Vector3(0.0, 3.6, 0.0)
	add_child(label)


func _process(delta: float) -> void:
	_t += delta
	_veil.rotation.z = _t * 0.8
	_veil.scale = Vector3.ONE * (1.0 + sin(_t * 2.3) * 0.03)
	_light.light_energy = 1.4 + sin(_t * 3.1) * 0.35
