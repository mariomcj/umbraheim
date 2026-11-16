class_name ShopWindow
extends PanelContainer
## Loja de um NPC (ferreiro, alquimista). Mostra o estoque em grade com o preço no
## tooltip. Clique compra 1; Shift+clique compra uma pilha (empilháveis).
## Vender: botão direito num item da mochila enquanto a loja está aberta.
## Os preços vêm de ShopRules, os mesmos que o servidor cobra.

var GOLD: Color = UiPalette.c("gold")
var PARCHMENT: Color = UiPalette.c("bone")
const COLS := 8
const ROWS := 6


class Shelf extends Control:
	var window: ShopWindow

	func _draw() -> void:
		window._draw_shelf(self)

	func _gui_input(event: InputEvent) -> void:
		window._shelf_input(self, event)


var inventory: InventoryWindow
var _rules: ShopRules
var _cell: float
var _shelf: Shelf
var _title: Label
var _greeting: Label
var _stock := PackedStringArray()
var _layout: Array = [] # [[índice no estoque, Rect2, item de exibição]]
var _buy_stack: int = 1
var _currency_name: String


func setup(inv: InventoryWindow) -> void:
	inventory = inv


func _ready() -> void:
	_rules = ShopRules.new(GameConfig.table("shops"), ItemCatalog.from_config())
	_cell = GameConfig.get_f("ui", "inventory_cell_px")
	_buy_stack = int(GameConfig.table("shops").get("buy_stack", 1))
	_currency_name = str(GameConfig.table("drops").get("currency_name", ""))
	theme_type_variation = &"WindowPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_title = _label("", 16, GOLD)
	_title.theme_type_variation = &"TitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var x := Button.new()
	x.text = "×"
	x.pressed.connect(Net.send_npc_close)
	top.add_child(x)
	_greeting = _label("", 12, UiPalette.c("bone_dim"))
	_greeting.theme_type_variation = &"LoreLabel"
	_greeting.autowrap_mode = TextServer.AUTOWRAP_WORD
	_greeting.custom_minimum_size = Vector2(COLS * _cell, 0)
	box.add_child(_greeting)
	_shelf = Shelf.new()
	_shelf.window = self
	_shelf.custom_minimum_size = Vector2(COLS, ROWS) * _cell
	_shelf.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(_shelf)
	var help := _label("Clique: comprar · Shift+clique: comprar %d\nBotão direito num item da mochila: vender" % _buy_stack, 11, UiPalette.c("bone_dim"))
	help.theme_type_variation = &"HintLabel"
	box.add_child(help)
	var close := Button.new()
	close.text = "Fechar"
	close.pressed.connect(Net.send_npc_close)
	box.add_child(close)
	visible = false


func open(shop_id: String) -> void:
	var shop := _rules.shop(shop_id)
	_stock = _rules.stock(shop_id)
	_title.text = str(shop.get("title", "Loja")).to_upper()
	_greeting.text = "“%s”" % str(shop.get("greeting", ""))
	visible = true
	inventory.npc_mode = "shop"
	if not inventory.visible:
		inventory.toggle()
	_place_beside_inventory.call_deferred()


func close() -> void:
	visible = false
	if inventory.npc_mode == "shop":
		inventory.npc_mode = ""


func _place_beside_inventory() -> void:
	reset_size()
	position = Vector2(inventory.global_position.x - get_combined_minimum_size().x - 10.0, inventory.global_position.y)


func _process(_delta: float) -> void:
	if not visible:
		return
	_shelf.queue_redraw()
	var hover := _entry_at(_shelf.get_local_mouse_position()) if _shelf.get_global_rect().has_point(_shelf.get_global_mouse_position()) else []
	if hover.is_empty():
		if _was_hovering:
			inventory.set_external_tooltip({})
		_was_hovering = false
		return
	_was_hovering = true
	var item: Dictionary = hover[2]
	var price := _price(str(item["base"]), 1)
	var extra: Array = [["Preço: %d %s" % [price, _currency_name], "jewel" if inventory.currency >= price else "red"]]
	if tax_pct > 0.0:
		extra.append(["inclui %d%% de imposto do castelo (%s)" % [roundi(tax_pct * 100.0), tax_owner], "dim"])
	if inventory.catalog.stack_max(item) > 1:
		var n := mini(_buy_stack, inventory.catalog.stack_max(item))
		extra.append(["Shift+clique: %d por %d %s" % [n, _price(str(item["base"]), n), _currency_name], "dim"])
	inventory.set_external_tooltip(item, extra)


var _was_hovering: bool = false
var tax_pct: float = 0.0 # imposto do castelo (rpc_castle_state)
var tax_owner: String = ""


## Preço de compra com o imposto do castelo, igual ao do servidor.
func _price(base_id: String, count: int) -> int:
	var total := _rules.buy_price(base_id) * count
	return total + CastleSystem.tax_on(total, tax_pct)


func _draw_shelf(c: Control) -> void:
	UiDraw.well_grid(c, Vector2.ZERO, COLS, ROWS, _cell)
	_layout.clear()
	var grid := InventoryGrid.new(COLS, ROWS)
	for i in _stock.size():
		var item := {"uid": -(i + 1), "base": _stock[i], "level": 0, "rarity": 0, "luck": false, "extra": 0, "exc": [], "count": 1}
		var size := inventory.catalog.size_of(item)
		var spot := grid.find_free(size)
		if spot.x < 0:
			continue
		grid.place(i + 1, spot.x, spot.y, size)
		var r := Rect2(Vector2(spot) * _cell, Vector2(size) * _cell).grow(-2)
		inventory.draw_item_icon(c, item, r)
		if inventory.currency < _price(_stock[i], 1):
			c.draw_rect(r, Color(0.3, 0.0, 0.0, 0.35)) # caro demais
		# preço no pé do item, com a moeda
		var price := _price(_stock[i], 1)
		var font := UiPalette.font("body_bold")
		var txt := str(price)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var at := Vector2(r.end.x - tw - 3, r.end.y - 3)
		c.draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.9))
		c.draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			UiPalette.c("arcane") if inventory.currency >= price else UiPalette.c("blood").lightened(0.3))
		UiDraw.coin(c, Vector2(at.x - 6, at.y - 4), 3.5)
		_layout.append([i, r, item])


func _entry_at(pos: Vector2) -> Array:
	for entry: Array in _layout:
		if (entry[1] as Rect2).has_point(pos):
			return entry
	return []


func _shelf_input(c: Control, event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		return
	c.accept_event()
	if inventory.held_uid() != 0:
		inventory.cancel_held()
		return
	var entry := _entry_at(c.get_local_mouse_position())
	if entry.is_empty():
		return
	var quantity := 1
	if (event as InputEventMouseButton).shift_pressed:
		quantity = mini(_buy_stack, inventory.catalog.stack_max(entry[2]))
	Net.send_shop_buy(int(entry[0]), quantity)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
