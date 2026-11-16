extends RefCounted
## Inventário em grade, codec de itens, bônus (refino, opções, conjuntos) e dados de itens.


func _catalog() -> ItemCatalog:
	var items := ConfigLoader.load_json("res://data/items.json")
	var opts := ConfigLoader.load_json("res://data/item_options.json")
	var sets := ConfigLoader.load_json("res://data/sets.json")
	for d in [items, opts, sets]:
		d.erase("_doc")
	return ItemCatalog.new(items, opts, sets)


func test_grid_place_overlap_and_bounds() -> String:
	var g := InventoryGrid.new(8, 8)
	if not g.place(1, 0, 0, Vector2i(1, 4)):
		return "não colocou o cajado 1x4 em (0,0)"
	if g.place(2, 0, 3, Vector2i(2, 2)):
		return "aceitou sobreposição"
	if g.place(3, 7, 7, Vector2i(2, 2)):
		return "aceitou item saindo da grade"
	if not g.place(2, 1, 0, Vector2i(2, 3)):
		return "não colocou o manto 2x3 ao lado"
	if g.uid_at(Vector2i(2, 2)) != 2 or g.uid_at(Vector2i(0, 3)) != 1 or g.uid_at(Vector2i(3, 0)) != 0:
		return "células com dono errado"
	return ""


func test_grid_move_and_find_free() -> String:
	var g := InventoryGrid.new(4, 4)
	g.place(1, 0, 0, Vector2i(2, 2))
	if not g.move(1, 1, 1):
		return "não moveu sobre a própria área"
	if g.rect_of(1) != Rect2i(1, 1, 2, 2) or g.uid_at(Vector2i(0, 0)) != 0:
		return "movimento deixou lixo nas células"
	var free := g.find_free(Vector2i(1, 4))
	if free != Vector2i(0, 0):
		return "find_free deveria achar a coluna 0, achou %s" % free
	g.place(2, 0, 0, Vector2i(1, 4))
	g.place(3, 3, 0, Vector2i(1, 4))
	if g.find_free(Vector2i(2, 2)) != Vector2i(-1, -1):
		return "não deveria caber 2x2"
	if not g.remove(1) or g.find_free(Vector2i(2, 2)) == Vector2i(-1, -1):
		return "remove não liberou espaço"
	return ""


func test_codec_roundtrip() -> String:
	var cat := _catalog()
	var item := {"uid": 77, "base": "vara_eclipse", "level": 9, "rarity": ItemCatalog.RARITY_EXCELLENT,
		"luck": true, "extra": 3, "exc": ["dmg_pct", "exc_rate"], "container": 1, "x": 0, "y": 0}
	var back := ItemCodec.decode(ItemCodec.encode(item, cat), cat)
	for k in ["uid", "base", "level", "rarity", "luck", "extra", "container"]:
		if back.get(k) != item[k]:
			return "campo '%s' diferente: %s vs %s" % [k, back.get(k), item[k]]
	var exc: Array = back["exc"]
	if exc.size() != 2 or not exc.has("dmg_pct") or not exc.has("exc_rate"):
		return "opções excelentes perdidas: %s" % [exc]
	return ""


func test_bonuses_refine_extra_luck_excellent() -> String:
	var cat := _catalog()
	var plain := cat.item_bonuses({"base": "cajado_osso", "level": 0})
	if plain.get("magic_min") != 4.0 or plain.get("magic_max") != 8.0:
		return "base do cajado errada: %s" % plain
	var refined := cat.item_bonuses({"base": "cajado_osso", "level": 9, "extra": 2, "luck": true, "exc": ["dmg_pct"]})
	var refine: Array = cat.options["refine_main"]
	var expect_min := 4.0 + float(refine[9]) + 2 * float(cat.options["extra_per_level"])
	if not is_equal_approx(refined["magic_min"], expect_min):
		return "refino/extra: esperado %.0f, veio %.0f" % [expect_min, refined["magic_min"]]
	if not is_equal_approx(refined.get("crit_chance", 0.0), float(cat.options["luck_crit_bonus"])):
		return "sorte não deu crítico"
	if not is_equal_approx(refined.get("damage_pct", 0.0), 0.02):
		return "opção excelente não aplicada"
	var armor := cat.item_bonuses({"base": "manto_acolito", "level": 3})
	if not is_equal_approx(armor["defense"], 6.0 + float(refine[3])):
		return "defesa do manto refinado errada"
	return ""


func test_set_bonuses() -> String:
	var cat := _catalog()
	var pieces: Array = []
	for b in ["capuz_acolito", "manto_acolito", "calcas_acolito"]:
		pieces.append({"base": b, "level": 0, "rarity": ItemCatalog.RARITY_ANCESTRAL})
	var bonus := cat.equipment_bonuses(pieces)
	var set: Dictionary = cat.sets["vigilia_eclipse"]
	var expect_def := 3.0 + 6.0 + 4.0 + float(set["bonuses"]["2"]["defense"])
	if not is_equal_approx(bonus.get("defense", 0.0), expect_def):
		return "defesa com bônus de 2 peças errada: %s" % bonus.get("defense")
	if not is_equal_approx(bonus.get("magic_max", 0.0), float(set["bonuses"]["3"]["magic_max"])):
		return "bônus de 3 peças ausente"
	if not is_equal_approx(bonus.get("stat_ene", 0.0), 3.0 * float(cat.options["ancestral_stat_bonus"])):
		return "atributo ancestral por peça errado"
	if bonus.has("mana_max_pct"):
		return "bônus de 4 peças não deveria valer com 3"
	var normal := cat.equipment_bonuses([{"base": "capuz_acolito", "level": 0, "rarity": 0}, {"base": "manto_acolito", "level": 0, "rarity": 0}])
	return "" if not normal.has("stat_ene") else "item normal não é de conjunto"


func test_names_slots_and_tooltip() -> String:
	var cat := _catalog()
	var ring := {"base": "anel_brasa", "level": 0}
	if not cat.fits_slot(ring, "ring2") or cat.fits_slot(ring, "amulet"):
		return "anel deveria caber nos dois slots de anel e só neles"
	if cat.fits_slot({"base": "joia_alma"}, "weapon"):
		return "joia não é equipável"
	var n := cat.display_name({"base": "manto_acolito", "level": 7, "rarity": ItemCatalog.RARITY_EXCELLENT})
	if not n.contains("+7") or not n.begins_with("Excelente"):
		return "nome errado: %s" % n
	var lines := cat.tooltip_lines({"base": "vara_eclipse", "level": 2, "luck": true, "extra": 1, "exc": ["hp_kill"]}, 1)
	if lines.size() < 5:
		return "tooltip curto demais: %s" % [lines]
	return ""


func test_item_data_consistency() -> String:
	var cat := _catalog()
	for id: String in cat.bases:
		var b: Dictionary = cat.bases[id]
		for key in ["name", "kind", "size", "level_req", "visual"]:
			if not b.has(key):
				return "item '%s' sem '%s'" % [id, key]
		if b["kind"] == "equip" and not ItemCatalog.EQUIP_SLOTS.has(str(b["slot"])) and str(b["slot"]) != "ring":
			return "item '%s' com slot inválido '%s'" % [id, b["slot"]]
	if cat.exc_ids.size() > 31:
		return "opções excelentes demais para a máscara de 31 bits"
	var drops := ConfigLoader.load_json("res://data/drops.json")
	for pool: String in drops["pools"]:
		for base_id: String in drops["pools"][pool]:
			if not cat.bases.has(base_id):
				return "pool '%s' usa item inexistente '%s'" % [pool, base_id]
	for set_id: String in cat.sets:
		for piece: String in cat.sets[set_id]["pieces"]:
			if not cat.bases.has(piece):
				return "conjunto '%s' usa item inexistente '%s'" % [set_id, piece]
	var cls := ConfigLoader.load_json("res://data/classes/feiticeiro.json")
	for start: Dictionary in cls["starting_items"]:
		if not cat.bases.has(start["base"]):
			return "item inicial inexistente '%s'" % start["base"]
	return ""
