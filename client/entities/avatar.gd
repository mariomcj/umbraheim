class_name Avatar
extends Node3D
## Representação visual de uma entidade (jogador ou monstro) no cliente.
## Posição vem de snapshots do servidor e é interpolada com um pequeno atraso
## (movement.interpolation_delay_ms) para suavizar o tick de 10–20 Hz.

const MAX_SAMPLES := 8
const RIM_SHADER := preload("res://assets/shaders/rim_highlight.gdshader")
const HP_BAR_WIDTH := 0.9
const DISSOLVE_SHADER := preload("res://assets/shaders/dissolve_world.gdshader")
const AURA_SHADER := preload("res://assets/vfx/shaders/pulse_aura_for_3d_character.gdshader")

static var _noise: NoiseTexture2D

@export var local_color: Color = Color(0.42, 0.22, 0.62)
@export var remote_color: Color = Color(0.32, 0.36, 0.33)
@export var hover_color: Color = Color(1.0, 0.35, 0.25)
@export var body_height: float = 1.8
## Flutuação vertical do corpo (espectros); 0 = parado no chão.
@export var float_amplitude: float = 0.0

var entity_id: int = 0
var is_monster: bool = false
var is_local: bool = false
var is_summon: bool = false
var display_name: String = ""
var monster_level: int = 0
var monster_type: String = "" # id em monsters.json (com _dourado), para o som
var monster_model: String = "" # modelo animado (models.json), para o som
var hp_frac: float = 1.0
var dying: bool = false

var _samples: Array[Vector4] = [] # (tempo_ms, x, z, yaw)
## true = a posição é escrita de fora a cada frame (predição local), sem interpolação.
var predicted: bool = false
var _delay_ms: float
var _rim: ShaderMaterial
var _hovered: bool = false
var _hp_back: MeshInstance3D
var _hp_fill: MeshInstance3D
var _hp_fill_mesh: QuadMesh
## Modelo 3D animado (data/config/models.json); null = as formas simples da cena.
var rig: ModelRig
var _last_pos: Vector3
var _speed: float = 0.0
var _appearance := PackedInt32Array()
var _catalog: ItemCatalog
## Contorno de base (aura); a seleção troca por um instante e volta para ele.
var _base_overlay: Material = null
var _shadow: MeshInstance3D # sombra de contato: disco macio sob os pés (o Compatibility não tem SSAO)

@onready var _body: MeshInstance3D = $Body
@onready var _label: Label3D = $NameLabel
@onready var _aura: OmniLight3D = get_node_or_null("Aura")


var _body_base_y: float


func _ready() -> void:
	_delay_ms = GameConfig.get_f("movement", "interpolation_delay_ms")
	_body_base_y = _body.position.y
	_rim = ShaderMaterial.new()
	_rim.shader = RIM_SHADER
	_build_hp_bar()
	_build_contact_shadow()


func setup_player(id: int, local: bool) -> void:
	entity_id = id
	is_local = local
	var mat := StandardMaterial3D.new()
	mat.albedo_color = local_color if local else remote_color
	mat.roughness = 0.8
	if local:
		mat.emission_enabled = true
		mat.emission = local_color
		mat.emission_energy_multiplier = 0.35
	_body.material_override = mat
	if _aura != null:
		_aura.visible = local
	display_name = ("Você #%d" if local else "#%d") % id
	_label.text = display_name
	# contorno discreto permanente no próprio personagem (leitura de silhueta)
	if local:
		_rim.set_shader_parameter("rim_color", Color(0.75, 0.55, 1.0))
		_rim.set_shader_parameter("intensity", 0.6)
		_set_overlay(_rim)


func setup_monster(id: int, def: Dictionary) -> void:
	entity_id = id
	is_monster = true
	monster_level = int(def.get("level", 1))
	monster_model = str(def.get("model", ""))
	display_name = str(def.get("name", "?"))
	_label.text = "%s  nv %d" % [display_name, monster_level]
	if bool(def.get("boss", false)):
		# chefe: maior, nome dourado e uma luz própria
		var s := float(def.get("scale", 1.8))
		scale = Vector3.ONE * s
		_label.modulate = Color(1.0, 0.78, 0.3)
		_label.text = "%s  · chefe nv %d" % [display_name, monster_level]
		_label.scale = Vector3.ONE / s * 1.25 # o nome não cresce junto com o corpo
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.45, 0.2)
		glow.light_energy = 1.3
		glow.omni_range = 4.0
		glow.position = Vector3(0, 1.0, 0)
		add_child(glow)
	if str(def.get("model", "")) != "":
		attach_model(str(def["model"]))
	if bool(def.get("golden", false)):
		_make_golden()
	if str(def.get("aura", "")) != "":
		_apply_aura(str(def["aura"]))


## Troca as formas simples pelo modelo animado `id` (as formas ficam escondidas).
func attach_model(id: String) -> void:
	if id == "" or (rig != null and rig.model_id == id):
		return
	if rig != null:
		rig.queue_free()
		rig = null
	rig = ModelRig.create(id)
	if rig == null:
		return
	add_child(rig)
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == _hp_back or mi == _hp_fill or mi == _shadow or rig.is_ancestor_of(mi) or (_gear != null and _gear.is_ancestor_of(mi)):
			continue
		mi.visible = false
	_last_pos = position
	_set_overlay(_rim if is_local else null) # os outros: contorno da região (AmbienceDirector.character_rim)
	if _catalog != null:
		set_appearance(_appearance, _catalog) # as armas vão para as mãos do modelo


## Contorno (seleção, o próprio personagem) no modelo ou nas formas simples.
func _set_overlay(mat: Material) -> void:
	if mat == null:
		mat = _base_overlay if _base_overlay != null else AmbienceDirector.character_rim
	if rig == null:
		_body.material_overlay = mat
		return
	for mi in rig.meshes:
		if is_instance_valid(mi):
			mi.material_overlay = mat


## Aura pulsante em volta do corpo (data/config/vfx.json -> auras).
func _apply_aura(aura_id: String) -> void:
	var auras: Dictionary = GameConfig.get_value("vfx", "auras")
	if not auras.has(aura_id):
		return
	var cfg: Dictionary = auras[aura_id]
	var c := GameConfig.color_of(cfg.get("color"))
	var mat := ShaderMaterial.new()
	mat.shader = AURA_SHADER
	mat.set_shader_parameter("aura_color", Color(c.r, c.g, c.b, float(cfg.get("alpha", 0.2))))
	# a casca cresce no espaço da malha: no modelo, desfaz a escala dele
	var unit := rig.model.scale.x if rig != null else 1.0
	mat.set_shader_parameter("aura_thickness", float(cfg.get("thickness_m", 0.05)) / maxf(0.001, unit))
	mat.set_shader_parameter("pulse_speed", float(cfg.get("pulse_speed", 1.0)))
	mat.set_shader_parameter("pulse_strength", float(cfg.get("pulse_strength", 0.3)))
	_base_overlay = mat
	if rig != null:
		_set_overlay(mat)
		return
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != _hp_back and mi != _hp_fill and mi.visible:
			mi.material_overlay = mat


## Cor do corpo pela classe (e o modelo da classe); evoluído ganha uma luz dourada aos pés.
func set_class_look(color: Color, evolved: bool, class_id: String = "") -> void:
	if class_id != "":
		attach_model(ModelRig.model_for_class(class_id))
	var mat := _body.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = color if not is_local else color.lightened(0.1)
		if is_local:
			mat.emission = color
	var glow: OmniLight3D = get_node_or_null("EvolutionGlow")
	if evolved and glow == null:
		glow = OmniLight3D.new()
		glow.name = "EvolutionGlow"
		glow.light_color = Color(1.0, 0.8, 0.4)
		glow.light_energy = 0.9
		glow.omni_range = 2.2
		glow.position = Vector3(0, 0.3, 0)
		add_child(glow)
	elif not evolved and glow != null:
		glow.queue_free()


## Invocação aliada (Espírito do Véu): translúcida, azulada e flutuando; sem barra de vida.
func setup_summon(id: int, def: Dictionary, color: Color, owner_name: String) -> void:
	entity_id = id
	is_summon = true
	display_name = str(def.get("name", "?"))
	_label.text = display_name if owner_name == "" else "%s de %s" % [display_name, owner_name]
	_label.modulate = color
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	_override_all(mat)
	float_amplitude = maxf(float_amplitude, 0.12)
	scale = Vector3.ONE * 0.8
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.8
	light.omni_range = 3.0
	light.position = Vector3(0, 1.0, 0)
	add_child(light)


## Um material para todas as peças (dourado, invocação). Tira antes as cores por superfície
## (tom do modelo): com as duas ao mesmo tempo o renderer Compatibility perde o material.
func _override_all(mat: Material) -> void:
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == _hp_back or mi == _hp_fill:
			continue
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, null)
		mi.material_override = mat


## Monstro dourado (invasão): todas as peças viram ouro brilhante, com luz própria.
func _make_golden() -> void:
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.95, 0.72, 0.22)
	gold.metallic = 0.9
	gold.roughness = 0.25
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.65, 0.15)
	gold.emission_energy_multiplier = 0.55
	_override_all(gold)
	_label.modulate = Color(1.0, 0.85, 0.35)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.3)
	light.light_energy = 1.0
	light.omni_range = 3.5
	light.position = Vector3(0, 1.2, 0)
	add_child(light)


## Nome do personagem (chega por rpc_player_name).
func set_player_name(n: String) -> void:
	display_name = n
	_label.text = n
	_label.modulate = Color(0.9, 0.55, 0.45)


## Status de PvP: Fora da Lei (laranja → vermelho → carmesim) ou Herói (azul), com o título.
func set_pvp_tag(outlaw: int, hero: int) -> void:
	var pvp := GameConfig.table("pvp")
	var info: Dictionary = {}
	if outlaw > 0:
		info = pvp["outlaw_levels"][outlaw - 1]
	elif hero > 0:
		info = pvp["hero_levels"][hero - 1]
	if info.is_empty():
		_label.text = display_name
		_label.modulate = Color(0.9, 0.55, 0.45)
		return
	_label.text = "%s · %s" % [display_name, info["name"]]
	_label.modulate = GameConfig.color_of(info["color"])


var _guild_label: Label3D
var _guild_icon: Sprite3D


## Guilda sobre o nome: símbolo de pixels e o nome entre ‹ ›; nome vazio = sem guilda.
## Cor: verde = a minha, vermelho = inimiga em guerra, dourado = as outras.
func set_guild(guild_name: String, symbol: String, color: Color) -> void:
	if guild_name.is_empty():
		if _guild_label != null:
			_guild_label.visible = false
			_guild_icon.visible = false
		return
	if _guild_label == null:
		_guild_label = _label.duplicate() as Label3D
		_guild_label.font_size = roundi(_label.font_size * 0.8)
		_guild_label.position = _label.position + Vector3(0.0, 0.3, 0.0)
		add_child(_guild_label)
		_guild_icon = Sprite3D.new()
		_guild_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_guild_icon.no_depth_test = _label.no_depth_test
		_guild_icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_guild_icon.pixel_size = 0.05
		_guild_icon.shaded = false
		_guild_icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_guild_icon.position = _label.position + Vector3(0.0, 0.68, 0.0)
		add_child(_guild_icon)
	_guild_label.text = "‹%s›" % guild_name
	_guild_label.modulate = color
	_guild_label.visible = not dying
	_guild_icon.texture = GuildSymbol.texture(symbol)
	_guild_icon.visible = not dying


var _gear: Node3D


## Troca o equipamento visível (vem do servidor via rpc_appearance).
func set_appearance(appearance: PackedInt32Array, catalog: ItemCatalog) -> void:
	_appearance = appearance
	_catalog = catalog
	if _gear != null:
		_gear.queue_free()
	if rig != null:
		rig.clear_weapons()
	_gear = EquipmentVisuals.build(appearance, catalog, rig)
	add_child(_gear)


func set_hovered(on: bool) -> void:
	if on == _hovered or is_local:
		return
	_hovered = on
	_rim.set_shader_parameter("rim_color", hover_color)
	_rim.set_shader_parameter("intensity", 1.4)
	_set_overlay(_rim if on else null)
	_update_hp_bar()


func set_hp(frac: float) -> void:
	if not is_equal_approx(frac, hp_frac):
		if rig != null and frac < hp_frac and frac > 0.0 and not dying:
			rig.play_once("hit")
		hp_frac = frac
		_update_hp_bar()


## Alvo do ponto de mira dos efeitos (peito).
func aim_point() -> Vector3:
	return global_position + Vector3.UP * body_height * 0.6


func push_sample(time_ms: float, x: float, z: float, yaw_rad: float) -> void:
	# salto grande (teletransporte, renascimento): não interpola, aparece direto no destino
	if not _samples.is_empty() and Vector2(_samples[-1].y, _samples[-1].z).distance_to(Vector2(x, z)) > 6.0:
		_samples.clear()
	_samples.append(Vector4(time_ms, x, z, yaw_rad))
	if _samples.size() > MAX_SAMPLES:
		_samples.remove_at(0)
	if _samples.size() == 1:
		position = Vector3(x, 0.0, z)
		rotation.y = yaw_rad


## Ataque corpo a corpo: a animação do modelo ou, sem ela, uma investida curta.
func play_attack() -> void:
	if rig != null and rig.play_once("attack"):
		return
	var node: Node3D = _body if rig == null else rig
	var t := create_tween()
	t.tween_property(node, "position:z", node.position.z + 0.35, 0.08)
	t.tween_property(node, "position:z", node.position.z, 0.18)


## Magia lançada (projétil, área, corrente, cura...): só o gesto do modelo.
func play_cast() -> void:
	if rig != null and not rig.play_once("cast"):
		rig.play_once("attack")


## Morte: afunda e encolhe; depois se remove.
func play_death() -> void:
	dying = true
	_label.visible = false
	if _guild_label != null:
		_guild_label.visible = false
		_guild_icon.visible = false
	if _hp_back != null:
		_hp_back.visible = false
		_hp_fill.visible = false
	var cfg: Dictionary = GameConfig.get_value("vfx", "dissolve")
	var wait := 0.0
	if rig != null and rig.play_once("death"):
		wait = clampf(rig.clip_length("death"), 0.3, float(cfg.get("anim_wait_max_s", 1.6)))
	# depois da queda, o corpo se desfaz de cima para baixo com a borda brilhante
	var mats := _dissolve_materials(cfg, wait > 0.0)
	if not mats.is_empty():
		var set_offset := func(v: float) -> void:
			for m: ShaderMaterial in mats:
				m.set_shader_parameter("offset", v)
		var d := create_tween()
		d.tween_interval(wait)
		d.tween_method(set_offset, 0.0, 1.0, float(cfg.get("duration_s", 1.2)))
		d.tween_callback(queue_free)
		return
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "position:y", -1.0, 0.9).set_ease(Tween.EASE_IN)
	t.tween_property(self, "scale", Vector3(1.2, 0.3, 1.2), 0.9)
	t.chain().tween_callback(queue_free)


## Troca o material de cada superfície visível por um de dissolução com a mesma cor e textura.
## `lying`: o corpo já caiu (animação de morte), então a faixa de altura é a do corpo no chão.
func _dissolve_materials(cfg: Dictionary, lying: bool) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	var by_source: Dictionary = {} # material original -> material de dissolução
	var base_y := global_position.y - 0.05
	var height := float(cfg.get("lying_height_m", 0.7)) if lying else body_height + 0.3
	var top_y := base_y + height * scale.y
	var border := GameConfig.color_of(cfg.get("border_color"), Color(0.7, 0.3, 1.0))
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == _hp_back or mi == _hp_fill or not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.material_override if mi.material_override != null else mi.get_active_material(i)
			if not by_source.has(src):
				var m := ShaderMaterial.new()
				m.shader = DISSOLVE_SHADER
				var std := src as BaseMaterial3D
				if std != null:
					m.set_shader_parameter("base_color", std.albedo_color)
					if std.albedo_texture != null:
						m.set_shader_parameter("albedo_texture", std.albedo_texture)
						m.set_shader_parameter("has_texture", true)
				else:
					m.set_shader_parameter("base_color", Color(0.5, 0.5, 0.55))
				m.set_shader_parameter("noise_texture", _dissolve_noise())
				m.set_shader_parameter("base_y", base_y)
				m.set_shader_parameter("top_y", top_y)
				m.set_shader_parameter("border_color", border)
				m.set_shader_parameter("border_height", float(cfg.get("border_m", 0.1)) / maxf(0.1, top_y - base_y))
				m.set_shader_parameter("emission_intensity", float(cfg.get("emission", 3.0)))
				by_source[src] = m
				out.append(m)
			mi.set_surface_override_material(i, by_source[src])
		mi.material_override = null
		mi.material_overlay = null
	return out


static func _dissolve_noise() -> NoiseTexture2D:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.frequency = 0.05
		_noise = NoiseTexture2D.new()
		_noise.width = 128
		_noise.height = 128
		_noise.seamless = true
		_noise.noise = fn
	return _noise


func _process(delta: float) -> void:
	if dying:
		return
	var bob := float_amplitude if rig == null else maxf(rig.float_m, float_amplitude)
	if bob > 0.0:
		var wave := sin(Time.get_ticks_msec() * 0.0025 + float(entity_id)) * bob
		if rig == null:
			_body.position.y = _body_base_y + wave
		else:
			rig.position.y = bob + wave
	# o próprio personagem com predição: a posição vem do LocalPredictor (client_main)
	if not predicted and _samples.size() >= 2:
		_interpolate()
	if rig != null and delta > 0.0:
		var step := Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length() / delta
		_speed = lerpf(_speed, minf(step, 20.0), clampf(delta * 10.0, 0.0, 1.0))
		_last_pos = position
		rig.update_locomotion(_speed)


func _interpolate() -> void:
	var render_time := Time.get_ticks_msec() - _delay_ms
	var a := _samples[0]
	var b := _samples[_samples.size() - 1]
	for i in range(_samples.size() - 1):
		if _samples[i].x <= render_time and render_time <= _samples[i + 1].x:
			a = _samples[i]
			b = _samples[i + 1]
			break
	var span := b.x - a.x
	var t := clampf((render_time - a.x) / span, 0.0, 1.0) if span > 0.0 else 1.0
	position = Vector3(lerpf(a.y, b.y, t), 0.0, lerpf(a.z, b.z, t))
	rotation.y = lerp_angle(a.w, b.w, t)


# ---------------------------------------------------------------- barra de vida (billboard)

## Disco escuro e macio no chão, que "assenta" o modelo (ambience.json -> contact_shadow).
func _build_contact_shadow() -> void:
	var cfg: Dictionary = GameConfig.get_value("ambience", "contact_shadow")
	if cfg.is_empty() or float(cfg.get("alpha", 0.0)) <= 0.0:
		return
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, float(cfg["alpha"])), Color(0, 0, 0, float(cfg["alpha"]) * 0.6), Color(0, 0, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * float(cfg.get("size_m", 0.9))
	_shadow = MeshInstance3D.new()
	_shadow.mesh = quad
	_shadow.material_override = mat
	_shadow.position.y = float(cfg.get("lift_m", 0.03))
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)


func _build_hp_bar() -> void:
	var y := _label.position.y - 0.22
	_hp_back = _make_bar_quad(Color(0.05, 0.03, 0.03, 0.85), y, 1)
	_hp_fill_mesh = QuadMesh.new()
	_hp_fill_mesh.size = Vector2(HP_BAR_WIDTH, 0.07)
	_hp_fill = _make_bar_quad(Color(0.8, 0.12, 0.1), y, 2)
	_hp_fill.mesh = _hp_fill_mesh
	_update_hp_bar()


func _make_bar_quad(color: Color, y: float, priority: int) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(HP_BAR_WIDTH + 0.04, 0.11)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = priority
	mat.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.position = Vector3(0.0, y, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _update_hp_bar() -> void:
	if _hp_back == null:
		return
	var show := not is_local and not dying and (hp_frac < 0.999 or _hovered)
	_hp_back.visible = show
	_hp_fill.visible = show and hp_frac > 0.0
	_hp_fill_mesh.size = Vector2(HP_BAR_WIDTH * hp_frac, 0.07)
	_hp_fill_mesh.center_offset = Vector3(-HP_BAR_WIDTH * (1.0 - hp_frac) * 0.5, 0.0, 0.0)
