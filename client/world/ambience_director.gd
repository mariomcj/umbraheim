class_name AmbienceDirector
extends Node
## Clima de cada região (data/config/ambience.json), aplicado por cima da cena quando a região carrega:
## Environment (ambiente, névoa, céu, glow, tonemap, ajustes), sol, luz de preenchimento sem sombra,
## camadas de névoa falsa, cor do chão, vinheta e partículas de ambiente que seguem o personagem.
## Perfis de qualidade: médio na Web, alto no desktop.
## As cenas guardam a geometria; região sem entrada em ambience.json fica como a cena define.

const TONEMAPS := {
	"linear": Environment.TONE_MAPPER_LINEAR, "reinhard": Environment.TONE_MAPPER_REINHARDT,
	"filmic": Environment.TONE_MAPPER_FILMIC, "aces": Environment.TONE_MAPPER_ACES, "agx": Environment.TONE_MAPPER_AGX,
}

const PARTICLE_SHADER := preload("res://assets/shaders/particle_tex.gdshader")
const PARTICLE_MIX_SHADER := preload("res://assets/shaders/particle_tex_mix.gdshader")
const GROUND_MACRO_SHADER := preload("res://assets/shaders/ground_macro.gdshader")
const BANNER_SHADER := preload("res://assets/shaders/cloth_banner.gdshader")
const RIM_SHADER := preload("res://assets/shaders/rim_highlight.gdshader")

## Contorno sutil de personagens e monstros na cor de assinatura da região (ambience.json ->
## regions.<id>.rim). Um material só, compartilhado: trocar de região muda todos de uma vez.
## Nulo no perfil sem contorno (character_rim = false).
static var character_rim: ShaderMaterial
const SHAPES_DIR := "res://assets/vfx/particles/kenney_particle_pack/"

var profile_name := ""
## Quem as partículas seguem (o próprio personagem); sem alvo, ficam onde nasceram.
var follow: Node3D
var _emitters: Array = [] # [CPUParticles3D, altura acima do alvo, já posto junto do alvo]
var _vignette: TextureRect
var _fill: DirectionalLight3D


func _ready() -> void:
	var cfg := GameConfig.section("ambience")
	profile_name = str(cfg.get("default_profile_web" if OS.has_feature("web") else "default_profile_desktop", "medio"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ambience-profile="): # debug: comparar perfis
			profile_name = arg.trim_prefix("--ambience-profile=")
	var layer := CanvasLayer.new()
	layer.layer = 1 # acima do mundo, abaixo do HUD (5) e da tela de entrada (30)
	add_child(layer)
	_vignette = TextureRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.visible = false
	layer.add_child(_vignette)


func profile() -> Dictionary:
	return (GameConfig.get_value("ambience", "profiles") as Dictionary).get(profile_name, {})


## Aplica o clima da região à cena recém-carregada (nó "World").
func apply(world: Node, region_id: String) -> void:
	var regions: Dictionary = GameConfig.get_value("ambience", "regions")
	var prof := profile()
	get_viewport().msaa_3d = int(prof.get("msaa_3d", 1)) as Viewport.MSAA
	var we := world.find_child("WorldEnvironment", false, false) as WorldEnvironment
	var moon := world.find_child("Moon", false, false) as DirectionalLight3D
	if moon != null:
		moon.directional_shadow_max_distance = float(prof.get("shadow_max_distance", moon.directional_shadow_max_distance))
	if not regions.has(region_id):
		_vignette.visible = false
		return
	var r: Dictionary = regions[region_id]
	if we != null and we.environment != null:
		we.environment = we.environment.duplicate() # a cena pode ser reaberta: não altera o recurso salvo
		_apply_environment(we.environment, r, prof)
	if moon != null and r.has("sun"):
		var sun: Dictionary = r["sun"]
		moon.light_color = _col(sun.get("color"), moon.light_color)
		moon.light_energy = float(sun.get("energy", moon.light_energy))
		moon.rotation = Vector3(deg_to_rad(-float(sun.get("elevation", 40.0))), deg_to_rad(float(sun.get("azimuth", 0.0))), 0.0)
	if r.has("fill") and moon != null:
		var fill: Dictionary = r["fill"]
		_fill = DirectionalLight3D.new()
		_fill.name = "AmbienceFill"
		_fill.shadow_enabled = false
		_fill.light_color = _col(fill.get("color"), Color.WHITE)
		_fill.light_energy = float(fill.get("energy", 0.2))
		_fill.light_specular = 0.0 # só preenche: sem brilho especular
		# oposta ao sol: mesmo ângulo de elevação, azimute + 180°
		_fill.rotation = Vector3(moon.rotation.x, moon.rotation.y + PI, 0.0)
		world.add_child(_fill)
	_apply_fake_fog(world, r.get("fake_fog", []), int(prof.get("fake_fog_layers", 2)))
	_apply_ground(world, r.get("ground", {}), prof)
	_apply_banners(world, r.get("banners", {}))
	_apply_rim(r.get("rim", {}), prof)
	_apply_vignette(r.get("vignette", {}))
	_apply_particles(world, r.get("particles", []), float(prof.get("particle_mult", 1.0)))
	_apply_scenery_tint(world, r.get("scenery_tint", {}))
	_apply_fires(world, r.get("fires", []), float(prof.get("particle_mult", 1.0)))
	if r.has("decor") and DisplayServer.get_name() != "headless" and world is Node3D:
		DecorLayer.build(world as Node3D, region_id, r["decor"], float(prof.get("decor_mult", 1.0)))


func _process(_delta: float) -> void:
	if follow == null or not is_instance_valid(follow):
		return
	for e: Array in _emitters:
		var p := e[0] as CPUParticles3D
		if is_instance_valid(p):
			p.global_position = follow.global_position + Vector3(0.0, float(e[1]), 0.0)
			if not bool(e[2]): # primeira vez junto do personagem: recomeça já cheio (preprocess) ali
				e[2] = true
				p.restart()


## Um emissor por tipo; local_coords desligado: as partículas ficam no mundo enquanto o emissor anda.
func _apply_particles(world: Node, list: Array, mult: float) -> void:
	_emitters.clear()
	var types: Dictionary = GameConfig.get_value("ambience", "particle_types")
	for entry: Dictionary in list:
		var def: Dictionary = types.get(str(entry.get("type", "")), {})
		var amount := int(round(float(entry.get("count", 0)) * mult))
		if def.is_empty() or amount <= 0:
			continue
		var p := _emitter(def, entry, amount)
		p.name = "Ambience_%s" % entry["type"]
		world.add_child(p)
		var height := float(def.get("height_m", 1.0))
		p.position = Vector3(0.0, height, 0.0)
		_emitters.append([p, height, false])


## Emissor de um tipo de partícula (ambience.json -> particle_types); entry dá cor, alfa e,
## nos fogos, a área (area_m) no lugar da do tipo.
static func _emitter(def: Dictionary, entry: Dictionary, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = float(def.get("lifetime_s", 5.0))
	p.preprocess = p.lifetime # já começa cheio
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = _vec3(entry.get("area_m", def.get("area_m", [14, 1, 14])))
	p.direction = _vec3(def.get("direction", [0, 1, 0]))
	p.spread = float(def.get("spread_deg", 45.0))
	var v: Array = def.get("velocity", [0.1, 0.3])
	p.initial_velocity_min = float(v[0])
	p.initial_velocity_max = float(v[1])
	p.gravity = _vec3(def.get("gravity", [0, 0, 0]))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = PARTICLE_MIX_SHADER if str(def.get("blend", "add")) == "mix" else PARTICLE_SHADER
	mat.set_shader_parameter("intensity", float(def.get("intensity", 1.0)))
	var tex := str(def.get("texture", ""))
	if tex != "" and ResourceLoader.exists(SHAPES_DIR + tex + ".png"):
		mat.set_shader_parameter("shape", load(SHAPES_DIR + tex + ".png"))
		mat.set_shader_parameter("has_shape", true)
		mat.set_shader_parameter("spin", float(def.get("spin", 0.0)))
		p.angle_min = 0.0
		p.angle_max = 360.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * float(def.get("size_m", 0.1))
	quad.material = mat
	p.mesh = quad
	# entra e sai devagar (sem "pipocar")
	var col := _col(entry.get("color"), Color.WHITE)
	var alpha := float(entry.get("alpha", 1.0))
	var fade := clampf(float(def.get("fade_in", 0.2)), 0.01, 0.49)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col, 0.0))
	ramp.set_color(1, Color(col, 0.0))
	ramp.add_point(fade, Color(col, alpha))
	ramp.add_point(1.0 - fade, Color(col, alpha))
	p.color_ramp = ramp
	var grow: Array = def.get("scale", [0.6, 1.3])
	p.scale_amount_min = float(grow[0])
	p.scale_amount_max = float(grow[1])
	if def.has("scale_end"): # fumaça abre, chama afina
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, float(def["scale_end"])))
		p.scale_amount_curve = curve
	return p


## Fogos em pontos fixos (braseiros, tochas): nas posições de nós da cena (as luzes que já existem),
## com modelo opcional e emissores de chama, fagulha e fumaça. ambience.json -> regions.<id>.fires.
func _apply_fires(world: Node, list: Array, mult: float) -> void:
	var types: Dictionary = GameConfig.get_value("ambience", "particle_types")
	var dirs: Dictionary = GameConfig.get_value("ambience", "decor_dirs")
	for entry: Dictionary in list:
		var nodes: Array[Node3D] = []
		for path: String in entry.get("nodes", []):
			if path.ends_with("/*"):
				var parent := world.get_node_or_null(path.trim_suffix("/*"))
				if parent != null:
					for c in parent.get_children():
						if c is Node3D:
							nodes.append(c as Node3D)
			elif world.get_node_or_null(path) is Node3D:
				nodes.append(world.get_node(path) as Node3D)
		for path: String in entry.get("hide", []): # a chama antiga (malha chapada) dá lugar às partículas
			var old := world.get_node_or_null(path)
			if old is Node3D:
				(old as Node3D).visible = false
		var off := _vec3(entry.get("offset", [0, 0, 0]))
		for n in nodes:
			var at := (world as Node3D).to_local(n.global_position) + off if world is Node3D else n.global_position + off
			var yaw := atan2(-at.x, -at.z) if bool(entry.get("face_center", false)) else 0.0
			var root := Node3D.new()
			root.name = "Fire_%s" % n.name
			root.position = at
			root.rotation.y = yaw
			world.add_child(root)
			var model := str(entry.get("model", ""))
			if model != "":
				var path := DecorLayer._resolve(model, dirs)
				if ResourceLoader.exists(path):
					var m := (load(path) as PackedScene).instantiate() as Node3D
					m.position = _vec3(entry.get("model_offset", [0, 0, 0]))
					m.scale = Vector3.ONE * float(entry.get("model_scale", 1.0))
					root.add_child(m)
			for e: Dictionary in entry.get("emit", []):
				var def: Dictionary = (types.get(str(e.get("type", "")), {}) as Dictionary).duplicate()
				for k: String in ["size_m", "velocity", "lifetime_s"]: # o fogo pode trocar o tamanho do tipo
					if e.has(k):
						def[k] = e[k]
				var amount := maxi(1, int(round(float(e.get("count", 0)) * mult)))
				if def.is_empty() or int(e.get("count", 0)) <= 0:
					continue
				var p := _emitter(def, e, amount)
				p.position = _vec3(e.get("offset", [0, 0, 0]))
				root.add_child(p)


## Retinge os modelos do RegionScenery por tipo (pinheiros secos, pedras frias...): ambience.json ->
## regions.<id>.scenery_tint, {tipo: cor}. Só materiais: não mexe no sorteio nem na colisão.
func _apply_scenery_tint(world: Node, tints: Dictionary) -> void:
	if tints.is_empty():
		return
	var cache: Dictionary = {}
	for s in world.find_children("*", "RegionScenery", true, false):
		for piece in s.get_children():
			for model in piece.get_children():
				var kind := str(model.get_meta(&"scenery_kind", ""))
				if not tints.has(kind):
					continue
				var tint := _col(tints[kind], Color.WHITE)
				for n in model.find_children("*", "MeshInstance3D", true, false):
					var mi := n as MeshInstance3D
					for i in mi.mesh.get_surface_count():
						var src := mi.mesh.surface_get_material(i)
						if not (src is BaseMaterial3D):
							continue
						var key := [src, kind]
						if not cache.has(key):
							var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
							m.albedo_color = m.albedo_color * tint
							cache[key] = m
						mi.set_surface_override_material(i, cache[key])


static func _vec3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _apply_environment(env: Environment, r: Dictionary, prof: Dictionary) -> void:
	if r.has("ambient"):
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = _col(r["ambient"].get("color"), env.ambient_light_color)
		env.ambient_light_energy = float(r["ambient"].get("energy", env.ambient_light_energy))
	if r.has("fog"):
		var fog: Dictionary = r["fog"]
		env.fog_enabled = true
		env.fog_light_color = _col(fog.get("color"), env.fog_light_color)
		env.fog_density = float(fog.get("density", env.fog_density))
		env.fog_height = float(fog.get("height", env.fog_height))
		env.fog_height_density = float(fog.get("height_density", env.fog_height_density))
	if r.has("sky") and env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		env.sky = env.sky.duplicate()
		var mat := env.sky.sky_material.duplicate() as ProceduralSkyMaterial
		mat.sky_top_color = _col(r["sky"].get("top"), mat.sky_top_color)
		mat.sky_horizon_color = _col(r["sky"].get("horizon"), mat.sky_horizon_color)
		mat.ground_horizon_color = mat.sky_horizon_color
		env.sky.sky_material = mat
	env.glow_enabled = bool(prof.get("glow", true))
	if env.glow_enabled and r.has("glow"):
		env.glow_intensity = float(r["glow"].get("intensity", env.glow_intensity))
		env.glow_hdr_threshold = float(r["glow"].get("threshold", env.glow_hdr_threshold))
		var levels := int(prof.get("glow_levels", 5))
		for i in 7:
			env.set_glow_level(i, 1.0 if i < levels and i >= 1 else 0.0)
	if r.has("adjust"):
		env.adjustment_enabled = true
		env.adjustment_contrast = float(r["adjust"].get("contrast", 1.0))
		env.adjustment_saturation = float(r["adjust"].get("saturation", 1.0))
	if r.has("tonemap"):
		env.tonemap_mode = TONEMAPS.get(str(r["tonemap"].get("mode", "filmic")), Environment.TONE_MAPPER_FILMIC)
		env.tonemap_white = float(r["tonemap"].get("white", 1.0))


## Camadas Fog/* da cena: cor e densidade dos dados; o perfil limita quantas ficam visíveis.
func _apply_fake_fog(world: Node, layers: Array, max_layers: int) -> void:
	var fog := world.find_child("Fog", false, false)
	if fog == null:
		return
	var i := 0
	for child in fog.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		mi.visible = i < max_layers
		var mat := mi.get_surface_override_material(0) as ShaderMaterial
		if mat != null and i < layers.size():
			mat = mat.duplicate() as ShaderMaterial
			var layer: Dictionary = layers[i]
			mat.set_shader_parameter("fog_color", _col(layer.get("color"), Color.GRAY))
			mat.set_shader_parameter("density", float(layer.get("density", 0.3)))
			mi.set_surface_override_material(0, mat)
		i += 1


## Cor do chão: multiplica a cor do material padrão ou as cores do shader de chão (dirt_dark, dirt_light, moss).
func _apply_ground(world: Node, ground: Dictionary, prof: Dictionary) -> void:
	var node := world.find_child("Ground", false, false) as MeshInstance3D
	if node == null or node.mesh == null or ground.is_empty():
		return
	var t: Array = ground.get("tint", [1.0, 1.0, 1.0])
	var tint := Color(float(t[0]), float(t[1]), float(t[2]))
	var mat := node.mesh.surface_get_material(0)
	if mat == null:
		return
	mat = mat.duplicate()
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		sm.albedo_color *= tint
		if ground.has("macro") and sm.albedo_texture != null:
			mat = _macro_material(sm, ground["macro"], bool(prof.get("ground_anti_tile", true)))
	elif mat is ShaderMaterial:
		var shm := mat as ShaderMaterial
		for p in ["dirt_dark", "dirt_light", "moss"]:
			var v: Variant = shm.get_shader_parameter(p)
			if v is Color:
				shm.set_shader_parameter(p, (v as Color) * tint)
		if ground.has("bump"): # relevo da neve/terra (ground_dirt.gdshader)
			shm.set_shader_parameter("bump", float(ground["bump"]))
			shm.set_shader_parameter("bump_scale", float(ground.get("bump_scale", 0.6)))
	node.set_surface_override_material(0, mat)


## Troca o StandardMaterial3D do chão pelo ground_macro.gdshader com a mesma textura e escala.
static func _macro_material(sm: StandardMaterial3D, macro: Dictionary, anti_tile: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GROUND_MACRO_SHADER
	m.set_shader_parameter("albedo_tex", sm.albedo_texture)
	m.set_shader_parameter("albedo_color", sm.albedo_color)
	m.set_shader_parameter("uv_scale", Vector2(sm.uv1_scale.x, sm.uv1_scale.y))
	m.set_shader_parameter("uv_offset", Vector2(sm.uv1_offset.x, sm.uv1_offset.y))
	m.set_shader_parameter("roughness", sm.roughness)
	if sm.normal_enabled and sm.normal_texture != null:
		m.set_shader_parameter("normal_tex", sm.normal_texture)
		m.set_shader_parameter("use_normal", true)
		m.set_shader_parameter("normal_scale", sm.normal_scale)
	for key: String in macro:
		var v: Variant = macro[key]
		m.set_shader_parameter(key, Color.html(v) if v is String else v)
	if not anti_tile:
		m.set_shader_parameter("anti_tile", 0.0)
	return m


## Estandartes de pano: troca a caixa chapada (nós com o prefixo dado, em "Decor") por um plano
## subdividido com o cloth_banner.gdshader, que balança e tem dobras, faixa e losango.
func _apply_banners(world: Node, cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	var decor := world.find_child("Decor", false, false)
	if decor == null:
		return
	var size_a: Array = cfg.get("size_m", [1.0, 2.0])
	var mesh := PlaneMesh.new()
	mesh.orientation = PlaneMesh.FACE_Z
	mesh.size = Vector2(float(size_a[0]), float(size_a[1]))
	mesh.subdivide_width = int(cfg.get("subdivide_w", 3))
	mesh.subdivide_depth = int(cfg.get("subdivide_h", 10))
	var mat := ShaderMaterial.new()
	mat.shader = BANNER_SHADER
	mat.set_shader_parameter("height", float(size_a[1]))
	for key: String in (cfg.get("params", {}) as Dictionary):
		var v: Variant = cfg["params"][key]
		mat.set_shader_parameter(key, Color.html(v) if v is String else v)
	var prefix := str(cfg.get("prefix", "Banner"))
	for child in decor.get_children():
		if child is MeshInstance3D and child.name.begins_with(prefix):
			(child as MeshInstance3D).mesh = mesh
			(child as MeshInstance3D).material_override = mat


## Contorno dos personagens na cor da região (fraco: o modelo realista pede um recorte fino).
func _apply_rim(cfg: Dictionary, prof: Dictionary) -> void:
	if cfg.is_empty() or not bool(prof.get("character_rim", true)):
		character_rim = null
		return
	if character_rim == null:
		character_rim = ShaderMaterial.new()
		character_rim.shader = RIM_SHADER
	character_rim.set_shader_parameter("rim_color", _col(cfg.get("color"), Color.WHITE))
	character_rim.set_shader_parameter("intensity", float(cfg.get("intensity", 0.35)))
	character_rim.set_shader_parameter("power", float(cfg.get("power", 3.0)))


## Vinheta: gradiente radial transparente no centro e cor da névoa nas bordas (não lê a tela).
func _apply_vignette(v: Dictionary) -> void:
	var strength := float(v.get("strength", 0.0))
	_vignette.visible = strength > 0.0
	if not _vignette.visible:
		return
	var col := _col(v.get("color"), Color.BLACK)
	var grad := Gradient.new()
	grad.set_color(0, Color(col, 0.0))
	grad.set_color(1, Color(col, strength))
	grad.add_point(0.55, Color(col, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 256
	tex.height = 256
	_vignette.texture = tex


static func _col(value: Variant, fallback: Color) -> Color:
	if value is String and Color.html_is_valid(str(value)):
		return Color.html(str(value))
	if value is Array:
		return GameConfig.color_of(value, fallback)
	return fallback
