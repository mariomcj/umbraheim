extends RefCounted
## Fase 6, parte 1: calendário dos eventos, faixas de nível, ingresso na Forja e a região
## da Fortaleza (bloqueios que abrem, pontos de nascimento andáveis).


func _events() -> Dictionary:
	return ConfigLoader.load_json("res://data/scheduled_events.json")


func test_schedule_math() -> String:
	# a cada 30 min, no minuto 0; portões 180 s antes
	var base := 1_700_000_000.0 - fmod(1_700_000_000.0, 1800.0) # um começo de ciclo
	if EventSystem.next_start(base - 600.0, 30, 0, 180.0) != base:
		return "10 min antes do começo, o próximo é este"
	if EventSystem.next_start(base - 100.0, 30, 0, 180.0) != base + 1800.0:
		return "com os portões já abertos (100 s antes), o próximo é o do ciclo seguinte"
	if EventSystem.next_start(base + 5.0, 30, 0, 180.0) != base + 1800.0:
		return "logo depois do começo, o próximo é o do ciclo seguinte"
	if EventSystem.next_start(base, 30, 10, 180.0) != base + 600.0:
		return "deslocamento de 10 min"
	return ""


func test_bands_and_tickets() -> String:
	var cat := ItemCatalog.from_config()
	for id: String in _events()["events"]:
		var e: Dictionary = _events()["events"][id]
		var bands: Array = e["bands"]
		var last := 0
		for b: Dictionary in bands:
			if int(b["min_level"]) != last + 1 and last != 0:
				return "%s: faixas com buraco ou sobreposição em %d" % [id, int(b["min_level"])]
			last = int(b["max_level"])
			var keys: Array = {"fortress": ["monster", "boss", "gate"], "waves": ["boss"], "circle": ["guard"], "siege": []}[str(e.get("logic", "fortress"))]
			for k: String in keys:
				if not MonsterCatalog.from_config().has(str(b[k])):
					return "%s: monstro inexistente %s" % [id, b[k]]
			for m: String in b.get("monsters", []):
				if not MonsterCatalog.from_config().has(m):
					return "%s: monstro inexistente %s" % [id, m]
		if EventSystem.band_for(int(bands[0]["min_level"]) - 1, bands) != -1 or EventSystem.band_for(int(bands[0]["min_level"]), bands) != 0:
			return "%s: limite da primeira faixa" % id
		if str(e.get("logic", "")) == "siege": # o cerco não tem ingresso: entra pelo Arauto
			for k in ["gate", "guard"]:
				if not MonsterCatalog.from_config().has(str(e[k])):
					return "cerco: monstro inexistente %s" % e[k]
			if not ResourceLoader.exists(str(GameConfig.region(str(e["region"]))["scene"])):
				return "cerco: cena da região não existe"
			continue
		var ticket := cat.base({"base": str(e["ticket"])})
		if ticket.is_empty() or str(ticket["use"]["type"]) != "event_ticket" or str(ticket["use"]["event"]) != id:
			return "%s: ingresso inválido" % id
		if not ResourceLoader.exists(str(GameConfig.region(str(e["region"]))["scene"])):
			return "%s: cena da região não existe" % id
	# o ingresso sai da Forja do Vórtice
	var book := RecipeBook.new(GameConfig.table("recipes"), cat)
	var r := book.evaluate([{"base": "pergaminho_sitiante", "count": 1}, {"base": "osso_brasa", "count": 1}, {"base": "joia_alma", "count": 1}])
	if str(r.get("recipe", "")) != "selo_fortaleza":
		return "a receita do Selo da Fortaleza não foi reconhecida: %s" % r
	for pair: Array in [[["osso_brasa", "joia_consagrada"], "emblema_arena"], [["pergaminho_sitiante", "joia_vida"], "marca_circulo"]]:
		var items: Array = []
		for b: String in pair[0]:
			items.append({"base": b, "count": 1})
		if str(book.evaluate(items).get("recipe", "")) != str(pair[1]):
			return "receita do %s não reconhecida" % pair[1]
	return ""


func test_arena_and_circle_rules() -> String:
	var rank := ArenaEvent.ranking({11: 40, 12: 155, 13: 0, 14: 90})
	if int(rank[0][0]) != 12 or int(rank[1][0]) != 14 or int(rank[3][0]) != 13:
		return "ranking errado: %s" % [rank]
	var e: Dictionary = _events()["events"]
	var ring: Dictionary = e["circulo"]["ring"]
	if CircleEvent.radius_at(0.0, ring) != float(ring["start_radius"]) or CircleEvent.radius_at(9999.0, ring) != float(ring["end_radius"]):
		return "anel no começo e no fim"
	var mid := (float(ring["shrink_start_s"]) + float(ring["shrink_end_s"])) / 2.0
	if not is_equal_approx(CircleEvent.radius_at(mid, ring), (float(ring["start_radius"]) + float(ring["end_radius"])) / 2.0):
		return "anel na metade do tempo"
	var waves: Array = e["arena"]["waves"]
	if not bool(waves[-1].get("boss", false)):
		return "a última onda deve trazer o campeão"
	for w: Dictionary in waves:
		if int(w["monster"]) >= (e["arena"]["bands"][0]["monsters"] as Array).size():
			return "onda com monstro fora da lista da faixa"
	var circulo := GameConfig.region("circulo")
	if str(circulo.get("pvp", "")) != "free" or not bool(circulo.get("no_items", false)) or GameConfig.region("arena").get("pvp", true) != false:
		return "regras de PvP e itens das regiões"
	return ""


func test_event_regions_walkable() -> String:
	var half := float(ConfigLoader.load_json("res://data/config/movement.json")["world_half_extent_m"])
	for region_id in ["arena", "circulo"]:
		var data := GameConfig.region(region_id)
		var grid := WorldBuilder.build_nav_grid(data, half)
		var spawn := Vector2(float(data["player_spawn"][0]), float(data["player_spawn"][1]))
		if not grid.is_walkable(spawn) or not SafeZones.new(data).contains(spawn):
			return "%s: antessala não andável ou não segura" % region_id
		for key: String in data["spawn_points"]:
			var pts: Array = data["spawn_points"][key]
			if pts[0] is float or pts[0] is int:
				pts = [pts]
			for p: Array in pts:
				if not grid.is_walkable(Vector2(float(p[0]), float(p[1]))):
					return "%s: ponto %s fora do chão: %s" % [region_id, key, p]
		var center := Vector2.ZERO
		var path := grid.find_path(spawn, center)
		if not path.is_empty() and path[-1].distance_to(center) < 1.0:
			return "%s: a grade fechada deveria isolar a antessala" % region_id
		WorldBuilder.apply_blockers(grid, data, false, ["grade"])
		path = grid.find_path(spawn, center)
		if path.is_empty() or path[-1].distance_to(center) > 1.0:
			return "%s: com a grade aberta, a antessala leva ao centro" % region_id
	return ""


func test_fortress_blockers() -> String:
	var data := GameConfig.region("fortaleza")
	var grid := WorldBuilder.build_nav_grid(data, float(ConfigLoader.load_json("res://data/config/movement.json")["world_half_extent_m"]))
	var spawn := Vector2(float(data["player_spawn"][0]), float(data["player_spawn"][1]))
	if not grid.is_walkable(spawn):
		return "a antessala não é andável"
	for key in ["courtyard", "hall"]:
		for p: Array in data["spawn_points"][key]:
			if not grid.is_walkable(Vector2(float(p[0]), float(p[1]))):
				return "ponto de %s fora do chão andável: %s" % [key, p]
	var courtyard := Vector2(0.0, 12.0)
	var hall := Vector2(0.0, -20.0)
	if not grid.find_path(spawn, courtyard).is_empty() and grid.find_path(spawn, courtyard)[-1].distance_to(courtyard) < 1.0:
		return "a grade fechada deveria isolar a antessala"
	WorldBuilder.apply_blockers(grid, data, false, ["grade"])
	var to_court := grid.find_path(spawn, courtyard)
	if to_court.is_empty() or to_court[-1].distance_to(courtyard) > 1.0:
		return "com a grade aberta, a antessala leva ao pátio"
	var to_hall := grid.find_path(courtyard, hall)
	if not to_hall.is_empty() and to_hall[-1].distance_to(hall) < 1.0:
		return "o portão fechado deveria isolar o salão"
	WorldBuilder.apply_blockers(grid, data, false, ["portao"])
	to_hall = grid.find_path(courtyard, hall)
	if to_hall.is_empty() or to_hall[-1].distance_to(hall) > 1.0:
		return "com o portão aberto, o pátio leva ao salão"
	var safe := SafeZones.new(data)
	if not safe.contains(spawn) or safe.contains(courtyard):
		return "só a antessala é segura"
	return ""



func test_siege_rules_and_castle() -> String:
	# captura: só uma guilda sozinha que não é a dona avança; disputa ou dona sozinha zera
	var st := SiegeEvent.capture_step([7], 3, 0, 0.0)
	if int(st[0]) != 7 or float(st[1]) != 1.0:
		return "começo da captura: %s" % [st]
	st = SiegeEvent.capture_step([7], 3, 7, 5.0)
	if float(st[1]) != 6.0:
		return "captura continua: %s" % [st]
	if float(SiegeEvent.capture_step([7, 3], 3, 7, 5.0)[1]) != 0.0 or float(SiegeEvent.capture_step([3], 3, 7, 5.0)[1]) != 0.0 			or float(SiegeEvent.capture_step([], 3, 7, 5.0)[1]) != 0.0:
		return "disputa, só a dona ou ninguém zera a captura"
	if CastleSystem.tax_on(12, 0.1) != 2 or CastleSystem.tax_on(100, 0.05) != 5 or CastleSystem.tax_on(100, 0.0) != 0:
		return "imposto arredondado para cima"
	var c := ConfigLoader.load_json("res://data/castle.json")
	if float(c["tax_default_pct"]) > float(c["tax_max_pct"]):
		return "imposto padrão acima do máximo"
	# região: o portão isola o trono do acampamento; acampamento e sala seguros, trono não
	var data := GameConfig.region("castelo")
	var grid := WorldBuilder.build_nav_grid(data, float(ConfigLoader.load_json("res://data/config/movement.json")["world_half_extent_m"]))
	var sp: Dictionary = data["spawn_points"]
	var camp := Vector2(float(sp["attackers"][0]), float(sp["attackers"][1]))
	var room := Vector2(float(sp["defenders"][0]), float(sp["defenders"][1]))
	var throne := Vector2(float(sp["throne"][0]), float(sp["throne"][1]))
	for pt: Vector2 in [camp, room, throne]:
		if not grid.is_walkable(pt):
			return "ponto fora do chão: %s" % pt
	var path := grid.find_path(camp, throne)
	if not path.is_empty() and path[-1].distance_to(throne) < 1.0:
		return "o portão fechado deveria isolar o trono do acampamento"
	path = grid.find_path(room, throne)
	if path.is_empty() or path[-1].distance_to(throne) > 1.0:
		return "a sala dos defensores leva ao trono"
	WorldBuilder.apply_blockers(grid, data, false, ["portao"])
	path = grid.find_path(camp, throne)
	if path.is_empty() or path[-1].distance_to(throne) > 1.0:
		return "com o portão aberto, o acampamento leva ao trono"
	var safe := SafeZones.new(data)
	if not safe.contains(camp) or not safe.contains(room) or safe.contains(throne):
		return "acampamento e sala seguros, trono não"
	if str(data["pvp"]) != "guild":
		return "PvP do castelo deve ser por guilda"
	# castelo no banco
	if not SqliteRepository.available():
		return "extensão godot-sqlite não carregada"
	var repo := SqliteRepository.new(":memory:")
	if not repo.open():
		return "não abriu o banco"
	if not repo.load_castle("castelo").is_empty():
		return "castelo novo começa sem registro"
	repo.save_castle({"id": "castelo", "guild_id": 4, "tax_pct": 0.12, "treasury": 777, "registered": [5, 9], "since": 123})
	var back := repo.load_castle("castelo")
	if int(back["guild_id"]) != 4 or not is_equal_approx(float(back["tax_pct"]), 0.12) or int(back["treasury"]) != 777 or back["registered"] != [5, 9]:
		return "castelo não voltou do banco: %s" % back
	repo.close()
	return ""
