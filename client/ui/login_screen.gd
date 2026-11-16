class_name LoginScreen
extends CanvasLayer
## Tela de entrada: conectar -> conta (entrar ou criar) -> escolher/criar personagem
## (docs/design/PROPOSTA_UI.md 3.1). Fundo: LoginScene (arte-título viva). A escolha ocupa a tela:
## atributos e descrição da classe à esquerda, o modelo 3D da classe no centro, os personagens como
## cartões à direita; no modo criar, setas trocam a classe e a cor do fundo. Só a última conta usada
## fica guardada (user://client.cfg); a senha nunca é salva.

signal entering(account: String, password: String, character_name: String)

var GOLD: Color = UiPalette.c("gold")
var PARCHMENT: Color = UiPalette.c("bone")
var DIM: Color = UiPalette.c("bone_dim")
const SETTINGS_PATH := "user://client.cfg"
const STAT_KEYS: PackedStringArray = ["str", "agi", "vit", "ene"]
const STAT_NAMES: PackedStringArray = ["Força", "Agilidade", "Vitalidade", "Energia"]

var _scene: LoginScene
var _panel: PanelContainer
var _status: Label
var _spinner: Control
var _login_box: VBoxContainer
var _account: LineEdit
var _password: LineEdit
var _select_root: Control
var _left: PanelContainer
var _right: PanelContainer
var _preview: ClassPreview
var _class_title: Label
var _class_sub: Label
var _class_desc: Label
var _stat_values: Array[Label] = []
var _char_list: VBoxContainer
var _new_card: Button
var _bottom: VBoxContainer
var _name_title: Label
var _class_nav: HBoxContainer
var _class_name: Label
var _create_row: HBoxContainer
var _new_name: LineEdit
var _create_char: Button
var _enter: Button
var _select_status: Label
var _characters: Array = [] # [[id, nome, classe, nível, evolução, renascimentos]]
var _new_class: String = ""
var _selected_id: int = 0
var _creating: bool = false
var _waiting: bool = false
var _password_cache: String = ""
## true enquanto o AutoLogin (reconexão, debug) cuida das respostas: a tela só mostra o aviso.
var passive: bool = false


func _ready() -> void:
	layer = 30
	_scene = LoginScene.new()
	add_child(_scene)
	_build_login()
	_build_select()
	get_viewport().size_changed.connect(_layout)
	_layout()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_account.text = str(cfg.get_value("login", "account", ""))
	Net.login_result_received.connect(_on_result)
	show_status("Conectando…", PARCHMENT, true)


# ---------------------------------------------------------------- API usada pelo cliente

## Mostra só um aviso (conectando, reconectando, falha), sem formulários.
func show_status(text: String, color: Color = Color.TRANSPARENT, hide_forms: bool = false) -> void:
	if color.a == 0.0:
		color = PARCHMENT
	visible = true
	if hide_forms:
		_login_box.visible = false
		_set_select_visible(false)
	var on_select := _select_root.visible
	_panel.visible = not on_select
	var label := _select_status if on_select else _status
	label.text = text
	label.add_theme_color_override("font_color", color)
	_spinner.visible = _waiting or text.ends_with("…")


func show_login() -> void:
	visible = true
	passive = false
	_set_select_visible(false)
	_panel.visible = true
	_login_box.visible = true
	_status.text = ""
	_spinner.visible = false
	_waiting = false
	(_password if not _account.text.is_empty() else _account).grab_focus.call_deferred()


## Debug: preenche o formulário e entra (para capturas da seleção de personagem); create cria a conta.
func fill_and_submit(account: String, password: String, create: bool = false) -> void:
	_account.text = account
	_password.text = password
	_submit_login(create)


## Nome da classe, ou o título da evolução se o personagem já evoluiu.
static func class_title(class_id: String, evolution: int) -> String:
	var cls := GameConfig.table("classes/" + class_id) if ResourceLoader.exists("res://data/classes/%s.json" % class_id) else {}
	if evolution > 0 and cls.has("evolution"):
		return str(cls["evolution"]["name"])
	return str(cls.get("name", class_id))


# ---------------------------------------------------------------- entrada (conta)

func _build_login() -> void:
	var holder := VBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"WindowPanel"
	_panel.custom_minimum_size = Vector2(360, 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.add_child(_panel)
	var bottom := Control.new()
	bottom.custom_minimum_size = Vector2(0, 30)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bottom)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)
	var sub := Label.new()
	sub.text = "o caminho só existe no seu diário"
	sub.theme_type_variation = &"LoreLabel"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)
	root.add_child(HSeparator.new())

	_login_box = VBoxContainer.new()
	_login_box.add_theme_constant_override("separation", 6)
	root.add_child(_login_box)
	_login_box.add_child(_field_label("CONTA"))
	_account = _edit("nome da conta")
	_login_box.add_child(_account)
	_login_box.add_child(_field_label("SENHA"))
	_password = _edit("senha")
	_password.secret = true
	_password.text_submitted.connect(func(_t: String) -> void: _submit_login(false))
	_account.text_submitted.connect(func(_t: String) -> void: _password.grab_focus())
	_login_box.add_child(_password)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	_login_box.add_child(gap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_login_box.add_child(row)
	var enter := _button("Entrar", func() -> void: _submit_login(false))
	enter.theme_type_variation = &"PrimaryButton"
	enter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(enter)
	var create := _button("Criar conta", func() -> void: _submit_login(true))
	create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(create)

	var status_row := HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 8)
	root.add_child(status_row)
	_spinner = Spinner.new()
	_spinner.custom_minimum_size = Vector2(14, 14)
	_spinner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_row.add_child(_spinner)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(300, 0)
	status_row.add_child(_status)

	var footer := Label.new() # versão do protocolo, discreta no canto
	footer.text = "Umbraheim · protocolo v%d" % Protocol.VERSION
	footer.theme_type_variation = &"HintLabel"
	footer.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.offset_right = -12.0
	footer.offset_bottom = -8.0
	add_child(footer)


func _submit_login(create: bool) -> void:
	if _waiting:
		return
	_waiting = true
	_password_cache = _password.text
	show_status("Criando a conta…" if create else "Entrando…")
	Net.send_login(_account.text.strip_edges().to_lower(), _password.text, create)


func _on_result(ok: bool, message: String, characters: Array) -> void:
	if not visible or passive:
		return
	_waiting = false
	if not ok:
		show_status(message, Color(1.0, 0.45, 0.35))
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # mantém as outras preferências (ex.: minimapa oculto)
	cfg.set_value("login", "account", _account.text.strip_edges().to_lower())
	cfg.save(SETTINGS_PATH)
	_password.text = ""
	var created := characters.size() > _characters.size() and _creating
	_characters = characters
	_login_box.visible = false
	if created: # personagem novo: já fica escolhido
		_selected_id = int(_characters[-1][0])
	_creating = _characters.is_empty()
	_set_select_visible(true)
	_rebuild_list()
	show_status(message, Color(1.0, 0.45, 0.35) if not message.is_empty() else PARCHMENT)
	if _characters.is_empty() and message.is_empty():
		_select_status.text = "Crie seu primeiro personagem."


# ---------------------------------------------------------------- escolha de personagem

func _build_select() -> void:
	_select_root = Control.new()
	_select_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_select_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_select_root.visible = false
	add_child(_select_root)

	_preview = ClassPreview.new()
	_select_root.add_child(_preview)

	# esquerda: a classe (título, descrição, atributos iniciais)
	_left = PanelContainer.new()
	_left.theme_type_variation = &"WindowPanel"
	_left.set_meta("no_window_fx", true) # painel fixo da tela, não janela arrastável
	_left.custom_minimum_size = Vector2(270, 0)
	_select_root.add_child(_left)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 6)
	_left.add_child(lbox)
	_class_title = Label.new()
	_class_title.theme_type_variation = &"TitleLabel"
	_class_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbox.add_child(_class_title)
	_class_sub = Label.new()
	_class_sub.theme_type_variation = &"HintLabel"
	lbox.add_child(_class_sub)
	_class_desc = Label.new()
	_class_desc.theme_type_variation = &"LoreLabel"
	_class_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_desc.custom_minimum_size = Vector2(240, 0)
	lbox.add_child(_class_desc)
	lbox.add_child(HSeparator.new())
	var stats_title := Label.new()
	stats_title.text = "ATRIBUTOS INICIAIS"
	stats_title.theme_type_variation = &"HintLabel"
	stats_title.add_theme_font_override("font", UiPalette.font("title"))
	lbox.add_child(stats_title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	lbox.add_child(grid)
	for i in STAT_NAMES.size():
		var box := PanelContainer.new()
		box.theme_type_variation = &"WellPanel"
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(box)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		box.add_child(v)
		var n := Label.new()
		n.text = STAT_NAMES[i]
		n.theme_type_variation = &"HintLabel"
		v.add_child(n)
		var val := Label.new()
		val.theme_type_variation = &"ValueLabel"
		val.add_theme_font_size_override("font_size", UiPalette.size("header") - 4)
		v.add_child(val)
		_stat_values.append(val)

	# direita: os personagens como cartões
	_right = PanelContainer.new()
	_right.theme_type_variation = &"WindowPanel"
	_right.set_meta("no_window_fx", true)
	_right.custom_minimum_size = Vector2(290, 0)
	_select_root.add_child(_right)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 6)
	_right.add_child(rbox)
	var rt := Label.new()
	rt.text = "PERSONAGENS"
	rt.theme_type_variation = &"TitleLabel"
	rbox.add_child(rt)
	_char_list = VBoxContainer.new()
	_char_list.add_theme_constant_override("separation", 4)
	rbox.add_child(_char_list)
	_new_card = _card("+  Novo personagem", "escolha a classe embaixo", Color.TRANSPARENT)
	_new_card.pressed.connect(func() -> void:
		_creating = true
		_refresh_select())
	rbox.add_child(_new_card)

	# embaixo no centro: nome do escolhido, ou classe com setas e o campo de nome (modo criar)
	_bottom = VBoxContainer.new()
	_bottom.alignment = BoxContainer.ALIGNMENT_END
	_bottom.add_theme_constant_override("separation", 8)
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_select_root.add_child(_bottom)
	_name_title = Label.new()
	_name_title.theme_type_variation = &"HeaderLabel"
	_name_title.add_theme_font_size_override("font_size", UiPalette.size("event"))
	_name_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_title.add_theme_constant_override("outline_size", 8)
	_bottom.add_child(_name_title)
	_class_nav = HBoxContainer.new()
	_class_nav.alignment = BoxContainer.ALIGNMENT_CENTER
	_class_nav.add_theme_constant_override("separation", 14)
	_bottom.add_child(_class_nav)
	var prev := _arrow("‹", -1)
	_class_nav.add_child(prev)
	_class_name = Label.new()
	_class_name.theme_type_variation = &"HeaderLabel"
	_class_name.add_theme_font_size_override("font_size", UiPalette.size("event") - 4)
	_class_name.add_theme_constant_override("outline_size", 8)
	_class_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_class_name.custom_minimum_size = Vector2(340, 0)
	_class_nav.add_child(_class_name)
	_class_nav.add_child(_arrow("›", 1))
	_create_row = HBoxContainer.new()
	_create_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_create_row.add_theme_constant_override("separation", 8)
	_bottom.add_child(_create_row)
	_new_name = _edit("nome do personagem")
	_new_name.custom_minimum_size = Vector2(240, 34)
	_new_name.max_length = GameConfig.get_i("server", "character_name_max")
	_new_name.text_submitted.connect(func(_t: String) -> void: _create_character())
	_create_row.add_child(_new_name)
	_create_char = _button("Criar", _create_character)
	_create_char.theme_type_variation = &"PrimaryButton"
	_create_row.add_child(_create_char)
	_select_status = Label.new()
	_select_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_select_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_select_status.custom_minimum_size = Vector2(360, 0)
	_select_status.add_theme_constant_override("outline_size", 5)
	_bottom.add_child(_select_status)

	_enter = _button("Entrar no mundo", _enter_world)
	_enter.theme_type_variation = &"PrimaryButton"
	_enter.custom_minimum_size = Vector2(220, 44)
	_enter.add_theme_font_size_override("font_size", UiPalette.size("strong") + 1)
	_select_root.add_child(_enter)
	_new_class = str(GameConfig.table("classes/index")["default"])


func _set_select_visible(on: bool) -> void:
	_select_root.visible = on
	_scene.set_select_mode(on)
	if on:
		_panel.visible = false
		_layout()


func _rebuild_list() -> void:
	for c in _char_list.get_children():
		c.queue_free()
	if not _characters.is_empty() and _characters.filter(func(c: Array) -> bool: return int(c[0]) == _selected_id).is_empty():
		_selected_id = int(_characters[0][0])
	for c: Array in _characters:
		var id := int(c[0])
		var class_id := str(c[2])
		var sub := "%s · nível %d%s" % [LoginScreen.class_title(class_id, int(c[4]) if c.size() > 4 else 0), int(c[3]),
			("  · renascido ×%d" % int(c[5])) if c.size() > 5 and int(c[5]) > 0 else ""]
		var b := _card(str(c[1]), sub, UiPalette.class_color(class_id))
		b.set_meta("id", id)
		b.pressed.connect(func() -> void:
			_selected_id = id
			_creating = false
			_refresh_select())
		b.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).double_click:
				_selected_id = id
				_enter_world())
		_char_list.add_child(b)
	var max_chars := GameConfig.get_i("server", "max_characters_per_account")
	_new_card.disabled = _characters.size() >= max_chars
	_refresh_select()


## Atualiza a tela conforme o modo (escolher ou criar) e a classe em destaque.
func _refresh_select() -> void:
	var max_chars := GameConfig.get_i("server", "max_characters_per_account")
	if _characters.size() >= max_chars:
		_creating = false
	var class_id := _new_class
	var evolution := 0
	var selected: Array = []
	for c: Array in _characters:
		if int(c[0]) == _selected_id:
			selected = c
	if not _creating and not selected.is_empty():
		class_id = str(selected[2])
		evolution = int(selected[4]) if selected.size() > 4 else 0
	for card in _char_list.get_children():
		(card as Button).button_pressed = not _creating and int(card.get_meta("id", 0)) == _selected_id
	_new_card.button_pressed = _creating
	var cls := GameConfig.table("classes/" + class_id)
	_class_title.text = LoginScreen.class_title(class_id, evolution).to_upper()
	_class_title.add_theme_color_override("font_color", UiPalette.class_color(class_id).lightened(0.35))
	_class_sub.text = ("evoluído de %s" % cls["name"]) if evolution > 0 else ("%d pontos por nível" % int(cls.get("points_per_level", 5)))
	_class_desc.text = str(cls.get("description", ""))
	var base: Dictionary = cls.get("base_stats", {})
	for i in STAT_KEYS.size():
		_stat_values[i].text = str(int(base.get(STAT_KEYS[i], 0)))
	_preview.set_class(class_id)
	_scene.set_tint(UiPalette.class_color(class_id))
	_name_title.visible = not _creating and not selected.is_empty()
	_name_title.text = str(selected[1]) if not selected.is_empty() else ""
	_class_nav.visible = _creating
	_create_row.visible = _creating
	_class_name.text = str(cls["name"])
	_class_name.add_theme_color_override("font_color", UiPalette.class_color(class_id).lightened(0.3))
	_enter.visible = not _creating and not _characters.is_empty()
	if _creating:
		_new_name.grab_focus.call_deferred()


func _cycle_class(step: int) -> void:
	var order: Array = GameConfig.table("classes/index")["order"]
	var i := order.find(_new_class)
	_new_class = str(order[posmod(i + step, order.size())])
	_refresh_select()


func _create_character() -> void:
	if _waiting or _new_name.text.strip_edges().is_empty():
		return
	_waiting = true
	_creating = true
	show_status("Criando personagem…")
	Net.send_create_character(_new_name.text.strip_edges(), _new_class)
	_new_name.text = ""


func _enter_world() -> void:
	if _selected_id == 0 or _waiting:
		return
	_waiting = true
	var name_of := ""
	for c: Array in _characters:
		if int(c[0]) == _selected_id:
			name_of = str(c[1])
	show_status("Entrando no mundo…")
	entering.emit(_account.text.strip_edges().to_lower(), _password_cache, name_of)
	Net.send_enter_world(_selected_id)


# ---------------------------------------------------------------- layout

## Posições conforme a tela: três colunas na tela larga; estreita (janela do navegador, celular),
## só os cartões e o painel de baixo, sem o modelo nem a coluna da classe.
func _layout() -> void:
	var v := get_viewport().get_visible_rect().size
	var wide := v.x >= 960.0
	var margin := 24.0
	_left.visible = wide
	_left.position = Vector2(margin, v.y * 0.18)
	_right.size = Vector2.ZERO
	var rw := _right.get_combined_minimum_size().x
	_right.position = Vector2(v.x - rw - margin, v.y * 0.18) if wide else Vector2((v.x - rw) * 0.5, 16.0)
	_bottom.size = Vector2(v.x, 0)
	_bottom.position = Vector2(0, v.y - _bottom.get_combined_minimum_size().y - (90.0 if not wide else 28.0))
	if wide:
		var pw := minf(420.0, v.x * 0.32)
		_preview.size = Vector2(pw, minf(v.y * 0.76, pw * 1.45))
		_preview.position = Vector2((v.x - pw) * 0.5, v.y * 0.08)
	else: # estreito: o modelo ocupa o vão entre os cartões e o nome
		var top := _right.position.y + _right.get_combined_minimum_size().y + 4.0
		var ph := maxf(_bottom.position.y - top, 0.0)
		var pw := minf(v.x, ph / 1.45)
		_preview.size = Vector2(pw, ph)
		_preview.position = Vector2((v.x - pw) * 0.5, top)
	_preview.visible = _preview.size.y >= 160.0
	_enter.position = Vector2(v.x - _enter.custom_minimum_size.x - margin, v.y - _enter.custom_minimum_size.y - 28.0) if wide \
		else Vector2((v.x - _enter.custom_minimum_size.x) * 0.5, v.y - _enter.custom_minimum_size.y - 24.0)


# ---------------------------------------------------------------- peças

## Cartão de personagem: botão alternável com losango na cor da classe, nome e linha de baixo.
func _card(title: String, sub: String, color: Color) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(266, 52)
	b.focus_mode = Control.FOCUS_NONE
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10.0
	row.offset_right = -8.0
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var d := DiamondButton.new()
	d.custom_minimum_size = Vector2(26, 26)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.selected = color.a > 0.0
	d.accent = color.lightened(0.25) if color.a > 0.0 else Color.TRANSPARENT
	d.glyph = title.left(1) if color.a > 0.0 else "+"
	row.add_child(d)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", UiPalette.font("title"))
	t.add_theme_font_size_override("font_size", UiPalette.size("strong"))
	t.add_theme_color_override("font_color", PARCHMENT if color.a > 0.0 else GOLD)
	col.add_child(t)
	var s := Label.new()
	s.text = sub
	s.theme_type_variation = &"HintLabel"
	col.add_child(s)
	return b


func _arrow(glyph: String, step: int) -> Button:
	var b := Button.new()
	b.text = glyph
	b.theme_type_variation = &"GhostButton"
	b.add_theme_font_size_override("font_size", UiPalette.size("event"))
	b.add_theme_color_override("font_color", GOLD)
	b.pressed.connect(_cycle_class.bind(step))
	return b


func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HintLabel"
	l.add_theme_font_override("font", UiPalette.font("title"))
	l.add_theme_color_override("font_color", GOLD)
	return l


func _edit(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 32)
	return e


func _button(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(fn)
	return b


## Losango girando ao lado do aviso enquanto espera o servidor.
class Spinner extends Control:
	func _process(delta: float) -> void:
		if visible:
			rotation += delta * 2.5
			pivot_offset = size * 0.5

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.45
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)])
		draw_polyline(pts, UiPalette.c("gold"), 1.5, true)
		draw_circle(c, 1.5, UiPalette.c("ember"))
