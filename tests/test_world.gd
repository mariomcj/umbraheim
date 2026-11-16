extends RefCounted
## Fase 4: regiões, portais e cenário procedural.


func _load(path: String) -> Dictionary:
	var d := ConfigLoader.load_json(path)
	d.erase("_doc")
	return d


func _regions() -> Dictionary:
	var out := {}
	for id: String in _load("res://data/world.json")["regions"]:
		out[id] = _load("res://data/regions/%s.json" % id)
	return out


func test_regions_and_portals_are_consistent() -> String:
	var world := _load("res://data/world.json")
	var regions := _regions()
	var monsters := _load("res://data/monsters.json")
	var errors := PackedStringArray()
	if not regions.has(str(world["home_region"])):
		errors.append("home_region inexistente")
	var last_level := 0
	for id: String in world["regions"]:
		var r: Dictionary = regions[id]
		if int(r.get("level_req", 0)) < last_level:
			errors.append("%s: nível mínimo menor que o da região anterior" % id)
		last_level = int(r.get("level_req", 0))
		if not ResourceLoader.exists(str(r["scene"])):
			errors.append("%s: cena não existe" % id)
		if not regions.has(str(r.get("respawn_region", id))):
			errors.append("%s: respawn_region inexistente" % id)
		for key in ["player_spawn", "teleport_point"]:
			if not r.has(key):
				errors.append("%s: falta %s" % [id, key])
		for sp: Dictionary in r["monster_spawns"]:
			if not monsters.has(str(sp["monster"])):
				errors.append("%s: monstro inexistente %s" % [id, sp["monster"]])
		for pt: Dictionary in r.get("portals", []):
			var to: Dictionary = regions.get(str(pt["to_region"]), {})
			if to.is_empty():
				errors.append("%s/%s: região de destino inexistente" % [id, pt["id"]])
				continue
			var back: Dictionary = {}
			for other: Dictionary in to.get("portals", []):
				if str(other["id"]) == str(pt["to_portal"]):
					back = other
			if back.is_empty():
				errors.append("%s/%s: portal de chegada %s não existe em %s" % [id, pt["id"], pt["to_portal"], pt["to_region"]])
				continue
			if str(back["to_region"]) != id:
				errors.append("%s/%s: o portal do outro lado não volta para cá" % [id, pt["id"]])
			# chegar dentro do raio do portal de lá mandaria o jogador de volta na hora
			var arrival := Vector2(float(back["arrival"][0]), float(back["arrival"][1]))
			if arrival.distance_to(Vector2(float(back["pos"][0]), float(back["pos"][1]))) <= float(back["radius_m"]) + 1.0:
				errors.append("%s: chegada perto demais do portal" % pt["to_region"])
		var has_portal_mark := false
		for lm: Dictionary in r["landmarks"]:
			has_portal_mark = has_portal_mark or str(lm["symbol"]) == "portal"
		if not r.get("portals", []).is_empty() and not has_portal_mark:
			errors.append("%s: portais sem marcação no diário" % id)
	return "; ".join(errors)


func test_portals_and_spawns_are_walkable() -> String:
	var errors := PackedStringArray()
	for id: String in _regions():
		var r: Dictionary = _regions()[id]
		var grid := WorldBuilder.build_nav_grid(r, 38.0)
		var points: Array = [["player_spawn", r["player_spawn"]], ["teleport_point", r["teleport_point"]]]
		for pt: Dictionary in r.get("portals", []):
			points.append(["portal " + str(pt["id"]), pt["pos"]])
			points.append(["chegada " + str(pt["id"]), pt["arrival"]])
		for p: Array in points:
			var v := Vector2(float(p[1][0]), float(p[1][1]))
			if grid.nearest_walkable_point(v).distance_to(v) > 1.0:
				errors.append("%s: %s está dentro de um obstáculo" % [id, p[0]])
		# do ponto de chegada dá para andar até cada portal
		var spawn := grid.nearest_walkable_point(Vector2(float(r["player_spawn"][0]), float(r["player_spawn"][1])))
		for pt: Dictionary in r.get("portals", []):
			var goal := Vector2(float(pt["pos"][0]), float(pt["pos"][1]))
			var path := grid.find_path(spawn, goal)
			if path.is_empty() or path[path.size() - 1].distance_to(goal) > 1.5:
				errors.append("%s: sem caminho até o portal %s" % [id, pt["id"]])
	return "; ".join(errors)


func test_golden_variants_and_bosses() -> String:
	var monsters := _load("res://data/monsters.json")
	var events := _load("res://data/events.json")
	var drops := _load("res://data/drops.json")
	var defs := MonsterCatalog.build(monsters, events)
	var g: Dictionary = events["golden"]
	var errors := PackedStringArray()
	for base_id: String in g["monsters"]:
		var gold: Dictionary = defs.get(base_id + MonsterCatalog.GOLDEN_SUFFIX_ID, {})
		if gold.is_empty():
			errors.append("sem variante dourada de %s" % base_id)
			continue
		if not is_equal_approx(float(gold["hp"]), float(monsters[base_id]["hp"]) * float(g["hp_mult"])) or not bool(gold["golden"]):
			errors.append("%s dourado com vida errada" % base_id)
		if str(gold["drop_table"]) != str(g["drop_table"]) or str(gold["visual"]) != str(monsters[base_id]["visual"]):
			errors.append("%s dourado com drop ou visual errado" % base_id)
	if not (drops["tables"] as Dictionary).has(str(g["drop_table"])):
		errors.append("tabela da invasão inexistente")
	# a ordem dos tipos não pode depender de quem monta (servidor e cliente)
	if MonsterCatalog.type_ids(defs) != MonsterCatalog.type_ids(MonsterCatalog.build(monsters, events)):
		errors.append("ordem dos tipos instável")
	var regions := _regions()
	var bosses_per_region := {}
	for id: String in regions:
		for sp: Dictionary in regions[id]["monster_spawns"]:
			var d: Dictionary = defs.get(str(sp["monster"]), {})
			if bool(d.get("boss", false)):
				bosses_per_region[id] = int(bosses_per_region.get(id, 0)) + int(sp["count"])
				if float(d["respawn_s"]) < 300.0:
					errors.append("chefe %s renasce rápido demais" % sp["monster"])
	for id: String in regions:
		if int(bosses_per_region.get(id, 0)) != 1:
			errors.append("%s deveria ter um chefe" % id)
	for id: String in events["invasion"]["regions"]:
		if not regions.has(id):
			errors.append("invasão em região inexistente %s" % id)
		for m: String in events["invasion"]["regions"][id]["monsters"]:
			if not defs.has(m + MonsterCatalog.GOLDEN_SUFFIX_ID):
				errors.append("invasão usa %s sem variante dourada" % m)
	return "; ".join(errors)


func test_scenery_is_deterministic() -> String:
	var a := _build("res://client/world/regions/bosque.tscn")
	var b := _build("res://client/world/regions/bosque.tscn")
	if a.is_empty() or a != b:
		return "o cenário procedural mudou entre duas montagens (%d vs %d peças)" % [a.size(), b.size()]
	return ""


func _build(path: String) -> PackedVector2Array:
	var root: Node = (load(path) as PackedScene).instantiate()
	var out := PackedVector2Array()
	for node in root.find_children("*", "", true, false):
		if node.has_method("populate"):
			node.call("populate")
			for child in node.get_children():
				out.append(Vector2((child as Node3D).position.x, (child as Node3D).position.z))
	root.free()
	return out
