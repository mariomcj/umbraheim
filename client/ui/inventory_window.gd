class_name InventoryWindow
extends PanelContainer
## Inventário (I ou V): equipamento em "boneco" + grade 8x8 onde cada item ocupa
## seu tamanho (cajado 1x4, manto 2x3...). Estilo clássico: clique pega o item,
## clique de novo solta (na grade, num slot ou fora da janela = jogar no chão).
## Botão direito equipa/desequipa. O servidor valida tudo; a janela só pede.

var GOLD: Color = UiPalette.c("gold")
var PARCHMENT: Color = UiPalette.c("bone")

## Retângulos dos slots de equipamento (px, relativos ao canvas).
const SLOT_RECTS := {
	"pet": Rect2(6, 0, 58, 58), "helm": Rect2(106, 0, 60, 60), "wings": Rect2(194, 0, 74, 60),
	"amulet": Rect2(70, 28, 30, 30),
	"weapon": Rect2(6, 70, 58, 136), "armor": Rect2(100, 70, 72, 98), "shield": Rect2(208, 70, 58, 136),
	"ring1": Rect2(70, 176, 28, 28), "pants": Rect2(100, 176, 72, 60), "ring2": Rect2(176, 176, 28, 28),
	"gloves": Rect2(6, 214, 58, 52), "boots": Rect2(208, 214, 58, 52),
}
const SLOT_LABELS := {
	"pet": "Mascote", "helm": "Elmo", "wings": "Asas", "amulet": "Colar", "weapon": "Arma",
	"armor": "Armadura", "shield": "Escudo", "ring1": "Anel", "pants": "Calças", "ring2": "Anel",
	"gloves": "Luvas", "boots": "Botas",
}


## Desenha o equipamento, a grade e os itens; trata cliques.
class Canvas extends Control:
	var window: InventoryWindow

	func _draw() -> void:
		window._draw_canvas(self)

	func _gui_input(event: InputEvent) -> void:
		window._canvas_input(self, event)

	## Slot vazio: o nome aparece só no tooltip (no slot fica a silhueta-guia).
	func _get_tooltip(at: Vector2) -> String:
		var slot := window._slot_at(at)
		return str(SLOT_LABELS.get(slot, "")) if slot != "" and not window._equipped.has(slot) else ""


## Item "na mão" seguindo o mouse, por cima de tudo.
class HeldLayer extends Control:
	var window: InventoryWindow

	func _draw() -> void:
		window._draw_held(self)


## Aviso para o registro de mensagens (ex.: "clique de novo para vender").
signal notice(text: String)
## Item novo na mochila (comprado, apanhado ou recebido numa troca): nome e cor da raridade.
signal item_gained(item_name: String, color: Color)
signal sfx(event: String) # som de interface (audio.json -> ui)
var _loaded_once: bool = false

var catalog: ItemCatalog
var shop_rules: ShopRules
var player_level: int = 1
var player_class: String = ""
var currency: int = 0
## Janela de NPC aberta ("", "forge", "shop", "storage"): muda o que o botão direito faz
## (mandar para a forja, vender, guardar no cofre).
var npc_mode: String = ""

var _external_tip: Dictionary = {} # tooltip pedido por outra janela: {item, extra}
var _sell_confirm_uid: int = 0
var _sell_confirm_until: int = 0

var _items: Dictionary = {} # uid -> item
var _grid: InventoryGrid
var _equipped: Dictionary = {} # slot -> uid
var _held_uid: int = 0
var _hover_uid: int = 0
var _cell: float
var _grid_origin := Vector2(0, 278)
var _canvas: Canvas
var _held_layer: HeldLayer
var _tooltip: PanelContainer
var _tooltip_box: VBoxContainer
var _currency_label: Label
var _colors: Dictionary = {}
var _tip_colors: Dictionary = {}


func _ready() -> void:
	catalog = ItemCatalog.from_config()
	shop_rules = ShopRules.new(GameConfig.table("shops"), catalog)
	_cell = GameConfig.get_f("ui", "inventory_cell_px")
	_grid = InventoryGrid.new(int(catalog.options["inventory_cols"]), int(catalog.options["inventory_rows"]))
	var rarity: Dictionary = GameConfig.get_value("ui", "rarity_colors")
	for k: String in rarity:
		_colors[k] = GameConfig.color_of(rarity[k])
	_tip_colors = {"name": PARCHMENT, "normal": PARCHMENT, "excellent": _colors.get("excellent", Color.GREEN),
		"ancestral": _colors.get("ancestral", Color.SKY_BLUE), "jewel": _colors.get("jewel", Color.GOLD),
		"blue": UiPalette.c("frost"), "red": UiPalette.c("blood").lightened(0.25), "dim": UiPalette.c("bone_dim")}

	theme_type_variation = &"WindowPanel" # moldura do tema (UiFx: animação e arrastar pelo título)
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -(_grid.cols * _cell + 24.0) - 14.0
	offset_right = -14.0
	offset_top = 52.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var help := Button.new() # as instruções saíram da janela: viram o tooltip do "?"
	help.text = "?"
	help.theme_type_variation = &"CloseButton"
	help.tooltip_text = "Clique: pegar e soltar\nBotão direito: equipar ou usar (com a janela do NPC aberta: vender, guardar, pôr na forja)\nSolte fora da janela: jogar no chão\nJoia segurada sobre um item: aplicar"
	help.focus_mode = Control.FOCUS_NONE
	top.add_child(help)
	var title := Label.new()
	title.text = "INVENTÁRIO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(toggle)
	top.add_child(close)
	_canvas = Canvas.new()
	_canvas.window = self
	_canvas.custom_minimum_size = Vector2(_grid.cols * _cell, _grid_origin.y + _grid.rows * _cell)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(_canvas)
	var footer := HBoxContainer.new() # rodapé: moeda com ícone
	footer.add_theme_constant_override("separation", 6)
	box.add_child(footer)
	var coin := CoinIcon.new()
	coin.custom_minimum_size = Vector2(16, 16)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(coin)
	_currency_label = Label.new()
	_currency_label.theme_type_variation = &"ValueLabel"
	_currency_label.add_theme_color_override("font_color", UiPalette.c("arcane"))
	footer.add_child(_currency_label)

	_held_layer = HeldLayer.new()
	_held_layer.window = self
	_held_layer.top_level = true
	_held_layer.z_index = 50 # acima da loja, do cofre e da forja (criadas depois)
	_held_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_held_layer)
	_tooltip = PanelContainer.new()
	_tooltip.add_theme_stylebox_override("panel", get_theme_stylebox("panel", "TooltipPanel"))
	_tooltip.top_level = true
	_tooltip.z_index = 60
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_box = VBoxContainer.new()
	_tooltip_box.add_theme_constant_override("separation", 1)
	_tooltip.add_child(_tooltip_box)
	_tooltip.visible = false
	add_child(_tooltip)
	visible = false


func toggle() -> void:
	visible = not visible
	if not visible:
		_held_uid = 0
		_tooltip.visible = false


func held_uid() -> int:
	return _held_uid


## O jogo clicou fora da janela segurando um item: joga no chão.
func drop_held_to_world() -> bool:
	if _held_uid == 0:
		return false
	if int(_items.get(_held_uid, {}).get("container", 0)) == ItemCatalog.CONTAINER_STORAGE:
		_held_uid = 0 # do cofre não se joga no chão: só devolve
		return true
	Net.send_item_action(Protocol.ITEM_DROP, _held_uid, 0, 0, 0)
	_held_uid = 0
	return true


func cancel_held() -> void:
	_held_uid = 0


## Outra janela (ex.: cofre) põe um item "na mão".
func hold(uid: int) -> void:
	if _items.has(uid):
		_held_uid = uid
		sfx.emit("item_pick")


## Tooltip de um item mostrado por outra janela (loja, cofre). Chamar a cada frame
## enquanto o mouse estiver sobre o item; {} limpa.
func set_external_tooltip(item: Dictionary, extra: Array = []) -> void:
	_external_tip = {} if item.is_empty() else {"item": item, "extra": extra}


## Itens usáveis da mochila com este efeito, do mais forte para o mais fraco (atalhos Z/X).
func best_consumable(effect_type: String) -> int:
	var best := 0
	var best_amount := -1.0
	for item: Dictionary in _items.values():
		var effect := catalog.use_effect(item)
		if int(item["container"]) != ItemCatalog.CONTAINER_INVENTORY or str(effect.get("type", "")) != effect_type:
			continue
		if catalog.level_req(item) > player_level:
			continue
		if float(effect.get("amount", 0.0)) > best_amount:
			best_amount = float(effect.get("amount", 0.0))
			best = int(item["uid"])
	return best


func count_consumable(effect_type: String) -> int:
	var n := 0
	for item: Dictionary in _items.values():
		if int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY and str(catalog.use_effect(item).get("type", "")) == effect_type:
			n += int(item.get("count", 1))
	return n


func items_in(container: int) -> Array:
	var out: Array = []
	for item: Dictionary in _items.values():
		if int(item["container"]) == container:
			out.append(item)
	return out


## Som do que mudou entre o estado anterior e o novo: equipar, mudar de lugar ou sair da mochila.
func _move_sound(known: Dictionary) -> String:
	var placed := false
	var left := false
	for uid: int in known:
		var old: Dictionary = known[uid]
		if not _items.has(uid):
			left = left or int(old["container"]) == ItemCatalog.CONTAINER_INVENTORY
			continue
		var now: Dictionary = _items[uid]
		var c := int(now["container"])
		if c != int(old["container"]) and c >= 1 and c <= ItemCatalog.EQUIP_SLOTS.size():
			return "item_equip"
		if c != int(old["container"]) or int(now["x"]) != int(old["x"]) or int(now["y"]) != int(old["y"]):
			placed = true
	if placed or left:
		return "item_place"
	return ""


func draw_item_icon(c: Control, item: Dictionary, r: Rect2) -> void:
	_draw_item(c, item, r)


func set_items(encoded: Array) -> void:
	var known := _items.duplicate()
	var first := not _loaded_once
	_loaded_once = true
	_items.clear()
	_equipped.clear()
	_grid = InventoryGrid.new(_grid.cols, _grid.rows)
	for a: PackedInt32Array in encoded:
		var item := ItemCodec.decode(a, catalog)
		if item.is_empty():
			continue
		_items[item["uid"]] = item
		var c := int(item["container"])
		if c == ItemCatalog.CONTAINER_INVENTORY:
			_grid.place(int(item["uid"]), int(item["x"]), int(item["y"]), catalog.size_of(item))
		elif c >= 1 and c <= ItemCatalog.EQUIP_SLOTS.size():
			_equipped[ItemCatalog.EQUIP_SLOTS[c - 1]] = int(item["uid"])
	if not _items.has(_held_uid):
		_held_uid = 0
	if not first:
		for uid: int in _items:
			if not known.has(uid) and int(_items[uid]["container"]) == ItemCatalog.CONTAINER_INVENTORY:
				item_gained.emit(catalog.display_name(_items[uid]), _rarity_color(_items[uid]))
		var ev := _move_sound(known)
		if ev != "":
			sfx.emit(ev)
	_canvas.queue_redraw()


func set_player(level: int, money: int) -> void:
	player_level = level
	if _loaded_once and money != currency:
		sfx.emit("coins")
	currency = money
	_currency_label.text = "%d %s" % [money, GameConfig.table("drops").get("currency_name", "")]


func _process(_delta: float) -> void:
	if not visible:
		_external_tip = {}
		return
	_held_layer.position = Vector2.ZERO
	_held_layer.size = get_viewport_rect().size
	_held_layer.queue_redraw()
	_canvas.queue_redraw()
	_update_tooltip()


# ---------------------------------------------------------------- desenho

func _draw_canvas(c: Control) -> void:
	# silhueta vaga do personagem atrás do boneco (linha fina)
	var fig := UiPalette.c("gold_dim", 0.12)
	var body_c := Vector2(136, 130)
	c.draw_arc(body_c + Vector2(0, -98), 22.0, 0.0, TAU, 24, fig, 1.0, true)
	c.draw_polyline(PackedVector2Array([body_c + Vector2(-60, -60), body_c + Vector2(-20, -72), body_c + Vector2(20, -72),
		body_c + Vector2(60, -60), body_c + Vector2(48, 40), body_c + Vector2(30, 140), body_c + Vector2(-30, 140),
		body_c + Vector2(-48, 40), body_c + Vector2(-60, -60)]), fig, 1.0, true)
	var held := _items.get(_held_uid, {}) as Dictionary
	for slot: String in SLOT_RECTS:
		var r: Rect2 = SLOT_RECTS[slot]
		var ok := not held.is_empty() and catalog.fits_slot(held, slot)
		c.draw_rect(r, UiPalette.c("well", 0.92))
		c.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(0, 0, 0, 0.5))
		c.draw_rect(r, UiPalette.c("gold") if ok else UiPalette.c("iron_edge"), false, 2.0 if ok else 1.0)
		if not _equipped.has(slot):
			UiDraw.slot_silhouette(c, slot, r)
		elif _equipped[slot] != _held_uid:
			_draw_item(c, _items[_equipped[slot]], r.grow(-3))
	UiDraw.well_grid(c, _grid_origin, _grid.cols, _grid.rows, _cell)
	# prévia de onde o item segurado cairia (borda tracejada verde ou vermelha)
	if _held_uid != 0:
		var target := _drop_cell(c.get_local_mouse_position())
		if target.x >= 0:
			var size := catalog.size_of(_items[_held_uid])
			var fits := _grid.can_place(target.x, target.y, size, _held_uid)
			var pr := Rect2(_grid_origin + Vector2(target) * _cell, Vector2(size) * _cell)
			var pc := UiPalette.c("ok") if fits else UiPalette.c("danger")
			c.draw_rect(pr, Color(pc, 0.16))
			UiDraw.dashed_rect(c, pr.grow(-1), Color(pc, 0.85))
	for uid: int in _items:
		var item: Dictionary = _items[uid]
		if int(item["container"]) != ItemCatalog.CONTAINER_INVENTORY or uid == _held_uid:
			continue
		var r := Rect2(_grid_origin + Vector2(int(item["x"]), int(item["y"])) * _cell, Vector2(catalog.size_of(item)) * _cell)
		_draw_item(c, item, r.grow(-2))


func _draw_held(c: Control) -> void:
	if _held_uid == 0 or not _items.has(_held_uid):
		return
	var item: Dictionary = _items[_held_uid]
	var size := Vector2(catalog.size_of(item)) * _cell
	var r := Rect2(c.get_local_mouse_position() - size * 0.5, size)
	c.draw_rect(Rect2(r.position + Vector2(5, 7), r.size), Color(0, 0, 0, 0.4)) # sombra
	_draw_item(c, item, r, 0.85)


## Ícone provisório: fundo, forma pela categoria, cor da raridade, nível no canto.
func _draw_item(c: Control, item: Dictionary, r: Rect2, alpha: float = 1.0) -> void:
	var b := catalog.base(item)
	var vis: Dictionary = b.get("visual", {})
	var col := GameConfig.color_of(vis.get("color"), Color.GRAY)
	var glow := GameConfig.color_of(vis.get("glow"), Color.WHITE)
	var border := _rarity_color(item)
	c.draw_rect(r, Color(0.08, 0.07, 0.075, 0.95 * alpha))
	c.draw_rect(r, Color(border, 0.12 * alpha)) # fundo na cor da raridade
	var center := r.get_center()
	var kind := str(b.get("kind", ""))
	var s := minf(r.size.x, r.size.y)
	if kind == "jewel":
		var j := s * 0.32
		c.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -j), center + Vector2(j * 0.8, 0), center + Vector2(0, j), center + Vector2(-j * 0.8, 0)]), Color(glow, alpha))
		c.draw_circle(center, j * 0.3, Color(1, 1, 1, 0.6 * alpha))
	else:
		match str(vis.get("mesh", "")):
			"potion":
				c.draw_circle(center + Vector2(0, s * 0.1), s * 0.26, Color(col, alpha))
				c.draw_rect(Rect2(center + Vector2(-s * 0.07, -s * 0.34), Vector2(s * 0.14, s * 0.2)), Color(0.75, 0.72, 0.65, alpha))
				c.draw_circle(center + Vector2(-s * 0.08, 0.0), s * 0.06, Color(glow, 0.8 * alpha))
			"scroll":
				c.draw_rect(Rect2(center - Vector2(s * 0.3, s * 0.22), Vector2(s * 0.6, s * 0.44)), Color(col, alpha))
				c.draw_line(center + Vector2(-s * 0.18, -s * 0.06), center + Vector2(s * 0.18, -s * 0.06), Color(0.3, 0.2, 0.1, alpha), 1.5)
				c.draw_line(center + Vector2(-s * 0.18, s * 0.06), center + Vector2(s * 0.12, s * 0.06), Color(0.3, 0.2, 0.1, alpha), 1.5)
			"sword":
				c.draw_line(Vector2(center.x, r.position.y + 6), Vector2(center.x, r.end.y - 14), Color(0.75, 0.75, 0.8, alpha), 5.0)
				c.draw_line(Vector2(center.x - 9, r.end.y - 14), Vector2(center.x + 9, r.end.y - 14), Color(col.lightened(0.3), alpha), 4.0)
				c.draw_line(Vector2(center.x, r.end.y - 14), Vector2(center.x, r.end.y - 4), Color(col, alpha), 4.0)
				c.draw_circle(Vector2(center.x, r.position.y + 14), 3.0, Color(glow, alpha))
			"gem":
				var g := s * 0.26
				c.draw_colored_polygon(PackedVector2Array([center + Vector2(-g, -g * 0.3), center + Vector2(0, -g), center + Vector2(g, -g * 0.3), center + Vector2(g * 0.6, g), center + Vector2(-g * 0.6, g)]), Color(col, alpha))
				c.draw_circle(center, g * 0.35, Color(glow, 0.7 * alpha))
			"book":
				c.draw_rect(r.grow(-s * 0.18), Color(col, alpha))
				c.draw_circle(center, s * 0.16, Color(glow, alpha))
			"staff":
				c.draw_line(Vector2(center.x, r.position.y + 10), Vector2(center.x, r.end.y - 6), Color(col.lightened(0.3), alpha), 5.0)
				c.draw_circle(Vector2(center.x, r.position.y + 10), 6.0, Color(glow, alpha))
			"shield":
				c.draw_circle(center, minf(r.size.x, r.size.y) * 0.36, Color(col.lightened(0.2), alpha))
			"wings":
				# duas asas em leque, a partir do centro
				for side in [-1.0, 1.0]:
					for i in 4:
						var a := lerpf(-0.6, 0.5, i / 3.0)
						var reach := r.size.x * lerpf(0.42, 0.26, i / 3.0)
						var tip := center + Vector2(cos(a) * side, -sin(a)) * reach
						c.draw_line(center, tip, Color(col.lightened(0.35), alpha), 4.0 - i * 0.5)
					c.draw_circle(center + Vector2(side * r.size.x * 0.32, -r.size.y * 0.18), 3.0, Color(glow, alpha))
			_:
				c.draw_rect(r.grow(-minf(r.size.x, r.size.y) * 0.22), Color(col.lightened(0.25), alpha))
	var lvl := int(item.get("level", 0))
	if lvl > 0:
		c.draw_string(ThemeDB.fallback_font, r.position + Vector2(3, 12), "+%d" % lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(GOLD, alpha))
	if lvl >= 7: # brilho pulsante a partir de +7
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 3.0)
		c.draw_rect(r.grow(-1), Color(glow, (0.12 + 0.05 * (lvl - 7)) * (0.6 + 0.4 * pulse) * alpha), false, 3.0)
	var count := int(item.get("count", 1))
	if count > 1:
		c.draw_string(ThemeDB.fallback_font, Vector2(r.position.x + 2, r.end.y - 3), str(count), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 4, 11, Color(PARCHMENT, alpha))
	c.draw_rect(r, Color(border, alpha), false, 1.5)


## Moeda do rodapé.
class CoinIcon extends Control:
	func _draw() -> void:
		UiDraw.coin(self, size * 0.5, minf(size.x, size.y) * 0.45)


func _rarity_color(item: Dictionary) -> Color:
	if str(catalog.base(item).get("kind", "")) == "jewel":
		return _colors.get("jewel", Color.GOLD)
	match int(item.get("rarity", 0)):
		ItemCatalog.RARITY_EXCELLENT:
			return _colors.get("excellent", Color.GREEN)
		ItemCatalog.RARITY_ANCESTRAL:
			return _colors.get("ancestral", Color.SKY_BLUE)
	return UiPalette.c("bone_dim", 0.7)


# ---------------------------------------------------------------- interação

func _item_at(pos: Vector2) -> int:
	for slot: String in SLOT_RECTS:
		if (SLOT_RECTS[slot] as Rect2).has_point(pos) and _equipped.has(slot):
			return _equipped[slot]
	var cell := Vector2i(((pos - _grid_origin) / _cell).floor())
	return _grid.uid_at(cell)


func _slot_at(pos: Vector2) -> String:
	for slot: String in SLOT_RECTS:
		if (SLOT_RECTS[slot] as Rect2).has_point(pos):
			return slot
	return ""


## Célula de canto do item segurado com o mouse no centro dele; (-1,-1) fora da grade.
func _drop_cell(pos: Vector2) -> Vector2i:
	if not Rect2(_grid_origin, Vector2(_grid.cols, _grid.rows) * _cell).has_point(pos) or _held_uid == 0:
		return Vector2i(-1, -1)
	var size := catalog.size_of(_items[_held_uid])
	var corner := (pos - _grid_origin) / _cell - Vector2(size) * 0.5 + Vector2(0.5, 0.5)
	return Vector2i(clampi(floori(corner.x), 0, _grid.cols - size.x), clampi(floori(corner.y), 0, _grid.rows - size.y))


func _canvas_input(c: Control, event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		if event is InputEventMouseMotion:
			_hover_uid = _item_at(c.get_local_mouse_position())
		return
	var pos := c.get_local_mouse_position()
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		var uid := _item_at(pos)
		if _held_uid != 0:
			_held_uid = 0
		elif uid != 0:
			_right_click_item(_items[uid])
		c.accept_event()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	c.accept_event()
	if _held_uid == 0:
		_held_uid = _item_at(pos)
		if _held_uid != 0:
			sfx.emit("item_pick")
		return
	var slot := _slot_at(pos)
	if slot != "":
		Net.send_item_action(Protocol.ITEM_MOVE, _held_uid, 1 + ItemCatalog.EQUIP_SLOTS.find(slot), 0, 0)
		_held_uid = 0
		return
	var under := _item_at(pos)
	var held: Dictionary = _items[_held_uid]
	if under != 0 and under != _held_uid and str(catalog.base(held).get("kind", "")) == "jewel":
		Net.send_item_action(Protocol.ITEM_USE_ON, _held_uid, under, 0, 0)
		_held_uid = 0
		return
	var cell := _drop_cell(pos)
	if cell.x >= 0:
		Net.send_item_action(Protocol.ITEM_MOVE, _held_uid, ItemCatalog.CONTAINER_INVENTORY, cell.x, cell.y)
		_held_uid = 0


## Botão direito num item da mochila ou equipado, conforme a janela de NPC aberta.
func _right_click_item(item: Dictionary) -> void:
	var uid := int(item["uid"])
	var in_bag := int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY
	if in_bag and npc_mode == "forge":
		Net.send_item_action(Protocol.ITEM_MOVE, uid, ItemCatalog.CONTAINER_FORGE, 0, 0)
	elif in_bag and npc_mode == "trade":
		Net.send_trade_action(Protocol.Trade.ADD_ITEM, uid)
	elif in_bag and npc_mode == "storage":
		Net.send_item_action(Protocol.ITEM_MOVE, uid, ItemCatalog.CONTAINER_STORAGE, -1, -1)
	elif in_bag and npc_mode == "shop":
		var now := Time.get_ticks_msec()
		if shop_rules.needs_sell_confirm(item) and not (_sell_confirm_uid == uid and now < _sell_confirm_until):
			_sell_confirm_uid = uid
			_sell_confirm_until = now + 3000
			notice.emit("Vender %s por %d %s? Botão direito de novo para confirmar." % [catalog.display_name(item),
				shop_rules.sell_price(item), GameConfig.table("drops").get("currency_name", "")])
			return
		_sell_confirm_uid = 0
		Net.send_shop_sell(uid)
	elif in_bag and not catalog.use_effect(item).is_empty():
		Net.send_item_action(Protocol.ITEM_USE, uid, 0, 0, 0)
	else:
		Net.send_item_action(Protocol.ITEM_AUTO, uid, 0, 0, 0)


var _debug_tooltip: bool = "--debug-tooltip" in OS.get_cmdline_user_args()


func _update_tooltip() -> void:
	var uid := _hover_uid if _held_uid == 0 and _canvas.get_global_rect().has_point(get_global_mouse_position()) else 0
	if _debug_tooltip and _equipped.has("weapon"):
		uid = _equipped["weapon"] # debug: mostra o tooltip da arma sem precisar do mouse
	var item: Dictionary = _items.get(uid, {})
	var extra: Array = []
	if not item.is_empty() and npc_mode == "shop" and int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY:
		extra = [["Venda: %d %s (botão direito)" % [shop_rules.sell_price(item), GameConfig.table("drops").get("currency_name", "")], "jewel"]]
	if item.is_empty() and not _external_tip.is_empty() and _held_uid == 0:
		item = _external_tip["item"]
		extra = _external_tip["extra"]
	if item.is_empty():
		_tooltip.visible = false
		return
	var key := hash([item, extra, player_level, player_class])
	if _tooltip.get_meta("key", 0) != key or not _tooltip.visible:
		for child in _tooltip_box.get_children():
			child.queue_free()
		var lines := catalog.tooltip_lines(item, player_level, player_class)
		lines.append_array(extra)
		var base_count := lines.size() - extra.size()
		for i in lines.size():
			var line: Array = lines[i]
			if i == base_count and base_count > 1: # separador antes do preço ou da venda
				_tooltip_box.add_child(HSeparator.new())
			var l := Label.new()
			l.text = str(line[0])
			if i == 0: # nome em Cinzel na cor da raridade
				l.add_theme_font_override("font", UiPalette.font("title"))
				l.add_theme_font_size_override("font_size", UiPalette.size("strong") + 1)
			else:
				l.add_theme_font_size_override("font_size", UiPalette.size("hint") + 1)
			l.add_theme_color_override("font_color", _tip_colors.get(str(line[1]), PARCHMENT))
			_tooltip_box.add_child(l)
			if i == 0 and lines.size() > 1 and base_count > 1:
				_tooltip_box.add_child(HSeparator.new())
		_tooltip.set_meta("key", key)
		_tooltip.reset_size()
	_tooltip.visible = true
	_tooltip.size = Vector2.ZERO # encolhe para o conteúdo atual
	var m := get_global_mouse_position()
	var vp := get_viewport_rect().size
	var tsize := _tooltip.get_combined_minimum_size()
	_tooltip.position = Vector2(clampf(m.x - tsize.x - 16.0, 4.0, vp.x - tsize.x - 4.0), clampf(m.y + 8.0, 4.0, vp.y - tsize.y - 4.0))
