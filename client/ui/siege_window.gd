class_name SiegeWindow
extends PanelContainer
## Janela do Arauto do Cerco: quem é dono do castelo, o imposto das lojas, as guildas
## inscritas e o horário do próximo cerco. Mestre: inscrever a guilda; quem é de guilda
## inscrita ou dona: entrar no cerco; mestre dono: imposto e tesouro.

var GOLD: Color = UiPalette.c("gold")
var TEXT: Color = UiPalette.c("bone")
var DIM: Color = UiPalette.c("bone_dim")

var state: Dictionary = {}
var schedule: Array = []
var _box: VBoxContainer
var _tax: SpinBox


func _ready() -> void:
	theme_type_variation = &"WindowPanel"
	custom_minimum_size = Vector2(420, 0)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 7)
	add_child(_box)
	visible = false
	Net.castle_state_received.connect(func(s: Dictionary) -> void:
		state = s
		if visible:
			_rebuild())
	Net.event_schedule_received.connect(func(rows: Array) -> void: schedule = rows)


func open() -> void:
	visible = true
	_rebuild()


func close() -> void:
	visible = false


func _siege_row() -> Array:
	for r: Array in schedule:
		if str(r[0]) == "cerco":
			return r
	return []


func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	var top := HBoxContainer.new()
	_box.add_child(top)
	var title := _label("ARAUTO DO CERCO", 16, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var x := Button.new()
	x.text = "×"
	x.pressed.connect(Net.send_npc_close)
	top.add_child(x)
	if state.is_empty():
		_box.add_child(_label("…", 12, DIM))
		return
	# placa: castelo e dono (símbolo num quadro de metal) | imposto grande
	var plate := PanelContainer.new()
	plate.theme_type_variation = &"WellPanel"
	_box.add_child(plate)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	plate.add_child(head)
	if str(state["owner"]) != "":
		var frame := PanelContainer.new()
		frame.theme_type_variation = &"WindowPanel"
		frame.add_child(GuildSymbol.rect(str(state["owner_symbol"]), 40.0))
		head.add_child(frame)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	var cname := _label(str(state["name"]), 14, TEXT)
	cname.add_theme_font_override("font", UiPalette.font("title"))
	info.add_child(cname)
	var owner_l := _label(("Dono: %s" % state["owner"]) if str(state["owner"]) != "" else "Sem dono: o trono é guardado pelos Guardiões", 12, GOLD if str(state["owner"]) != "" else DIM)
	owner_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(owner_l)
	var tax_box := VBoxContainer.new()
	head.add_child(tax_box)
	var tax_big := _label("%d%%" % roundi(float(state["tax_pct"]) * 100.0), 16, GOLD)
	tax_big.theme_type_variation = &"HeaderLabel"
	tax_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tax_box.add_child(tax_big)
	var tax_cap := _label("imposto", 11, DIM)
	tax_cap.theme_type_variation = &"HintLabel"
	tax_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tax_box.add_child(tax_cap)
	var row := _siege_row()
	if not row.is_empty():
		var secs := int(row[3])
		var when := "%dd %dh" % [secs / 86400, (secs % 86400) / 3600] if secs >= 86400 else Hud._clock(secs)
		var phase: String = ["Próximo cerco em %s", "PORTÕES ABERTOS: entre em %s", "Cerco em andamento: %s restantes", "Cerco encerrando"][clampi(int(row[2]), 0, 3)]
		var timer := _label(phase % when if "%s" in phase else phase, 14, UiPalette.c("ember"))
		timer.add_theme_font_override("font", UiPalette.font("title"))
		timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(timer)
	var regs: PackedStringArray = state["registered"]
	_box.add_child(_label("Inscritas: %s" % (", ".join(regs) if not regs.is_empty() else "nenhuma ainda"), 12, TEXT))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_box.add_child(buttons)
	if str(state["my_guild"]) == "":
		var hint := _label("Só guildas lutam no cerco (G para fundar ou entrar numa).", 11, DIM)
		hint.theme_type_variation = &"HintLabel"
		_box.add_child(hint)
	elif not bool(state["is_owner"]) and int(state["my_role"]) == 0 and not bool(state["mine_in"]):
		var reg := Button.new()
		reg.text = "Inscrever %s (%d Óbolos)" % [state["my_guild"], int(state["fee"])]
		reg.theme_type_variation = &"PrimaryButton"
		reg.pressed.connect(Net.send_castle_action.bind(Protocol.Castle.REGISTER, 0))
		buttons.add_child(reg)
	if bool(state["mine_in"]):
		var enter := Button.new()
		enter.text = "Entrar no cerco"
		enter.theme_type_variation = &"PrimaryButton"
		enter.disabled = row.is_empty() or not int(row[2]) in [1, 2]
		enter.pressed.connect(Net.send_castle_action.bind(Protocol.Castle.ENTER, 0))
		buttons.add_child(enter)
	if int(state["treasury"]) >= 0: # sou o mestre da guilda dona
		_box.add_child(HSeparator.new())
		_box.add_child(_label("Tesouro do castelo: %d Óbolos" % int(state["treasury"]), 12, GOLD))
		var tax_row := HBoxContainer.new()
		tax_row.add_theme_constant_override("separation", 6)
		_box.add_child(tax_row)
		tax_row.add_child(_label("Imposto:", 12, TEXT))
		_tax = SpinBox.new()
		_tax.min_value = 0
		_tax.max_value = roundi(float(state["tax_max_pct"]) * 100.0)
		_tax.value = roundi(float(state["tax_pct"]) * 100.0)
		_tax.suffix = "%"
		tax_row.add_child(_tax)
		var set_tax := Button.new()
		set_tax.text = "Definir"
		set_tax.pressed.connect(func() -> void: Net.send_castle_action(Protocol.Castle.SET_TAX, roundi(_tax.value * 10.0)))
		tax_row.add_child(set_tax)
		var withdraw := Button.new()
		withdraw.text = "Sacar tesouro"
		withdraw.disabled = int(state["treasury"]) <= 0
		withdraw.pressed.connect(Net.send_castle_action.bind(Protocol.Castle.WITHDRAW, 0))
		tax_row.add_child(withdraw)
	_recenter.call_deferred()


func _recenter() -> void:
	await get_tree().process_frame
	size = Vector2.ZERO
	position = ((get_viewport_rect().size - size) / 2.0).floor()


static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if font_size >= 16: # títulos e cabeçalhos em Cinzel (tema)
		l.theme_type_variation = &"TitleLabel"
	return l
