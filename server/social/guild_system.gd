class_name GuildSystem
extends RefCounted
## Guildas (data/guilds.json): fundação na cidade, convite, cargos (mestre, braço direito,
## oficiais, membros), expulsão, liderança, símbolo de pixels e guerra de guildas.
## Tudo fica em memória (carregado do banco ao abrir o servidor) e cada mudança é
## gravada na hora pelo repositório. Os membros são guardados pelo id do personagem,
## então a guilda existe com os membros offline.

class Guild:
	var id: int
	var name: String
	var symbol: String
	var wins: int = 0
	var members: Dictionary = {} # character_id -> {name, class_id, level, role}


class War:
	var a: int # guilda que declarou
	var b: int
	var score: Dictionary = {} # guild id -> mortes
	var goal: int
	var ends_at: float

	## Soma uma morte para a guilda; true se chegou à meta.
	func add_kill(guild_id: int) -> bool:
		score[guild_id] = int(score.get(guild_id, 0)) + 1
		return int(score[guild_id]) >= goal

	func enemy_of(guild_id: int) -> int:
		return b if guild_id == a else a

	## Guilda vencedora (0 = empate).
	func winner() -> int:
		var sa := int(score.get(a, 0))
		var sb := int(score.get(b, 0))
		return a if sa > sb else (b if sb > sa else 0)


var server: GameServer
var cfg: Dictionary
var repo: GameRepository
var guilds: Dictionary = {} # id -> Guild
var wars: Array[War] = []
var _guild_of: Dictionary = {} # character_id -> guild id
var _invites: Dictionary = {} # peer convidado -> {guild, from, until}
var _war_offers: Dictionary = {} # guild id que recebeu -> {from_guild, until}
var _state_timer: float = 0.0


func _init(game_server: GameServer, guild_table: Dictionary, repository: GameRepository) -> void:
	server = game_server
	cfg = guild_table
	repo = repository
	for g: Dictionary in repo.load_guilds():
		var guild := Guild.new()
		guild.id = int(g["id"])
		guild.name = str(g["name"])
		guild.symbol = str(g["symbol"])
		guild.wins = int(g.get("wins", 0))
		for m: Dictionary in g["members"]:
			guild.members[int(m["character_id"])] = {"name": str(m["name"]), "class_id": str(m["class_id"]),
				"level": int(m["level"]), "role": int(m["role"])}
			_guild_of[int(m["character_id"])] = guild.id
		guilds[guild.id] = guild
	if not guilds.is_empty():
		print("[guild] %d guilda(s) carregada(s)" % guilds.size())


# ---------------------------------------------------------------- consultas

func guild_of(p: ServerPlayer) -> Guild:
	return guilds.get(_guild_of.get(p.character_id, -1))


func role_of(p: ServerPlayer) -> int:
	var g := guild_of(p)
	return int(g.members[p.character_id]["role"]) if g != null else -1


func same_guild(a: ServerPlayer, b: ServerPlayer) -> bool:
	return a.character_id != 0 and _guild_of.has(a.character_id) and _guild_of.get(a.character_id) == _guild_of.get(b.character_id)


func war_of(guild_id: int) -> War:
	for w in wars:
		if w.a == guild_id or w.b == guild_id:
			return w
	return null


## As guildas dos dois estão em guerra entre si.
func at_war(a: ServerPlayer, b: ServerPlayer) -> bool:
	var ga := guild_of(a)
	var gb := guild_of(b)
	if ga == null or gb == null or ga == gb:
		return false
	var w := war_of(ga.id)
	return w != null and w.enemy_of(ga.id) == gb.id


func find_guild(guild_name: String) -> Guild:
	var key := guild_name.strip_edges().to_lower()
	for g: Guild in guilds.values():
		if g.name.to_lower() == key:
			return g
	return null


func online_members(g: Guild) -> Array[ServerPlayer]:
	var out: Array[ServerPlayer] = []
	for p: ServerPlayer in server.players.values():
		if g.members.has(p.character_id):
			out.append(p)
	return out


func _role_cfg(role: int) -> Dictionary:
	var roles: Array = cfg["roles"]
	return roles[clampi(role, 0, roles.size() - 1)]


func _role_count(g: Guild, role: int) -> int:
	var n := 0
	for m: Dictionary in g.members.values():
		if int(m["role"]) == role:
			n += 1
	return n


func _member_id_by_name(g: Guild, member_name: String) -> int:
	var key := member_name.strip_edges().to_lower()
	for cid: int in g.members:
		if str(g.members[cid]["name"]).to_lower() == key:
			return cid
	return 0


# ---------------------------------------------------------------- regras puras (testadas)

## Nome limpo (espaços simples, sem pontas) ou "" se for inválido.
static func clean_name(raw: String, name_cfg: Dictionary) -> String:
	var parts := raw.strip_edges().split(" ", false)
	var out := " ".join(parts)
	if out.length() < int(name_cfg["min_length"]) or out.length() > int(name_cfg["max_length"]):
		return ""
	for i in out.length():
		var ch := out.substr(i, 1)
		var letter := ch.to_lower() != ch.to_upper()
		var digit := ch >= "0" and ch <= "9"
		if not (letter or digit or ch == " "):
			return ""
	return out


## Símbolo válido: size² caracteres hexadecimais (índices da paleta) com min_filled pintados.
static func valid_symbol(symbol: String, symbol_cfg: Dictionary) -> bool:
	var size := int(symbol_cfg["size"])
	var colors := (symbol_cfg["palette"] as Array).size()
	if symbol.length() != size * size:
		return false
	var filled := 0
	for i in symbol.length():
		var v := "0123456789abcdef".find(symbol[i])
		if v < 0 or v >= colors:
			return false
		if v > 0:
			filled += 1
	return filled >= int(symbol_cfg["min_filled"])


## Quem tem o cargo `actor` pode expulsar quem tem o cargo `target`?
static func can_kick(actor: int, target: int, roles: Array) -> bool:
	return actor >= 0 and actor < target and bool(roles[actor].get("kick", false))


# ---------------------------------------------------------------- ações

func handle(p: ServerPlayer, action: int, target: String, extra: String) -> void:
	match action:
		Protocol.Guild.CREATE:
			create(p, target, extra)
		Protocol.Guild.INVITE:
			invite(p, target)
		Protocol.Guild.ACCEPT:
			accept(p)
		Protocol.Guild.DECLINE:
			decline(p)
		Protocol.Guild.LEAVE:
			leave(p)
		Protocol.Guild.KICK:
			kick(p, target)
		Protocol.Guild.PROMOTE:
			change_role(p, target, -1)
		Protocol.Guild.DEMOTE:
			change_role(p, target, 1)
		Protocol.Guild.TRANSFER:
			transfer(p, target)
		Protocol.Guild.DISBAND:
			disband(p)
		Protocol.Guild.WAR_DECLARE:
			declare_war(p, target)
		Protocol.Guild.WAR_ACCEPT:
			answer_war(p, true)
		Protocol.Guild.WAR_DECLINE:
			answer_war(p, false)
		Protocol.Guild.SET_SYMBOL:
			set_symbol(p, extra)


func create(p: ServerPlayer, raw_name: String, symbol: String) -> void:
	var c: Dictionary = cfg["create"]
	if guild_of(p) != null:
		server.chat.system(p.peer_id, "Você já está numa guilda.")
		return
	if p.level < int(c["min_level"]):
		server.chat.system(p.peer_id, "Só a partir do nível %d se pode fundar uma guilda." % int(c["min_level"]))
		return
	if not server.region_of(p).safe.contains(p.position):
		server.chat.system(p.peer_id, "Guildas se fundam na cidade.")
		return
	var guild_name := clean_name(raw_name, cfg["name"])
	if guild_name.is_empty():
		server.chat.system(p.peer_id, "Nome de guilda inválido: de %d a %d letras ou números." % [int(cfg["name"]["min_length"]), int(cfg["name"]["max_length"])])
		return
	symbol = symbol.to_lower()
	if not valid_symbol(symbol, cfg["symbol"]):
		server.chat.system(p.peer_id, "Desenhe o símbolo da guilda (pelo menos %d pixels)." % int(cfg["symbol"]["min_filled"]))
		return
	if p.currency < int(c["cost"]):
		server.chat.system(p.peer_id, "Fundar uma guilda custa %d Óbolos." % int(c["cost"]))
		return
	if find_guild(guild_name) != null:
		server.chat.system(p.peer_id, "Já existe uma guilda chamada %s." % guild_name)
		return
	var id := repo.create_guild(guild_name, symbol, p.character_id)
	if id == 0:
		server.chat.system(p.peer_id, "Já existe uma guilda chamada %s." % guild_name)
		return
	p.currency -= int(c["cost"])
	var g := Guild.new()
	g.id = id
	g.name = guild_name
	g.symbol = symbol
	g.members[p.character_id] = _member_record(p, 0)
	guilds[id] = g
	_guild_of[p.character_id] = id
	_invites.erase(p.peer_id)
	server.save_player(p) # a cobrança fica gravada junto com a guilda
	server.announce("Nova guilda", "%s fundou a guilda %s" % [p.char_name, guild_name])
	print("[guild] %s fundou %s (#%d)" % [p.char_name, guild_name, id])
	send_state(g)
	broadcast_tag(p)


func invite(p: ServerPlayer, target_name: String) -> void:
	var g := guild_of(p)
	if g == null:
		server.chat.system(p.peer_id, "Você não está numa guilda.")
		return
	if not bool(_role_cfg(role_of(p)).get("invite", false)):
		server.chat.system(p.peer_id, "Seu cargo não pode convidar.")
		return
	var t := server.find_player_by_name(target_name)
	if t == null:
		server.chat.system(p.peer_id, "%s não está online." % target_name.strip_edges())
		return
	if t == p:
		return
	if guild_of(t) != null:
		server.chat.system(p.peer_id, "%s já está numa guilda." % t.char_name)
		return
	if t.level < int(cfg["member_min_level"]):
		server.chat.system(p.peer_id, "%s precisa de nível %d para entrar numa guilda." % [t.char_name, int(cfg["member_min_level"])])
		return
	if g.members.size() >= int(cfg["max_members"]):
		server.chat.system(p.peer_id, "A guilda está cheia (%d)." % int(cfg["max_members"]))
		return
	_invites[t.peer_id] = {"guild": g.id, "from": p.peer_id, "until": server.now + float(cfg["invite_timeout_s"])}
	Net.send_to(t.peer_id, &"rpc_prompt", [Protocol.Prompt.GUILD_INVITE, p.char_name, g.name])
	server.chat.system(p.peer_id, "Convite da guilda enviado a %s." % t.char_name)


func accept(p: ServerPlayer) -> void:
	var inv: Dictionary = _invites.get(p.peer_id, {})
	_invites.erase(p.peer_id)
	var g: Guild = guilds.get(int(inv.get("guild", 0)))
	if inv.is_empty() or g == null or server.now > float(inv["until"]):
		server.chat.system(p.peer_id, "O convite da guilda expirou.")
		return
	if guild_of(p) != null:
		return
	if g.members.size() >= int(cfg["max_members"]):
		server.chat.system(p.peer_id, "A guilda %s está cheia." % g.name)
		return
	var last := (cfg["roles"] as Array).size() - 1
	if not repo.set_guild_member(g.id, p.character_id, last):
		server.chat.system(p.peer_id, "Não foi possível entrar na guilda agora.")
		return
	g.members[p.character_id] = _member_record(p, last)
	_guild_of[p.character_id] = g.id
	_tell(g, "%s entrou na guilda." % p.char_name)
	send_state(g)
	broadcast_tag(p)


func decline(p: ServerPlayer) -> void:
	var inv: Dictionary = _invites.get(p.peer_id, {})
	_invites.erase(p.peer_id)
	var from: ServerPlayer = server.players.get(int(inv.get("from", 0)))
	if from != null:
		server.chat.system(from.peer_id, "%s recusou o convite da guilda." % p.char_name)


func leave(p: ServerPlayer) -> void:
	var g := guild_of(p)
	if g == null:
		return
	if role_of(p) == 0:
		server.chat.system(p.peer_id, "O mestre não sai da guilda: passe a liderança ou desfaça a guilda.")
		return
	_remove_member(g, p.character_id)
	server.chat.system(p.peer_id, "Você saiu da guilda %s." % g.name)
	_tell(g, "%s saiu da guilda." % p.char_name)
	send_state(g)


func kick(p: ServerPlayer, target_name: String) -> void:
	var g := guild_of(p)
	if g == null:
		return
	var cid := _member_id_by_name(g, target_name)
	if cid == 0:
		server.chat.system(p.peer_id, "%s não é da sua guilda." % target_name.strip_edges())
		return
	if not can_kick(role_of(p), int(g.members[cid]["role"]), cfg["roles"]):
		server.chat.system(p.peer_id, "Você não pode expulsar %s." % g.members[cid]["name"])
		return
	var kicked_name := str(g.members[cid]["name"])
	_remove_member(g, cid)
	for t: ServerPlayer in server.players.values():
		if t.character_id == cid:
			server.chat.system(t.peer_id, "Você foi expulso da guilda %s." % g.name)
	_tell(g, "%s foi expulso da guilda." % kicked_name)
	send_state(g)


## delta -1 = promover (cargo mais alto), +1 = rebaixar. Só o mestre; ninguém vira mestre assim.
func change_role(p: ServerPlayer, target_name: String, delta: int) -> void:
	var g := guild_of(p)
	if g == null or role_of(p) != 0:
		server.chat.system(p.peer_id, "Só o mestre muda cargos.")
		return
	var cid := _member_id_by_name(g, target_name)
	if cid == 0 or cid == p.character_id:
		server.chat.system(p.peer_id, "%s não é da sua guilda." % target_name.strip_edges())
		return
	var roles: Array = cfg["roles"]
	var role := int(g.members[cid]["role"]) + delta
	if role < 1 or role >= roles.size():
		server.chat.system(p.peer_id, "%s já está no cargo %s." % [g.members[cid]["name"], "mais alto" if delta < 0 else "mais baixo"])
		return
	var limit := int(roles[role]["max"])
	if limit > 0 and _role_count(g, role) >= limit:
		server.chat.system(p.peer_id, "A guilda já tem %d %s." % [limit, roles[role]["name"]])
		return
	_set_role(g, cid, role)
	_tell(g, "%s agora é %s." % [g.members[cid]["name"], roles[role]["name"]])
	send_state(g)


## O mestre passa a liderança: os dois trocam de cargo.
func transfer(p: ServerPlayer, target_name: String) -> void:
	var g := guild_of(p)
	if g == null or role_of(p) != 0:
		server.chat.system(p.peer_id, "Só o mestre passa a liderança.")
		return
	var cid := _member_id_by_name(g, target_name)
	if cid == 0 or cid == p.character_id:
		server.chat.system(p.peer_id, "%s não é da sua guilda." % target_name.strip_edges())
		return
	var old_role := int(g.members[cid]["role"])
	_set_role(g, cid, 0)
	_set_role(g, p.character_id, old_role)
	_tell(g, "%s é o novo mestre da guilda." % g.members[cid]["name"])
	send_state(g)


func disband(p: ServerPlayer) -> void:
	var g := guild_of(p)
	if g == null or role_of(p) != 0:
		server.chat.system(p.peer_id, "Só o mestre desfaz a guilda.")
		return
	if war_of(g.id) != null:
		server.chat.system(p.peer_id, "A guilda está em guerra: termine a guerra antes.")
		return
	if not repo.delete_guild(g.id):
		return
	var online := online_members(g)
	for cid: int in g.members:
		_guild_of.erase(cid)
	guilds.erase(g.id)
	_war_offers.erase(g.id)
	for t in online:
		server.chat.system(t.peer_id, "A guilda %s foi desfeita." % g.name)
		Net.send_to(t.peer_id, &"rpc_guild_state", [{}])
		broadcast_tag(t)
	server.castle.on_guild_disbanded(g.id)
	print("[guild] %s desfez %s" % [p.char_name, g.name])


func set_symbol(p: ServerPlayer, symbol: String) -> void:
	var g := guild_of(p)
	symbol = symbol.to_lower()
	if g == null or role_of(p) != 0:
		server.chat.system(p.peer_id, "Só o mestre muda o símbolo.")
		return
	if not valid_symbol(symbol, cfg["symbol"]) or not repo.set_guild_symbol(g.id, symbol):
		server.chat.system(p.peer_id, "Símbolo inválido.")
		return
	g.symbol = symbol
	_tell(g, "O símbolo da guilda mudou.")
	send_state(g)
	for t in online_members(g):
		broadcast_tag(t)


# ---------------------------------------------------------------- guerra

func declare_war(p: ServerPlayer, target_guild: String) -> void:
	var g := guild_of(p)
	if g == null or not bool(_role_cfg(role_of(p)).get("war", false)):
		server.chat.system(p.peer_id, "Seu cargo não pode declarar guerra.")
		return
	var other := find_guild(target_guild)
	if other == null or other == g:
		server.chat.system(p.peer_id, "Guilda %s não encontrada." % target_guild.strip_edges())
		return
	if war_of(g.id) != null:
		server.chat.system(p.peer_id, "Sua guilda já está em guerra.")
		return
	if war_of(other.id) != null:
		server.chat.system(p.peer_id, "%s já está em guerra." % other.name)
		return
	var deciders: Array[ServerPlayer] = []
	for t in online_members(other):
		if bool(_role_cfg(int(other.members[t.character_id]["role"])).get("war", false)):
			deciders.append(t)
	if deciders.is_empty():
		server.chat.system(p.peer_id, "Ninguém de %s que possa aceitar uma guerra está online." % other.name)
		return
	_war_offers[other.id] = {"from_guild": g.id, "until": server.now + float(cfg["war"]["offer_timeout_s"])}
	for t in deciders:
		Net.send_to(t.peer_id, &"rpc_prompt", [Protocol.Prompt.GUILD_WAR, p.char_name, g.name])
	_tell(g, "%s declarou guerra a %s. Esperando a resposta." % [p.char_name, other.name])


func answer_war(p: ServerPlayer, yes: bool) -> void:
	var g := guild_of(p)
	if g == null or not _war_offers.has(g.id):
		return
	if not bool(_role_cfg(role_of(p)).get("war", false)):
		return
	var offer: Dictionary = _war_offers[g.id]
	_war_offers.erase(g.id)
	var other: Guild = guilds.get(int(offer["from_guild"]))
	if other == null or server.now > float(offer["until"]):
		server.chat.system(p.peer_id, "A declaração de guerra expirou.")
		return
	if not yes:
		_tell(other, "%s recusou a guerra." % g.name)
		_tell(g, "%s recusou a guerra contra %s." % [p.char_name, other.name])
		return
	if war_of(g.id) != null or war_of(other.id) != null:
		server.chat.system(p.peer_id, "Uma das guildas já está em guerra.")
		return
	var w := War.new()
	w.a = other.id
	w.b = g.id
	w.goal = int(cfg["war"]["kill_goal"])
	w.ends_at = server.now + float(cfg["war"]["duration_s"])
	wars.append(w)
	server.announce("Guerra de guildas!", "%s × %s — vence quem derrubar %d primeiro" % [other.name, g.name, w.goal])
	print("[guild] guerra: %s x %s" % [other.name, g.name])
	send_state(g)
	send_state(other)
	for t: ServerPlayer in online_members(g) + online_members(other):
		broadcast_tag(t) # a cor do nome muda para os inimigos


## Morte de PvP entre guildas em guerra: conta no placar (sem infâmia; ver PvpSystem.on_kill).
func war_kill(killer: ServerPlayer, victim: ServerPlayer) -> void:
	var gk := guild_of(killer)
	var w := war_of(gk.id) if gk != null else null
	if w == null:
		return
	var reached := w.add_kill(gk.id)
	var gv: Guild = guilds.get(w.enemy_of(gk.id))
	var line := "%s derrubou %s: %s %d × %d %s" % [killer.char_name, victim.char_name, gk.name,
		int(w.score.get(gk.id, 0)), int(w.score.get(gv.id, 0)), gv.name]
	_tell(gk, line)
	_tell(gv, line)
	if reached:
		end_war(w)
	else:
		send_state(gk)
		send_state(gv)


func end_war(w: War) -> void:
	wars.erase(w)
	var ga: Guild = guilds.get(w.a)
	var gb: Guild = guilds.get(w.b)
	if ga == null or gb == null:
		return
	var win := w.winner()
	var result := "%s %d × %d %s" % [ga.name, int(w.score.get(ga.id, 0)), int(w.score.get(gb.id, 0)), gb.name]
	if win == 0:
		server.announce("A guerra terminou empatada", result)
	else:
		var gw: Guild = guilds[win]
		gw.wins += 1
		repo.add_guild_win(gw.id)
		server.announce("%s venceu a guerra!" % gw.name, result)
	print("[guild] fim da guerra: %s" % result)
	send_state(ga)
	send_state(gb)
	for t: ServerPlayer in online_members(ga) + online_members(gb):
		broadcast_tag(t)


## Debug (GM): faz a guerra da guilda do jogador acabar em `seconds`.
func gm_end_war_in(p: ServerPlayer, seconds: float) -> void:
	var g := guild_of(p)
	var w := war_of(g.id) if g != null else null
	if w != null:
		w.ends_at = server.now + seconds


# ---------------------------------------------------------------- mundo

func on_enter(p: ServerPlayer) -> void:
	var g := guild_of(p)
	if g != null:
		g.members[p.character_id]["level"] = p.level
		_tell(g, "%s entrou no jogo." % p.char_name, p)
		send_state(g)
	else:
		Net.send_to(p.peer_id, &"rpc_guild_state", [{}])
	broadcast_tag(p)
	for other: ServerPlayer in server.players.values():
		if other != p:
			var og := guild_of(other)
			if og != null:
				Net.send_to(p.peer_id, &"rpc_player_guild", [other.id, og.name, og.symbol])


## Chamado depois que o jogador já saiu de server.players.
func on_leave(p: ServerPlayer) -> void:
	_invites.erase(p.peer_id)
	var g := guild_of(p)
	if g != null:
		g.members[p.character_id]["level"] = p.level
		_tell(g, "%s saiu do jogo." % p.char_name)
		send_state(g)


func update(dt: float) -> void:
	for w: War in wars.duplicate():
		if server.now >= w.ends_at:
			end_war(w)
	_state_timer += dt
	if _state_timer < float(cfg["state_interval_s"]):
		return
	_state_timer = 0.0
	for g: Guild in guilds.values():
		if not online_members(g).is_empty():
			send_state(g)


## Estado da guilda para cada membro online (cada um recebe o próprio cargo).
func send_state(g: Guild) -> void:
	var online := {}
	for t in online_members(g):
		online[t.character_id] = t
		g.members[t.character_id]["level"] = t.level
	var list: Array = []
	var ids := g.members.keys()
	ids.sort_custom(func(x: int, y: int) -> bool:
		var rx := int(g.members[x]["role"])
		var ry := int(g.members[y]["role"])
		return rx < ry if rx != ry else str(g.members[x]["name"]) < str(g.members[y]["name"]))
	for cid: int in ids:
		var m: Dictionary = g.members[cid]
		var t: ServerPlayer = online.get(cid)
		list.append([m["name"], int(m["role"]), int(m["level"]), m["class_id"], t != null, t.region_id if t != null else ""])
	var war := {}
	var w := war_of(g.id)
	if w != null:
		var enemy: Guild = guilds.get(w.enemy_of(g.id))
		war = {"enemy": enemy.name, "enemy_symbol": enemy.symbol, "mine": int(w.score.get(g.id, 0)),
			"theirs": int(w.score.get(enemy.id, 0)), "goal": w.goal, "left_s": maxi(0, ceili(w.ends_at - server.now))}
	for cid: int in online:
		var t: ServerPlayer = online[cid]
		Net.send_to(t.peer_id, &"rpc_guild_state", [{"name": g.name, "symbol": g.symbol, "role": int(g.members[cid]["role"]),
			"wins": g.wins, "max_members": int(cfg["max_members"]), "members": list, "war": war}])


## Guilda do jogador para todos (nome e símbolo sobre a cabeça).
func broadcast_tag(p: ServerPlayer) -> void:
	var g := guild_of(p)
	Net.broadcast(server.peers(), &"rpc_player_guild", [p.id, g.name if g != null else "", g.symbol if g != null else ""])


func _member_record(p: ServerPlayer, role: int) -> Dictionary:
	return {"name": p.char_name, "class_id": p.class_id, "level": p.level, "role": role}


func _set_role(g: Guild, cid: int, role: int) -> void:
	g.members[cid]["role"] = role
	repo.set_guild_member(g.id, cid, role)


func _remove_member(g: Guild, cid: int) -> void:
	repo.remove_guild_member(cid)
	g.members.erase(cid)
	_guild_of.erase(cid)
	for t: ServerPlayer in server.players.values():
		if t.character_id == cid:
			Net.send_to(t.peer_id, &"rpc_guild_state", [{}])
			broadcast_tag(t)


## Mensagem do sistema para os membros online (menos `except`).
func _tell(g: Guild, text: String, except: ServerPlayer = null) -> void:
	for t in online_members(g):
		if t != except:
			server.chat.system(t.peer_id, text)
