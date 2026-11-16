extends RefCounted
## Fase 3: hash de senha, repositório SQLite (em memória), diário serializado e
## reconstrução do personagem a partir do registro salvo.


func _catalog() -> ItemCatalog:
	var t := {}
	for n in ["items", "item_options", "sets"]:
		t[n] = ConfigLoader.load_json("res://data/%s.json" % n)
		t[n].erase("_doc")
	return ItemCatalog.new(t["items"], t["item_options"], t["sets"])


func test_pbkdf2_known_vectors() -> String:
	# vetores públicos de PBKDF2-HMAC-SHA256 (P = "password", S = "salt", 32 bytes)
	var salt := "salt".to_utf8_buffer()
	var cases := {
		1: "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b",
		2: "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43",
		4096: "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a",
	}
	for c: int in cases:
		var h := PasswordHasher.hash_password("password", salt, c)
		if h != cases[c]:
			return "c=%d: %s" % [c, h]
	if not PasswordHasher.equals(cases[1], cases[1]) or PasswordHasher.equals(cases[1], cases[2]):
		return "comparação errada"
	var iterations := int(ConfigLoader.load_json("res://data/config/server.json")["password_iterations"])
	var t := Time.get_ticks_msec()
	PasswordHasher.hash_password("uma senha qualquer", PasswordHasher.new_salt(), iterations)
	print("        (PBKDF2 com %d iterações: %d ms, numa thread do servidor)" % [iterations, Time.get_ticks_msec() - t])
	return ""


func test_repository_accounts_and_characters() -> String:
	if not SqliteRepository.available():
		return "extensão godot-sqlite não carregada"
	var repo := SqliteRepository.new(":memory:")
	if not repo.open():
		return "não abriu o banco"
	var id := repo.create_account("ana", "00ff", "abcd", 10)
	if id == 0 or repo.create_account("ana", "00", "00", 1) != 0:
		return "criação de conta (ou duplicata aceita)"
	if int(repo.find_account("ana")["id"]) != id or not repo.find_account("bia").is_empty():
		return "busca de conta"
	var rec := {"name": "Ysolde", "class_id": "feiticeiro", "level": 7, "xp": 120, "points": 3,
		"stats": {"str": 18, "agi": 19, "vit": 15, "ene": 44}, "currency": 999, "hp": 55.5, "mana": 40.0,
		"region_id": "ruinas", "pos": [1.5, -2.25], "learned_spells": 31,
		"items": [
			{"uid": 41, "base": "vara_eclipse", "level": 9, "rarity": 1, "luck": true, "extra": 2, "exc": ["dmg_pct", "exc_rate"], "container": 0, "x": 2, "y": 0, "count": 1},
			{"uid": 42, "base": "pocao_vida_menor", "level": 0, "rarity": 0, "luck": false, "extra": 0, "exc": [], "container": ItemCatalog.CONTAINER_STORAGE, "x": 5, "y": 6, "count": 17},
		],
		"journals": {"ruinas": {"strokes": [[0.0, 0.0, 1.5, 2.5]], "marks": [["x", 1.0, 2.0, "Aqui"]], "discovered": ["_entrada"]}}}
	var cid := repo.create_character(id, rec)
	if cid == 0:
		return "não criou o personagem"
	if not repo.character_name_taken("YSOLDE") or repo.character_name_taken("Hálvor"):
		return "checagem de nome (sem diferenciar maiúsculas)"
	if repo.list_characters(id).size() != 1 or str(repo.list_characters(id)[0]["name"]) != "Ysolde":
		return "lista de personagens"
	var back := repo.load_character(cid)
	if int(back["level"]) != 7 or int(back["stats"]["ene"]) != 44 or int(back["currency"]) != 999 or not is_equal_approx(float(back["pos"][1]), -2.25):
		return "atributos não voltaram iguais: %s" % back
	var items: Array = back["items"]
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["uid"]) < int(b["uid"]))
	if items.size() != 2 or not bool(items[0]["luck"]) or (items[0]["exc"] as Array) != ["dmg_pct", "exc_rate"] or int(items[1]["count"]) != 17 or int(items[1]["container"]) != ItemCatalog.CONTAINER_STORAGE:
		return "itens não voltaram iguais: %s" % [items]
	if str(back["journals"]["ruinas"]["marks"][0][3]) != "Aqui":
		return "diário não voltou"
	# salvar de novo com um item a menos e outro novo
	back["items"] = [items[1], {"uid": 50, "base": "anel_brasa", "level": 0, "rarity": 0, "luck": false, "extra": 0, "exc": [], "container": 10, "x": 0, "y": 0, "count": 1}]
	back["level"] = 8
	if not repo.save_character(back):
		return "save falhou"
	var again := repo.load_character(cid)
	if int(again["level"]) != 8 or (again["items"] as Array).size() != 2 or repo.max_item_uid() != 50:
		return "regravação: nível %s, itens %s, max uid %d" % [again["level"], (again["items"] as Array).size(), repo.max_item_uid()]
	repo.close()
	return ""


func test_journal_round_trip() -> String:
	var j := RegionJournal.new(0.15, 32)
	for i in 100:
		j.add_point(Vector2(i * 0.5, sin(i * 0.2) * 3.0), i == 50)
	j.add_mark("star", Vector2(3, 4), "Cristal")
	j.set_discovered("cristal")
	var d := j.to_dict()
	var copy := RegionJournal.new(0.15, 32)
	copy.load_dict(JSON.parse_string(JSON.stringify(d)))
	var a := j.export_strokes()
	var b := copy.export_strokes()
	if a.size() != b.size() or a.size() != 2:
		return "número de traços: %d vs %d" % [a.size(), b.size()]
	for s in a.size():
		if a[s].size() != b[s].size() or a[s][a[s].size() - 1].distance_to(b[s][b[s].size() - 1]) > 0.01:
			return "traço %d diferente" % s
	if not copy.is_discovered("cristal") or copy.export_marks() != j.export_marks():
		return "marcas ou descobertas não voltaram"
	return ""


func test_character_codec_places_items() -> String:
	var cat := _catalog()
	var inv := InventoryService.new(cat)
	var rec := {"id": 3, "account_id": 1, "name": "Teste", "class_id": "feiticeiro", "level": 2, "xp": 0, "points": 0,
		"stats": {"str": 18, "agi": 18, "vit": 15, "ene": 30}, "currency": 5, "hp": 10.0, "mana": 5.0,
		"region_id": "ruinas", "pos": [0.0, 0.0], "learned_spells": 15, "items": [
			{"uid": 1, "base": "cajado_osso", "level": 0, "rarity": 0, "luck": false, "extra": 0, "exc": [], "container": 1, "x": 0, "y": 0, "count": 1},
			{"uid": 2, "base": "manto_acolito", "level": 3, "rarity": 0, "luck": false, "extra": 0, "exc": [], "container": 0, "x": 4, "y": 2, "count": 1},
			{"uid": 3, "base": "joia_alma", "level": 0, "rarity": 0, "luck": false, "extra": 0, "exc": [], "container": ItemCatalog.CONTAINER_FORGE, "x": 0, "y": 0, "count": 1},
			{"uid": 4, "base": "item_que_nao_existe", "level": 0, "rarity": 0, "luck": false, "extra": 0, "exc": [], "container": 0, "x": 0, "y": 0, "count": 1},
		]}
	var p := ServerPlayer.new()
	CharacterCodec.apply(p, rec, inv)
	if p.equipment.get("weapon", 0) != 1:
		return "cajado não voltou equipado"
	if p.inventory.rect_of(2).position != Vector2i(4, 2):
		return "manto não voltou para (4,2)"
	if int(p.items[3]["container"]) != ItemCatalog.CONTAINER_INVENTORY:
		return "item da mesa da forja deveria voltar para a mochila"
	if p.items.has(4):
		return "item com base desconhecida deveria ser ignorado"
	var out := CharacterCodec.to_record(p, {})
	if (out["items"] as Array).size() != 3 or int(out["learned_spells"]) != 15:
		return "registro de volta incompleto"
	return ""

func test_migration_from_v1() -> String:
	if not SqliteRepository.available():
		return "extensão godot-sqlite não carregada"
	var path := "user://teste_migracao_v1.db"
	for suffix in ["", "-wal", "-shm"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	# banco no formato antigo (versão 1, sem infâmia nem herói) com um personagem
	var raw: Object = ClassDB.instantiate("SQLite")
	raw.set("path", ProjectSettings.globalize_path(path))
	raw.set("verbosity_level", 0)
	raw.call("open_db")
	for sql: String in SqliteRepository.SCHEMA:
		raw.call("query", sql)
	raw.call("query", "INSERT INTO schema_version (version) VALUES (1);")
	raw.call("query", "INSERT INTO accounts (name, salt, hash, iterations, created_at) VALUES ('velha', '00', '00', 1, 0);")
	raw.call("query", """INSERT INTO characters (account_id, name, name_key, class_id, level, xp, points, str, agi, vit, ene,
		currency, hp, mana, region_id, pos_x, pos_z, learned_spells, created_at, saved_at)
		VALUES (1, 'Antigo', 'antigo', 'feiticeiro', 12, 0, 0, 18, 18, 15, 30, 77, 50, 50, 'ruinas', 0, 0, 15, 0, 0);""")
	raw.call("close_db")
	var repo := SqliteRepository.new(path)
	if not repo.open():
		return "não abriu o banco antigo"
	var rec := repo.load_character(1)
	if int(rec.get("level", 0)) != 12 or int(rec.get("currency", 0)) != 77 or int(rec.get("infamy", -1)) != 0 or int(rec.get("hero", -1)) != 0:
		return "personagem antigo não voltou certo depois da migração: %s" % rec
	rec["infamy"] = 4
	rec["hero"] = 2
	if not repo.save_character(rec) or int(repo.load_character(1)["infamy"]) != 4:
		return "infâmia não foi salva depois da migração"
	if repo.create_guild("Antigos", "6".repeat(64), 1) == 0 or repo.load_guilds().size() != 1:
		return "tabelas de guilda (versão 3) não foram criadas na migração"
	repo.close()
	var again := SqliteRepository.new(path) # abrir de novo não migra duas vezes
	if not again.open() or int(again.load_character(1)["hero"]) != 2:
		return "segunda abertura falhou"
	again.close()
	for suffix in ["", "-wal", "-shm"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	return ""


func test_pvp_levels() -> String:
	var cfg := ConfigLoader.load_json("res://data/pvp.json")
	var levels: Array = cfg["outlaw_levels"]
	var expected := {0: 0, 1: 1, 2: 1, 3: 2, 5: 2, 6: 3, 50: 3}
	for infamy: int in expected:
		if PvpSystem.level_for(infamy, levels, "infamy") != expected[infamy]:
			return "infâmia %d deveria dar nível %d" % [infamy, expected[infamy]]
	var last := -1
	for lv: Dictionary in levels:
		if int(lv["infamy"]) <= last or float(lv["item_drop_chance"]) > 1.0:
			return "níveis de Fora da Lei fora de ordem ou chance inválida"
		last = int(lv["infamy"])
	if PvpSystem.level_for(1, cfg["hero_levels"], "points") != 1:
		return "herói com 1 ponto"
	return ""
