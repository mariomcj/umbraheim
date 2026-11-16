class_name ForgeWindow
extends PanelContainer
## Janela da Forja do Vórtice. Mostra o que está na forja, a receita reconhecida,
## a chance e o custo (prévia calculada com o mesmo RecipeBook do servidor).
## Para colocar itens: botão direito no item do inventário (com a forja aberta)
## ou pegar o item e clicar na mesa da forja. Clique num item da mesa devolve.

var GOLD: Color = UiPalette.c("gold")
var PARCHMENT: Color = UiPalette.c("bone")
const COLS := 6
const ROWS := 4


class Table extends Control:
	var window: ForgeWindow

	func _draw() -> void:
		window._draw_table(self)

	func _gui_input(event: InputEvent) -> void:
		window._table_input(self, event)


var inventory: InventoryWindow
var _book: RecipeBook
var _cell: float
var _table: Table
var _recipe_label: Label
var _chance_label: Label
var _hint_label: Label
var _combine: Button
var _layout: Array = [] # [[uid, Rect2]] para clique
var _chance_pct: int = -1 # chance da receita reconhecida (-1 = nenhuma), desenhada no círculo


func setup(inv: InventoryWindow) -> void:
	inventory = inv


func _ready() -> void:
	_book = RecipeBook.new(GameConfig.table("recipes"), ItemCatalog.from_config())
	_cell = GameConfig.get_f("ui", "inventory_cell_px")
	theme_type_variation = &"WindowPanel"
	position = Vector2(330, 130)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := _label("FORJA DO VÓRTICE", 16, UiPalette.c("ember"))
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_color_override("font_color", UiPalette.c("ember"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var x := Button.new()
	x.text = "×"
	x.pressed.connect(Net.send_npc_close)
	top.add_child(x)
	_table = Table.new()
	_table.window = self
	_table.custom_minimum_size = Vector2(COLS, ROWS) * _cell
	_table.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(_table)
	_recipe_label = _label("", 14, GOLD)
	box.add_child(_recipe_label)
	_chance_label = _label("", 13, PARCHMENT)
	box.add_child(_chance_label)
	_hint_label = _label("", 12, Color(0.65, 0.62, 0.56))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint_label.custom_minimum_size = Vector2(COLS * _cell, 0)
	box.add_child(_hint_label)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_combine = Button.new()
	_combine.text = "Combinar"
	_combine.theme_type_variation = &"PrimaryButton"
	_combine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_combine.pressed.connect(Net.send_forge_combine)
	buttons.add_child(_combine)
	var close := Button.new()
	close.text = "Fechar"
	close.pressed.connect(Net.send_npc_close)
	buttons.add_child(close)
	var help := _label("Botão direito num item do inventário: colocar na forja.\nClique num item da mesa: devolver.", 11, UiPalette.c("bone_dim"))
	help.theme_type_variation = &"HintLabel"
	box.add_child(help)
	visible = false


func open() -> void:
	visible = true
	inventory.npc_mode = "forge"
	if not inventory.visible:
		inventory.toggle()


func close() -> void:
	visible = false
	inventory.npc_mode = ""


func _process(_delta: float) -> void:
	if not visible:
		return
	var items := inventory.items_in(ItemCatalog.CONTAINER_FORGE)
	var e := _book.evaluate(items)
	_chance_pct = roundi(float(e["chance"]) * 100.0) if e["valid"] else -1
	if e["valid"]:
		_recipe_label.text = str(e["name"])
		var currency_name := str(GameConfig.table("drops").get("currency_name", ""))
		_chance_label.text = "Chance: %d%%   ·   Custo: %d %s%s" % [roundi(float(e["chance"]) * 100.0), int(e["cost"]), currency_name,
			"   ·   protegido" if bool(e["protected"]) else ""]
		var refine := int(e["target_uid"]) != 0
		_hint_label.text = ("Se falhar, o item será DESTRUÍDO." if refine and not bool(e["protected"]) else
			("Se falhar, o selo preserva o item." if refine else "Se falhar, os ingredientes se perdem."))
		if e.has("sacrifice"):
			_hint_label.text = "%s será sacrificado, com sucesso ou não. Resultado: um par de asas sorteado." % e["sacrifice"]
		_combine.disabled = inventory.currency < int(e["cost"])
	else:
		_recipe_label.text = "—"
		_chance_label.text = ""
		_hint_label.text = str(e["hint"])
		_combine.disabled = true
	_table.queue_redraw()


func _draw_table(c: Control) -> void:
	UiDraw.well_grid(c, Vector2.ZERO, COLS, ROWS, _cell)
	# círculo rúnico atrás das vagas, com a chance no centro
	var center := c.size * 0.5
	var radius := minf(c.size.x, c.size.y) * 0.46
	var rune_col := UiPalette.c("blood").lightened(0.2) if _chance_pct < 0 else UiPalette.c("ember")
	UiDraw.rune_circle(c, center, radius, rune_col, Time.get_ticks_msec() / 1000.0)
	if _chance_pct >= 0:
		var font := UiPalette.font("title")
		var txt := "%d%%" % _chance_pct
		var fs := UiPalette.size("header") + 4
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		c.draw_string(font, center + Vector2(-tw * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiPalette.c("gold"), 0.35))
	# disposição simples: os itens da forja em fila, cada um no seu tamanho
	_layout.clear()
	var grid := InventoryGrid.new(COLS, ROWS)
	for item: Dictionary in inventory.items_in(ItemCatalog.CONTAINER_FORGE):
		var size := inventory.catalog.size_of(item)
		var spot := grid.find_free(size)
		if spot.x < 0:
			continue
		grid.place(int(item["uid"]), spot.x, spot.y, size)
		var r := Rect2(Vector2(spot) * _cell, Vector2(size) * _cell).grow(-2)
		inventory.draw_item_icon(c, item, r)
		_layout.append([int(item["uid"]), r])
	if inventory.held_uid() != 0 and c.get_global_rect().has_point(c.get_global_mouse_position()):
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.9, 0.3, 0.4, 0.15))


func _table_input(c: Control, event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		return
	c.accept_event()
	if inventory.held_uid() != 0:
		Net.send_item_action(Protocol.ITEM_MOVE, inventory.held_uid(), ItemCatalog.CONTAINER_FORGE, 0, 0)
		inventory.cancel_held()
		return
	var pos := c.get_local_mouse_position()
	for entry: Array in _layout:
		if (entry[1] as Rect2).has_point(pos):
			Net.send_item_action(Protocol.ITEM_MOVE, int(entry[0]), ItemCatalog.CONTAINER_INVENTORY, -1, -1)
			return


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
