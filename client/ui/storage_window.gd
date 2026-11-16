class_name StorageWindow
extends PanelContainer
## Cofre (armazém) do personagem, aberto no Guardião do Cofre. Mesma interação do
## inventário: clique pega/solta (entre o cofre e a mochila), botão direito num item
## da mochila guarda, botão direito num item do cofre retira. O servidor valida tudo.

var GOLD: Color = UiPalette.c("gold")

class Vault extends Control:
	var window: StorageWindow

	func _draw() -> void:
		window._draw_vault(self)

	func _gui_input(event: InputEvent) -> void:
		window._vault_input(self, event)


var inventory: InventoryWindow
var _cell: float
var _cols: int
var _rows: int
var _vault: Vault
var _grid: InventoryGrid
var _was_hovering: bool = false


func setup(inv: InventoryWindow) -> void:
	inventory = inv


func _ready() -> void:
	_cell = GameConfig.get_f("ui", "inventory_cell_px")
	var options := GameConfig.table("item_options")
	_cols = int(options.get("storage_cols", 8))
	_rows = int(options.get("storage_rows", 10))
	theme_type_variation = &"WindowPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := Label.new()
	title.text = "COFRE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var x := Button.new()
	x.text = "×"
	x.pressed.connect(Net.send_npc_close)
	top.add_child(x)
	_vault = Vault.new()
	_vault.window = self
	_vault.custom_minimum_size = Vector2(_cols, _rows) * _cell
	_vault.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(_vault)
	var help := Label.new()
	help.text = "Clique: pegar/soltar · botão direito na mochila: guardar\nbotão direito no cofre: retirar"
	help.theme_type_variation = &"HintLabel"
	box.add_child(help)
	var close := Button.new()
	close.text = "Fechar"
	close.pressed.connect(Net.send_npc_close)
	box.add_child(close)
	visible = false


func open() -> void:
	visible = true
	inventory.npc_mode = "storage"
	if not inventory.visible:
		inventory.toggle()
	_place_beside_inventory.call_deferred()


func close() -> void:
	visible = false
	if inventory.npc_mode == "storage":
		inventory.npc_mode = ""


func _place_beside_inventory() -> void:
	reset_size()
	position = Vector2(inventory.global_position.x - get_combined_minimum_size().x - 10.0, inventory.global_position.y)


func _process(_delta: float) -> void:
	if not visible:
		return
	_grid = InventoryGrid.new(_cols, _rows)
	for item: Dictionary in inventory.items_in(ItemCatalog.CONTAINER_STORAGE):
		_grid.place(int(item["uid"]), int(item["x"]), int(item["y"]), inventory.catalog.size_of(item))
	_vault.queue_redraw()
	var uid := 0
	if inventory.held_uid() == 0 and _vault.get_global_rect().has_point(_vault.get_global_mouse_position()):
		uid = _grid.uid_at(Vector2i((_vault.get_local_mouse_position() / _cell).floor()))
	if uid != 0:
		_was_hovering = true
		inventory.set_external_tooltip(_item(uid), [["Botão direito: retirar", "dim"]])
	elif _was_hovering:
		_was_hovering = false
		inventory.set_external_tooltip({})


func _item(uid: int) -> Dictionary:
	for item: Dictionary in inventory.items_in(ItemCatalog.CONTAINER_STORAGE):
		if int(item["uid"]) == uid:
			return item
	return {}


func _draw_vault(c: Control) -> void:
	UiDraw.well_grid(c, Vector2.ZERO, _cols, _rows, _cell)
	if _grid == null:
		return
	var held := inventory.held_uid()
	var cell := _drop_cell(c.get_local_mouse_position())
	if held != 0 and cell.x >= 0:
		var size := inventory.catalog.size_of(_held_item())
		var fits := _grid.can_place(cell.x, cell.y, size, held)
		var pr := Rect2(Vector2(cell) * _cell, Vector2(size) * _cell)
		var pc := UiPalette.c("ok") if fits else UiPalette.c("danger")
		c.draw_rect(pr, Color(pc, 0.16))
		UiDraw.dashed_rect(c, pr.grow(-1), Color(pc, 0.85))
	for item: Dictionary in inventory.items_in(ItemCatalog.CONTAINER_STORAGE):
		if int(item["uid"]) == held:
			continue
		var r := Rect2(Vector2(int(item["x"]), int(item["y"])) * _cell, Vector2(inventory.catalog.size_of(item)) * _cell)
		inventory.draw_item_icon(c, item, r.grow(-2))


func _held_item() -> Dictionary:
	for item: Dictionary in inventory.items_in(ItemCatalog.CONTAINER_INVENTORY) + inventory.items_in(ItemCatalog.CONTAINER_STORAGE):
		if int(item["uid"]) == inventory.held_uid():
			return item
	return {}


## Canto do item segurado com o mouse no centro dele; (-1,-1) fora do cofre.
func _drop_cell(pos: Vector2) -> Vector2i:
	var held := _held_item()
	if held.is_empty() or not Rect2(Vector2.ZERO, Vector2(_cols, _rows) * _cell).has_point(pos):
		return Vector2i(-1, -1)
	var size := inventory.catalog.size_of(held)
	var corner := pos / _cell - Vector2(size) * 0.5 + Vector2(0.5, 0.5)
	return Vector2i(clampi(floori(corner.x), 0, _cols - size.x), clampi(floori(corner.y), 0, _rows - size.y))


func _vault_input(c: Control, event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed) or _grid == null:
		return
	var mb := event as InputEventMouseButton
	var pos := c.get_local_mouse_position()
	var under := _grid.uid_at(Vector2i((pos / _cell).floor()))
	c.accept_event()
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if inventory.held_uid() != 0:
			inventory.cancel_held()
		elif under != 0:
			Net.send_item_action(Protocol.ITEM_MOVE, under, ItemCatalog.CONTAINER_INVENTORY, -1, -1)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if inventory.held_uid() == 0:
		if under != 0:
			inventory.hold(under)
		return
	var cell := _drop_cell(pos)
	if cell.x >= 0:
		Net.send_item_action(Protocol.ITEM_MOVE, inventory.held_uid(), ItemCatalog.CONTAINER_STORAGE, cell.x, cell.y)
		inventory.cancel_held()
