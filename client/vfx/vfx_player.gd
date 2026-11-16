class_name VfxPlayer
extends Node3D
## Efeitos visuais do combate (só visual; o servidor já decidiu tudo).
## Cada magia tem antecipação, execução e impacto (seção 4 da especificação).
## Tudo com CPUParticles3D + shaders simples, compatível com WebGL 2; a quantidade
## de partículas e o uso de luzes seguem o preset de qualidade (data/config/vfx.json).

const PARTICLE_SHADER := preload("res://assets/shaders/particle_tex.gdshader")
const SHAPES_DIR := "res://assets/vfx/particles/kenney_particle_pack/"
const RUNE_SHADER := preload("res://assets/shaders/rune_circle.gdshader")

var camera_rig: IsoCameraRig

var _particle_scale: float = 1.0
var _lights: bool = true
var _shake_scale: float = 1.0
var _particle_material: ShaderMaterial
var _dmg_colors: Dictionary = {}
var _rise: float
var _text_duration: float
var _click_marker: MeshInstance3D
var _shape_materials: Dictionary = {} # tipo de partícula -> ShaderMaterial com a textura
var _shape_size: float = 1.4
var _click_tween: Tween


func _ready() -> void:
	var presets: Dictionary = GameConfig.get_value("vfx", "presets")
	var preset: Dictionary = presets.get(GameConfig.get_s("vfx", "quality"), {})
	_particle_scale = float(preset.get("particle_scale", 1.0))
	_lights = bool(preset.get("lights", true))
	_shake_scale = float(preset.get("shake", 1.0))
	_particle_material = ShaderMaterial.new()
	_particle_material.shader = PARTICLE_SHADER
	_shape_size = GameConfig.get_f("vfx", "particle_shape_size")
	var shapes: Dictionary = GameConfig.get_value("vfx", "particle_shapes")
	for kind: String in shapes:
		var def: Dictionary = shapes[kind]
		var path := SHAPES_DIR + str(def.get("texture", "")) + ".png"
		if str(def.get("texture", "")) == "" or not ResourceLoader.exists(path):
			continue
		var mat := ShaderMaterial.new()
		mat.shader = PARTICLE_SHADER
		mat.set_shader_parameter("shape", load(path))
		mat.set_shader_parameter("has_shape", true)
		mat.set_shader_parameter("spin", float(def.get("spin", 0.0)))
		_shape_materials[kind] = mat
	var colors: Dictionary = GameConfig.get_value("ui", "damage_colors")
	for k: String in colors:
		_dmg_colors[k] = GameConfig.color_of(colors[k])
	_rise = GameConfig.get_f("ui", "floating_text_rise_m")
	_text_duration = GameConfig.get_f("ui", "floating_text_duration_s")
	_click_marker = _make_rune_quad(Color(0.95, 0.8, 0.45), 1.0)
	_click_marker.visible = false
	add_child(_click_marker)


# ---------------------------------------------------------------- magias

## caster/target podem ser null (entidade fora da tela); usa as posições conhecidas.
func play_cast(spell: Dictionary, caster: Avatar, target: Avatar, target_pos: Vector3, chain: Array[Avatar], mine: bool) -> void:
	var color := GameConfig.color_of(spell.get("color"), Color(0.6, 0.3, 1.0))
	var from := caster.aim_point() + caster.global_basis.z * 0.35 if caster != null else target_pos + Vector3.UP
	if caster != null and str(spell["kind"]) != "melee":
		caster.play_cast()
	match str(spell["kind"]):
		"projectile":
			_projectile(from, target, target_pos, float(spell.get("projectile_speed_mps", 20.0)), color, int(spell["slot"]) == 0)
			if mine:
				shake(GameConfig.get_f("vfx", "shake_cast"))
		"area":
			_area(target_pos, float(spell.get("radius_m", 2.0)), float(spell.get("cast_delay_s", 0.5)), color, mine)
		"chain":
			_chain(from, target, chain, color)
			if mine:
				shake(GameConfig.get_f("vfx", "shake_cast") * 1.5)
		"melee":
			if caster != null:
				caster.play_attack()
			var at := target.aim_point() if target != null else target_pos + Vector3.UP
			var hit := func() -> void: _slash(at, color, int(spell["slot"]) != 0)
			get_tree().create_timer(float(spell.get("cast_delay_s", 0.1))).timeout.connect(hit)
			if mine:
				shake(GameConfig.get_f("vfx", "shake_cast"))
		"nova":
			var center := caster.global_position if caster != null else target_pos
			_area(center, float(spell.get("radius_m", 2.0)), maxf(0.15, float(spell.get("cast_delay_s", 0.3))), color, mine)
		"buff", "heal":
			if caster != null:
				_aura_burst(caster, color)
		"summon":
			if caster != null:
				impact(caster.aim_point() + caster.global_basis.z * 1.2, color, 1.3)


func _projectile(from: Vector3, target: Avatar, target_pos: Vector3, speed: float, color: Color, small: bool) -> void:
	var bolt := Node3D.new()
	add_child(bolt)
	bolt.global_position = from
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.11 if small else 0.17
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 10
	sphere.rings = 5
	core.mesh = sphere
	core.material_override = _emissive(color, 4.0)
	bolt.add_child(core)
	var trail := _particles(color, int(GameConfig.get_i("vfx", "projectile_trail_particles") * (0.6 if small else 1.0)), 0.35, false, "trail")
	trail.local_coords = false
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 0.8
	trail.scale_amount_min = 0.15
	trail.scale_amount_max = 0.3
	bolt.add_child(trail)
	trail.emitting = true
	if _lights:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 1.2
		light.omni_range = 3.0
		bolt.add_child(light)
	var end := target.aim_point() if target != null else target_pos + Vector3.UP
	var duration := maxf(0.05, from.distance_to(end) / maxf(1.0, speed))
	var target_ref: WeakRef = weakref(target) if target != null else null # o alvo pode sumir durante o voo
	var fly := func(k: float) -> void:
		if not is_instance_valid(bolt):
			return
		var alive_target: Avatar = target_ref.get_ref() if target_ref != null else null
		var goal := alive_target.aim_point() if alive_target != null and not alive_target.dying else end
		bolt.global_position = from.lerp(goal, k)
	var land := func() -> void:
		impact(bolt.global_position, color, 0.7 if small else 1.0)
		core.visible = false
		trail.emitting = false
		_free_later(bolt, trail.lifetime)
	var t := create_tween()
	t.tween_method(fly, 0.0, 1.0, duration)
	t.tween_callback(land)


func _area(center: Vector3, radius: float, delay: float, color: Color, mine: bool) -> void:
	var rune := _make_rune_quad(color, radius * 2.2)
	add_child(rune)
	rune.global_position = center + Vector3.UP * 0.04
	rune.scale = Vector3.ONE * 0.2
	var mat := rune.material_override as ShaderMaterial
	var set_intensity := func(v: float) -> void: mat.set_shader_parameter("intensity", v)
	var erupt := func() -> void:
		_eruption(center, radius, color)
		if mine:
			shake(GameConfig.get_f("vfx", "shake_area"))
	var t := create_tween()
	t.tween_property(rune, "scale", Vector3.ONE, delay * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_method(set_intensity, 0.3, 2.6, delay)
	t.tween_callback(erupt)
	t.tween_method(set_intensity, 2.6, 0.0, 0.6)
	t.tween_callback(rune.queue_free)


func _eruption(center: Vector3, radius: float, color: Color) -> void:
	var fire := _particles(color, GameConfig.get_i("vfx", "area_particles"), 0.9, true, "area")
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = radius * 0.85
	fire.scale = Vector3(1.0, 0.15, 1.0) # disco achatado
	fire.direction = Vector3.UP
	fire.spread = 15.0
	fire.initial_velocity_min = 3.0
	fire.initial_velocity_max = 7.0
	fire.gravity = Vector3(0, -2.0, 0)
	fire.scale_amount_min = 0.4
	fire.scale_amount_max = 0.9
	_spawn_burst(fire, center + Vector3.UP * 0.2)
	var dark := _particles(Color(0.35, 0.05, 0.4), int(GameConfig.get_i("vfx", "area_particles") * 0.5), 1.2, true, "smoke")
	dark.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dark.emission_sphere_radius = radius * 0.6
	dark.direction = Vector3.UP
	dark.initial_velocity_min = 1.0
	dark.initial_velocity_max = 3.0
	dark.scale_amount_min = 0.6
	dark.scale_amount_max = 1.2
	_spawn_burst(dark, center + Vector3.UP * 0.5)
	_flash(center + Vector3.UP * 1.0, color, 6.0, radius * 3.0, 0.45)


func _chain(from: Vector3, first: Avatar, chain: Array[Avatar], color: Color) -> void:
	var points: Array[Vector3] = [from]
	for a: Avatar in [first] + chain:
		if is_instance_valid(a):
			points.append(a.aim_point())
	if points.size() < 2:
		return
	var bolt := Node3D.new()
	add_child(bolt)
	var mat := _emissive(color, 5.0)
	for i in range(1, points.size()):
		_lightning_segment(bolt, points[i - 1], points[i], mat)
		impact(points[i], color, 0.8)
	if _lights:
		_flash(points[1], color, 3.0, 5.0, 0.3)
	var t := create_tween()
	for k in 4: # tremulação
		t.tween_property(bolt, "visible", false, 0.04)
		t.tween_property(bolt, "visible", true, 0.04)
	t.tween_callback(bolt.queue_free)


## Raio irregular: pequenos cilindros entre pontos com desvio aleatório.
func _lightning_segment(parent: Node3D, a: Vector3, b: Vector3, mat: Material) -> void:
	var jags := 7
	var prev := a
	var side := (b - a).cross(Vector3.UP).normalized()
	for j in range(1, jags + 1):
		var t := float(j) / jags
		var p := a.lerp(b, t)
		if j < jags:
			p += side * randf_range(-0.28, 0.28) + Vector3.UP * randf_range(-0.2, 0.2)
		var seg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.035
		cyl.bottom_radius = 0.035
		cyl.height = prev.distance_to(p)
		cyl.radial_segments = 4
		cyl.rings = 1
		seg.mesh = cyl
		seg.material_override = mat
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(seg)
		var mid := (prev + p) * 0.5
		var dir := (p - prev).normalized()
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		seg.global_transform = Transform3D(Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, PI / 2.0), mid)
		prev = p


# ---------------------------------------------------------------- impactos e eventos

func impact(at: Vector3, color: Color, size: float = 1.0) -> void:
	var burst := _particles(color, int(GameConfig.get_i("vfx", "impact_particles") * size), 0.4, true, "impact")
	burst.direction = Vector3.UP
	burst.spread = 180.0
	burst.initial_velocity_min = 1.5 * size
	burst.initial_velocity_max = 4.0 * size
	burst.scale_amount_min = 0.15
	burst.scale_amount_max = 0.35 * size
	_spawn_burst(burst, at)
	_flash(at, color, 2.5 * size, 3.0, 0.2)


## Corte de lâmina: um arco brilhante rápido no alvo e o impacto.
func _slash(at: Vector3, color: Color, heavy: bool) -> void:
	var arc := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42 if heavy else 0.32
	torus.outer_radius = torus.inner_radius + 0.06
	torus.rings = 16
	torus.ring_segments = 4
	arc.mesh = torus
	arc.material_override = _emissive(color, 5.0)
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(arc)
	arc.global_position = at
	arc.rotation = Vector3(1.2, randf() * TAU, 0.4)
	arc.scale = Vector3.ONE * 0.4
	var t := create_tween()
	t.tween_property(arc, "scale", Vector3.ONE * (1.25 if heavy else 1.0), 0.14).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(arc, "rotation:y", arc.rotation.y + 2.4, 0.18)
	t.tween_callback(arc.queue_free)
	impact(at, color, 1.0 if heavy else 0.7)


## Bônus e cura: anel de partículas subindo em volta de quem lançou.
func _aura_burst(view: Avatar, color: Color) -> void:
	var column := _particles(color, int(GameConfig.get_i("vfx", "levelup_particles") * 0.6), 1.1, true, "aura")
	column.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	column.emission_ring_axis = Vector3.UP
	column.emission_ring_radius = 0.9
	column.emission_ring_inner_radius = 0.7
	column.emission_ring_height = 0.1
	column.direction = Vector3.UP
	column.spread = 8.0
	column.gravity = Vector3.ZERO
	column.initial_velocity_min = 1.5
	column.initial_velocity_max = 3.0
	column.scale_amount_min = 0.15
	column.scale_amount_max = 0.3
	_spawn_burst(column, view.global_position + Vector3.UP * 0.1)
	_flash(view.aim_point(), color, 3.0, 5.0, 0.5)


func melee_hit(attacker: Avatar, target: Avatar) -> void:
	if attacker != null:
		attacker.play_attack()
	if target != null:
		impact(target.aim_point(), Color(0.9, 0.15, 0.1), 0.6)
		if target.is_local:
			shake(GameConfig.get_f("vfx", "shake_hit_taken"))


func death(view: Avatar) -> void:
	var puff := _particles(Color(0.4, 0.1, 0.5), GameConfig.get_i("vfx", "death_particles"), 1.0, true, "death")
	puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	puff.emission_sphere_radius = 0.5
	puff.direction = Vector3.UP
	puff.initial_velocity_min = 0.5
	puff.initial_velocity_max = 1.8
	puff.scale_amount_min = 0.3
	puff.scale_amount_max = 0.7
	_spawn_burst(puff, view.aim_point())
	view.play_death()


func level_up(view: Avatar, level: int) -> void:
	var gold := Color(1.0, 0.78, 0.3)
	var column := _particles(gold, GameConfig.get_i("vfx", "levelup_particles"), 1.4, true, "levelup")
	column.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	column.emission_ring_axis = Vector3.UP
	column.emission_ring_radius = 0.8
	column.emission_ring_inner_radius = 0.6
	column.emission_ring_height = 0.1
	column.direction = Vector3.UP
	column.spread = 5.0
	column.gravity = Vector3.ZERO
	column.initial_velocity_min = 2.0
	column.initial_velocity_max = 4.0
	column.scale_amount_min = 0.2
	column.scale_amount_max = 0.4
	_spawn_burst(column, view.global_position + Vector3.UP * 0.1)
	_flash(view.aim_point(), gold, 4.0, 6.0, 0.8)
	# level < 0: o mesmo brilho, para "magia aprendida"
	# level < 0: o mesmo brilho, para "magia aprendida" (-1), "evolução" (-2) e chegada de teletransporte (-3, sem texto)
	if level == -3:
		return
	var text: String = "NÍVEL %d!" % level if level > 0 else {-1: "MAGIA APRENDIDA!", -2: "EVOLUÇÃO!", -4: "MAESTRIA!", -5: "RENASCIMENTO!"}.get(level, "")
	floating_text(view.aim_point() + Vector3.UP * 1.2, text, gold, 1.6 if level != -1 else 1.3)


## Refino/forja: sucesso = explosão de luz dourada; falha = cinzas caindo;
## destruído = nuvem escura maior e o texto em vermelho.
func refine(view: Avatar, outcome: int, level: int) -> void:
	var at := view.aim_point() + Vector3.UP * 0.4
	match outcome:
		Protocol.FX_SUCCESS:
			var gold := Color(1.0, 0.85, 0.4)
			var burst := _particles(gold, GameConfig.get_i("vfx", "impact_particles") * 2, 0.8, true, "levelup")
			burst.direction = Vector3.UP
			burst.spread = 180.0
			burst.gravity = Vector3(0, -1.0, 0)
			burst.initial_velocity_min = 2.0
			burst.initial_velocity_max = 5.0
			burst.scale_amount_min = 0.2
			burst.scale_amount_max = 0.45
			_spawn_burst(burst, at)
			_flash(at, gold, 7.0, 7.0, 0.6)
			floating_text(at + Vector3.UP * 0.9, ("+%d!" % level) if level > 0 else "Sucesso!", gold, 1.7)
			if view.is_local:
				shake(0.18)
		Protocol.FX_FAIL, Protocol.FX_DESTROYED:
			var destroyed := outcome == Protocol.FX_DESTROYED
			var ash := _particles(Color(0.45, 0.42, 0.4), GameConfig.get_i("vfx", "impact_particles") * (3 if destroyed else 1), 1.4, true, "smoke")
			ash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			ash.emission_sphere_radius = 0.3
			ash.direction = Vector3.UP
			ash.spread = 60.0
			ash.gravity = Vector3(0, -2.5, 0)
			ash.initial_velocity_min = 0.5
			ash.initial_velocity_max = 2.0
			ash.scale_amount_min = 0.15
			ash.scale_amount_max = 0.35
			_spawn_burst(ash, at)
			_flash(at, Color(0.8, 0.15, 0.1), 3.0 if destroyed else 1.5, 4.0, 0.35)
			floating_text(at + Vector3.UP * 0.9, "Destruído!" if destroyed else "Falhou", Color(0.9, 0.2, 0.15), 1.5 if destroyed else 1.2)
			if view.is_local and destroyed:
				shake(0.3)


func damage_number(view: Avatar, amount: int, kind: int) -> void:
	var color: Color
	var size := 1.0
	if kind == Protocol.DMG_HEAL:
		var heal: Color = _dmg_colors.get("heal", Color.GREEN)
		floating_text(view.aim_point() + Vector3.UP * 0.6, "+%d" % amount, heal, 1.1)
		return
	if view.is_local:
		color = _dmg_colors.get("taken", Color.RED)
	elif kind == Protocol.DMG_EXCELLENT:
		color = _dmg_colors.get("excellent", Color.GREEN)
		size = 1.45
	elif kind == Protocol.DMG_CRITICAL:
		color = _dmg_colors.get("critical", Color.CYAN)
		size = 1.3
	else:
		color = _dmg_colors.get("normal", Color.WHITE)
	var jitter := Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	floating_text(view.aim_point() + Vector3.UP * 0.8 + jitter, str(amount), color, size)


func floating_text(at: Vector3, text: String, color: Color, size: float = 1.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.007 * size
	label.font_size = 56
	label.outline_size = 14
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.render_priority = 10
	label.outline_render_priority = 9
	add_child(label)
	label.global_position = at
	var t := create_tween().set_parallel(true)
	t.tween_property(label, "global_position", at + Vector3.UP * _rise, _text_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(label, "modulate:a", 0.0, _text_duration * 0.5).set_delay(_text_duration * 0.5)
	t.chain().tween_callback(label.queue_free)


func click_marker(at: Vector3) -> void:
	_click_marker.visible = true
	_click_marker.global_position = at + Vector3.UP * 0.03
	var mat := _click_marker.material_override as ShaderMaterial
	var set_intensity := func(v: float) -> void: mat.set_shader_parameter("intensity", v)
	var hide_marker := func() -> void: _click_marker.visible = false
	if _click_tween != null:
		_click_tween.kill()
	_click_tween = create_tween().set_parallel(true)
	_click_tween.tween_property(_click_marker, "scale", Vector3.ONE * 0.45, 0.45).from(Vector3.ONE * 1.1)
	_click_tween.tween_method(set_intensity, 1.6, 0.0, 0.45)
	_click_tween.chain().tween_callback(hide_marker)


## Tremida de câmera (somente para efeitos do próprio jogador).
func shake(amount: float) -> void:
	if camera_rig != null:
		camera_rig.shake(amount * _shake_scale)


# ---------------------------------------------------------------- utilitários

## `shape`: tipo em vfx.json -> particle_shapes (textura da Kenney); vazio ou sem textura = disco macio.
func _particles(color: Color, amount: int, lifetime: float, one_shot: bool, shape: String = "") -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(1, int(amount * _particle_scale))
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 0.9 if one_shot else 0.0
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.5
	quad.material = _shape_materials.get(shape, _particle_material)
	p.mesh = quad
	if _shape_materials.has(shape):
		quad.size = Vector2.ONE * 0.5 * _shape_size # a forma ocupa menos do quadrado que o disco macio
		p.angle_min = 0.0
		p.angle_max = 360.0 # cada partícula começa num ângulo (o shader gira a partir dele)
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.3))
	p.scale_amount_curve = curve
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _spawn_burst(p: CPUParticles3D, at: Vector3) -> void:
	add_child(p)
	p.global_position = at
	p.emitting = true
	_free_later(p, p.lifetime + 0.2)


func _flash(at: Vector3, color: Color, energy: float, light_range: float, duration: float) -> void:
	if not _lights:
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	add_child(light)
	light.global_position = at
	var t := create_tween()
	t.tween_property(light, "light_energy", 0.0, duration)
	t.tween_callback(light.queue_free)


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r * energy * 0.5, color.g * energy * 0.5, color.b * energy * 0.5)
	return m


func _make_rune_quad(color: Color, size: float) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	var mat := ShaderMaterial.new()
	mat.shader = RUNE_SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("intensity", 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _free_later(node: Node, seconds: float) -> void:
	var free_it := func() -> void:
		if is_instance_valid(node):
			node.queue_free()
	get_tree().create_timer(seconds).timeout.connect(free_it)
