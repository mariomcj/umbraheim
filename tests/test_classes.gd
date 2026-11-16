extends RefCounted
## Fase 5, parte 3: três classes (atributos, magias, itens), invocações, bônus
## temporários, missão de evolução e a gravação da evolução no banco.

const KINDS: PackedStringArray = ["projectile", "melee", "area", "nova", "chain", "buff", "heal", "summon"]


func _classes() -> Dictionary:
	var out := {}
	for c: String in ConfigLoader.load_json("res://data/classes/index.json")["order"]:
		out[c] = ConfigLoader.load_json("res://data/classes/%s.json" % c)
	return out


func test_class_formulas() -> String:
	var hp := {}
	var dmg := {}
	for c: String in _classes():
		var cls: Dictionary = _classes()[c]
		var calc := StatCalculator.new(cls["derived"])
		var d := calc.compute(1, cls["base_stats"])
		for k in ["hp_max", "mana_max", "magic_min", "magic_max", "defense", "attack_speed", "hp_regen_s", "mana_regen_s", "move_speed_mps"]:
			if not d.has(k) or float(d[k]) <= 0.0:
				return "%s: %s inválido (%s)" % [c, k, d.get(k)]
		if float(d["magic_min"]) > float(d["magic_max"]):
			return "%s: dano mínimo maior que o máximo" % c
		hp[c] = float(d["hp_max"])
		dmg[c] = float(d["magic_max"])
		if not cls.has("evolution") or str(cls["evolution"].get("name", "")) == "":
			return "%s sem evolução" % c
	if not (hp["cavaleiro"] > hp["vidente"] and hp["vidente"] > hp["feiticeiro"]):
		return "vida esperada: cavaleiro > vidente > feiticeiro (%s)" % hp
	if dmg["vidente"] >= dmg["feiticeiro"]:
		return "a vidente (suporte) não deve bater mais que o feiticeiro: %s" % dmg
	return ""


func test_spell_kinds_and_buffs() -> String:
	var spells := ConfigLoader.load_json("res://data/spells.json")
	var buff_keys := ServerPlayer.ADDITIVE_BONUSES + ServerPlayer.COMBAT_BONUSES + PackedStringArray(["hp_max_pct", "mana_max_pct"])
	for id: String in spells:
		if id.begins_with("_"):
			continue
		var s: Dictionary = spells[id]
		if not str(s["kind"]) in KINDS:
			return "%s: tipo desconhecido %s" % [id, s["kind"]]
		match str(s["kind"]):
			"buff":
				for k: String in s["buff"]["stats"]:
					if not k in buff_keys:
						return "%s: o bônus %s não é aplicado em lugar nenhum" % [id, k]
				if float(s["buff"]["duration_s"]) <= 0.0:
					return "%s: bônus sem duração" % id
			"heal":
				if float(s.get("radius_m", 0.0)) <= 0.0 or float(s.get("heal_mult", 0.0)) <= 0.0:
					return "%s: cura sem raio ou multiplicador" % id
			"summon":
				for k in ["name", "duration_s", "attack_interval_s", "attack_range_m", "damage_mult", "move_speed_mps", "follow_distance_m", "visual"]:
					if not (s["summon"] as Dictionary).has(k):
						return "%s: invocação sem %s" % [id, k]
				if not ResourceLoader.exists(str(s["summon"]["visual"])):
					return "%s: visual inexistente" % id
			"melee":
				if float(s["range_m"]) > 4.0:
					return "%s: corpo a corpo com alcance de %.1f m" % [id, float(s["range_m"])]
	if SummonSystem.summon_type_ids(spells) != ["invocar_espirito"]:
		return "tipos de invocação: %s" % [SummonSystem.summon_type_ids(spells)]
	if not SpellSystem.is_self_cast(spells["veu_protetor"]) or SpellSystem.is_self_cast(spells["golpe_profano"]):
		return "magias sem alvo"
	return ""


func test_buffs_change_stats() -> String:
	var cls: Dictionary = _classes()["cavaleiro"]
	var calc := StatCalculator.new(cls["derived"])
	var cat := ItemCatalog.from_config()
	var p := ServerPlayer.new()
	p.class_id = "cavaleiro"
	p.level = 10
	p.stats = (cls["base_stats"] as Dictionary).duplicate()
	p.recompute(calc, cat)
	var defense := float(p.derived["defense"])
	var spells := ConfigLoader.load_json("res://data/spells.json")
	var b: Dictionary = spells["juramento_sombrio"]["buff"]
	p.buffs["juramento"] = {"name": b["name"], "until": 99.0, "stats": b["stats"]}
	p.recompute(calc, cat)
	if not is_equal_approx(float(p.derived["defense"]), defense + 10.0) or not is_equal_approx(float(p.derived["damage_pct"]), 0.25):
		return "Juramento: defesa %.1f (antes %.1f), dano %+.2f" % [p.derived["defense"], defense, p.derived["damage_pct"]]
	p.buffs.clear()
	p.recompute(calc, cat)
	if not is_equal_approx(float(p.derived["defense"]), defense):
		return "o bônus não saiu"
	return ""


func test_class_items() -> String:
	var cat := ItemCatalog.from_config()
	var sword := {"base": "espada_ferrugem"}
	var staff := {"base": "cajado_osso"}
	if not cat.allowed_for(sword, "cavaleiro") or cat.allowed_for(sword, "feiticeiro") or cat.allowed_for(staff, "cavaleiro") or not cat.allowed_for(staff, "vidente"):
		return "restrição de classe errada"
	if not cat.allowed_for({"base": "broquel_cinzas"}, "vidente"):
		return "item sem lista de classes vale para todas"
	var lines := cat.tooltip_lines(sword, 10, "feiticeiro")
	var found := false
	for l: Array in lines:
		if str(l[0]).begins_with("Classe:") and l[1] == "red":
			found = true
	if not found:
		return "a dica deveria avisar (em vermelho) que a espada não é da classe"
	if not cat.is_quest_item({"base": "selo_juramento"}):
		return "selo não é item de missão"
	return ""


func test_evolution_quest_rules() -> String:
	var quest: Dictionary = ConfigLoader.load_json("res://data/quests.json")["evolucao"]
	var need := int(quest["steps"][0]["count"])
	var state := {"step": 0, "count": 0}
	if QuestSystem.apply_kill(state, quest, "ruinas"):
		return "morte em outra região não conta"
	for i in need - 1:
		QuestSystem.apply_kill(state, quest, "geleira")
	if int(state["step"]) != 0 or int(state["count"]) != need - 1:
		return "contagem: %s" % state
	if QuestSystem.can_turn_in(state, quest, {"selo_juramento": 1}):
		return "não entrega com o passo de matar pela metade"
	QuestSystem.apply_kill(state, quest, "geleira")
	if int(state["step"]) != 1 or QuestSystem.apply_kill(state, quest, "geleira"):
		return "deveria ter passado ao passo do selo e parado de contar: %s" % state
	if QuestSystem.can_turn_in(state, quest, {}) or not QuestSystem.can_turn_in(state, quest, {"selo_juramento": 1}):
		return "entrega com e sem o selo"
	if QuestSystem.can_turn_in({"done": true}, quest, {"selo_juramento": 1}):
		return "missão concluída não se entrega de novo"
	for c: String in _classes():
		if str((quest["intro"] as Dictionary).get(c, "")) == "":
			return "missão sem texto para %s" % c
	return ""


func test_evolution_saved() -> String:
	if not SqliteRepository.available():
		return "extensão godot-sqlite não carregada"
	var repo := SqliteRepository.new(":memory:")
	if not repo.open():
		return "não abriu o banco"
	var acc := repo.create_account("conta_demo", "00", "00", 1)
	var cid := repo.create_character(acc, {"name": "Brannoc", "class_id": "cavaleiro", "level": 20, "xp": 0, "points": 0,
		"stats": {"str": 28, "agi": 20, "vit": 25, "ene": 10}, "currency": 0, "hp": 10.0, "mana": 5.0,
		"region_id": "ruinas", "pos": [0.0, 0.0], "learned_spells": 15, "items": [], "journals": {},
		"evolution": 0, "quests": {"evolucao": {"step": 1, "count": 0}}})
	var rec := repo.load_character(cid)
	if str(rec["class_id"]) != "cavaleiro" or int(rec["quests"]["evolucao"]["step"]) != 1:
		return "classe ou missão não voltaram: %s" % rec
	rec["evolution"] = 1
	rec["quests"] = {"evolucao": {"done": true}}
	repo.save_character(rec)
	var again := repo.load_character(cid)
	if int(again["evolution"]) != 1 or not bool(again["quests"]["evolucao"]["done"]):
		return "evolução não foi salva"
	if int(repo.list_characters(acc)[0]["evolution"]) != 1:
		return "a lista de personagens não traz a evolução"
	repo.close()
	return ""
