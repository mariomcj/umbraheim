class_name PvpSystem
extends RefCounted
## PvP com consequências (data/pvp.json): quem pode atacar quem, autodefesa,
## infâmia (Fora da Lei em níveis), pontos de herói, penalidades ao morrer e o
## decaimento da infâmia com tempo online e monstros mortos.

var server: GameServer
var cfg: Dictionary
var _timer: float = 0.0


func _init(game_server: GameServer, pvp_table: Dictionary) -> void:
	server = game_server
	cfg = pvp_table


## 0 = cidadão; 1..n = nível de Fora da Lei (índice em outlaw_levels + 1).
func outlaw_level(p: ServerPlayer) -> int:
	return level_for(p.infamy, cfg["outlaw_levels"], "infamy")


func hero_level(p: ServerPlayer) -> int:
	return level_for(p.hero, cfg["hero_levels"], "points")


static func level_for(value: int, levels: Array, key: String) -> int:
	var out := 0
	for i in levels.size():
		if value >= int(levels[i][key]):
			out = i + 1
	return out


func outlaw_info(p: ServerPlayer) -> Dictionary:
	var lv := outlaw_level(p)
	return cfg["outlaw_levels"][lv - 1] if lv > 0 else {}


## "" se pode atacar; senão o motivo.
func can_attack(attacker: ServerPlayer, target: ServerPlayer) -> String:
	if target == null or not target.alive:
		return "Alvo inválido."
	if target == attacker:
		return "Você não pode se atacar."
	if attacker.region_id != target.region_id:
		return "Alvo inválido."
	var min_level := int(cfg["min_level"])
	if attacker.level < min_level:
		return "Só a partir do nível %d se pode atacar outros jogadores." % min_level
	if target.level < min_level:
		return "%s ainda é protegido (nível abaixo de %d)." % [target.char_name, min_level]
	var rule: Variant = server.region_of(attacker).data.get("pvp", true)
	if rule is bool and not rule:
		return "Aqui não se luta entre jogadores."
	var safe := server.region_of(attacker).safe
	if safe.contains(attacker.position) or safe.contains(target.position):
		return "Não se luta numa zona segura."
	if str(rule) == "guild" and server.guilds.same_guild(attacker, target):
		return "Vocês são da mesma guilda."
	if free_pvp(attacker):
		return "" # todos contra todos (Círculo, cerco): grupo não protege
	if server.party.same_group(attacker.peer_id, target.peer_id):
		return "Vocês estão no mesmo grupo."
	if server.guilds.same_guild(attacker, target):
		return "Vocês são da mesma guilda."
	return ""


## Atacar é justificado se o alvo é Fora da Lei, se o alvo atacou primeiro (autodefesa)
## ou se as guildas dos dois estão em guerra.
func justified(attacker: ServerPlayer, target: ServerPlayer) -> bool:
	if free_pvp(attacker):
		return true
	return outlaw_level(target) > 0 or float(attacker.self_defense.get(target.id, 0.0)) > server.now 		or server.guilds.at_war(attacker, target)


## Golpe de jogador em jogador: a vítima ganha autodefesa contra um agressor sem motivo.
func on_hit(attacker: ServerPlayer, target: ServerPlayer) -> void:
	if justified(attacker, target):
		return
	var first := float(target.self_defense.get(attacker.id, 0.0)) <= server.now
	target.self_defense[attacker.id] = server.now + float(cfg["self_defense_s"])
	if first:
		server.send_message(target.peer_id, "%s atacou você! Você pode revidar sem penalidade por %d s." % [attacker.char_name, int(cfg["self_defense_s"])])


## Região de PvP livre (pvp: "free", ou "guild" = livre menos a própria guilda): sem infâmia, herói nem penalidade.
func free_pvp(p: ServerPlayer) -> bool:
	return str(server.region_of(p).data.get("pvp", "")) in ["free", "guild"]


func on_kill(killer: ServerPlayer, victim: ServerPlayer) -> void:
	if free_pvp(victim):
		server.events.on_pvp_kill(killer, victim)
		print("[pvp] %s derrubou %s (PvP livre)" % [killer.char_name, victim.char_name])
		return
	var was_justified := justified(killer, victim)
	var victim_outlaw := outlaw_level(victim)
	if server.guilds.at_war(killer, victim):
		server.guilds.war_kill(killer, victim) # guerra de guildas: conta no placar, sem infâmia nem herói
	elif victim_outlaw > 0 and outlaw_level(killer) == 0:
		var before := hero_level(killer)
		killer.hero += 1
		server.send_message(killer.peer_id, "Você derrubou um Fora da Lei. Pontos de herói: %d." % killer.hero)
		if hero_level(killer) > before:
			server.announce("Um novo herói", "%s agora é %s" % [killer.char_name, cfg["hero_levels"][hero_level(killer) - 1]["name"]])
	elif not was_justified:
		var before_lv := outlaw_level(killer)
		killer.infamy += 1
		killer.infamy_decay = 0.0
		var info := outlaw_info(killer)
		server.send_message(killer.peer_id, "Você matou %s sem motivo. Agora você é %s (infâmia %d)." % [victim.char_name, info.get("name", "?"), killer.infamy])
		if outlaw_level(killer) > before_lv:
			server.announce("Fora da Lei!", "%s agora é %s" % [killer.char_name, info["name"]])
	print("[pvp] %s matou %s (justificado %s, infâmia %d, herói %d)" % [killer.char_name, victim.char_name, was_justified, killer.infamy, killer.hero])
	killer.self_defense.erase(victim.id)
	victim.self_defense.clear()
	if victim_outlaw > 0:
		_death_penalty(victim)
	broadcast_tag(killer)
	broadcast_tag(victim)


## Fora da Lei que morre perde XP e pode deixar cair um item (o carmesim, até equipado).
func _death_penalty(p: ServerPlayer) -> void:
	var info := outlaw_info(p)
	if info.is_empty():
		return
	var loss := roundi(server.xp_to_next(p.level) * float(info["xp_loss_pct"]))
	if loss > 0:
		p.xp = maxi(0, p.xp - loss)
		server.send_message(p.peer_id, "Sua infâmia cobrou %d de XP." % loss)
	if server.rng.randf() >= float(info["item_drop_chance"]):
		return
	var candidates: Array = []
	for item: Dictionary in p.items.values():
		var c := int(item["container"])
		if c == ItemCatalog.CONTAINER_INVENTORY or (bool(info["drop_equipped"]) and c >= 1 and c <= ItemCatalog.EQUIP_SLOTS.size()):
			candidates.append(item)
	if candidates.is_empty():
		return
	var item: Dictionary = candidates[server.rng.randi() % candidates.size()]
	var before := server.inventory.appearance(p)
	server.inventory.take(p, int(item["uid"]))
	server.region_of(p).drops.spawn_item(item, p.position, 0, float(cfg["dropped_item_owner_s"]))
	server.send_message(p.peer_id, "Na queda, você deixou cair %s." % server.catalog.display_name(item))
	server.recompute(p)
	server.send_inventory(p)
	if server.inventory.appearance(p) != before:
		server.broadcast_appearance(p)


func shop_refuses(p: ServerPlayer) -> bool:
	return bool(outlaw_info(p).get("shops_refuse", false))


func on_monster_kill(p: ServerPlayer) -> void:
	if p.infamy > 0:
		_add_decay(p, float(cfg["decay_online_s"]) / maxf(1.0, float(cfg["decay_monster_kills"])))


## A cada segundo: infâmia cai com o tempo online; autodefesas vencidas somem.
func update(dt: float) -> void:
	_timer += dt
	if _timer < 1.0:
		return
	var step := _timer
	_timer = 0.0
	for p: ServerPlayer in server.players.values():
		if p.infamy > 0:
			_add_decay(p, step)
		for attacker_id: int in p.self_defense.keys():
			if float(p.self_defense[attacker_id]) <= server.now:
				p.self_defense.erase(attacker_id)


func _add_decay(p: ServerPlayer, amount: float) -> void:
	p.infamy_decay += amount
	while p.infamy > 0 and p.infamy_decay >= float(cfg["decay_online_s"]):
		p.infamy_decay -= float(cfg["decay_online_s"])
		p.infamy -= 1
		server.send_message(p.peer_id, "Sua infâmia diminuiu (%d)." % p.infamy if p.infamy > 0 else "Você não é mais um Fora da Lei.")
		broadcast_tag(p)


## Status de um jogador para todos: [nível de Fora da Lei, nível de herói].
func broadcast_tag(p: ServerPlayer) -> void:
	Net.broadcast(server.peers(), &"rpc_player_tag", [p.id, outlaw_level(p), hero_level(p)])


func send_tags_to(peer_id: int) -> void:
	for p: ServerPlayer in server.players.values():
		Net.send_to(peer_id, &"rpc_player_tag", [p.id, outlaw_level(p), hero_level(p)])
