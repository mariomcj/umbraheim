class_name LoginScene
extends Control
## Fundo vivo da tela de entrada (docs/design/PROPOSTA_AMBIENTACAO.md, seção 5), tudo em 2D e barato:
## arte-título com zoom lento e paralaxe, pulso da lua, relâmpago distante, fumaça no terço de baixo,
## brasas subindo, cinza caindo e vinheta. Na escolha de personagem a arte escurece e fumaça e brasas
## ganham a cor da classe (set_select_mode / set_tint). Valores em data/config/login_scene.json.

const ART_WIDE := preload("res://client/ui/art/umbraheim_title_wide.jpg")
const ART_TALL := preload("res://client/ui/art/umbraheim_title_tall.jpg")
const SMOKE_SHADER := preload("res://assets/shaders/ui_smoke.gdshader")

var _cfg: Dictionary
var _art: TextureRect
var _moon: TextureRect
var _flash: TextureRect
var _smokes: Array[ColorRect] = []
var _embers: CPUParticles2D
var _embers_violet: CPUParticles2D
var _ash: CPUParticles2D
var _vignette: TextureRect
var _base_rect := Rect2()
var _tall := false
var _t := 0.0
var _next_flash := 0.0
var _flash_times: Array[float] = []
var _select := false
var _tint_tween: Tween
var _ember_a := Color.WHITE
var _ember_b := Color.WHITE


func _ready() -> void:
	_cfg = GameConfig.section("login_scene")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.02, 0.05)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_moon = _additive_rect(_radial_texture(_col(_cfg["moon"]["color"]), 0.0))
	_art.add_child(_moon)
	_flash = _additive_rect(_vertical_texture(_col(_cfg["lightning"]["color"])))
	_flash.modulate.a = 0.0
	add_child(_flash)
	var sm: Dictionary = _cfg["smoke"]
	for i in 2:
		var r := ColorRect.new()
		var mat := ShaderMaterial.new()
		mat.shader = SMOKE_SHADER
		mat.set_shader_parameter("smoke_color", _col(sm["color"]))
		mat.set_shader_parameter("alpha", float(sm["alpha"]))
		mat.set_shader_parameter("scale", float(sm["scale"]) * (1.0 + i * 0.35))
		mat.set_shader_parameter("speed", float(sm["speed"]) * (1.0 if i == 0 else -1.3))
		mat.set_shader_parameter("seed", float(i) * 4.2)
		r.material = mat
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		_smokes.append(r)
	var em: Dictionary = _cfg["embers"]
	var violet_n := int(round(float(em["count"]) * float(em["violet_share"])))
	_embers = _make_embers(int(em["count"]) - violet_n, em, _col(em["colors"][0]), _col(em["colors"][1]))
	_embers_violet = _make_embers(maxi(1, violet_n), em, _col(em["violet"]), _col(em["violet"]).darkened(0.4))
	_ash = _make_ash(_cfg["ash"])
	var fade := TextureRect.new() # escurece a base, onde ficam os formulários
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0, 0, 0, 0.8))
	grad.set_offset(0, 0.6)
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0.5, 0.0)
	gtex.fill_to = Vector2(0.5, 1.0)
	fade.texture = gtex
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	_vignette = TextureRect.new()
	var vc := _col(_cfg["vignette"]["color"])
	_vignette.texture = _radial_texture(vc, float(_cfg["vignette"]["strength"]), true)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)
	resized.connect(_layout)
	_schedule_flash()
	_layout.call_deferred()


## Escolha de personagem: arte escurecida, fumaça mais forte; cor da classe em set_tint.
func set_select_mode(on: bool) -> void:
	_select = on
	var sel: Dictionary = _cfg["select"]
	var tw := create_tween().set_parallel()
	tw.tween_property(_art, "self_modulate", Color(1, 1, 1) * (float(sel["art_dim"]) if on else 1.0), float(sel["tint_s"]))
	for r in _smokes:
		var mat := r.material as ShaderMaterial
		tw.tween_method(func(a: float) -> void: mat.set_shader_parameter("alpha", a),
			float(mat.get_shader_parameter("alpha")), float(sel["smoke_alpha"]) if on else float(_cfg["smoke"]["alpha"]), float(sel["tint_s"]))
	if not on:
		set_tint(Color.TRANSPARENT)


## Cor da classe destacada na fumaça e nas brasas (TRANSPARENT = cores normais da cena).
func set_tint(color: Color) -> void:
	var dur := float(_cfg["select"]["tint_s"])
	var smoke_to := _col(_cfg["smoke"]["color"]) if color.a == 0.0 else color.darkened(0.55)
	var em: Dictionary = _cfg["embers"]
	var ember_a := _col(em["colors"][0]) if color.a == 0.0 else color.lightened(0.35)
	var ember_b := _col(em["colors"][1]) if color.a == 0.0 else color.darkened(0.3)
	if _tint_tween != null:
		_tint_tween.kill()
	_tint_tween = create_tween().set_parallel()
	for r in _smokes:
		var mat := r.material as ShaderMaterial
		var from: Color = mat.get_shader_parameter("smoke_color")
		_tint_tween.tween_method(func(c: Color) -> void: mat.set_shader_parameter("smoke_color", c), from, smoke_to, dur)
	var from_a := _ember_a
	var from_b := _ember_b
	_tint_tween.tween_method(func(k: float) -> void:
		_ember_a = from_a.lerp(ember_a, k)
		_ember_b = from_b.lerp(ember_b, k)
		_set_ramp(_embers.color_ramp, _ember_a, _ember_b), 0.0, 1.0, dur)


func _process(delta: float) -> void:
	_t += delta
	var art: Dictionary = _cfg["art"]
	# zoom de ida e volta (seno) e paralaxe leve com o mouse
	var k := 0.5 - 0.5 * cos(TAU * _t / float(art["ken_burns_s"]))
	var zoom := lerpf(1.0, float(art["ken_burns_zoom"]), k)
	var mouse := get_local_mouse_position() / maxf(1.0, size.x) - Vector2(0.5, 0.5)
	var par := -mouse * float(art["parallax_px"])
	var sz := _base_rect.size * zoom
	_art.position = _base_rect.position - (sz - _base_rect.size) * 0.5 + par
	_art.size = sz
	var moon: Dictionary = _cfg["moon"]
	var pulse := 0.5 - 0.5 * cos(TAU * _t / float(moon["period_s"]))
	_moon.modulate.a = lerpf(float(moon["alpha_min"]), float(moon["alpha_max"]), pulse)
	if _t >= _next_flash:
		_lightning()
		_schedule_flash()


func _layout() -> void:
	var v := size
	if v.x <= 0.0 or v.y <= 0.0:
		return
	var aspect := v.x / v.y
	_tall = aspect < 0.95
	_art.texture = ART_TALL if _tall else ART_WIDE
	var tex := Vector2(_art.texture.get_size())
	# tela mais estreita que 16:10 (4:3, janela do navegador): a arte inteira na largura, sem cortar o nome
	var fit := aspect >= 0.95 and aspect < 1.6
	var s := minf(v.x / tex.x, v.y / tex.y) if fit else maxf(v.x / tex.x, v.y / tex.y)
	var sz := tex * s
	_base_rect = Rect2((v - sz) * 0.5, sz)
	if fit: # a arte inteira cabe: fica no alto, deixando espaço embaixo para o formulário
		_base_rect.position.y = minf(_base_rect.position.y, 0.0)
	var m: Dictionary = _cfg["moon"]["tall" if _tall else "wide"]
	var uv := Vector2(float(m["uv"][0]), float(m["uv"][1]))
	var r := float(m["radius"])
	_moon.anchor_left = uv.x - r
	_moon.anchor_right = uv.x + r
	_moon.anchor_top = uv.y - r * sz.x / sz.y
	_moon.anchor_bottom = uv.y + r * sz.x / sz.y
	_flash.position = Vector2.ZERO
	_flash.size = Vector2(v.x, v.y * 0.4)
	var h := v.y * float(_cfg["smoke"]["height"])
	for i in _smokes.size():
		_smokes[i].position = Vector2(0, v.y - h * (1.0 - i * 0.2))
		_smokes[i].size = Vector2(v.x, h * (1.0 - i * 0.2))
	for p: CPUParticles2D in [_embers, _embers_violet]:
		p.position = Vector2(v.x * 0.5, v.y + 6.0)
		p.emission_rect_extents = Vector2(v.x * 0.5, 4.0)
	_ash.position = Vector2(v.x * 0.4, -10.0)
	_ash.emission_rect_extents = Vector2(v.x * 0.7, 4.0)
	_process(0.0)


func _schedule_flash() -> void:
	var lt: Dictionary = _cfg["lightning"]
	var min_gap := maxf(float(lt["min_s"]), 60.0 / maxf(1.0, float(lt["max_per_min"])))
	_next_flash = _t + randf_range(min_gap, maxf(min_gap, float(lt["max_s"])))


## Clarão violeta no terço de cima, com um segundo mais fraco logo depois.
func _lightning() -> void:
	var lt: Dictionary = _cfg["lightning"]
	var cutoff := _t - 60.0
	_flash_times = _flash_times.filter(func(x: float) -> bool: return x > cutoff)
	if _flash_times.size() >= int(lt["max_per_min"]):
		return
	_flash_times.append(_t)
	var d := float(lt["flash_s"])
	var tw := create_tween()
	tw.tween_property(_flash, "modulate:a", float(lt["strength"]), d * 0.3)
	tw.tween_property(_flash, "modulate:a", 0.0, d * 0.7)
	tw.tween_interval(float(lt["second_delay_s"]))
	tw.tween_property(_flash, "modulate:a", float(lt["second_strength"]), d * 0.3)
	tw.tween_property(_flash, "modulate:a", 0.0, d)


func _make_embers(count: int, em: Dictionary, c0: Color, c1: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = maxi(1, count)
	p.lifetime = float(em["lifetime_s"])
	p.preprocess = p.lifetime
	p.texture = _dot_texture()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0, -1)
	p.spread = 12.0
	p.gravity = Vector2(0, -4.0)
	p.initial_velocity_min = float(em["speed"][0])
	p.initial_velocity_max = float(em["speed"][1])
	p.scale_amount_min = float(em["size_px"][0]) / 16.0
	p.scale_amount_max = float(em["size_px"][1]) / 16.0
	# ziguezague lento: aceleração tangencial que troca de sinal pelo sorteio
	p.tangential_accel_min = -float(em["sway_px"]) * 0.2
	p.tangential_accel_max = float(em["sway_px"]) * 0.2
	var ramp := Gradient.new()
	_set_ramp(ramp, c0, c1)
	p.color_ramp = ramp
	if _ember_a == Color.WHITE:
		_ember_a = c0
		_ember_b = c1
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	add_child(p)
	return p


## Brasa: entra, cor a, cor b, some (arrays inteiros: a ordem dos pontos não muda).
static func _set_ramp(ramp: Gradient, a: Color, b: Color) -> void:
	ramp.offsets = PackedFloat32Array([0.0, 0.1, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(a, 0.0), Color(a, 0.95), Color(b, 0.85), Color(b, 0.0)])


func _make_ash(a: Dictionary) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = int(a["count"])
	p.lifetime = float(a["lifetime_s"])
	p.preprocess = p.lifetime
	p.texture = _dot_texture()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0.45, 1.0)
	p.spread = 10.0
	p.gravity = Vector2(1.0, 2.0)
	p.initial_velocity_min = float(a["speed"][0])
	p.initial_velocity_max = float(a["speed"][1])
	p.scale_amount_min = float(a["size_px"][0]) / 16.0
	p.scale_amount_max = float(a["size_px"][1]) / 16.0
	var c := _col(a["color"])
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.85, 1.0])
	ramp.colors = PackedColorArray([Color(c, 0.0), Color(c, float(a["alpha"])), Color(c, float(a["alpha"])), Color(c, 0.0)])
	p.color_ramp = ramp
	add_child(p)
	return p


func _additive_rect(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	r.material = mat
	return r


static var _dot: Texture2D


static func _dot_texture() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 16
		t.height = 16
		_dot = t
	return _dot


## Radial: brilho no centro (lua) ou, com edge = true, transparente no centro e cor nas bordas (vinheta).
static func _radial_texture(color: Color, strength: float, edge: bool = false) -> Texture2D:
	var g := Gradient.new()
	if edge:
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(color, 0.0), Color(color, 0.0), Color(color, strength)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(color, 1.0), Color(color, 0.35), Color(color, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 1.0) if edge else Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	return t


static func _vertical_texture(color: Color) -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(color, 1.0))
	g.set_color(1, Color(color, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	t.width = 8
	t.height = 128
	return t


static func _col(v: Variant) -> Color:
	return Color.html(str(v)) if v is String and Color.html_is_valid(str(v)) else Color.WHITE
