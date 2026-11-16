extends Node3D
## Vitrine da biblioteca de assets (só para conferir o visual; não faz parte do jogo).
## Monta tudo por código a partir das pastas, então assets novos aparecem sozinhos:
## - uma fileira de esferas e cubos por pasta de textura (albedo + normal + rugosidade);
## - os shaders mágicos de assets/vfx/shaders, cada um num objeto, com cores do tema;
## - partículas com as imagens do Kenney; o céu com uma HDRI noturna;
## - uma fileira de amostras por kit de modelos (assets/models/<categoria>/<kit>) e o manequim com as animações principais.
## Rodar: godot --path . res://scenes/dev/asset_showcase.tscn  (ou --screenshot=... --screenshot-frames=N)
## --focus=models enquadra só os modelos; --focus=<parte do nome do kit> (ex.: fantasy_races) chega perto de um kit.

const TEXTURE_DIR := "res://assets/textures/"
const SHADER_DIR := "res://assets/vfx/shaders/"
const HDRI := "res://assets/hdri/moonless_golf_1k.hdr"
const PARTICLES := "res://assets/vfx/particles/kenney_particle_pack/"
const MODEL_DIR := "res://assets/models/"
const ANIM_GLB := "res://assets/models/characters/animations/UAL1_Standard.glb"
const ANIM_GLB_2 := "res://assets/models/characters/animations/UAL2_Standard.glb"
const SHOW_ANIMS: Array[String] = ["idle", "walk", "run", "attack", "attack_2", "cast", "hit", "death"]
const MODELS_PER_KIT := 10
const MODEL_SIZE := 1.8

## Parâmetros de demonstração por shader (o resto fica no padrão do autor).
const SHADER_PARAMS := {
	"aura_3d": {"_ColorAura": Color(0.6, 0.1, 1.0), "_ColorRim": Color(1.0, 0.3, 0.6)},
	"cartoon_3d_fire": {"color_outer": Color(0.45, 0.05, 0.6, 0.7), "color_inner": Color(1.2, 0.5, 1.4, 0.0)},
	"colored_fresnel_shader": {},
	"dither_portals": {"color_one": Color(0.7, 0.2, 1.0), "color_two": Color(0.05, 0.0, 0.08)},
	"enhanced_dissolve_ragdoll_alternative_tutorial": {"t": 0.45, "color_edge": Color(0.8, 0.2, 1.0)},
	"fire_and_electric_shader": {"fire_color": Color(0.6, 0.15, 1.0)},
	"glowing_shield_beam_buble_dark_magic_fresnel": {"color": Color(0.15, 0.0, 0.2), "glow_color": Color(0.7, 0.2, 1.0), "dist": 1.0, "speed": 1.0, "glow_intensity": 3.0, "glow_amount": 2.0, "pos_mult": 1.0},
	"godot_4_vertical_dissolve_shader": {"offset": 0.45, "base_color": Color(0.3, 0.3, 0.35), "borderColor": Color(0.8, 0.2, 1.0)},
	"pixelated_portal": {},
	"pulse_aura_for_3d_character": {"aura_color": Color(1.4, 0.3, 2.0, 0.12)},
}

var shader_errors: PackedStringArray = []
var _shot_path: String = ""
var _shot_frames: int = 0
var _focus: String = ""
var model_errors: PackedStringArray = []
var _row_z: Dictionary = {}


func _ready() -> void:
	# a cena roda sozinha (sem o main.gd), então trata ela mesma o --screenshot
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--screenshot="):
			_shot_path = arg.trim_prefix("--screenshot=")
			_shot_frames = 180
		elif arg.begins_with("--screenshot-frames="):
			_shot_frames = arg.trim_prefix("--screenshot-frames=").to_int()
		elif arg.begins_with("--focus="):
			_focus = arg.trim_prefix("--focus=")
	_environment()
	var noise := _noise()
	var z := 0.0
	for folder in _subdirs(TEXTURE_DIR):
		if folder == "misc":
			continue
		var x := 0.0
		_label(Vector3(-2.2, 0.4, z), folder.to_upper(), 64)
		for asset in _subdirs(TEXTURE_DIR + folder):
			_material_swatch(TEXTURE_DIR + folder + "/" + asset + "/", asset, Vector3(x, 0.0, z))
			x += 2.2
		z += 2.8
	var sx := 0.0
	_label(Vector3(-2.2, 0.4, z), "SHADERS", 64)
	for file in DirAccess.get_files_at(SHADER_DIR):
		if file.ends_with(".gdshader"):
			_shader_demo(file.get_basename(), Vector3(sx, 0.0, z), noise)
			sx += 2.4
	z += 3.0
	_particles(Vector3(0.0, 0.0, z))
	z += 3.2
	var models_z0 := z
	var kits := 0
	for cat in _subdirs(MODEL_DIR):
		for kit in _subdirs(MODEL_DIR + cat):
			if kit == "animations":
				continue
			if _model_row(MODEL_DIR + cat + "/" + kit + "/", cat + "/" + kit, z):
				_row_z[kit] = z
				z += 3.0
				kits += 1
	if _anim_row(z):
		z += 3.0
	var cam := Camera3D.new()
	add_child(cam)
	var focus_kit := ""
	for kit: String in _row_z:
		if _focus != "" and _focus != "models" and kit.contains(_focus):
			focus_kit = kit
	if focus_kit != "":
		var rz: float = _row_z[focus_kit]
		cam.position = Vector3(4.8, 1.6, rz + 6.0)
		cam.look_at(Vector3(4.8, 0.3, rz))
	elif _focus == "models":
		cam.position = Vector3(10.5, 7.5, z + 3.5)
		cam.look_at(Vector3(10.5, 0.0, models_z0 + (z - models_z0) * 0.45))
	else:
		cam.position = Vector3(10.0, 13.0, z + 7.0)
		cam.look_at(Vector3(10.0, 0.0, z * 0.5))
	cam.fov = 58.0
	print("[vitrine] %d kits de modelos, shaders: %s" % [kits, ", ".join(SHADER_PARAMS.keys())])


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = load(HDRI)
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 2.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.008
	env.fog_light_color = Color(0.1, 0.08, 0.14)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation = Vector3(-0.9, 0.6, 0.0)
	moon.light_color = Color(0.75, 0.75, 0.95)
	moon.light_energy = 1.1
	moon.shadow_enabled = true
	add_child(moon)
	var torch := OmniLight3D.new()
	torch.position = Vector3(6.0, 3.0, 4.0)
	torch.light_color = Color(1.0, 0.55, 0.25)
	torch.light_energy = 3.0
	torch.omni_range = 14.0
	add_child(torch)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	ground.position = Vector3(10.0, -0.75, 6.0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.05, 0.05, 0.06)
	ground.material_override = gm
	add_child(ground)


func _material_swatch(dir: String, asset: String, pos: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".import"):
			continue
		if f.contains("_albedo."):
			mat.albedo_texture = load(dir + f)
		elif f.contains("_normal."):
			mat.normal_enabled = true
			mat.normal_texture = load(dir + f)
		elif f.contains("_roughness."):
			mat.roughness_texture = load(dir + f)
	mat.uv1_scale = Vector3(1.5, 1.5, 1.5)
	var mi := MeshInstance3D.new()
	var mesh: PrimitiveMesh = SphereMesh.new() if int(pos.x / 2.2) % 2 == 0 else BoxMesh.new()
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = Vector3(1.3, 1.3, 1.3)
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	_label(pos + Vector3(0, 1.1, 0), asset, 28)


func _shader_demo(name: String, pos: Vector3, noise: NoiseTexture2D) -> void:
	var shader: Shader = load(SHADER_DIR + name + ".gdshader")
	if shader == null:
		shader_errors.append(name)
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for u: Dictionary in shader.get_shader_uniform_list():
		if int(u["type"]) == TYPE_OBJECT: # texturas: ruído (o retrato do portal usa a mesma)
			mat.set_shader_parameter(u["name"], noise)
	for k: String in SHADER_PARAMS.get(name, {}):
		mat.set_shader_parameter(k, SHADER_PARAMS[name][k])
	var mi := MeshInstance3D.new()
	var portal := name.contains("portal")
	if portal:
		var q := QuadMesh.new()
		q.size = Vector2(1.8, 1.8)
		mi.mesh = q
	elif name.contains("fire"):
		var c := CylinderMesh.new()
		c.top_radius = 0.1
		c.bottom_radius = 0.5
		c.height = 1.6
		mi.mesh = c
	else:
		var s := SphereMesh.new()
		mi.mesh = s
	mi.material_override = mat
	mi.position = pos + (Vector3(0, 0.3, 0) if portal else Vector3.ZERO)
	add_child(mi)
	_label(pos + Vector3(0, 1.3, 0), name.left(28), 26)


func _particles(pos: Vector3) -> void:
	var i := 0
	for img in ["flame_02.png", "magic_03.png", "smoke_05.png", "spark_04.png", "star_06.png", "twirl_02.png"]:
		var tex := load(PARTICLES + img) as Texture2D
		if tex == null:
			continue
		var p := CPUParticles3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.6, 0.6)
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.albedo_color = [Color(1.0, 0.5, 0.2), Color(0.7, 0.3, 1.0), Color(0.4, 0.4, 0.45), Color(1.0, 0.8, 0.4), Color(0.6, 0.8, 1.0), Color(0.8, 0.2, 1.0)][i]
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		quad.material = m
		p.mesh = quad
		p.amount = 24
		p.lifetime = 1.4
		p.direction = Vector3.UP
		p.spread = 20.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.4
		p.gravity = Vector3(0, 0.3, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.3
		p.position = pos + Vector3(i * 2.4, -0.4, 0)
		add_child(p)
		_label(p.position + Vector3(0, 2.0, 0), img.get_basename(), 26)
		i += 1


## Amostra de até MODELS_PER_KIT modelos do kit, espalhados pela lista, cada um reduzido para caber em MODEL_SIZE.
func _model_row(dir: String, title: String, z: float) -> bool:
	var files: PackedStringArray = []
	_model_files(dir, files)
	if files.is_empty():
		return false
	files.sort()
	_label(Vector3(-2.2, 0.4, z), title.get_file().to_upper() + " (%d)" % files.size(), 40)
	var n := mini(MODELS_PER_KIT, files.size())
	for i in n:
		var path := files[int(float(i) * files.size() / n)]
		var node := _instance(path)
		if node == null:
			continue
		_fit(node, Vector3(i * 2.4, -0.75, z))
		_label(Vector3(i * 2.4, 1.35, z), path.get_file().get_basename().left(22), 22)
		_animate_if_humanoid(node, SHOW_ANIMS[i % SHOW_ANIMS.size()])
	return true


var _ual_library: AnimationLibrary = null


## Personagens com o esqueleto de 65 ossos da Quaternius recebem a biblioteca de animações (mesmos nomes de ossos).
func _animate_if_humanoid(node: Node3D, anim: String) -> void:
	if not node.find_children("*", "AnimationPlayer", true, false).is_empty():
		return
	var skels := node.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty() or (skels[0] as Skeleton3D).get_bone_count() != 65:
		return
	if _ual_library == null:
		var src := _instance(ANIM_GLB)
		if src == null:
			return
		var src_ap := src.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		_ual_library = src_ap.get_animation_library(&"")
		src.queue_free()
	var ap := AnimationPlayer.new()
	node.add_child(ap)
	ap.add_animation_library(&"", _ual_library)
	if not ap.has_animation(anim):
		anim = "idle"
	ap.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
	ap.play(anim)
	_label(node.position + Vector3(0, 2.0, 0), anim, 26)


## Manequim da Universal Animation Library tocando cada animação principal, lado a lado.
func _anim_row(z: float) -> bool:
	if not ResourceLoader.exists(ANIM_GLB):
		return false
	_label(Vector3(-2.2, 0.4, z), "ANIMAÇÕES", 40)
	var x := 0.0
	for anim in SHOW_ANIMS:
		var path := ANIM_GLB if anim != "attack_2" else ANIM_GLB_2
		var node := _instance(path)
		if node == null:
			continue
		node.position = Vector3(x, -0.75, z)
		var players := node.find_children("*", "AnimationPlayer", true, false)
		if players.is_empty() or not (players[0] as AnimationPlayer).has_animation(anim):
			model_errors.append("%s sem animação %s" % [path.get_file(), anim])
		else:
			var ap := players[0] as AnimationPlayer
			ap.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
			ap.play(anim)
		_label(Vector3(x, 2.2, z), anim, 30)
		x += 2.4
	return true


func _instance(path: String) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		model_errors.append(path.get_file())
		return null
	var node := scene.instantiate() as Node3D
	add_child(node)
	return node


## Escala o modelo para o maior lado caber em MODEL_SIZE e apoia a base no chão em `pos`.
func _fit(node: Node3D, pos: Vector3) -> void:
	var box := AABB()
	var first := true
	var inv := node.global_transform.affine_inverse()
	for vi: VisualInstance3D in node.find_children("*", "VisualInstance3D", true, false):
		var b := inv * vi.global_transform * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var size := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var k := MODEL_SIZE / size if size > 0.001 else 1.0
	node.scale = Vector3.ONE * k
	node.position = pos - Vector3(box.get_center().x, box.position.y, box.get_center().z) * k


static func _model_files(dir: String, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gltf") or f.ends_with(".glb"):
			out.append(dir + f)
	for d in DirAccess.get_directories_at(dir):
		_model_files(dir + d + "/", out)


func _label(pos: Vector3, text: String, font_size: int) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 8
	l.modulate = Color(0.95, 0.85, 0.6)
	l.position = pos
	add_child(l)


func _noise() -> NoiseTexture2D:
	var n := NoiseTexture2D.new()
	n.width = 256
	n.height = 256
	n.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	n.noise = fn
	return n


static func _subdirs(path: String) -> PackedStringArray:
	var out := DirAccess.get_directories_at(path)
	out.sort()
	return out


func _process(_delta: float) -> void:
	if _shot_path == "":
		return
	_shot_frames -= 1
	if _shot_frames > 0:
		return
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(_shot_path)
	print("[vitrine] captura %s -> %s | FPS %d | shaders com erro: %s | modelos com erro: %s" % [error_string(err), _shot_path, Engine.get_frames_per_second(), shader_errors, model_errors])
	_shot_path = ""
	get_tree().quit()
