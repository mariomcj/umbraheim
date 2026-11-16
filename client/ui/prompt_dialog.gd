class_name PromptDialog
extends PanelContainer
## Convites que pedem resposta (grupo, troca, guilda, guerra de guildas, amizade), um de
## cada vez, no alto da tela.
## Somem sozinhos depois do tempo do servidor (o servidor também os expira).

var GOLD: Color = UiPalette.c("gold")

var _queue: Array[Dictionary] = [] # {kind, from, detail, until}
var _text: Label
var _timer_label: Label
var _title: Label
var _bar: ProgressBar


func _ready() -> void:
	theme_type_variation = &"WindowPanel"
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_top = 200.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_text = Label.new()
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.custom_minimum_size = Vector2(300, 0)
	box.add_child(_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	# cancelar à esquerda, confirmação (principal) à direita
	var no := Button.new()
	no.text = "Recusar"
	no.theme_type_variation = &"GhostButton"
	no.custom_minimum_size = Vector2(110, 32)
	no.pressed.connect(func() -> void: _answer(false))
	row.add_child(no)
	var yes := Button.new()
	yes.text = "Aceitar"
	yes.theme_type_variation = &"PrimaryButton"
	yes.custom_minimum_size = Vector2(110, 32)
	yes.pressed.connect(func() -> void: _answer(true))
	row.add_child(yes)
	_bar = ProgressBar.new() # prazo do convite, esvaziando
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 3)
	box.add_child(_bar)
	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.theme_type_variation = &"HintLabel"
	box.add_child(_timer_label)
	visible = false
	Net.prompt_received.connect(_on_prompt)


const _TITLES := {Protocol.Prompt.PARTY_INVITE: "GRUPO", Protocol.Prompt.TRADE_REQUEST: "TROCA",
	Protocol.Prompt.GUILD_INVITE: "GUILDA", Protocol.Prompt.GUILD_WAR: "GUERRA DE GUILDAS", Protocol.Prompt.FRIEND_REQUEST: "AMIZADE"}


func _on_prompt(kind: int, from_name: String, detail: String) -> void:
	_queue.append({"kind": kind, "from": from_name, "detail": detail, "until": Time.get_ticks_msec() + _timeout_s(kind) * 1000.0})
	_show_next()


## Mesmo prazo que o servidor usa para cada tipo de convite.
static func _timeout_s(kind: int) -> float:
	var social := GameConfig.table("social")
	var guilds := GameConfig.table("guilds")
	match kind:
		Protocol.Prompt.PARTY_INVITE:
			return float(social["party"]["invite_timeout_s"])
		Protocol.Prompt.TRADE_REQUEST:
			return float(social["trade"]["request_timeout_s"])
		Protocol.Prompt.GUILD_INVITE:
			return float(guilds["invite_timeout_s"])
		Protocol.Prompt.GUILD_WAR:
			return float(guilds["war"]["offer_timeout_s"])
		_:
			return float(social["friends"]["request_timeout_s"])


## Debug/bots: aceita o convite que estiver aberto.
func accept_current() -> void:
	if visible:
		_answer(true)


func _show_next() -> void:
	while not _queue.is_empty() and Time.get_ticks_msec() > float(_queue[0]["until"]):
		_queue.pop_front()
	if _queue.is_empty():
		visible = false
		return
	var p := _queue[0]
	_title.text = _TITLES.get(int(p["kind"]), "CONVITE")
	_bar.max_value = _timeout_s(int(p["kind"]))
	match int(p["kind"]):
		Protocol.Prompt.PARTY_INVITE:
			_text.text = "%s convidou você para o grupo." % p["from"]
		Protocol.Prompt.TRADE_REQUEST:
			_text.text = "%s quer trocar itens com você." % p["from"]
		Protocol.Prompt.GUILD_INVITE:
			_text.text = "%s convidou você para a guilda %s." % [p["from"], p["detail"]]
		Protocol.Prompt.GUILD_WAR:
			var w: Dictionary = GameConfig.table("guilds")["war"]
			_text.text = "%s, da guilda %s, declarou guerra à sua guilda.
Vence quem derrubar %d primeiro (até %d min)." % [
				p["from"], p["detail"], int(w["kill_goal"]), roundi(float(w["duration_s"]) / 60.0)]
		_:
			_text.text = "%s quer ser seu amigo." % p["from"]
	visible = true
	reset_size()


func _answer(yes: bool) -> void:
	if _queue.is_empty():
		return
	var p: Dictionary = _queue.pop_front()
	match int(p["kind"]):
		Protocol.Prompt.PARTY_INVITE:
			Net.send_party_action(Protocol.Party.ACCEPT if yes else Protocol.Party.DECLINE)
		Protocol.Prompt.TRADE_REQUEST:
			Net.send_trade_action(Protocol.Trade.ACCEPT if yes else Protocol.Trade.DECLINE)
		Protocol.Prompt.GUILD_INVITE:
			Net.send_guild_action(Protocol.Guild.ACCEPT if yes else Protocol.Guild.DECLINE)
		Protocol.Prompt.GUILD_WAR:
			Net.send_guild_action(Protocol.Guild.WAR_ACCEPT if yes else Protocol.Guild.WAR_DECLINE)
		_:
			Net.send_friend_action(Protocol.Friend.ACCEPT if yes else Protocol.Friend.DECLINE)
	_show_next()


func _process(_delta: float) -> void:
	if not visible:
		return
	if _queue.is_empty() or Time.get_ticks_msec() > float(_queue[0]["until"]):
		if not _queue.is_empty():
			_queue.pop_front()
		_show_next()
		return
	var left := (float(_queue[0]["until"]) - Time.get_ticks_msec()) / 1000.0
	_timer_label.text = "expira em %d s" % ceili(left)
	_bar.value = left
