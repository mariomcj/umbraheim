class_name SocialWindow
extends PanelContainer
## Janela social (G = guilda, F = amigos). Guilda: fundar (nome + símbolo de pixels),
## membros com cargo, nível e região, ações por cargo (clique no membro), convite,
## guerra de guildas e símbolo. Amigos: lista com online/offline, sussurrar, remover.
## Tudo é pedido ao servidor, que confere as regras de novo.

signal whisper_requested(character_name: String)

var GOLD: Color = UiPalette.c("gold")
var DIM: Color = UiPalette.c("bone_dim")
var TEXT: Color = UiPalette.c("bone")
const TAB_GUILD := 0
const TAB_FRIENDS := 1

var guild_state: Dictionary = {}
var friends: Array = []
var my_name: String = ""

var _cfg: Dictionary
var _tabs: TabContainer
# guilda: sem guilda
var _create_box: VBoxContainer
var _create_name: LineEdit
var _create_editor: GuildSymbolEditor
# guilda: com guilda
var _guild_box: VBoxContainer
var _header: HBoxContainer
var _members: VBoxContainer
var _war_info: VBoxContainer
var _war_row: HBoxContainer
var _war_name: LineEdit
var _invite_row: HBoxContainer
var _invite_name: LineEdit
var _symbol_editor: GuildSymbolEditor
var _symbol_save: Button
var _symbol_button: Button
var _leave_button: Button
var _member_menu: PopupMenu
var _menu_member: String = ""
var _confirm_disband: bool = false
# amigos
var _friend_name: LineEdit
var _friend_rows: VBoxContainer
var _confirm_remove: String = ""


func _ready() -> void:
	_cfg = GameConfig.table("guilds")
	theme_type_variation = &"WindowPanel"
	position = Vector2(14, 118) # lado esquerdo, abaixo do texto de depuração: o mundo continua visível
	custom_minimum_size = Vector2(440, 0)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)
	var top := HBoxContainer.new()
	outer.add_child(top)
	var title := _label("SOCIAL", 16, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Fechar (Esc)"
	close.pressed.connect(hide)
	top.add_child(close)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(416, 0)
	outer.add_child(_tabs)
	_build_guild_tab()
	_build_friends_tab()
	for i in _tabs.get_tab_count(): # abas com losango
		_tabs.set_tab_icon(i, UiThemeBuilder._diamond_texture(12, UiPalette.c("gold"), i == 0, UiPalette.c("gold_dim")))
	_tabs.tab_changed.connect(func(cur: int) -> void:
		for i in _tabs.get_tab_count():
			_tabs.set_tab_icon(i, UiThemeBuilder._diamond_texture(12, UiPalette.c("gold"), i == cur, UiPalette.c("gold_dim"))))
	_member_menu = PopupMenu.new()
	_member_menu.id_pressed.connect(_on_member_menu)
	add_child(_member_menu)
	visible = false
	Net.guild_state_received.connect(set_guild_state)
	Net.friends_state_received.connect(set_friends)
	set_guild_state({})
	set_friends([])


## Abre na aba pedida; se já estava aberta nela, fecha.
func toggle_tab(tab: int) -> void:
	if visible and _tabs.current_tab == tab:
		hide()
		return
	_tabs.current_tab = tab
	show()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- guilda

func _build_guild_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Guilda"
	tab.add_theme_constant_override("separation", 8)
	_tabs.add_child(tab)

	_create_box = VBoxContainer.new()
	_create_box.add_theme_constant_override("separation", 8)
	tab.add_child(_create_box)
	_create_box.add_child(_label("Você não está numa guilda. Peça um convite a quem já tem uma,\nou funde a sua:", 12, TEXT))
	_create_name = LineEdit.new()
	_create_name.placeholder_text = "Nome da guilda"
	_create_name.max_length = int(_cfg["name"]["max_length"])
	_create_box.add_child(_create_name)
	_create_box.add_child(_label("Símbolo:", 12, GOLD))
	_create_editor = GuildSymbolEditor.new()
	_create_box.add_child(_create_editor)
	var c: Dictionary = _cfg["create"]
	_create_box.add_child(_label("Precisa de nível %d e %d Óbolos, e só se funda na cidade." % [int(c["min_level"]), int(c["cost"])], 11, DIM))
	var found := Button.new()
	found.text = "Fundar guilda"
	found.pressed.connect(func() -> void:
		Net.send_guild_action(Protocol.Guild.CREATE, _create_name.text, _create_editor.symbol))
	_create_box.add_child(found)

	_guild_box = VBoxContainer.new()
	_guild_box.add_theme_constant_override("separation", 8)
	tab.add_child(_guild_box)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 10)
	_guild_box.add_child(_header)
	_guild_box.add_child(_label("MEMBROS  (clique num membro para as ações)", 11, GOLD))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_guild_box.add_child(scroll)
	_members = VBoxContainer.new()
	_members.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_members.add_theme_constant_override("separation", 1)
	scroll.add_child(_members)
	_invite_row = HBoxContainer.new()
	_guild_box.add_child(_invite_row)
	_invite_name = LineEdit.new()
	_invite_name.placeholder_text = "Nome do personagem"
	_invite_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_row.add_child(_invite_name)
	var inv := Button.new()
	inv.text = "Convidar"
	inv.pressed.connect(func() -> void:
		Net.send_guild_action(Protocol.Guild.INVITE, _invite_name.text)
		_invite_name.text = "")
	_invite_row.add_child(inv)
	_guild_box.add_child(_label("GUERRA DE GUILDAS", 11, GOLD))
	_war_info = VBoxContainer.new()
	_guild_box.add_child(_war_info)
	_war_row = HBoxContainer.new()
	_guild_box.add_child(_war_row)
	_war_name = LineEdit.new()
	_war_name.placeholder_text = "Nome da guilda rival"
	_war_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_war_row.add_child(_war_name)
	var war := Button.new()
	war.text = "Declarar guerra"
	war.pressed.connect(func() -> void:
		Net.send_guild_action(Protocol.Guild.WAR_DECLARE, _war_name.text)
		_war_name.text = "")
	_war_row.add_child(war)
	_symbol_editor = GuildSymbolEditor.new()
	_symbol_editor.visible = false
	_guild_box.add_child(_symbol_editor)
	_symbol_save = Button.new()
	_symbol_save.text = "Salvar símbolo"
	_symbol_save.visible = false
	_symbol_save.pressed.connect(func() -> void:
		Net.send_guild_action(Protocol.Guild.SET_SYMBOL, "", _symbol_editor.symbol)
		_symbol_editor.visible = false
		_symbol_save.visible = false)
	_guild_box.add_child(_symbol_save)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	_guild_box.add_child(bottom)
	var chat_hint := _label("Chat da guilda: /gu texto", 11, DIM)
	chat_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(chat_hint)
	_symbol_button = Button.new()
	_symbol_button.text = "Editar símbolo"
	_symbol_button.pressed.connect(func() -> void:
		_symbol_editor.set_symbol(str(guild_state.get("symbol", "")))
		_symbol_editor.visible = not _symbol_editor.visible
		_symbol_save.visible = _symbol_editor.visible)
	bottom.add_child(_symbol_button)
	_leave_button = Button.new()
	_leave_button.pressed.connect(_on_leave_pressed)
	bottom.add_child(_leave_button)


func set_guild_state(state: Dictionary) -> void:
	var was_in := not guild_state.is_empty()
	guild_state = state
	var in_guild := not state.is_empty()
	_create_box.visible = not in_guild
	_guild_box.visible = in_guild
	if in_guild != was_in:
		_confirm_disband = false
		_symbol_editor.visible = false
		_symbol_save.visible = false
	if not in_guild:
		return
	var roles: Array = _cfg["roles"]
	var my_role := int(state["role"])
	var role_cfg: Dictionary = roles[clampi(my_role, 0, roles.size() - 1)]
	# cabeçalho
	for ch in _header.get_children():
		ch.queue_free()
	_header.add_child(GuildSymbol.rect(str(state["symbol"]), 48.0))
	var info := VBoxContainer.new()
	_header.add_child(info)
	info.add_child(_label(str(state["name"]), 17, GOLD))
	var members: Array = state["members"]
	var online := 0
	for m: Array in members:
		if bool(m[4]):
			online += 1
	info.add_child(_label("Seu cargo: %s · %d/%d membros (%d online) · %d vitória(s) em guerra" % [
		role_cfg["name"], members.size(), int(state["max_members"]), online, int(state["wins"])], 11, DIM))
	# membros
	for ch in _members.get_children():
		ch.queue_free()
	for mi in members.size():
		var m: Array = members[mi]
		var stripe := _stripe_row(mi)
		_members.add_child(stripe)
		var srow := stripe.get_child(0) as HBoxContainer
		srow.add_child(PresenceDot.make(bool(m[4])))
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		var role: Dictionary = roles[clampi(int(m[1]), 0, roles.size() - 1)]
		var where := _region_name(str(m[5])) if bool(m[4]) else "offline"
		b.text = "%s  ·  %s  ·  nv %d  ·  %s" % [m[0], role["name"], int(m[2]), where]
		b.add_theme_color_override("font_color", GameConfig.color_of(role["color"]) if bool(m[4]) else DIM)
		b.pressed.connect(_open_member_menu.bind(m))
		srow.add_child(b)
	# guerra
	for ch in _war_info.get_children():
		ch.queue_free()
	var war: Dictionary = state["war"]
	if war.is_empty():
		_war_info.add_child(_label("Sem guerra no momento." if bool(role_cfg["war"]) else "Sem guerra no momento. Só o mestre e o braço direito declaram guerra.", 11, DIM))
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_war_info.add_child(row)
		row.add_child(GuildSymbol.rect(str(war["enemy_symbol"]), 28.0))
		var left := int(war["left_s"])
		row.add_child(_label("Contra %s:  %d × %d  (vence quem chegar a %d) · %d:%02d restantes" % [
			war["enemy"], int(war["mine"]), int(war["theirs"]), int(war["goal"]), left / 60, left % 60], 12, UiPalette.c("blood").lightened(0.35)))
	_war_row.visible = war.is_empty() and bool(role_cfg["war"])
	_invite_row.visible = bool(role_cfg["invite"])
	_symbol_button.visible = my_role == 0
	_leave_button.text = ("Confirmar: desfazer?" if _confirm_disband else "Desfazer guilda") if my_role == 0 else "Sair da guilda"


func _on_leave_pressed() -> void:
	if int(guild_state.get("role", -1)) != 0:
		Net.send_guild_action(Protocol.Guild.LEAVE)
		return
	if not _confirm_disband: # segundo clique confirma
		_confirm_disband = true
		_leave_button.text = "Confirmar: desfazer?"
		return
	_confirm_disband = false
	Net.send_guild_action(Protocol.Guild.DISBAND)


func _open_member_menu(m: Array) -> void:
	_menu_member = str(m[0])
	var roles: Array = _cfg["roles"]
	var mine := int(guild_state["role"])
	var theirs := int(m[1])
	_member_menu.clear()
	var me := _menu_member.to_lower() == my_name.to_lower()
	if not me and bool(m[4]):
		_member_menu.add_item("Sussurrar", 0)
	if mine == 0 and not me:
		if theirs > 1:
			_member_menu.add_item("Promover a %s" % roles[theirs - 1]["name"], 1)
		if theirs >= 1 and theirs < roles.size() - 1:
			_member_menu.add_item("Rebaixar a %s" % roles[theirs + 1]["name"], 2)
		_member_menu.add_item("Passar a liderança", 4)
	if not me and mine >= 0 and mine < theirs and bool(roles[mine]["kick"]):
		_member_menu.add_item("Expulsar", 3)
	if _member_menu.item_count == 0:
		return
	_member_menu.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(6, 6)
	_member_menu.reset_size()
	_member_menu.popup()


func _on_member_menu(id: int) -> void:
	match id:
		0:
			whisper_requested.emit(_menu_member)
		1:
			Net.send_guild_action(Protocol.Guild.PROMOTE, _menu_member)
		2:
			Net.send_guild_action(Protocol.Guild.DEMOTE, _menu_member)
		3:
			Net.send_guild_action(Protocol.Guild.KICK, _menu_member)
		4:
			Net.send_guild_action(Protocol.Guild.TRANSFER, _menu_member)


# ---------------------------------------------------------------- amigos

func _build_friends_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Amigos"
	tab.add_theme_constant_override("separation", 8)
	_tabs.add_child(tab)
	var row := HBoxContainer.new()
	tab.add_child(row)
	_friend_name = LineEdit.new()
	_friend_name.placeholder_text = "Nome (precisa estar online)"
	_friend_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_friend_name)
	var add := Button.new()
	add.text = "Adicionar"
	add.pressed.connect(func() -> void:
		Net.send_friend_action(Protocol.Friend.REQUEST, _friend_name.text)
		_friend_name.text = "")
	row.add_child(add)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	_friend_rows = VBoxContainer.new()
	_friend_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friend_rows.add_theme_constant_override("separation", 2)
	scroll.add_child(_friend_rows)


func set_friends(list: Array) -> void:
	friends = list
	for ch in _friend_rows.get_children():
		ch.queue_free()
	if list.is_empty():
		_friend_rows.add_child(_label("Nenhum amigo ainda. Clique num jogador e escolha\n\"Adicionar amigo\", ou digite o nome acima.", 12, DIM))
		return
	for fi in list.size():
		var f: Array = list[fi]
		var on := bool(f[1])
		var stripe := _stripe_row(fi)
		_friend_rows.add_child(stripe)
		var row := stripe.get_child(0) as HBoxContainer
		row.add_child(PresenceDot.make(on))
		var l := _label("%s  ·  nv %d  ·  %s" % [f[0], int(f[2]), _region_name(str(f[4])) if on else "offline"],
			12, TEXT if on else DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if on:
			var w := Button.new()
			w.text = "Sussurrar"
			w.add_theme_font_size_override("font_size", 11)
			w.pressed.connect(func() -> void: whisper_requested.emit(str(f[0])))
			row.add_child(w)
		var r := Button.new()
		var fname := str(f[0])
		r.text = "Confirmar?" if _confirm_remove == fname else "Remover"
		r.add_theme_font_size_override("font_size", 11)
		r.pressed.connect(func() -> void:
			if _confirm_remove != fname: # segundo clique confirma
				_confirm_remove = fname
				r.text = "Confirmar?"
				return
			_confirm_remove = ""
			Net.send_friend_action(Protocol.Friend.REMOVE, fname))
		row.add_child(r)


# ---------------------------------------------------------------- utilidades

## Linha de lista com fundo alternado sutil (par: levemente mais claro).
func _stripe_row(i: int) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.c("bone", 0.04) if i % 2 == 0 else Color(0, 0, 0, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 4
	p.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	p.add_child(row)
	return p


## Ponto de presença: verde aceso online, cinza vazado offline.
class PresenceDot extends Control:
	var online: bool

	static func make(on: bool) -> PresenceDot:
		var d := PresenceDot.new()
		d.online = on
		d.custom_minimum_size = Vector2(12, 12)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return d

	func _draw() -> void:
		var ct := size * 0.5
		if online:
			draw_circle(ct, 5.5, Color(UiPalette.c("ok"), 0.25))
			draw_circle(ct, 3.5, UiPalette.c("ok"))
		else:
			draw_arc(ct, 3.5, 0.0, TAU, 16, UiPalette.c("bone_dim", 0.7), 1.2, true)


func _region_name(region_id: String) -> String:
	return str(GameConfig.region(region_id).get("name", region_id)) if region_id != "" else "?"


static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if font_size >= 16: # títulos e cabeçalhos em Cinzel (tema)
		l.theme_type_variation = &"TitleLabel"
	return l
