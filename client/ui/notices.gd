class_name Notices
extends Control
## Avisos da tela (docs/design/PROPOSTA_UI.md 3.6), atrás das barras da HUD:
## - placa de evento no topo (título em Cinzel âmbar, separador com losango, entrada animada);
## - título de área (Cinzel grande, sem placa, só contorno e sombra larga);
## - toasts à direita, acima da lista de eventos (losango + texto, somem sozinhos);
## - tela de morte (escurece, vinheta vermelha, "VOCÊ CAIU" e o cronômetro de retorno).
## Tempos e tamanhos em ui.json -> theme.notices.

var _cfg: Dictionary
var _event_plate: PanelContainer
var _event_title: Label
var _event_sub: Label
var _event_tween: Tween
var _area_box: VBoxContainer
var _area_title: Label
var _area_sub: Label
var _area_born: int = -100000
var _toasts: VBoxContainer
var _death: Control
var _death_timer: Label
var _dead: bool = false


func _ready() -> void:
	_cfg = UiPalette.theme_cfg().get("notices", {})
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_death()
	_build_area()
	_build_event()
	_build_toasts()


# ---------------------------------------------------------------- API

## Título de área ao entrar numa região ou zona.
func show_area(title: String, subtitle: String) -> void:
	_area_title.text = title
	_area_sub.text = subtitle
	_area_sub.visible = subtitle != ""
	_area_born = Time.get_ticks_msec()


## Aviso de evento (anúncios do servidor, portões que abrem).
func show_event(title: String, subtitle: String) -> void:
	_event_title.text = title
	_event_sub.text = subtitle
	_event_sub.visible = subtitle != ""
	_event_plate.visible = true
	_event_plate.reset_size()
	_event_plate.position.x = (size.x - _event_plate.size.x) * 0.5
	_event_plate.pivot_offset = _event_plate.size * 0.5
	if _event_tween != null:
		_event_tween.kill()
	_event_plate.scale = Vector2.ONE * 0.9
	_event_plate.modulate.a = 0.0
	_event_tween = create_tween()
	_event_tween.set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_event_tween.tween_property(_event_plate, "scale", Vector2.ONE, 0.3)
	_event_tween.tween_property(_event_plate, "modulate:a", 1.0, 0.2)
	_event_tween.chain().tween_interval(float(_cfg.get("event_s", 4.5)))
	_event_tween.chain().tween_property(_event_plate, "modulate:a", 0.0, 0.8)
	_event_tween.chain().tween_callback(_event_plate.hide)


## Toast com losango (glyph = inicial ou símbolo; accent = cor do losango).
func show_toast(text: String, glyph: String, accent: Color) -> void:
	var row := PanelContainer.new()
	row.theme_type_variation = &"WellPanel"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	row.add_child(box)
	var icon := DiamondButton.new()
	icon.glyph = glyph
	icon.accent = accent
	icon.selected = true
	icon.glyph_font = "body_bold"
	icon.custom_minimum_size = Vector2(32, 32)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", UiPalette.size("hint") + 2)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(l)
	_toasts.add_child(row)
	while _toasts.get_child_count() > int(_cfg.get("toast_max", 4)):
		_toasts.get_child(0).free()
	row.modulate.a = 0.0
	var tw := row.create_tween()
	tw.tween_property(row, "modulate:a", 1.0, 0.2)
	tw.tween_interval(float(_cfg.get("toast_s", 4.0)))
	tw.tween_property(row, "modulate:a", 0.0, 0.6)
	tw.tween_callback(row.queue_free)


## Estado de vida do jogador (PS): mostra ou esconde a tela de morte.
func set_death(alive: bool, respawn_ms: int) -> void:
	if not alive:
		_death_timer.text = "de volta ao Refúgio em %d s" % ceili(respawn_ms / 1000.0)
	if alive == not _dead:
		return
	_dead = not alive
	var tw := _death.create_tween()
	if _dead:
		_death.visible = true
		tw.tween_property(_death, "modulate:a", 1.0, float(_cfg.get("death_fade_s", 0.8)))
	else:
		tw.tween_property(_death, "modulate:a", 0.0, 0.3)
		tw.tween_callback(_death.hide)


func _process(_delta: float) -> void:
	var age := (Time.get_ticks_msec() - _area_born) / 1000.0
	var hold := float(_cfg.get("area_s", 3.0))
	_area_box.modulate.a = clampf(minf(age / 0.4, 1.0 - (age - hold) / 1.2), 0.0, 1.0)
	# com a placa de evento na tela, o título de área desce para baixo dela
	var top := float(_cfg.get("area_top_px", 130))
	if _event_plate.visible:
		top = maxf(top, _event_plate.position.y + _event_plate.size.y + 12.0)
	_area_box.offset_top = top


# ---------------------------------------------------------------- construção

func _build_death() -> void:
	_death = Control.new()
	_death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.modulate.a = 0.0
	_death.visible = false
	add_child(_death)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UiPalette.c("ink", float(_cfg.get("death_dim", 0.45)))
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.add_child(dim)
	var vignette := TextureRect.new() # vinheta vermelha: transparente no centro, sangue nas bordas
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(UiPalette.c("blood").darkened(0.5), 0.0),
		Color(UiPalette.c("blood").darkened(0.5), float(_cfg.get("death_vignette", 0.75)))])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.15, 0.5)
	gt.width = 256
	gt.height = 256
	vignette.texture = gt
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.add_child(vignette)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.add_child(box)
	var title := Label.new()
	title.text = "VOCÊ CAIU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UiPalette.font("title"))
	title.add_theme_font_size_override("font_size", int(_cfg.get("death_px", 52)))
	title.add_theme_color_override("font_color", UiPalette.c("blood").lightened(0.15))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	box.add_child(title)
	_death_timer = Label.new()
	_death_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_timer.add_theme_font_size_override("font_size", UiPalette.size("strong"))
	_death_timer.add_theme_constant_override("outline_size", 6)
	_death_timer.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	box.add_child(_death_timer)


func _build_area() -> void:
	_area_box = VBoxContainer.new()
	_area_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_area_box.offset_top = float(_cfg.get("area_top_px", 130))
	_area_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_area_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area_box.add_theme_constant_override("separation", 2)
	_area_box.modulate.a = 0.0
	add_child(_area_box)
	_area_title = _big_label(UiPalette.size("area"), UiPalette.c("gold"))
	_area_box.add_child(_area_title)
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(260, 10)
	sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area_box.add_child(sep)
	_area_sub = Label.new()
	_area_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_area_sub.add_theme_font_size_override("font_size", UiPalette.size("strong"))
	_area_sub.add_theme_constant_override("outline_size", 6)
	_area_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_area_box.add_child(_area_sub)


func _build_event() -> void:
	_event_plate = PanelContainer.new()
	_event_plate.theme_type_variation = &"WindowPanel"
	_event_plate.set_meta("no_window_fx", true) # aviso, não janela: sem arrastar nem som de abrir
	_event_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_event_plate.position.y = float(_cfg.get("event_top_px", 74))
	_event_plate.visible = false
	add_child(_event_plate)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size = Vector2(float(_cfg.get("event_min_w_px", 420)), 0)
	_event_plate.add_child(box)
	_event_title = _big_label(int(_cfg.get("event_px", 28)), UiPalette.c("ember"))
	box.add_child(_event_title)
	box.add_child(HSeparator.new()) # o separador do tema já tem o losango no meio
	_event_sub = Label.new()
	_event_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_sub.add_theme_font_size_override("font_size", UiPalette.size("strong"))
	box.add_child(_event_sub)


func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 1.0
	_toasts.anchor_right = 1.0
	_toasts.offset_left = -300.0
	_toasts.offset_right = -14.0
	_toasts.offset_bottom = float(_cfg.get("toast_bottom_px", 284))
	_toasts.offset_top = _toasts.offset_bottom - 260.0
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.add_theme_constant_override("separation", 4)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)


static func _big_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiPalette.font("title"))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55)) # sombra larga
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.add_theme_constant_override("shadow_outline_size", 18)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
