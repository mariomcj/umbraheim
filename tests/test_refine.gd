extends RefCounted
## Refino com joias (simulação estatística) e receitas da Forja do Vórtice.


func _catalog() -> ItemCatalog:
	var items := ConfigLoader.load_json("res://data/items.json")
	var opts := ConfigLoader.load_json("res://data/item_options.json")
	var sets := ConfigLoader.load_json("res://data/sets.json")
	for d in [items, opts, sets]:
		d.erase("_doc")
	return ItemCatalog.new(items, opts, sets)


func _cfg() -> Dictionary:
	var c := ConfigLoader.load_json("res://data/refine.json")
	c.erase("_doc")
	return c


func _book(cat: ItemCatalog) -> RecipeBook:
	var r := ConfigLoader.load_json("res://data/recipes.json")
	r.erase("_doc")
	return RecipeBook.new(r, cat)


func test_bless_always_works_until_limit() -> String:
	var cat := _catalog()
	var cfg := _cfg()
	var rng := RandomNumberGenerator.new()
	var item := {"uid": 1, "base": "cajado_osso", "level": 0, "extra": 0}
	for expected in range(1, 7):
		var r := RefineRules.apply_jewel("bless", item, cat, cfg, rng)
		if r["result"] != RefineRules.SUCCESS or r["level"] != expected:
			return "bênção falhou indo para +%d: %s" % [expected, r]
		item["level"] = r["level"]
	var over := RefineRules.apply_jewel("bless", item, cat, cfg, rng)
	if over["result"] != RefineRules.INVALID:
		return "bênção deveria ser recusada em +6"
	var jewel := RefineRules.apply_jewel("bless", {"base": "joia_alma"}, cat, cfg, rng)
	return "" if jewel["result"] == RefineRules.INVALID else "joia não pode ser refinada"


## Simulação: taxa de sucesso da alma ~ chance configurada, com e sem Sorte.
func test_soul_success_rate_and_luck() -> String:
	var cat := _catalog()
	var cfg := _cfg()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var n := 20000
	for luck in [false, true]:
		var ok := 0
		for i in n:
			var r := RefineRules.apply_jewel("soul", {"base": "manto_acolito", "level": 6, "luck": luck}, cat, cfg, rng)
			if r["result"] == RefineRules.SUCCESS:
				ok += 1
		var expected := float(cfg["soul"]["chance"]) + (float(cfg["soul"]["luck_bonus"]) if luck else 0.0)
		var rate := float(ok) / n
		if absf(rate - expected) > 0.015:
			return "sorte=%s: taxa %.3f, esperado %.3f" % [luck, rate, expected]
	return ""


func test_soul_failure_downgrades() -> String:
	var cat := _catalog()
	var cfg := _cfg()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for i in 400:
		for start in [5, 8]:
			var r := RefineRules.apply_jewel("soul", {"base": "manto_acolito", "level": start}, cat, cfg, rng)
			if r["result"] == RefineRules.FAIL:
				seen[start] = r["level"]
	if seen.get(5) != 4:
		return "falha em +5 deveria ir para +4, foi %s" % seen.get(5)
	if seen.get(8) != 0:
		return "falha em +8 deveria voltar a +0, foi %s" % seen.get(8)
	var at9 := RefineRules.apply_jewel("soul", {"base": "manto_acolito", "level": 9}, cat, cfg, rng)
	return "" if at9["result"] == RefineRules.INVALID else "alma não deveria passar de +9"


func test_life_extra_option() -> String:
	var cat := _catalog()
	var cfg := _cfg()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var got_success := false
	var got_reset := false
	for i in 200:
		var r := RefineRules.apply_jewel("life", {"base": "cajado_osso", "level": 0, "extra": 2}, cat, cfg, rng)
		if r["result"] == RefineRules.SUCCESS and r["extra"] == 3:
			got_success = true
		if r["result"] == RefineRules.FAIL and r["extra"] == 0:
			got_reset = true
	if not (got_success and got_reset):
		return "vida: sucesso %s, zerou na falha %s" % [got_success, got_reset]
	var maxed := RefineRules.apply_jewel("life", {"base": "cajado_osso", "extra": int(cat.options["extra_max"])}, cat, cfg, rng)
	return "" if maxed["result"] == RefineRules.INVALID else "extra no máximo deveria ser recusada"


func test_forge_refine_recipe() -> String:
	var cat := _catalog()
	var book := _book(cat)
	var item := {"uid": 9, "base": "vara_eclipse", "level": 9, "luck": true, "rarity": 0}
	var ingredients := [item, {"base": "joia_consagrada"}, {"base": "joia_alma"}, {"base": "joia_vortice"}]
	var e := book.evaluate(ingredients)
	var r: Dictionary = book.recipes["refine_high"]
	var expected := float(r["levels"]["9"]["chance"]) + float(r["luck_bonus"])
	if not e["valid"] or not is_equal_approx(e["chance"], expected) or e["target_uid"] != 9:
		return "refino +9 inválido ou chance errada: %s" % e
	var with_charms := book.evaluate(ingredients + [{"base": "talisma_fortuna"}, {"base": "talisma_fortuna"}, {"base": "selo_preservacao"}])
	if not with_charms["valid"] or not with_charms["protected"] or with_charms["chance"] <= e["chance"]:
		return "talismãs/selo não aplicados: %s" % with_charms
	if with_charms["chance"] > float(r["max_chance"]) + 0.0001:
		return "chance passou do teto"
	var missing := book.evaluate([item, {"base": "joia_consagrada"}])
	if missing["valid"] or str(missing["hint"]).is_empty():
		return "faltando joias deveria explicar o que falta"
	var low := book.evaluate([{"uid": 1, "base": "cajado_osso", "level": 5}, {"base": "joia_vortice"}])
	if low["valid"]:
		return "item +5 não usa o refino superior"
	var exc := book.evaluate([{"uid": 2, "base": "vara_eclipse", "level": 9, "rarity": 1}, {"base": "joia_consagrada"}, {"base": "joia_alma"}, {"base": "joia_vortice"}])
	if not is_equal_approx(exc["chance"], float(r["levels"]["9"]["chance"]) - float(r["rarity_penalty"])):
		return "penalidade de excelente não aplicada"
	return ""


func test_forge_craft_recipes() -> String:
	var cat := _catalog()
	var book := _book(cat)
	var e := book.evaluate([{"base": "joia_genese"}, {"base": "joia_vortice"}])
	if not e["valid"] or e["result_base"] != "talisma_fortuna":
		return "receita do talismã não reconhecida: %s" % e
	var extra := book.evaluate([{"base": "joia_genese"}, {"base": "joia_vortice"}, {"base": "joia_alma"}])
	if extra["valid"]:
		return "ingrediente sobrando deveria invalidar"
	for id: String in book.recipes:
		var r: Dictionary = book.recipes[id]
		if r["type"] == "craft":
			if not cat.bases.has(r["result"]):
				return "receita '%s' gera item inexistente" % id
			for k: String in r["ingredients"]:
				if not cat.bases.has(k):
					return "receita '%s' usa item inexistente '%s'" % [id, k]
	return ""

func test_forge_wings_recipe() -> String:
	var cat := _catalog()
	var book := _book(cat)
	var r: Dictionary = book.recipes["asas_t1"]
	var jewels := [{"base": "joia_vortice"}, {"base": "joia_vortice"}, {"base": "joia_genese"}, {"base": "joia_alma"}]
	var low := book.evaluate([{"uid": 1, "base": "manto_acolito", "level": 6}] + jewels)
	if low["valid"] or not str(low["hint"]).contains("+7"):
		return "item +6 deveria ser recusado explicando o mínimo: %s" % low
	var e7 := book.evaluate([{"uid": 2, "base": "manto_acolito", "level": 7}] + jewels)
	if not e7["valid"] or not is_equal_approx(e7["chance"], float(r["base_chance"])) or str(e7.get("sacrifice", "")).is_empty():
		return "asas com item +7: %s" % e7
	var e10 := book.evaluate([{"uid": 3, "base": "vara_eclipse", "level": 10, "luck": true, "rarity": 1}] + jewels)
	var expected := float(r["base_chance"]) + 3 * float(r["per_level"]) + float(r["luck_bonus"]) + float(r["excellent_bonus"])
	if not is_equal_approx(e10["chance"], minf(expected, float(r["max_chance"]))):
		return "chance com +10, sorte e excelente: %s (esperado %.2f)" % [e10["chance"], expected]
	var e15 := book.evaluate([{"uid": 4, "base": "vara_eclipse", "level": 15, "luck": true, "rarity": 1}] + jewels)
	if e15["chance"] > float(r["max_chance"]) + 0.0001:
		return "chance passou do teto"
	var wings := book.evaluate([{"uid": 5, "base": "asas_fuligem", "level": 9}] + jewels)
	if wings["valid"]:
		return "asas não podem ser sacrificadas"
	# com as joias do refino, o mesmo item continua indo para o refino superior
	var refine := book.evaluate([{"uid": 6, "base": "vara_eclipse", "level": 9}, {"base": "joia_consagrada"}, {"base": "joia_alma"}, {"base": "joia_vortice"}])
	if not refine["valid"] or refine["target_uid"] != 6:
		return "o refino superior deixou de ser reconhecido"
	for base_id: String in r["results"]:
		if str(cat.bases.get(base_id, {}).get("slot", "")) != "wings":
			return "resultado %s não é asa" % base_id
	return ""
