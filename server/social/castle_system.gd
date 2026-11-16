class_name CastleSystem
extends RefCounted
## O Castelo das Brasas (data/castle.json): a guilda dona, o imposto que ela cobra nas
## lojas, o tesouro e as guildas inscritas no próximo cerco. Tudo gravado no banco a cada
## mudança. O cerco em si é um evento (SiegeEvent); no fim, ele chama set_owner().

var server: GameServer
var cfg: Dictionary
var repo: GameRepository
var owner_guild: int = 0
var tax_pct: float = 0.0
var treasury: int = 0
var registered: Array = [] # ids das guildas inscritas
var since: int = 0


func _init(game_server: GameServer, castle_table: Dictionary, repository: GameRepository) -> void:
	server = game_server
	cfg = castle_table
	repo = repository
	var rec := repo.load_castle(str(cfg["id"]))
	if not rec.is_empty():
		owner_guild = int(rec["guild_id"])
		tax_pct = float(rec["tax_pct"])
		treasury = int(rec["treasury"])
		registered = rec["registered"]
		since = int(rec["since"])


func _save() -> void:
	repo.save_castle({"id": str(cfg["id"]), "guild_id": owner_guild, "tax_pct": tax_pct, "treasury": treasury,
		"registered": registered, "since": since})


func owner() -> GuildSystem.Guild:
	return server.guilds.guilds.get(owner_guild)


# ---------------------------------------------------------------- regras puras (testadas)

## Imposto sobre uma compra (arredondado para cima: a menor compra com imposto paga 1).
static func tax_on(total: int, pct: float) -> int:
	return ceili(total * pct) if pct > 0.0 else 0


# ---------------------------------------------------------------- impostos

## Compra numa loja: devolve o imposto a cobrar e já o soma no tesouro.
func collect(total: int) -> int:
	if owner_guild == 0:
		return 0
	var t := tax_on(total, tax_pct)
	if t > 0:
		treasury += t
		_save()
	return t


func current_tax() -> float:
	return tax_pct if owner_guild != 0 else 0.0


# ---------------------------------------------------------------- ações (Arauto do Cerco)

func handle(p: ServerPlayer, action: int, value: int) -> void:
	if not server.region_of(p).npcs.is_open(p, "siege"):
		server.send_message(p.peer_id, "Fale com o Arauto do Cerco, no Refúgio.")
		return
	match action:
		Protocol.Castle.REGISTER:
			_register(p)
		Protocol.Castle.ENTER:
			var why := can_enter(p)
			if why == "":
				why = server.events.try_enter(p, "cerco", true)
			if why != "":
				server.send_message(p.peer_id, why)
		Protocol.Castle.SET_TAX:
			_set_tax(p, value)
		Protocol.Castle.WITHDRAW:
			_withdraw(p)
	send_state(p)


func _register(p: ServerPlayer) -> void:
	var g := server.guilds.guild_of(p)
	if g == null or server.guilds.role_of(p) != 0:
		server.send_message(p.peer_id, "Só o mestre de uma guilda inscreve a guilda no cerco.")
		return
	if g.id == owner_guild:
		server.send_message(p.peer_id, "Sua guilda é a dona do castelo: ela defende sem se inscrever.")
		return
	if g.id in registered:
		server.send_message(p.peer_id, "%s já está inscrita." % g.name)
		return
	if server.events.runs["cerco"].state != EventSystem.State.IDLE:
		server.send_message(p.peer_id, "As inscrições fecham quando os portões do cerco abrem.")
		return
	if g.members.size() < int(cfg["min_members"]):
		server.send_message(p.peer_id, "A guilda precisa de pelo menos %d membros." % int(cfg["min_members"]))
		return
	var fee := int(cfg["register_fee"])
	if p.currency < fee:
		server.send_message(p.peer_id, "A inscrição custa %d Óbolos." % fee)
		return
	p.currency -= fee
	registered.append(g.id)
	_save()
	server.announce("Cerco ao Castelo", "%s se inscreveu para o próximo cerco" % g.name)
	broadcast_state()


## "" se o jogador pode entrar no cerco (guilda inscrita ou dona).
func can_enter(p: ServerPlayer) -> String:
	var g := server.guilds.guild_of(p)
	if g == null:
		return "Só guildas lutam no cerco."
	if g.id != owner_guild and not g.id in registered:
		return "%s não está inscrita neste cerco." % g.name
	return ""


func _set_tax(p: ServerPlayer, permille: int) -> void:
	if not _is_owner_master(p):
		server.send_message(p.peer_id, "Só o mestre da guilda dona do castelo define o imposto.")
		return
	tax_pct = clampf(permille / 1000.0, 0.0, float(cfg["tax_max_pct"]))
	_save()
	server.announce(str(cfg["name"]), "%s fixou o imposto das lojas em %d%%" % [owner().name, roundi(tax_pct * 100.0)])
	broadcast_state()


func _withdraw(p: ServerPlayer) -> void:
	if not _is_owner_master(p):
		server.send_message(p.peer_id, "Só o mestre da guilda dona do castelo saca o tesouro.")
		return
	if treasury <= 0:
		server.send_message(p.peer_id, "O tesouro está vazio.")
		return
	p.currency += treasury
	server.send_message(p.peer_id, "Você sacou %d Óbolos do tesouro do castelo." % treasury)
	print("[castelo] %s sacou %d do tesouro" % [p.char_name, treasury])
	treasury = 0
	_save()
	server.save_player(p)


func _is_owner_master(p: ServerPlayer) -> bool:
	var g := server.guilds.guild_of(p)
	return g != null and g.id == owner_guild and server.guilds.role_of(p) == 0


# ---------------------------------------------------------------- fim do cerco e guildas

## O cerco terminou: `guild_id` fica com o castelo (0 = ninguém). Inscrições zeram.
func set_owner(guild_id: int) -> void:
	if guild_id != owner_guild:
		owner_guild = guild_id
		since = int(Time.get_unix_time_from_system())
		tax_pct = float(cfg["tax_default_pct"]) if guild_id != 0 else 0.0
		treasury = 0
	registered.clear()
	_save()
	broadcast_state()


func on_guild_disbanded(guild_id: int) -> void:
	registered.erase(guild_id)
	if guild_id == owner_guild:
		owner_guild = 0
		tax_pct = 0.0
		treasury = 0
	_save()
	broadcast_state()


# ---------------------------------------------------------------- estado para o cliente

func state_for(p: ServerPlayer) -> Dictionary:
	var g := owner()
	var mine := server.guilds.guild_of(p)
	var names := PackedStringArray()
	for gid: int in registered:
		var rg: GuildSystem.Guild = server.guilds.guilds.get(gid)
		if rg != null:
			names.append(rg.name)
	return {
		"name": str(cfg["name"]),
		"owner": g.name if g != null else "",
		"owner_symbol": g.symbol if g != null else "",
		"tax_pct": current_tax(),
		"tax_max_pct": float(cfg["tax_max_pct"]),
		"treasury": treasury if _is_owner_master(p) else -1,
		"registered": names,
		"fee": int(cfg["register_fee"]),
		"my_guild": mine.name if mine != null else "",
		"my_role": server.guilds.role_of(p),
		"mine_in": mine != null and (mine.id == owner_guild or mine.id in registered),
		"is_owner": mine != null and mine.id == owner_guild,
	}


func send_state(p: ServerPlayer) -> void:
	Net.send_to(p.peer_id, &"rpc_castle_state", [state_for(p)])


func broadcast_state() -> void:
	for p: ServerPlayer in server.players.values():
		send_state(p)
