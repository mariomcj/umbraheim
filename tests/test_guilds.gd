extends RefCounted
## Fase 5, parte 2: regras de guilda (nome, símbolo, cargos, placar da guerra) e o
## repositório de guildas e amigos (SQLite em memória).


func _cfg() -> Dictionary:
	return ConfigLoader.load_json("res://data/guilds.json")


func test_guild_names() -> String:
	var name_cfg: Dictionary = _cfg()["name"]
	var cases := {
		"  Corvos   da Cinza ": "Corvos da Cinza",
		"Lobos do Véu": "Lobos do Véu",
		"Ordem 13": "Ordem 13",
		"x!": "",
		"ab": "",
		"Nome<script>": "",
		"Um nome comprido demais aqui": "",
		"Ação": "Ação",
	}
	for raw: String in cases:
		var got := GuildSystem.clean_name(raw, name_cfg)
		if got != cases[raw]:
			return "'%s' deveria virar '%s', veio '%s'" % [raw, cases[raw], got]
	return ""


func test_guild_symbols() -> String:
	var sym_cfg: Dictionary = _cfg()["symbol"]
	var n := int(sym_cfg["size"])
	var good := "6".repeat(int(sym_cfg["min_filled"])) + "0".repeat(n * n - int(sym_cfg["min_filled"]))
	if not GuildSystem.valid_symbol(good, sym_cfg):
		return "símbolo mínimo válido recusado"
	if GuildSystem.valid_symbol("0".repeat(n * n), sym_cfg):
		return "símbolo vazio aceito"
	if GuildSystem.valid_symbol(good.left(n * n - 1), sym_cfg):
		return "tamanho errado aceito"
	if GuildSystem.valid_symbol(good.left(n * n - 1) + "z", sym_cfg) or GuildSystem.valid_symbol(good.to_upper().replace("6", "G"), sym_cfg):
		return "caractere fora da paleta aceito"
	if (sym_cfg["palette"] as Array).size() > 16:
		return "a paleta precisa caber num dígito hexadecimal"
	return ""


func test_guild_roles() -> String:
	var roles: Array = _cfg()["roles"]
	if int(roles[0]["max"]) != 1:
		return "deve haver um só mestre"
	if not GuildSystem.can_kick(0, 3, roles) or not GuildSystem.can_kick(1, 2, roles):
		return "mestre e braço direito expulsam cargos abaixo"
	if GuildSystem.can_kick(1, 1, roles) or GuildSystem.can_kick(2, 0, roles) or GuildSystem.can_kick(2, 3, roles):
		return "ninguém expulsa o mesmo cargo, um cargo acima, nem sem permissão"
	return ""


func test_war_score() -> String:
	var w := GuildSystem.War.new()
	w.a = 1
	w.b = 2
	w.goal = 3
	if w.winner() != 0:
		return "0 × 0 é empate"
	w.add_kill(2)
	w.add_kill(1)
	if w.add_kill(1) or w.winner() != 1:
		return "2 × 1: ainda não chegou à meta e a guilda 1 vence"
	if not w.add_kill(1):
		return "a terceira morte chega à meta"
	if w.enemy_of(1) != 2 or w.enemy_of(2) != 1:
		return "inimigo errado"
	return ""


func test_guild_and_friend_repository() -> String:
	if not SqliteRepository.available():
		return "extensão godot-sqlite não carregada"
	var repo := SqliteRepository.new(":memory:")
	if not repo.open():
		return "não abriu o banco"
	var acc := repo.create_account("conta_demo", "00", "00", 1)
	var ids: Array[int] = []
	for n in ["Ysolde", "Hálvor", "Mirta"]:
		ids.append(repo.create_character(acc, {"name": n, "class_id": "feiticeiro", "level": 20, "xp": 0, "points": 0,
			"stats": {"str": 18, "agi": 18, "vit": 15, "ene": 30}, "currency": 0, "hp": 10.0, "mana": 5.0,
			"region_id": "ruinas", "pos": [0.0, 0.0], "learned_spells": 15, "items": [], "journals": {}}))
	var sym := "6".repeat(64)
	var gid := repo.create_guild("Corvos da Cinza", sym, ids[0])
	if gid == 0 or repo.create_guild("CORVOS DA CINZA", sym, ids[1]) != 0 or not repo.guild_name_taken("corvos da cinza"):
		return "criação (ou nome repetido aceito)"
	if not repo.set_guild_member(gid, ids[1], 3) or not repo.set_guild_member(gid, ids[1], 2):
		return "entrar / mudar de cargo"
	repo.set_guild_symbol(gid, "b".repeat(64))
	repo.add_guild_win(gid)
	var gs := repo.load_guilds()
	if gs.size() != 1 or (gs[0]["members"] as Array).size() != 2 or str(gs[0]["symbol"]) != "b".repeat(64) or int(gs[0]["wins"]) != 1:
		return "guilda não voltou igual: %s" % [gs]
	var roles := {}
	for m: Dictionary in gs[0]["members"]:
		roles[str(m["name"])] = int(m["role"])
	if roles.get("Ysolde", -1) != 0 or roles.get("Hálvor", -1) != 2:
		return "cargos errados: %s" % roles
	# o servidor, ao abrir, recarrega as guildas do banco (membros offline incluídos)
	var system := GuildSystem.new(null, _cfg(), repo)
	var p := ServerPlayer.new()
	p.character_id = ids[1]
	var q := ServerPlayer.new()
	q.character_id = ids[0]
	if system.find_guild("corvos da cinza") == null or system.guild_of(p) == null or system.role_of(p) != 2 or not system.same_guild(p, q):
		return "GuildSystem não recarregou a guilda do banco"
	repo.remove_guild_member(ids[1])
	if (repo.load_guilds()[0]["members"] as Array).size() != 1:
		return "saída não gravou"
	# amigos: mútuo, sem duplicar
	if not repo.add_friendship(ids[0], ids[2]) or not repo.add_friendship(ids[2], ids[0]):
		return "amizade"
	if repo.list_friends(ids[0]).size() != 1 or str(repo.list_friends(ids[2])[0]["name"]) != "Ysolde":
		return "lista de amigos: %s / %s" % [repo.list_friends(ids[0]), repo.list_friends(ids[2])]
	repo.remove_friendship(ids[2], ids[0])
	if not repo.list_friends(ids[0]).is_empty() or not repo.list_friends(ids[2]).is_empty():
		return "remover tira dos dois lados"
	if not repo.delete_guild(gid) or not repo.load_guilds().is_empty() or repo.guild_name_taken("Corvos da Cinza"):
		return "desfazer a guilda"
	repo.close()
	return ""
