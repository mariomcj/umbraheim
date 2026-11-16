class_name ChatBox
extends VBoxContainer
## Chat e mensagens do sistema (canto inferior esquerdo). Enter abre a linha de digitação.
## Comandos:
##   texto               geral          /g texto       grupo
##   /s Nome texto       sussurro       /r texto       responde ao último sussurro
##   /convidar Nome      convida ao grupo               /sair       sai do grupo
##   /expulsar Nome      tira do grupo (líder)          /trocar Nome  propõe troca
##   /gu texto           guilda         /gconvidar Nome  convida à guilda
##   /amigo Nome         pede amizade
##   /ajuda
## As linhas são Labels (sem BBCode): nada que um jogador digite vira formatação.

const COLORS := {
	Protocol.Chat.GENERAL: Color(0.92, 0.9, 0.84),
	Protocol.Chat.WHISPER: Color(0.95, 0.6, 0.95),
	Protocol.Chat.PARTY: Color(0.5, 0.85, 1.0),
	Protocol.Chat.SYSTEM: Color(0.95, 0.8, 0.45),
	Protocol.Chat.GUILD: Color(0.55, 0.95, 0.55),
}
## Etiqueta curta de canal antes de cada linha (docs/design/PROPOSTA_UI.md 3.5).
const TAGS := {
	Protocol.Chat.GENERAL: "G", Protocol.Chat.WHISPER: "S", Protocol.Chat.PARTY: "Gr",
	Protocol.Chat.SYSTEM: "!", Protocol.Chat.GUILD: "Gu",
}
## Canais que o losango da linha de digitação alterna (texto sem "/" vai para o canal atual).
const TYPE_CHANNELS: Array[int] = [Protocol.Chat.GENERAL, Protocol.Chat.PARTY, Protocol.Chat.GUILD]
const HELP := "Comandos: /g grupo · /gu guilda · /s Nome sussurro · /r responder · /convidar Nome · /sair · /expulsar Nome · /trocar Nome · /gconvidar Nome · /amigo Nome · G guilda · F amigos"

var _lines: VBoxContainer
var _input: LineEdit
var _entries: Array[Dictionary] = [] # {label (a linha: etiqueta + texto), born}
var _input_row: HBoxContainer
var _channel_button: DiamondButton
var _channel: int = Protocol.Chat.GENERAL
var _bg_alpha: float = 0.0 # fundo atrás das linhas: some junto com elas
var _history_max: int
var _visible_lines: int
var _fade_s: float
var _last_whisper_from: String = ""


func _ready() -> void:
	var cfg: Dictionary = GameConfig.table("social")["chat"]
	_history_max = int(cfg["history_lines"])
	_visible_lines = int(cfg["visible_lines"])
	_fade_s = float(cfg["fade_s"])
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 14.0
	offset_right = 500.0
	offset_top = -330.0
	offset_bottom = -126.0
	alignment = BoxContainer.ALIGNMENT_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 1)
	_lines = VBoxContainer.new()
	_lines.alignment = BoxContainer.ALIGNMENT_END
	_lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.clip_contents = true
	add_child(_lines)
	_input_row = HBoxContainer.new()
	_input_row.add_theme_constant_override("separation", 6)
	_input_row.visible = false
	add_child(_input_row)
	_channel_button = DiamondButton.new() # canal atual; clique troca
	_channel_button.custom_minimum_size = Vector2(30, 30)
	_channel_button.glyph_font = "body_bold"
	_channel_button.pressed.connect(_cycle_channel)
	_input_row.add_child(_channel_button)
	_input = LineEdit.new()
	_input.placeholder_text = "Enter para enviar · /ajuda"
	_input.max_length = int(cfg["max_length"])
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiPalette.c("ink"), 0.85)
	sb.border_color = UiPalette.c("gold_dim")
	sb.set_border_width_all(1)
	sb.set_content_margin_all(5)
	_input.add_theme_stylebox_override("normal", sb)
	_input.add_theme_stylebox_override("focus", sb)
	_input.text_submitted.connect(_submit)
	_input_row.add_child(_input)
	_update_channel_button()
	Net.chat_received.connect(_on_chat)


func is_typing() -> bool:
	return _input_row.visible and _input.has_focus()


func _cycle_channel() -> void:
	_channel = TYPE_CHANNELS[(TYPE_CHANNELS.find(_channel) + 1) % TYPE_CHANNELS.size()]
	_update_channel_button()
	_input.grab_focus()


func _update_channel_button() -> void:
	_channel_button.glyph = TAGS[_channel]
	_channel_button.accent = COLORS[_channel]
	var names := {Protocol.Chat.GENERAL: "Geral", Protocol.Chat.PARTY: "Grupo", Protocol.Chat.GUILD: "Guilda"}
	_channel_button.tooltip_text = "%s (clique para trocar)" % names[_channel]


func open(prefill: String = "") -> void:
	_input_row.visible = true
	_input.text = prefill
	_input.grab_focus()
	_input.caret_column = prefill.length()


func close() -> void:
	_input.text = ""
	_input.release_focus()
	_input_row.visible = false


## Mensagem do sistema/jogo (o antigo registro de mensagens).
func add_line(text: String, color: Color = COLORS[Protocol.Chat.SYSTEM], channel: int = Protocol.Chat.SYSTEM) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := Label.new() # etiqueta do canal, em negrito na cor dele
	tag.text = "[%s]" % TAGS.get(channel, "!")
	tag.add_theme_font_override("font", UiPalette.font("body_bold"))
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", COLORS.get(channel, color))
	tag.add_theme_constant_override("outline_size", 4)
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tag)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	_lines.add_child(row)
	_entries.append({"label": row, "born": Time.get_ticks_msec()})
	while _entries.size() > _history_max:
		(_entries[0]["label"] as Control).queue_free()
		_entries.remove_at(0)


func _on_chat(channel: int, from_name: String, text: String) -> void:
	var prefix := ""
	match channel:
		Protocol.Chat.GENERAL:
			prefix = "%s: " % from_name
		Protocol.Chat.WHISPER:
			prefix = ("[sussurro] %s: " if not from_name.begins_with("→") else "[sussurro %s] ") % from_name
			if not from_name.begins_with("→"):
				_last_whisper_from = from_name
		Protocol.Chat.PARTY:
			prefix = "[grupo] %s: " % from_name
		Protocol.Chat.GUILD:
			prefix = "[guilda] %s: " % from_name
	add_line(prefix + text, COLORS.get(channel, Color.WHITE), channel)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not is_visible_in_tree():
		return
	if not _input_row.visible and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		open()
		get_viewport().set_input_as_handled()
	elif _input_row.visible and k.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _submit(text: String) -> void:
	close()
	text = text.strip_edges()
	if text.is_empty():
		return
	if not text.begins_with("/"):
		Net.send_chat(_channel, "", text) # canal do losango (geral, grupo ou guilda)
		return
	var cmd := text.get_slice(" ", 0).to_lower()
	var rest := text.substr(cmd.length()).strip_edges()
	var first := rest.get_slice(" ", 0)
	var after := rest.substr(first.length()).strip_edges()
	match cmd:
		"/g", "/p", "/grupo":
			Net.send_chat(Protocol.Chat.PARTY, "", rest)
		"/s", "/w", "/sussurrar":
			if first.is_empty() or after.is_empty():
				add_line("Use: /s Nome mensagem")
			else:
				Net.send_chat(Protocol.Chat.WHISPER, first, after)
		"/r":
			if _last_whisper_from.is_empty():
				add_line("Ninguém sussurrou para você ainda.")
			else:
				Net.send_chat(Protocol.Chat.WHISPER, _last_whisper_from, rest)
		"/convidar":
			Net.send_party_action(Protocol.Party.INVITE, first)
		"/sair":
			Net.send_party_action(Protocol.Party.LEAVE)
		"/expulsar":
			Net.send_party_action(Protocol.Party.KICK, first)
		"/trocar":
			Net.send_trade_action(Protocol.Trade.REQUEST, 0, first)
		"/gu", "/guilda":
			Net.send_chat(Protocol.Chat.GUILD, "", rest)
		"/gconvidar":
			Net.send_guild_action(Protocol.Guild.INVITE, first)
		"/amigo":
			Net.send_friend_action(Protocol.Friend.REQUEST, first)
		"/ajuda", "/?":
			add_line(HELP)
		_:
			add_line("Comando desconhecido. " + HELP)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var open_now := _input_row.visible
	var shown := 0
	var max_alpha := 0.0
	for i in range(_entries.size() - 1, -1, -1):
		var e := _entries[i]
		var l: Control = e["label"]
		var limit := _visible_lines * (2 if open_now else 1)
		if shown >= limit:
			l.visible = false
			continue
		shown += 1
		l.visible = true
		var age := (now - int(e["born"])) / 1000.0
		l.modulate.a = 1.0 if open_now else clampf(1.0 - (age - _fade_s) / 2.0, 0.0, 1.0)
		max_alpha = maxf(max_alpha, l.modulate.a)
	var bg := 0.85 if open_now else 0.55 * max_alpha
	if not is_equal_approx(bg, _bg_alpha):
		_bg_alpha = bg
		queue_redraw()


## Fundo de tinta atrás das linhas visíveis (55%, some com elas; 85% e moldura ao digitar).
func _draw() -> void:
	if _bg_alpha <= 0.01:
		return
	var top := size.y
	for e in _entries:
		var l: Control = e["label"]
		if l.visible and l.modulate.a > 0.01:
			top = minf(top, _lines.position.y + l.position.y)
	if _input_row.visible:
		top = minf(top, _input_row.position.y)
	var r := Rect2(Vector2(-8, top - 6), Vector2(size.x + 16, size.y - top + 12))
	draw_rect(r, Color(UiPalette.c("ink"), _bg_alpha))
	if _input_row.visible:
		draw_rect(r, UiPalette.c("gold_dim", 0.8), false, 1.0)
