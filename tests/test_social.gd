extends RefCounted
## Fase 3, parte 2: limpeza do chat, divisão de XP no grupo e checagem de espaço da troca.


func _catalog() -> ItemCatalog:
	var t := {}
	for n in ["items", "item_options", "sets"]:
		t[n] = ConfigLoader.load_json("res://data/%s.json" % n)
		t[n].erase("_doc")
	return ItemCatalog.new(t["items"], t["item_options"], t["sets"])


func _player(level: int, pos: Vector2, class_id: String = "feiticeiro") -> ServerPlayer:
	var p := ServerPlayer.new()
	p.level = level
	p.position = pos
	p.class_id = class_id
	p.alive = true
	return p


func test_chat_clean() -> String:
	if ChatService.clean("  olá\u0007 mundo\n ", 160) != "olá mundo":
		return "não tirou controle/espaços: '%s'" % ChatService.clean("  olá\u0007 mundo\n ", 160)
	if ChatService.clean("x".repeat(500), 160).length() != 160:
		return "não cortou no tamanho máximo"
	if ChatService.clean("[color=red]oi[/color]", 160) != "[color=red]oi[/color]":
		return "o texto deve passar igual (o cliente mostra sem BBCode)"
	return ""


func test_party_xp_shares() -> String:
	var cfg: Dictionary = ConfigLoader.load_json("res://data/social.json")["party"]
	var killer := _player(10, Vector2.ZERO)
	var near := _player(30, Vector2(5, 0))
	var far := _player(50, Vector2(500, 0))
	var dead := _player(20, Vector2(1, 0))
	dead.alive = false
	var members: Array[ServerPlayer] = [killer, near, far, dead]
	var s := PartySystem.shares(members, killer, Vector2(2, 0), 1000, cfg)
	if s.size() != 2:
		return "só quem está vivo e perto recebe (vieram %d)" % s.size()
	var total := 1000.0 * (1.0 + float(cfg["bonus_per_member"]))
	if int(s[0][1]) != roundi(total * 10 / 40.0) or int(s[1][1]) != roundi(total * 30 / 40.0):
		return "divisão por nível errada: %d e %d" % [s[0][1], s[1][1]]
	var other_class := _player(10, Vector2(1, 0), "outra_classe")
	var mixed: Array[ServerPlayer] = [killer, other_class]
	var m := PartySystem.shares(mixed, killer, Vector2.ZERO, 1000, cfg)
	var expected := roundi(1000.0 * (1.0 + float(cfg["bonus_per_member"]) + float(cfg["bonus_per_distinct_class"])) / 2.0)
	if int(m[0][1]) != expected:
		return "bônus por classes diferentes: %d, esperado %d" % [m[0][1], expected]
	var alone: Array[ServerPlayer] = [killer]
	if int(PartySystem.shares(alone, killer, Vector2(900, 0), 77, cfg)[0][1]) != 77:
		return "quem matou sempre recebe, mesmo longe"
	return ""


func test_grid_clone_is_independent() -> String:
	var g := InventoryGrid.new(4, 4)
	g.place(1, 0, 0, Vector2i(2, 2))
	var c := g.clone()
	c.place(2, 2, 0, Vector2i(2, 2))
	if g.uid_at(Vector2i(2, 0)) != 0 or c.uid_at(Vector2i(2, 0)) != 2 or c.uid_at(Vector2i(0, 0)) != 1:
		return "a cópia compartilha células com o original"
	return ""


func test_trade_fits_all() -> String:
	var cat := _catalog()
	var inv := InventoryService.new(cat)
	var p := ServerPlayer.new()
	inv.init_player(p)
	var uid := 1
	# deixa só uma coluna livre (8x8, cajados 1x4 em 7 colunas)
	for x in 7:
		for y in [0, 4]:
			inv.give(p, {"uid": uid, "base": "cajado_osso", "level": 0, "rarity": 0, "luck": false, "extra": 0, "exc": [], "container": 0, "x": 0, "y": 0, "count": 1})
			uid += 1
	var staff := {"uid": 900, "base": "vara_eclipse", "count": 1}
	var robe := {"uid": 901, "base": "manto_acolito", "count": 1}
	if not inv.fits_all(p, [staff, staff.duplicate()]):
		return "dois cajados 1x4 cabem na última coluna"
	if inv.fits_all(p, [staff, staff.duplicate(), staff.duplicate()]):
		return "três cajados não cabem"
	if inv.fits_all(p, [robe]):
		return "manto 2x3 não cabe numa coluna"
	if p.inventory.count() != 14:
		return "a simulação mexeu na mochila de verdade"
	return ""
