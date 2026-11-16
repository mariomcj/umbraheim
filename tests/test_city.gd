extends RefCounted
## Fase 2, parte 3: preços das lojas, pilhas, armazém, zona segura e consistência
## dos dados da cidade (NPCs, estoques, consumíveis, magias por grimório).


func _load(path: String) -> Dictionary:
	var d := ConfigLoader.load_json(path)
	d.erase("_doc")
	return d


func _catalog() -> ItemCatalog:
	return ItemCatalog.new(_load("res://data/items.json"), _load("res://data/item_options.json"), _load("res://data/sets.json"))


func _player(inv: InventoryService) -> ServerPlayer:
	var p := ServerPlayer.new()
	inv.init_player(p)
	return p


func _item(uid: int, base: String, count: int = 1) -> Dictionary:
	return {"uid": uid, "base": base, "level": 0, "rarity": 0, "luck": false, "extra": 0, "exc": [], "container": 0, "x": 0, "y": 0, "count": count}


func test_shop_prices() -> String:
	var cat := _catalog()
	var rules := ShopRules.new(_load("res://data/shops.json"), cat)
	var staff := _item(1, "vara_eclipse")
	var base_sell := rules.sell_price(staff)
	if rules.buy_price("vara_eclipse") != int(cat.bases["vara_eclipse"]["price"]):
		return "preço de compra diferente do items.json"
	if base_sell <= 0 or base_sell >= rules.buy_price("vara_eclipse"):
		return "venda deveria ser uma fração do preço (%d)" % base_sell
	staff["level"] = 9
	staff["luck"] = true
	var refined := rules.sell_price(staff)
	if refined <= base_sell * 5:
		return "+9 com sorte deveria valer bem mais (%d vs %d)" % [refined, base_sell]
	staff["rarity"] = ItemCatalog.RARITY_EXCELLENT
	if rules.sell_price(staff) <= refined:
		return "excelente deveria valer mais"
	if not rules.needs_sell_confirm(staff):
		return "item valioso deveria pedir confirmação"
	var potions := _item(2, "pocao_vida_menor", 10)
	if rules.sell_price(potions) != rules.sell_price(_item(3, "pocao_vida_menor")) * 10:
		return "pilha deveria valer unidade × quantidade"
	if rules.needs_sell_confirm(_item(4, "pocao_vida_menor")):
		return "uma poção não deveria pedir confirmação"
	# a loja nunca paga mais do que cobra (sem lucro infinito comprando e vendendo)
	for shop_id: String in rules.cfg["shops"]:
		for base_id in rules.stock(shop_id):
			if rules.sell_price(_item(9, base_id)) >= rules.buy_price(base_id):
				return "%s: venda >= compra" % base_id
	return ""


func test_stacking_and_room() -> String:
	var cat := _catalog()
	var inv := InventoryService.new(cat)
	var p := _player(inv)
	if not inv.give(p, _item(1, "pocao_vida_menor", 15)):
		return "não deu 15 poções"
	if not inv.give(p, _item(2, "pocao_vida_menor", 8)):
		return "não deu mais 8 poções"
	var stacks: Array = []
	for it: Dictionary in p.items.values():
		stacks.append(int(it["count"]))
	stacks.sort()
	if stacks != [3, 20]:
		return "pilhas esperadas [3, 20], vieram %s" % [stacks]
	if p.inventory.count() != 2:
		return "deveriam ser 2 células ocupadas, são %d" % p.inventory.count()
	inv.consume_one(p, 1)
	if int(p.items[1]["count"]) != 19:
		return "consumir não baixou a pilha"
	# mochila cheia: só cabe se completar pilha existente
	var uid := 100
	while inv.give(p, _item(uid, "botas_acolito")):
		uid += 1
	while inv.give(p, _item(uid, "anel_brasa")): # tapa os buracos de 1 célula
		uid += 1
	# pilhas de 19 e 3: sobram 1 + 17 = 18 lugares
	if not inv.has_room(p, _item(500, "pocao_vida_menor", 18)):
		return "deveriam caber 18 poções nas pilhas existentes"
	if inv.has_room(p, _item(501, "pocao_vida_menor", 19)):
		return "não deveriam caber 19 poções (pilhas quase cheias + mochila cheia)"
	if inv.give(p, _item(502, "pocao_mana_menor", 1)):
		return "aceitou item novo com a mochila cheia"
	return ""


func test_storage_moves() -> String:
	var cat := _catalog()
	var inv := InventoryService.new(cat)
	var p := _player(inv)
	inv.give(p, _item(1, "manto_acolito"))
	inv.give(p, _item(2, "cajado_osso"))
	if inv.to_storage(p, 1, -1, -1) != "":
		return "não guardou o manto"
	if int(p.items[1]["container"]) != ItemCatalog.CONTAINER_STORAGE or p.inventory.has(1) or not p.storage.has(1):
		return "manto em lugar errado depois de guardar"
	if inv.to_storage(p, 2, 0, 0) == "":
		return "cajado foi para cima do manto no cofre"
	if inv.to_storage(p, 2, 4, 0) != "":
		return "não guardou o cajado em (4,0)"
	if inv.to_storage(p, 1, 6, 5) != "":
		return "não moveu o manto dentro do cofre"
	if p.storage.rect_of(1).position != Vector2i(6, 5):
		return "manto não está em (6,5) no cofre"
	if inv.move_to_inventory(p, 1, -1, -1) != "":
		return "não retirou o manto"
	if p.storage.has(1) or not p.inventory.has(1):
		return "retirar deixou lixo no cofre"
	if inv.equip(p, 1, "armor") != "":
		return "não equipou o manto retirado"
	if inv.to_storage(p, 1, -1, -1) == "":
		return "aceitou guardar item equipado"
	return ""


func test_safe_zones() -> String:
	var region := _load("res://data/regions/ruinas.json")
	var safe := SafeZones.new(region)
	var spawn := Vector2(float(region["player_spawn"][0]), float(region["player_spawn"][1]))
	if not safe.contains(spawn):
		return "o ponto de chegada deveria ser zona segura"
	for sp: Dictionary in region["monster_spawns"]:
		if safe.contains(Vector2(float(sp["pos"][0]), float(sp["pos"][1]))):
			return "monstro nascendo dentro da cidade"
	for npc: Dictionary in region["npcs"]:
		if not safe.contains(Vector2(float(npc["pos"][0]), float(npc["pos"][1]))):
			return "NPC %s fora da zona segura" % npc["id"]
	if safe.contains(Vector2.ZERO):
		return "o Círculo Rúnico não deveria ser zona segura"
	return ""


func test_city_data_references() -> String:
	var cat := _catalog()
	var shops := _load("res://data/shops.json")
	var region := _load("res://data/regions/ruinas.json")
	var spells := _load("res://data/spells.json")
	var scene: Node = (load(str(region["scene"])) as PackedScene).instantiate()
	var errors := PackedStringArray()
	for npc: Dictionary in region["npcs"]:
		var role := str(npc["role"])
		if not role in ["shop", "storage", "vortex_forge", "quest", "siege"]:
			errors.append("papel desconhecido: %s" % role)
		if role == "shop" and not (shops["shops"] as Dictionary).has(str(npc.get("shop", ""))):
			errors.append("loja inexistente para %s" % npc["id"])
		if scene.get_node_or_null(str(npc["scene_node"])) == null:
			errors.append("nó visual %s não existe na cena" % npc["scene_node"])
	scene.free()
	for shop_id: String in shops["shops"]:
		for base_id: String in shops["shops"][shop_id]["stock"]:
			if not cat.bases.has(base_id):
				errors.append("%s vende item inexistente %s" % [shop_id, base_id])
	var classes: Dictionary = {}
	for class_id: String in _load("res://data/classes/index.json")["order"]:
		classes[class_id] = _load("res://data/classes/%s.json" % class_id)
	for base_id: String in cat.bases:
		var b: Dictionary = cat.bases[base_id]
		if int(b.get("price", 0)) <= 0 and str(b.get("kind", "")) != "quest":
			errors.append("%s sem preço" % base_id)
		for c: String in b.get("classes", []):
			if not classes.has(c):
				errors.append("%s cita classe inexistente %s" % [base_id, c])
		var use: Dictionary = b.get("use", {})
		if not use.is_empty():
			if not str(use["type"]) in ["heal_hp", "heal_mana", "return", "learn_spell", "event_ticket"]:
				errors.append("%s: uso desconhecido %s" % [base_id, use["type"]])
			if str(use["type"]) == "learn_spell":
				var who: Array = b.get("classes", classes.keys())
				for c: String in who:
					if classes.has(c) and not (classes[c]["spells"] as Array).has(str(use["spell"])):
						errors.append("%s ensina magia fora da classe %s" % [base_id, c])
	for class_id: String in classes:
		var c: Dictionary = classes[class_id]
		for s: String in c["starting_spells"] + c.get("evolution", {}).get("spells", []):
			if not (c["spells"] as Array).has(s) or not spells.has(s):
				errors.append("%s: magia inicial/de evolução inválida: %s" % [class_id, s])
		for s: String in c["spells"]:
			if not spells.has(s):
				errors.append("%s: magia inexistente %s" % [class_id, s])
		if (c["spells"] as Array).size() > 31:
			errors.append("%s: mais de 31 magias não cabem na máscara de bits" % class_id)
		var slots := {}
		for s: String in c["spells"]:
			var slot := int(spells[s]["slot"])
			if slots.has(slot):
				errors.append("%s: duas magias na tecla %d" % [class_id, slot])
			slots[slot] = true
		if not slots.has(0):
			errors.append("%s sem ataque básico (slot 0)" % class_id)
		for start: Dictionary in c["starting_items"]:
			if not cat.bases.has(start["base"]) or not cat.allowed_for({"base": start["base"]}, class_id):
				errors.append("%s: item inicial inválido %s" % [class_id, start["base"]])
	return "; ".join(errors)
