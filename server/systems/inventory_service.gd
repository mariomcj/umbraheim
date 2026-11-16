class_name InventoryService
extends RefCounted
## Operações autoritativas de inventário, equipamento e armazém de um jogador.
## Toda movimentação pedida pelo cliente passa por aqui e é validada (espaço na grade,
## slot compatível, nível exigido). Retorna "" em caso de sucesso ou a mensagem de erro.

var catalog: ItemCatalog
var cols: int
var rows: int
var storage_cols: int
var storage_rows: int


func _init(item_catalog: ItemCatalog) -> void:
	catalog = item_catalog
	cols = int(catalog.options.get("inventory_cols", 8))
	rows = int(catalog.options.get("inventory_rows", 8))
	storage_cols = int(catalog.options.get("storage_cols", 8))
	storage_rows = int(catalog.options.get("storage_rows", 10))


func init_player(p: ServerPlayer) -> void:
	p.inventory = InventoryGrid.new(cols, rows)
	p.storage = InventoryGrid.new(storage_cols, storage_rows)
	p.items.clear()
	p.equipment.clear()


## Coloca um item novo no inventário: primeiro completa pilhas iguais, depois ocupa
## a primeira posição livre. Só altera o inventário se couber tudo.
func give(p: ServerPlayer, item: Dictionary) -> bool:
	if not has_room(p, item):
		return false
	var left := int(item.get("count", 1))
	for stack in _stacks_of(p, item):
		var room := catalog.stack_max(item) - int(stack["count"])
		var n := mini(room, left)
		stack["count"] = int(stack["count"]) + n
		left -= n
		if left == 0:
			return true
	item["count"] = left
	var spot := p.inventory.find_free(catalog.size_of(item))
	p.inventory.place(int(item["uid"]), spot.x, spot.y, catalog.size_of(item))
	item["container"] = ItemCatalog.CONTAINER_INVENTORY
	item["x"] = spot.x
	item["y"] = spot.y
	p.items[item["uid"]] = item
	return true


## O item (com sua quantidade) cabe no inventário?
func has_room(p: ServerPlayer, item: Dictionary) -> bool:
	var left := int(item.get("count", 1))
	for stack in _stacks_of(p, item):
		left -= catalog.stack_max(item) - int(stack["count"])
	return left <= 0 or p.inventory.find_free(catalog.size_of(item)).x >= 0


## Pilhas do mesmo item na mochila (só para empilháveis).
func _stacks_of(p: ServerPlayer, item: Dictionary) -> Array:
	var out: Array = []
	if catalog.stack_max(item) <= 1:
		return out
	for other: Dictionary in p.items.values():
		if int(other["container"]) == ItemCatalog.CONTAINER_INVENTORY and str(other["base"]) == str(item["base"]) \
				and int(other["uid"]) != int(item["uid"]) and int(other.get("count", 1)) < catalog.stack_max(item):
			out.append(other)
	return out


## Equipa direto (itens iniciais), sem passar pela grade.
func equip_direct(p: ServerPlayer, item: Dictionary) -> bool:
	var slot := catalog.default_slot(item)
	if slot == "" or p.equipment.has(slot):
		return false
	p.items[item["uid"]] = item
	_set_equipped(p, item, slot)
	return true


func move_to_inventory(p: ServerPlayer, uid: int, x: int, y: int) -> String:
	var item: Dictionary = p.items.get(uid, {})
	if item.is_empty():
		return "Item inexistente."
	if int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY:
		return "" if p.inventory.move(uid, x, y) else "Não cabe aí."
	if x < 0: # "qualquer lugar livre"
		var free := p.inventory.find_free(catalog.size_of(item))
		if free.x < 0:
			return "Inventário cheio."
		x = free.x
		y = free.y
	if not p.inventory.can_place(x, y, catalog.size_of(item)):
		return "Não cabe aí."
	_detach(p, item)
	p.inventory.place(uid, x, y, catalog.size_of(item))
	item["container"] = ItemCatalog.CONTAINER_INVENTORY
	item["x"] = x
	item["y"] = y
	return ""


func equip(p: ServerPlayer, uid: int, slot: String) -> String:
	var item: Dictionary = p.items.get(uid, {})
	if item.is_empty():
		return "Item inexistente."
	if not catalog.fits_slot(item, slot):
		return "Este item não vai nesse lugar."
	if p.level < catalog.level_req(item):
		return "Nível insuficiente (precisa de %d)." % catalog.level_req(item)
	if not catalog.allowed_for(item, p.class_id):
		return "Sua classe não usa este item."
	if p.equipment.get(slot, 0) == uid:
		return ""
	var from_inventory := int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY
	var origin := p.inventory.rect_of(uid).position
	_detach(p, item)
	# troca: o item que estava no slot volta para o inventário
	if p.equipment.has(slot):
		var old: Dictionary = p.items[p.equipment[slot]]
		_unequip(p, old)
		var size := catalog.size_of(old)
		var spot := origin if from_inventory and p.inventory.can_place(origin.x, origin.y, size) else p.inventory.find_free(size)
		if spot.x < 0:
			# sem espaço: desfaz tudo
			_set_equipped(p, old, slot)
			if from_inventory:
				p.inventory.place(uid, origin.x, origin.y, catalog.size_of(item))
			return "Inventário cheio."
		p.inventory.place(int(old["uid"]), spot.x, spot.y, size)
		old["container"] = ItemCatalog.CONTAINER_INVENTORY
		old["x"] = spot.x
		old["y"] = spot.y
	_set_equipped(p, item, slot)
	return ""


## Botão direito: equipa (no slot padrão ou no segundo anel) ou desequipa para um lugar livre.
func auto(p: ServerPlayer, uid: int) -> String:
	var item: Dictionary = p.items.get(uid, {})
	if item.is_empty():
		return "Item inexistente."
	if int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY:
		var slot := catalog.default_slot(item)
		if slot == "":
			return "Este item não pode ser equipado."
		if slot == "ring1" and p.equipment.has("ring1") and not p.equipment.has("ring2"):
			slot = "ring2"
		return equip(p, uid, slot)
	var spot := p.inventory.find_free(catalog.size_of(item))
	if spot.x < 0:
		return "Inventário cheio."
	return move_to_inventory(p, uid, spot.x, spot.y)


## Tira o item do jogador (para jogar no chão, vender ou consumir). Retorna o item ou {}.
func take(p: ServerPlayer, uid: int) -> Dictionary:
	var item: Dictionary = p.items.get(uid, {})
	if item.is_empty():
		return {}
	_detach(p, item)
	p.items.erase(uid)
	return item


## Gasta uma unidade de uma pilha (ou o item inteiro).
func consume_one(p: ServerPlayer, uid: int) -> void:
	var item: Dictionary = p.items.get(uid, {})
	if item.is_empty():
		return
	if int(item.get("count", 1)) > 1:
		item["count"] = int(item["count"]) - 1
	else:
		take(p, uid)


# ---------------------------------------------------------------- armazém

## Mochila -> armazém (x < 0 = primeiro lugar livre).
func to_storage(p: ServerPlayer, uid: int, x: int, y: int) -> String:
	var item: Dictionary = p.items.get(uid, {})
	if item.is_empty():
		return "Item inexistente."
	var size := catalog.size_of(item)
	if int(item["container"]) == ItemCatalog.CONTAINER_STORAGE:
		return "" if x >= 0 and p.storage.move(uid, x, y) else "Não cabe aí."
	if int(item["container"]) != ItemCatalog.CONTAINER_INVENTORY:
		return "Só itens da mochila vão para o cofre (desequipe antes)."
	if x < 0:
		var free := p.storage.find_free(size)
		if free.x < 0:
			return "O cofre está cheio."
		x = free.x
		y = free.y
	if not p.storage.can_place(x, y, size):
		return "Não cabe aí."
	_detach(p, item)
	p.storage.place(uid, x, y, size)
	item["container"] = ItemCatalog.CONTAINER_STORAGE
	item["x"] = x
	item["y"] = y
	return ""


# ---------------------------------------------------------------- Forja do Vórtice

func to_forge(p: ServerPlayer, uid: int) -> String:
	var item: Dictionary = p.items.get(uid, {})
	if item.is_empty() or int(item["container"]) != ItemCatalog.CONTAINER_INVENTORY:
		return "Só itens da mochila vão para a forja (desequipe antes)."
	_detach(p, item)
	item["container"] = ItemCatalog.CONTAINER_FORGE
	item["x"] = 0
	item["y"] = 0
	return ""


func forge_items(p: ServerPlayer) -> Array:
	return items_in(p, ItemCatalog.CONTAINER_FORGE)


func items_in(p: ServerPlayer, container: int) -> Array:
	var out: Array = []
	for item: Dictionary in p.items.values():
		if int(item["container"]) == container:
			out.append(item)
	return out


## Devolve tudo da forja para a mochila; o que não couber é retornado (vai para o chão).
func return_forge(p: ServerPlayer) -> Array:
	return return_container(p, ItemCatalog.CONTAINER_FORGE)


func return_container(p: ServerPlayer, container: int) -> Array:
	var leftovers: Array = []
	for item: Dictionary in items_in(p, container):
		if move_to_inventory(p, int(item["uid"]), -1, -1) != "":
			leftovers.append(take(p, int(item["uid"])))
	return leftovers


# ---------------------------------------------------------------- troca

## Mochila -> oferta da troca (sai da grade; volta se a troca for cancelada).
func to_trade(p: ServerPlayer, uid: int) -> String:
	var item: Dictionary = p.items.get(uid, {})
	if catalog.is_quest_item(item):
		return "Itens de missão não se trocam."
	if item.is_empty() or int(item["container"]) != ItemCatalog.CONTAINER_INVENTORY:
		return "Só itens da mochila podem ser oferecidos (desequipe antes)."
	_detach(p, item)
	item["container"] = ItemCatalog.CONTAINER_TRADE
	item["x"] = 0
	item["y"] = 0
	return ""


## Cabem todos estes itens na mochila do jogador? (simulação sem empilhar = pior caso)
func fits_all(p: ServerPlayer, incoming: Array) -> bool:
	var g := p.inventory.clone()
	var fake_uid := -1
	for item: Dictionary in incoming:
		var size := catalog.size_of(item)
		var spot := g.find_free(size)
		if spot.x < 0:
			return false
		g.place(fake_uid, spot.x, spot.y, size)
		fake_uid -= 1
	return true


func encode_all(p: ServerPlayer) -> Array:
	var out: Array = []
	for item: Dictionary in p.items.values():
		out.append(ItemCodec.encode(item, catalog))
	return out


## Aparência replicada: [índice da base ou -1, nível, raridade] por slot visível.
func appearance(p: ServerPlayer) -> PackedInt32Array:
	var a := PackedInt32Array()
	for slot in ItemCatalog.VISIBLE_SLOTS:
		if p.equipment.has(slot):
			var item: Dictionary = p.items[p.equipment[slot]]
			a.append_array([catalog.base_ids.find(str(item["base"])), int(item["level"]), int(item["rarity"])])
		else:
			a.append_array([-1, 0, 0])
	return a


## Tira o item do lugar onde está (grade, cofre, slot ou forja), sem apagá-lo.
func _detach(p: ServerPlayer, item: Dictionary) -> void:
	var uid := int(item["uid"])
	match int(item["container"]):
		ItemCatalog.CONTAINER_INVENTORY:
			p.inventory.remove(uid)
		ItemCatalog.CONTAINER_STORAGE:
			p.storage.remove(uid)
		ItemCatalog.CONTAINER_FORGE, ItemCatalog.CONTAINER_TRADE:
			pass
		_:
			_unequip(p, item)


func _set_equipped(p: ServerPlayer, item: Dictionary, slot: String) -> void:
	p.equipment[slot] = int(item["uid"])
	item["container"] = 1 + ItemCatalog.EQUIP_SLOTS.find(slot)
	item["x"] = 0
	item["y"] = 0


func _unequip(p: ServerPlayer, item: Dictionary) -> void:
	for slot: String in p.equipment.keys():
		if p.equipment[slot] == int(item["uid"]):
			p.equipment.erase(slot)
