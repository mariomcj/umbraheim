extends RefCounted
## Fórmulas de atributos, tabela de XP, rolagem de dano e navegação.


func _class_data() -> Dictionary:
	var d := ConfigLoader.load_json("res://data/classes/feiticeiro.json")
	d.erase("_doc")
	return d


func test_stat_formulas_parse_and_compute() -> String:
	var data := _class_data()
	var calc := StatCalculator.new(data["derived"])
	if not calc.errors.is_empty():
		return "fórmulas inválidas: %s" % calc.errors
	var d1 := calc.compute(1, data["base_stats"])
	for key in ["hp_max", "mana_max", "magic_min", "magic_max", "defense", "attack_speed", "hp_regen_s", "mana_regen_s", "move_speed_mps"]:
		if not d1.has(key):
			return "derivado ausente: %s" % key
	if d1["hp_max"] <= 0.0 or d1["mana_max"] <= 0.0 or d1["magic_max"] < d1["magic_min"]:
		return "valores iniciais incoerentes: %s" % d1
	var more_ene: Dictionary = data["base_stats"].duplicate()
	more_ene["ene"] = int(more_ene["ene"]) + 20
	var d2 := calc.compute(1, more_ene)
	if d2["magic_max"] <= d1["magic_max"] or d2["mana_max"] <= d1["mana_max"]:
		return "Energia não aumenta dano mágico/mana"
	var more_vit: Dictionary = data["base_stats"].duplicate()
	more_vit["vit"] = int(more_vit["vit"]) + 10
	if calc.compute(1, more_vit)["hp_max"] <= d1["hp_max"]:
		return "Vitalidade não aumenta a vida"
	return ""


func test_xp_table_grows_and_level_up() -> String:
	var prog := Progression.new(ConfigLoader.load_json("res://data/progression.json"))
	var prev := 0
	for lv in range(1, 60):
		var need := prog.xp_to_next(lv)
		if need <= prev:
			return "XP não cresce no nível %d (%d <= %d)" % [lv, need, prev]
		prev = need
	if prog.xp_to_next(prog.max_level) != 0:
		return "nível máximo deveria pedir 0 XP"
	var r := prog.apply_xp(1, 0, prog.xp_to_next(1) + prog.xp_to_next(2) + 5)
	if r[0] != 3 or r[1] != 5 or r[2] != 2:
		return "apply_xp errado: %s" % [r]
	if prog.monster_xp(5) <= prog.monster_xp(3):
		return "monstro mais forte deveria dar mais XP"
	return ""


## Simulação estatística: taxas de crítico/excelente e dano mínimo.
func test_damage_roll_distribution() -> String:
	var cfg := {"crit_chance": 0.1, "excellent_chance": 0.05, "excellent_mult": 1.2, "defense_factor": 1.0, "min_damage": 1}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var n := 20000
	var counts := [0, 0, 0]
	for i in n:
		var r := CombatRules.roll(10.0, 20.0, 1.0, 0.0, 0.0, cfg, rng)
		counts[r.y] += 1
		if r.y == Protocol.DMG_EXCELLENT and r.x != 24:
			return "excelente deveria ser 20 * 1.2 = 24, veio %d" % r.x
		if r.y == Protocol.DMG_CRITICAL and r.x != 20:
			return "crítico deveria ser o máximo (20), veio %d" % r.x
		if r.y == Protocol.DMG_NORMAL and (r.x < 10 or r.x > 20):
			return "normal fora da faixa: %d" % r.x
	var exc := float(counts[2]) / n
	var crit := float(counts[1]) / n
	if absf(exc - 0.05) > 0.01 or absf(crit - 0.1) > 0.015:
		return "taxas fora do esperado: excelente %.3f, crítico %.3f" % [exc, crit]
	var weak := CombatRules.roll(1.0, 2.0, 1.0, 0.0, 50.0, cfg, rng)
	return "" if weak.x == 1 else "dano mínimo deveria ser 1, veio %d" % weak.x


func test_nav_grid_paths_around_wall() -> String:
	var grid := NavGrid.new()
	var wall: Array[Rect2] = [Rect2(-1.0, -10.0, 2.0, 16.0)] # parede de x -1..1, z -10..6
	grid.build(20.0, 0.5, wall, 0.4)
	if grid.is_walkable(Vector2(0, 0)) or not grid.is_walkable(Vector2(5, 0)):
		return "bloqueio incorreto"
	var path := grid.find_path(Vector2(-5, 0), Vector2(5, 0))
	if path.size() < 3:
		return "deveria contornar a parede: %s" % path
	for i in range(1, path.size()):
		if not grid.has_line_of_sight(path[i - 1], path[i]):
			return "trecho atravessa a parede: %s -> %s" % [path[i - 1], path[i]]
	if not path[path.size() - 1].is_equal_approx(Vector2(5, 0)):
		return "não termina no destino"
	var direct := grid.find_path(Vector2(-5, 10), Vector2(5, 10))
	if direct.size() != 2:
		return "caminho livre deveria ser reto: %s" % direct
	var slid := grid.slide(Vector2(-1.6, 0), Vector2(0.5, 0.5))
	if not grid.is_walkable(slid):
		return "slide entrou na parede"
	return ""


func test_game_data_references() -> String:
	var spells := ConfigLoader.load_json("res://data/spells.json")
	var monsters := ConfigLoader.load_json("res://data/monsters.json")
	var drops := ConfigLoader.load_json("res://data/drops.json")
	var region := ConfigLoader.load_json("res://data/regions/ruinas.json")
	var cls := _class_data()
	var slots := {}
	for id: String in cls["spells"]:
		if not spells.has(id):
			return "classe usa magia inexistente '%s'" % id
		var s: Dictionary = spells[id]
		for key in ["name", "slot", "kind", "mana_cost", "cooldown_s", "range_m", "damage_mult", "damage_bonus", "color"]:
			if not s.has(key):
				return "magia '%s' sem '%s'" % [id, key]
		if slots.has(int(s["slot"])):
			return "duas magias no slot %d" % int(s["slot"])
		slots[int(s["slot"])] = true
	if not slots.has(0):
		return "classe sem ataque básico (slot 0)"
	for mid: String in monsters:
		if mid.begins_with("_"):
			continue # _doc
		var m: Dictionary = monsters[mid]
		if not drops["tables"].has(m["drop_table"]) and not bool(m.get("structure", false)):
			return "monstro '%s' usa tabela de drop inexistente" % mid
		if not ResourceLoader.exists(str(m["visual"])):
			return "visual do monstro '%s' não existe: %s" % [mid, m["visual"]]
	for table: Dictionary in drops["tables"].values():
		for e: Dictionary in table["entries"]:
			if e.has("pool") and not drops["pools"].has(e["pool"]):
				return "pool de drop inexistente '%s'" % e["pool"]
	for sp: Dictionary in region["monster_spawns"]:
		if not monsters.has(sp["monster"]):
			return "spawn de monstro inexistente '%s'" % sp["monster"]
	if not ResourceLoader.exists(str(region["scene"])):
		return "cena da região não existe"
	return ""
