extends RefCounted
## Fase 6, parte 3: árvore de maestria (bônus, pré-requisitos, limites), custo do reset e
## gravação de reset e maestria no banco.


func _cfg() -> Dictionary:
	var t := ConfigLoader.load_json("res://data/mastery.json")
	t.erase("_doc")
	return t


func test_mastery_nodes_valid() -> String:
	var keys := ServerPlayer.ADDITIVE_BONUSES + ServerPlayer.COMBAT_BONUSES + PackedStringArray(["hp_max_pct", "mana_max_pct"])
	var nodes := MasterySystem.index_nodes(_cfg())
	if (_cfg()["trees"] as Array).size() != 3:
		return "são três árvores (ataque, defesa, utilidade)"
	for id: String in nodes:
		var n: Dictionary = nodes[id]
		if not str(n["stat"]) in keys:
			return "%s: o bônus %s não é aplicado em lugar nenhum" % [id, n["stat"]]
		if str(n["text"]).count("%s") != 1:
			return "%s: o texto precisa de um %%s" % id
		for req: Array in n["requires"]:
			if not nodes.has(str(req[0])) or int(req[1]) > int(nodes[str(req[0])]["max"]):
				return "%s: pré-requisito impossível %s" % [id, req]
	var expr := Expression.new()
	if expr.parse(str(_cfg()["xp_to_next"]), ["mlevel"]) != OK or int(expr.execute([0])) <= 0:
		return "xp_to_next da maestria inválida"
	return ""


func test_mastery_rules() -> String:
	var nodes := MasterySystem.index_nodes(_cfg())
	var m := {}
	if MasterySystem.can_spend(m, "furia", nodes, 0) == "":
		return "sem pontos livres não se gasta"
	if MasterySystem.can_spend(m, "golpe_preciso", nodes, 5) == "":
		return "golpe_preciso exige 5 em fúria"
	m["furia"] = 5
	if MasterySystem.can_spend(m, "golpe_preciso", nodes, 5) != "":
		return "com 5 em fúria, golpe_preciso libera"
	m["furia"] = int(nodes["furia"]["max"])
	if MasterySystem.can_spend(m, "furia", nodes, 5) == "":
		return "nó no máximo não aceita mais"
	if MasterySystem.can_spend(m, "nao_existe", nodes, 5) == "":
		return "nó desconhecido"
	var b := MasterySystem.bonuses_for({"furia": 3, "pele_pedra": 2, "vigor": 1}, nodes)
	if not is_equal_approx(float(b["damage_pct"]), 0.03) or not is_equal_approx(float(b["defense"]), 8.0) or not is_equal_approx(float(b["hp_max_pct"]), 0.02):
		return "bônus somados errados: %s" % b
	return ""


func test_mastery_in_stats() -> String:
	var cls := ConfigLoader.load_json("res://data/classes/feiticeiro.json")
	var calc := StatCalculator.new(cls["derived"])
	var cat := ItemCatalog.from_config()
	var p := ServerPlayer.new()
	p.class_id = "feiticeiro"
	p.level = 400
	p.stats = (cls["base_stats"] as Dictionary).duplicate()
	p.recompute(calc, cat)
	var defense := float(p.derived["defense"])
	var hp := p.hp_max
	p.mastery_bonuses = MasterySystem.bonuses_for({"pele_pedra": 5, "vigor": 5}, MasterySystem.index_nodes(_cfg()))
	p.recompute(calc, cat)
	if not is_equal_approx(float(p.derived["defense"]), defense + 20.0) or not is_equal_approx(p.hp_max, hp * 1.1):
		return "maestria nos atributos: defesa %.1f (antes %.1f), vida %.1f (antes %.1f)" % [p.derived["defense"], defense, p.hp_max, hp]
	return ""


func test_reset_cost_and_saved() -> String:
	var rc := ConfigLoader.load_json("res://data/reset.json")
	if MasterySystem.reset_cost(0, rc) != int(rc["cost_base"]) or MasterySystem.reset_cost(2, rc) != int(rc["cost_base"]) + 2 * int(rc["cost_per_reset"]):
		return "custo do reset"
	if int(rc["level_req"]) > int(ConfigLoader.load_json("res://data/progression.json")["max_level"]):
		return "o reset não pode exigir mais que o nível máximo"
	if not SqliteRepository.available():
		return "extensão godot-sqlite não carregada"
	var repo := SqliteRepository.new(":memory:")
	if not repo.open():
		return "não abriu o banco"
	var acc := repo.create_account("conta_demo", "00", "00", 1)
	var cid := repo.create_character(acc, {"name": "Vetusta", "class_id": "feiticeiro", "level": 1, "xp": 0, "points": 450,
		"stats": {"str": 18, "agi": 18, "vit": 15, "ene": 30}, "currency": 0, "hp": 10.0, "mana": 5.0,
		"region_id": "ruinas", "pos": [0.0, 0.0], "learned_spells": 15, "items": [], "journals": {},
		"resets": 2, "master_level": 7, "master_xp": 1234, "master_points": 3, "mastery": {"furia": 4}})
	var rec := repo.load_character(cid)
	if int(rec["resets"]) != 2 or int(rec["master_level"]) != 7 or int(rec["master_xp"]) != 1234 or int(rec["master_points"]) != 3 or int(rec["mastery"]["furia"]) != 4:
		return "reset e maestria não voltaram: %s" % rec
	if int(repo.list_characters(acc)[0]["resets"]) != 2:
		return "a lista de personagens não traz os renascimentos"
	repo.close()
	return ""
