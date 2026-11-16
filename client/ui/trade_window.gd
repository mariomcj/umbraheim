class_name TradeWindow
extends PanelContainer
## Troca entre jogadores, com confirmação dupla:
##   botão direito num item da mochila = oferecer; clique num item da sua oferta = tirar;
##   "Pronto" trava a sua oferta; com os dois prontos, "Confirmar" — e só quando os
##   dois confirmam o servidor troca tudo. Qualquer mudança desfaz Pronto e Confirmar.

var GOLD: Color = UiPalette.c("gold")
var PARCHMENT: Color = UiPalette.c("bone")
var OK_COLOR: Color = UiPalette.c("ok")


class Offer extends Control:
	var window: TradeWindow
	var mine: bool

	func _draw() -> void:
		window._draw_offer(self)

	func _gui_input(event: InputEvent) -> void:
		window._offer_input(self, event)


var inventory: InventoryWindow
var state: Dictionary = {}
var _cell: float
var _cols: int
var _rows: int
var _title: Label
var _their_offer: Offer
var _my_offer: Offer
var _their_status: Label
var _my_status: Label
var _their_currency: Label
var _currency_edit: SpinBox
var _ready_button: Button
var _confirm_button: Button
var _layouts: Dictionary = {} # Offer -> [[item, Rect2]]
var _hovering: bool = false


func setup(inv: InventoryWindow) -> void:
	inventory = inv


func _ready() -> void:
	_cell = GameConfig.get_f("ui", "inventory_cell_px")
	var cfg: Dictionary = GameConfig.table("social")["trade"]
	_cols = int(cfg["offer_cols"])
	_rows = int(cfg["offer_rows"])
	theme_type_variation = &"WindowPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	add_child(box)
	_title = _label("TROCA", 16, GOLD)
	_title.theme_type_variation = &"TitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	box.add_child(cols)
	var mine_col := VBoxContainer.new()
	mine_col.add_theme_constant_override("separation", 5)
	cols.add_child(mine_col)
	cols.add_child(VSeparator.new())
	var their_col := VBoxContainer.new()
	their_col.add_theme_constant_override("separation", 5)
	cols.add_child(their_col)
	_my_status = _label("Sua oferta", 12, PARCHMENT)
	mine_col.add_child(_my_status)
	_my_offer = _make_offer(true)
	mine_col.add_child(_my_offer)
	var money := HBoxContainer.new()
	mine_col.add_child(money)
	_their_status = _label("", 12, PARCHMENT)
	their_col.add_child(_their_status)
	_their_offer = _make_offer(false)
	their_col.add_child(_their_offer)
	_their_currency = _label("", 13, UiPalette.c("arcane"))
	their_col.add_child(_their_currency)
	money.add_child(_label("Seus Óbolos: ", 13, UiPalette.c("arcane")))
	_currency_edit = SpinBox.new()
	_currency_edit.min_value = 0
	_currency_edit.step = 1
	_currency_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_currency_edit.get_line_edit().text_submitted.connect(func(_t: String) -> void: _send_currency())
	_currency_edit.get_line_edit().focus_exited.connect(_send_currency)
	money.add_child(_currency_edit)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	_ready_button = _button("Pronto", func() -> void: Net.send_trade_action(Protocol.Trade.LOCK))
	buttons.add_child(_ready_button)
	_confirm_button = _button("Confirmar", func() -> void: Net.send_trade_action(Protocol.Trade.CONFIRM))
	_confirm_button.theme_type_variation = &"PrimaryButton"
	buttons.add_child(_confirm_button)
	buttons.add_child(_button("Cancelar", func() -> void: Net.send_trade_action(Protocol.Trade.CANCEL)))
	var hint := _label("Botão direito na mochila: oferecer · clique na sua oferta: tirar", 11, UiPalette.c("bone_dim"))
	hint.theme_type_variation = &"HintLabel"
	box.add_child(hint)
	visible = false
	Net.trade_state_received.connect(_on_state)
	Net.trade_closed_received.connect(func(_reason: String) -> void: close())


func _on_state(s: Dictionary) -> void:
	var opening := not visible
	state = s
	state["their_decoded"] = []
	for a: PackedInt32Array in s.get("their_items", []):
		var item := ItemCodec.decode(a, inventory.catalog)
		if not item.is_empty():
			state["their_decoded"].append(item)
	_title.text = "TROCA COM %s" % str(s["partner"]).to_upper()
	_their_status.text = "Oferta de %s  %s" % [s["partner"], _flags(bool(s["their_locked"]), bool(s["their_confirmed"]))]
	_my_status.text = "Sua oferta  %s" % _flags(bool(s["my_locked"]), bool(s["my_confirmed"]))
	_their_currency.text = "Óbolos de %s: %d" % [s["partner"], int(s["their_currency"])]
	_currency_edit.max_value = inventory.currency
	if not _currency_edit.get_line_edit().has_focus():
		_currency_edit.set_value_no_signal(int(s["my_currency"]))
	_ready_button.disabled = bool(s["my_locked"])
	_confirm_button.disabled = not (bool(s["my_locked"]) and bool(s["their_locked"])) or bool(s["my_confirmed"])
	# o botão final só "acende" (âmbar) com os dois prontos; antes fica apagado
	_confirm_button.modulate.a = 1.0 if not _confirm_button.disabled else 0.55
	if opening:
		visible = true
		inventory.npc_mode = "trade"
		if not inventory.visible:
			inventory.toggle()
		_place_beside_inventory.call_deferred()


func close() -> void:
	visible = false
	state = {}
	if inventory.npc_mode == "trade":
		inventory.npc_mode = ""
	inventory.set_external_tooltip({})


static func _flags(locked: bool, confirmed: bool) -> String:
	if confirmed:
		return "· CONFIRMOU ✔"
	if locked:
		return "· pronto ✔"
	return "· escolhendo…"


func _send_currency() -> void:
	if visible and int(_currency_edit.value) != int(state.get("my_currency", 0)):
		Net.send_trade_action(Protocol.Trade.SET_CURRENCY, int(_currency_edit.value))


func _place_beside_inventory() -> void:
	reset_size()
	position = Vector2(inventory.global_position.x - get_combined_minimum_size().x - 10.0, inventory.global_position.y)


func _process(_delta: float) -> void:
	if not visible:
		return
	_their_offer.queue_redraw()
	_my_offer.queue_redraw()
	var hover: Dictionary = {}
	for offer: Offer in [_their_offer, _my_offer]:
		if offer.get_global_rect().has_point(offer.get_global_mouse_position()):
			for entry: Array in _layouts.get(offer, []):
				if (entry[1] as Rect2).has_point(offer.get_local_mouse_position()):
					hover = entry[0]
	if not hover.is_empty():
		_hovering = true
		inventory.set_external_tooltip(hover)
	elif _hovering:
		_hovering = false
		inventory.set_external_tooltip({})


func _draw_offer(c: Offer) -> void:
	var locked := bool(state.get("my_locked" if c.mine else "their_locked", false))
	UiDraw.well_grid(c, Vector2.ZERO, _cols, _rows, _cell)
	if locked:
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(UiPalette.c("spectral"), 0.05))
	var items: Array = inventory.items_in(ItemCatalog.CONTAINER_TRADE) if c.mine else state.get("their_decoded", [])
	var grid := InventoryGrid.new(_cols, _rows)
	var layout: Array = []
	for item: Dictionary in items:
		var size := inventory.catalog.size_of(item)
		var spot := grid.find_free(size)
		if spot.x < 0:
			continue
		grid.place(layout.size() + 1, spot.x, spot.y, size)
		var r := Rect2(Vector2(spot) * _cell, Vector2(size) * _cell).grow(-2)
		inventory.draw_item_icon(c, item, r)
		layout.append([item, r])
	_layouts[c] = layout
	if locked:
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(UiPalette.c("spectral"), 0.7), false, 2.0)
	if bool(state.get("my_confirmed" if c.mine else "their_confirmed", false)):
		# selo "CONFIRMADO" sobre a coluna de quem já aceitou
		var font := UiPalette.font("title")
		var fs := UiPalette.size("strong") + 2
		var txt := "CONFIRMADO"
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var mid := c.size * 0.5
		var band := Rect2(Vector2(0, mid.y - fs * 0.9), Vector2(c.size.x, fs * 1.6))
		c.draw_rect(band, Color(0, 0, 0, 0.55))
		c.draw_rect(band, Color(UiPalette.c("spectral"), 0.8), false, 1.5)
		c.draw_string(font, Vector2(mid.x - tw * 0.5, mid.y + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.c("spectral"))


func _offer_input(c: Offer, event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		return
	c.accept_event()
	if not c.mine:
		return
	if inventory.held_uid() != 0: # soltar um item da mochila aqui = oferecer
		Net.send_trade_action(Protocol.Trade.ADD_ITEM, inventory.held_uid())
		inventory.cancel_held()
		return
	for entry: Array in _layouts.get(c, []):
		if (entry[1] as Rect2).has_point(c.get_local_mouse_position()):
			Net.send_trade_action(Protocol.Trade.REMOVE_ITEM, int(entry[0]["uid"]))
			return


func _make_offer(mine: bool) -> Offer:
	var o := Offer.new()
	o.window = self
	o.mine = mine
	o.custom_minimum_size = Vector2(_cols, _rows) * _cell
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	return o


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(fn)
	return b
