class_name UiThemeBuilder
## Monta o Theme único da interface a partir de data/config/ui.json -> theme ("relicário de ferro negro",
## docs/design/PROPOSTA_UI.md). As texturas das molduras (placa, poço, botões, losangos, separador)
## são geradas aqui por código, sem arte externa; o cliente aplica o tema na janela raiz.
##
## Variações de tipo (theme_type_variation): WindowPanel, WellPanel, PrimaryButton, DangerButton,
## GhostButton, CloseButton, TitleLabel, HeaderLabel, HintLabel, LoreLabel, ValueLabel.


## Aplica o tema a toda a interface: mescla no tema padrão da Godot (o tema da janela raiz não chega
## aos controles dentro de CanvasLayer) e troca a fonte de reserva, usada nos desenhos feitos à mão.
static func install() -> void:
	var t := build()
	var target := ThemeDB.get_default_theme()
	target.merge_with(t)
	target.default_font = t.default_font
	target.default_font_size = t.default_font_size
	ThemeDB.fallback_font = t.default_font
	ThemeDB.fallback_font_size = t.default_font_size


static func build() -> Theme:
	var cfg := UiPalette.theme_cfg()
	var fr: Dictionary = cfg["frame"]
	var t := Theme.new()
	t.default_font = UiPalette.font("body")
	t.default_font_size = UiPalette.size("text")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(fr.get("seed", 7))
	var noise := float(fr.get("noise_strength", 0.05))

	# ---- painéis
	var win_px := int(fr["window_tex_px"])
	var window := _texbox(_plate_image(win_px, rng, noise), int(fr["window_margin_px"]), int(fr["window_content_px"]))
	var well := _texbox(_well_image(int(fr["well_tex_px"]), rng, noise), int(fr["well_margin_px"]), int(fr["well_margin_px"]))
	t.set_stylebox("panel", "PanelContainer", window)
	t.set_stylebox("panel", "Panel", window)
	t.set_type_variation("WindowPanel", "PanelContainer")
	t.set_stylebox("panel", "WindowPanel", window)
	t.set_type_variation("WellPanel", "PanelContainer")
	t.set_stylebox("panel", "WellPanel", well)
	t.set_type_variation("ParchmentPanel", "PanelContainer") # missões: o papel do diário
	t.set_stylebox("panel", "ParchmentPanel", _texbox(_paper_image(win_px * 2, rng), int(fr["window_margin_px"]) + 6, int(fr["window_content_px"]) + 6))
	t.set_stylebox("panel", "TooltipPanel", _texbox(_plate_image(win_px, rng, noise), int(fr["window_margin_px"]), 8))
	t.set_color("font_color", "TooltipLabel", UiPalette.c("bone"))
	t.set_font_size("font_size", "TooltipLabel", UiPalette.size("text"))

	# ---- botões
	var bpx := int(fr["button_tex_px"])
	var bm := int(fr["button_margin_px"])
	var pad := Vector2(float(fr["button_pad_x"]), float(fr["button_pad_y"]))
	_button_type(t, "Button", bpx, bm, pad, UiPalette.c("gold_dim"), UiPalette.c("gold"), Color(0, 0, 0, 0), rng, noise)
	t.set_type_variation("PrimaryButton", "Button")
	_button_type(t, "PrimaryButton", bpx, bm, pad, UiPalette.c("ember", 0.8), UiPalette.c("ember"), UiPalette.c("ember", 0.18), rng, noise)
	t.set_type_variation("DangerButton", "Button")
	_button_type(t, "DangerButton", bpx, bm, pad, UiPalette.c("blood", 0.7), UiPalette.c("blood"), UiPalette.c("blood", 0.15), rng, noise)
	t.set_type_variation("GhostButton", "Button")
	var ghost := StyleBoxFlat.new()
	ghost.bg_color = Color(0, 0, 0, 0)
	ghost.set_content_margin_all(4)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(st, "GhostButton", ghost)
	# fechar: losango com "×" (UiFx troca os botões "×" das janelas para esta variação)
	t.set_type_variation("CloseButton", "Button")
	var cpx := int(fr.get("close_px", 24))
	var close_states := {
		"normal": [UiPalette.c("gold_dim"), UiPalette.c("ink", 0.9)],
		"hover": [UiPalette.c("gold"), UiPalette.c("ember", 0.35)],
		"pressed": [UiPalette.c("gold"), UiPalette.c("blood", 0.45)],
	}
	for st: String in close_states:
		var sb := StyleBoxTexture.new()
		sb.texture = _diamond_texture(cpx, close_states[st][0], false, close_states[st][1])
		sb.content_margin_left = cpx * 0.3
		sb.content_margin_right = cpx * 0.3
		sb.content_margin_top = 0
		sb.content_margin_bottom = 2
		t.set_stylebox(st, "CloseButton", sb)
		if st == "pressed":
			t.set_stylebox("hover_pressed", "CloseButton", sb)
	t.set_stylebox("focus", "CloseButton", StyleBoxEmpty.new())
	t.set_font_size("font_size", "CloseButton", 15)
	for type in ["Button", "PrimaryButton", "DangerButton", "GhostButton", "CloseButton"]:
		t.set_color("font_color", type, UiPalette.c("bone"))
		t.set_color("font_hover_color", type, Color(1.0, 0.95, 0.85))
		t.set_color("font_pressed_color", type, UiPalette.c("gold"))
		t.set_color("font_focus_color", type, UiPalette.c("bone"))
		t.set_color("font_disabled_color", type, UiPalette.c("bone_dim", 0.6))
		t.set_font("font", type, UiPalette.font("body_medium"))
	t.set_font("font", "PrimaryButton", UiPalette.font("title"))
	t.set_color("font_color", "GhostButton", UiPalette.c("bone_dim"))
	t.set_color("font_hover_color", "GhostButton", UiPalette.c("gold"))

	# ---- caixas de seleção e opções: losangos
	var dsize := 16
	for type in ["CheckBox", "CheckButton"]:
		t.set_icon("checked", type, _diamond_texture(dsize, UiPalette.c("gold"), true))
		t.set_icon("unchecked", type, _diamond_texture(dsize, UiPalette.c("gold_dim"), false))
		t.set_icon("radio_checked", type, _diamond_texture(dsize, UiPalette.c("gold"), true))
		t.set_icon("radio_unchecked", type, _diamond_texture(dsize, UiPalette.c("gold_dim"), false))
		t.set_icon("checked_disabled", type, _diamond_texture(dsize, UiPalette.c("bone_dim", 0.5), true))
		t.set_icon("unchecked_disabled", type, _diamond_texture(dsize, UiPalette.c("bone_dim", 0.4), false))
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(3)
		for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			t.set_stylebox(st, type, empty)
		t.set_color("font_color", type, UiPalette.c("bone"))
		t.set_color("font_hover_color", type, Color(1.0, 0.95, 0.85))
		t.set_color("font_pressed_color", type, UiPalette.c("gold"))
		t.set_color("font_hover_pressed_color", type, UiPalette.c("gold"))

	# ---- campos de texto: fundo tinta e filete inferior que acende no foco
	var edit := StyleBoxFlat.new()
	edit.bg_color = UiPalette.c("ink", 0.9)
	edit.border_color = UiPalette.c("gold_dim")
	edit.border_width_bottom = 1
	edit.content_margin_left = 8
	edit.content_margin_right = 8
	edit.content_margin_top = 5
	edit.content_margin_bottom = 5
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = UiPalette.c("gold")
	edit_focus.border_width_bottom = 2
	edit_focus.bg_color = Color(0.06, 0.05, 0.05, 0.95)
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, edit)
		t.set_stylebox("focus", type, edit_focus)
		t.set_stylebox("read_only", type, edit)
		t.set_color("font_color", type, UiPalette.c("bone"))
		t.set_color("font_placeholder_color", type, UiPalette.c("bone_dim", 0.7))
		t.set_color("caret_color", type, UiPalette.c("gold"))
		t.set_color("selection_color", type, UiPalette.c("gold", 0.3))

	# ---- rótulos
	t.set_color("font_color", "Label", UiPalette.c("bone"))
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	_label_variation(t, "TitleLabel", "title", UiPalette.size("window_title"), UiPalette.c("gold"))
	_label_variation(t, "HeaderLabel", "title", UiPalette.size("header"), UiPalette.c("gold"))
	_label_variation(t, "HintLabel", "body", UiPalette.size("hint"), UiPalette.c("bone_dim"))
	_label_variation(t, "LoreLabel", "lore_italic", UiPalette.size("text"), UiPalette.c("bone_dim"))
	_label_variation(t, "ValueLabel", "body_bold", UiPalette.size("text"), UiPalette.c("gold"))
	_label_variation(t, "InkLabel", "lore", UiPalette.size("text"), UiPalette.c("paper_ink")) # texto no pergaminho
	_label_variation(t, "InkTitle", "lore", UiPalette.size("header"), UiPalette.c("paper_red"))
	for ink in ["InkLabel", "InkTitle"]:
		t.set_constant("outline_size", ink, 0)
	t.set_color("default_color", "RichTextLabel", UiPalette.c("bone"))
	t.set_font("normal_font", "RichTextLabel", UiPalette.font("body"))
	t.set_font("bold_font", "RichTextLabel", UiPalette.font("body_bold"))
	t.set_font("italics_font", "RichTextLabel", UiPalette.font("body_italic"))

	# ---- separadores com losango no meio
	var sep := StyleBoxTexture.new()
	sep.texture = _separator_texture(96, 9)
	sep.texture_margin_left = 44
	sep.texture_margin_right = 44
	sep.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sep.content_margin_top = 4
	sep.content_margin_bottom = 4
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 10)

	# ---- barras de rolagem e de progresso
	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = UiPalette.c("well", 0.6)
	scroll_bg.set_content_margin_all(2)
	var grab := StyleBoxFlat.new()
	grab.bg_color = UiPalette.c("gold_dim", 0.8)
	grab.set_corner_radius_all(1)
	grab.content_margin_left = 3
	grab.content_margin_right = 3
	var grab_hi := grab.duplicate() as StyleBoxFlat
	grab_hi.bg_color = UiPalette.c("gold")
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, scroll_bg)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab_hi)
		t.set_stylebox("grabber_pressed", type, grab_hi)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = UiPalette.c("well", 0.9)
	bar_bg.border_color = UiPalette.c("iron_edge")
	bar_bg.set_border_width_all(1)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = UiPalette.c("gold")
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", UiPalette.c("bone"))

	# ---- abas
	var tab_sel := StyleBoxFlat.new()
	tab_sel.bg_color = UiPalette.c("iron_top")
	tab_sel.border_color = UiPalette.c("gold")
	tab_sel.border_width_bottom = 2
	tab_sel.set_content_margin_all(6)
	tab_sel.content_margin_left = 12
	tab_sel.content_margin_right = 12
	var tab_un := tab_sel.duplicate() as StyleBoxFlat
	tab_un.bg_color = UiPalette.c("ink", 0.8)
	tab_un.border_color = UiPalette.c("gold_dim", 0.5)
	tab_un.border_width_bottom = 1
	var tab_hover := tab_un.duplicate() as StyleBoxFlat
	tab_hover.border_color = UiPalette.c("ember")
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, tab_sel)
		t.set_stylebox("tab_unselected", type, tab_un)
		t.set_stylebox("tab_hovered", type, tab_hover)
		t.set_color("font_selected_color", type, UiPalette.c("gold"))
		t.set_color("font_unselected_color", type, UiPalette.c("bone_dim"))
		t.set_color("font_hovered_color", type, UiPalette.c("bone"))
		t.set_font("font", type, UiPalette.font("title"))
		t.set_font_size("font_size", type, UiPalette.size("hint") + 1)
	t.set_stylebox("panel", "TabContainer", well)

	# ---- listas e menus
	t.set_stylebox("panel", "ItemList", well)
	t.set_color("font_color", "ItemList", UiPalette.c("bone"))
	t.set_color("font_selected_color", "ItemList", UiPalette.c("gold"))
	t.set_stylebox("panel", "PopupMenu", window)
	t.set_color("font_color", "PopupMenu", UiPalette.c("bone"))
	t.set_color("font_hover_color", "PopupMenu", UiPalette.c("gold"))
	t.set_stylebox("panel", "OptionButton", window)
	return t


# ------------------------------------------------------------------ helpers de tipo

static func _label_variation(t: Theme, type: String, font_role: String, font_size: int, color: Color) -> void:
	t.set_type_variation(type, "Label")
	t.set_font("font", type, UiPalette.font(font_role))
	t.set_font_size("font_size", type, font_size)
	t.set_color("font_color", type, color)


static func _button_type(t: Theme, type: String, px: int, margin: int, pad: Vector2, edge: Color, edge_hover: Color,
		glow: Color, rng: RandomNumberGenerator, noise: float) -> void:
	var normal := _button_box(_button_image(px, edge, glow, false, rng, noise), margin, pad)
	var hover_glow := UiPalette.c("ember", 0.22) if glow.a == 0.0 else Color(glow, glow.a * 1.8)
	var hover := _button_box(_button_image(px, edge_hover, hover_glow, false, rng, noise), margin, pad)
	var pressed := _button_box(_button_image(px, edge_hover, glow, true, rng, noise), margin, pad)
	pressed.content_margin_top += 1
	pressed.content_margin_bottom -= 1
	var disabled := _button_box(_button_image(px, Color(edge, 0.35), Color(0, 0, 0, 0), false, rng, noise), margin, pad)
	disabled.modulate_color = Color(1, 1, 1, 0.55)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = UiPalette.c("gold", 0.6)
	focus.set_border_width_all(1)
	focus.set_expand_margin_all(2)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, focus)


static func _texbox(img: Image, margin: int, content: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(content)
	return sb


static func _button_box(img: Image, margin: int, pad: Vector2) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.set_texture_margin_all(margin)
	sb.content_margin_left = pad.x
	sb.content_margin_right = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_bottom = pad.y
	return sb


# ------------------------------------------------------------------ imagens geradas

## Placa de ferro escuro: gradiente, grão, filete externo, filete dourado interno e losangos nos cantos.
static func _plate_image(px: int, rng: RandomNumberGenerator, noise: float) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var top := UiPalette.c("iron_top", 0.96)
	var bottom := UiPalette.c("iron_bottom", 0.96)
	for y in px:
		var base := top.lerp(bottom, float(y) / float(px - 1))
		for x in px:
			var n := (rng.randf() - 0.5) * noise
			img.set_pixel(x, y, Color(base.r + n, base.g + n, base.b + n, base.a))
	_rect_outline(img, 0, UiPalette.c("iron_edge"))
	_rect_outline(img, 3, UiPalette.c("gold", 0.35))
	var d := int(UiPalette.theme_cfg()["frame"].get("diamond_px", 5))
	for corner in [Vector2i(3, 3), Vector2i(px - 4, 3), Vector2i(3, px - 4), Vector2i(px - 4, px - 4)]:
		_diamond(img, corner, d, UiPalette.c("gold"), true)
	return img


## Pergaminho: papel claro com manchas suaves e borda queimada (escurece para as bordas).
static func _paper_image(px: int, rng: RandomNumberGenerator) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var paper := UiPalette.c("paper")
	var edge := UiPalette.c("paper_edge")
	var fnl := FastNoiseLite.new()
	fnl.seed = rng.randi()
	fnl.frequency = 0.08
	for y in px:
		for x in px:
			var d := minf(minf(x, px - 1 - x), minf(y, px - 1 - y)) / (px * 0.5) # 0 na borda, 1 no meio
			var burn := 1.0 - smoothstep(0.0, 0.28, d + fnl.get_noise_2d(x * 3.0, y * 3.0) * 0.06)
			var stain := fnl.get_noise_2d(x, y) * 0.06 + (rng.randf() - 0.5) * 0.03
			var col := paper.lerp(edge, burn * 0.85)
			img.set_pixel(x, y, Color(col.r + stain, col.g + stain, col.b + stain * 0.8, 1.0))
	_rect_outline(img, 0, edge.darkened(0.4))
	return img


## Poço: fundo mais escuro com sombra interna (borda de cima escura, de baixo clara).
static func _well_image(px: int, rng: RandomNumberGenerator, noise: float) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var base := UiPalette.c("well", 0.92)
	for y in px:
		for x in px:
			var n := (rng.randf() - 0.5) * noise * 0.6
			var shade := 0.0
			if y < 3:
				shade = -0.04 * float(3 - y)
			img.set_pixel(x, y, Color(base.r + n + shade, base.g + n + shade, base.b + n + shade, base.a))
	_rect_outline(img, 0, UiPalette.c("iron_edge", 0.9))
	for x in range(1, px - 1):
		img.set_pixel(x, px - 2, UiPalette.c("gold_dim", 0.25))
	return img


## Botão: placa com cantos chanfrados, filete na cor do estado e brilho interno opcional.
static func _button_image(px: int, edge: Color, glow: Color, pressed: bool, rng: RandomNumberGenerator, noise: float) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var top := UiPalette.c("iron_top", 0.97)
	var bottom := UiPalette.c("iron_bottom", 0.97)
	if pressed:
		var swap := top
		top = bottom
		bottom = swap
	var chamfer := 3
	for y in px:
		var base := top.lerp(bottom, float(y) / float(px - 1))
		for x in px:
			if _outside_chamfer(x, y, px, chamfer):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var n := (rng.randf() - 0.5) * noise
			var col := Color(base.r + n, base.g + n, base.b + n, base.a)
			if glow.a > 0.0:
				# brilho mais forte perto das bordas, por dentro
				var edge_dist := mini(mini(x, px - 1 - x), mini(y, px - 1 - y))
				var k := clampf(1.0 - float(edge_dist) / (px * 0.45), 0.0, 1.0)
				col = col.lerp(Color(glow, 1.0), glow.a * k)
			img.set_pixel(x, y, col)
	# filete na borda chanfrada
	for y in px:
		for x in px:
			if _outside_chamfer(x, y, px, chamfer):
				continue
			var on_edge := x == 0 or y == 0 or x == px - 1 or y == px - 1
			on_edge = on_edge or _outside_chamfer(x - 1, y - 1, px, chamfer) or _outside_chamfer(x + 1, y + 1, px, chamfer)
			on_edge = on_edge or _outside_chamfer(x + 1, y - 1, px, chamfer) or _outside_chamfer(x - 1, y + 1, px, chamfer)
			if on_edge:
				img.set_pixel(x, y, edge)
	if not pressed:
		for x in range(chamfer + 1, px - chamfer - 1):
			img.set_pixel(x, 1, Color(1, 1, 1, 0.07)) # "luz" no topo
	return img


static func _outside_chamfer(x: int, y: int, px: int, c: int) -> bool:
	if x < 0 or y < 0 or x >= px or y >= px:
		return true
	return x + y < c or (px - 1 - x) + y < c or x + (px - 1 - y) < c or (px - 1 - x) + (px - 1 - y) < c


static func _rect_outline(img: Image, inset: int, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for x in range(inset, w - inset):
		_blend(img, x, inset, color)
		_blend(img, x, h - 1 - inset, color)
	for y in range(inset + 1, h - 1 - inset):
		_blend(img, inset, y, color)
		_blend(img, w - 1 - inset, y, color)


static func _diamond(img: Image, center: Vector2i, r: int, color: Color, filled: bool) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var dist := absi(dx) + absi(dy)
			if dist > r or (not filled and dist < r - 1):
				continue
			var x := center.x + dx
			var y := center.y + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				_blend(img, x, y, color)


static func _blend(img: Image, x: int, y: int, color: Color) -> void:
	img.set_pixel(x, y, img.get_pixel(x, y).blend(color))


static func _diamond_texture(px: int, color: Color, filled: bool, inner: Color = Color.TRANSPARENT) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mid := px / 2
	_diamond(img, Vector2i(mid, mid), mid - 2, Color(color, 0.25) if inner.a == 0.0 else inner, true)
	_diamond(img, Vector2i(mid, mid), mid - 1, color, false)
	if filled:
		_diamond(img, Vector2i(mid, mid), mid - 4, color, true)
	return ImageTexture.create_from_image(img)


## Separador: linha dourada que esmaece nas pontas, com um losango no meio.
static func _separator_texture(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mid_y := h / 2
	for x in w:
		var k := 1.0 - absf(float(x) - w * 0.5) / (w * 0.5)
		img.set_pixel(x, mid_y, UiPalette.c("gold", 0.15 + 0.5 * k))
	_diamond(img, Vector2i(w / 2, mid_y), 3, UiPalette.c("gold"), true)
	return ImageTexture.create_from_image(img)
