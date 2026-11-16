class_name CharacterCodec
extends RefCounted
## ServerPlayer <-> registro do repositório (ver GameRepository).


static func to_record(p: ServerPlayer, journals: Dictionary) -> Dictionary:
	var items: Array = []
	for item: Dictionary in p.items.values():
		items.append(item.duplicate(true)) # itens na mesa da forja voltam para a mochila ao carregar (apply)
	return {
		"id": p.character_id, "account_id": p.account_id, "name": p.char_name, "class_id": p.class_id,
		"level": p.level, "xp": p.xp, "points": p.points, "stats": p.stats.duplicate(),
		"currency": p.currency, "hp": p.hp, "mana": p.mana,
		"region_id": p.region_id, "pos": [p.position.x, p.position.y],
		"learned_spells": p.learned_spells, "items": items, "journals": journals,
		"infamy": p.infamy, "hero": p.hero,
		"evolution": p.evolution, "quests": p.quests.duplicate(true),
		"resets": p.resets, "master_level": p.master_level, "master_xp": p.master_xp,
		"master_points": p.master_points, "mastery": p.mastery.duplicate(),
	}


## Preenche o jogador com o registro salvo. Itens que não couberem onde estavam
## (dados mudaram, tamanho de grade mudou, mesa da forja) vão para o primeiro lugar livre.
static func apply(p: ServerPlayer, rec: Dictionary, inventory: InventoryService) -> void:
	p.character_id = int(rec["id"])
	p.account_id = int(rec.get("account_id", 0))
	p.char_name = str(rec["name"])
	p.class_id = str(rec["class_id"])
	p.level = int(rec["level"])
	p.xp = int(rec["xp"])
	p.points = int(rec["points"])
	for k: String in rec["stats"]:
		p.stats[k] = int(rec["stats"][k])
	p.currency = int(rec["currency"])
	p.hp = float(rec["hp"])
	p.mana = float(rec["mana"])
	p.region_id = str(rec["region_id"])
	p.position = Vector2(float(rec["pos"][0]), float(rec["pos"][1]))
	p.learned_spells = int(rec["learned_spells"])
	p.infamy = int(rec.get("infamy", 0))
	p.hero = int(rec.get("hero", 0))
	p.evolution = int(rec.get("evolution", 0))
	p.resets = int(rec.get("resets", 0))
	p.master_level = int(rec.get("master_level", 0))
	p.master_xp = int(rec.get("master_xp", 0))
	p.master_points = int(rec.get("master_points", 0))
	p.mastery = {}
	for k: Variant in rec.get("mastery", {}):
		p.mastery[str(k)] = int(rec["mastery"][k])
	var q: Variant = rec.get("quests", {})
	p.quests = (q as Dictionary).duplicate(true) if q is Dictionary else {}
	inventory.init_player(p)
	var homeless: Array = []
	for item: Dictionary in rec.get("items", []):
		if inventory.catalog.base(item).is_empty():
			push_warning("[db] item com base desconhecida ignorado: %s" % item.get("base", "?"))
			continue
		var c := int(item["container"])
		var size := inventory.catalog.size_of(item)
		if c == ItemCatalog.CONTAINER_INVENTORY and p.inventory.place(int(item["uid"]), int(item["x"]), int(item["y"]), size):
			p.items[item["uid"]] = item
		elif c == ItemCatalog.CONTAINER_STORAGE and p.storage.place(int(item["uid"]), int(item["x"]), int(item["y"]), size):
			p.items[item["uid"]] = item
		elif c >= 1 and c <= ItemCatalog.EQUIP_SLOTS.size() and not p.equipment.has(ItemCatalog.EQUIP_SLOTS[c - 1]):
			p.items[item["uid"]] = item
			p.equipment[ItemCatalog.EQUIP_SLOTS[c - 1]] = int(item["uid"])
		else:
			homeless.append(item)
	for item: Dictionary in homeless:
		if inventory.give(p, item):
			continue
		var spot := p.storage.find_free(inventory.catalog.size_of(item))
		if spot.x >= 0:
			p.storage.place(int(item["uid"]), spot.x, spot.y, inventory.catalog.size_of(item))
			item["container"] = ItemCatalog.CONTAINER_STORAGE
			item["x"] = spot.x
			item["y"] = spot.y
			p.items[item["uid"]] = item
		else:
			push_warning("[db] sem espaço para %s do personagem %d" % [item["base"], p.character_id])
