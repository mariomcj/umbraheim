class_name DropSystem
extends RefCounted
## Drops no chão: sorteio pela tabela do monstro, posse temporária de quem matou,
## expiração e coleta (validada pelo alcance e pelo espaço no inventário, no servidor).
## Um drop é moeda ({kind:"currency", amount}) ou um item de verdade ({kind:"item", item}).

var server: GameServer
var region: RegionInstance
var cfg: Dictionary
var drops: Dictionary = {} # id -> Dictionary


func _init(game_server: GameServer, region_instance: RegionInstance, drop_table: Dictionary) -> void:
	server = game_server
	region = region_instance
	cfg = drop_table


## Sorteia os drops do monstro (drop_rolls vezes: chefes e dourados soltam vários).
func roll_for(m: ServerMonster, owner_peer: int) -> void:
	var rolls := maxi(1, int(m.def.get("drop_rolls", 1)))
	var spread := 1.0 + 0.35 * (rolls - 1) # vários itens se espalham mais
	for i in rolls:
		_roll_once(m, owner_peer, spread)


func _roll_once(m: ServerMonster, owner_peer: int, spread: float) -> void:
	var table: Dictionary = cfg["tables"].get(str(m.def["drop_table"]), {})
	if table.is_empty() or server.rng.randf() > float(table["drop_chance"]):
		return
	var entry := _weighted(table["entries"])
	if entry.is_empty():
		return
	var scatter := float(cfg["scatter_m"]) * spread
	var pos := region.grid.nearest_walkable_point(m.position + Vector2(server.rng.randf_range(-scatter, scatter), server.rng.randf_range(-scatter, scatter)))
	if str(entry["type"]) == "currency":
		var amount := server.rng.randi_range(int(entry["min"]), int(entry["max"]))
		_spawn({"kind": "currency", "amount": amount, "rarity": Protocol.RARITY_CURRENCY,
			"label": "%d %s" % [amount, cfg["currency_name"]]}, pos, owner_peer, float(cfg["owner_s"]))
	else:
		var item := server.factory.create_rolled(_pick(entry["pool"]))
		spawn_item(item, pos, owner_peer, float(cfg["owner_s"]))


## Item no chão (drop de monstro ou jogado pelo jogador).
func spawn_item(item: Dictionary, pos: Vector2, owner_peer: int, owner_s: float = 0.0) -> void:
	if item.is_empty():
		return
	_spawn({"kind": "item", "item": item, "rarity": _display_rarity(item),
		"label": server.catalog.display_name(item)}, pos, owner_peer, owner_s)


func _spawn(drop: Dictionary, pos: Vector2, owner_peer: int, owner_s: float) -> void:
	drop["id"] = server.next_drop_id()
	drop["pos"] = pos
	drop["owner"] = owner_peer
	drop["owner_until"] = server.now + owner_s
	drop["expires"] = server.now + float(cfg["lifetime_s"])
	drops[drop["id"]] = drop
	server.broadcast_drop(region, drop)


func _display_rarity(item: Dictionary) -> int:
	if str(server.catalog.base(item).get("kind", "")) == "jewel":
		return Protocol.RARITY_JEWEL
	match int(item.get("rarity", 0)):
		ItemCatalog.RARITY_EXCELLENT:
			return Protocol.RARITY_EXCELLENT
		ItemCatalog.RARITY_ANCESTRAL:
			return Protocol.RARITY_ANCESTRAL
	return Protocol.RARITY_NORMAL


func get_drop(id: int) -> Dictionary:
	return drops.get(id, {})


func pickup_range() -> float:
	return float(cfg["pickup_range_m"])


## Coleta: retorna mensagem de erro ("" = sucesso).
func try_pickup(p: ServerPlayer, id: int) -> String:
	var drop: Dictionary = drops.get(id, {})
	if drop.is_empty():
		return "O item já não está lá."
	if not server.party.same_group(int(drop["owner"]), p.peer_id) and server.now < float(drop["owner_until"]):
		return "Este item ainda pertence a outro jogador."
	if p.position.distance_to(drop["pos"]) > pickup_range() + 0.2:
		return "Longe demais."
	if drop["kind"] == "currency":
		var amount := roundi(int(drop["amount"]) * (1.0 + float(p.derived.get("currency_pct", 0.0))))
		p.currency += amount
		server.send_message(p.peer_id, "Você recebeu %d %s." % [amount, cfg["currency_name"]])
	else:
		if not server.inventory.give(p, drop["item"]):
			return "Inventário cheio."
		server.send_message(p.peer_id, "Você pegou: %s." % drop["label"])
		server.send_inventory(p)
	drops.erase(id)
	server.broadcast_drop_removed(region, id)
	return ""


func update() -> void:
	for id: int in drops.keys():
		if server.now >= float(drops[id]["expires"]):
			drops.erase(id)
			server.broadcast_drop_removed(region, id)


## Para um jogador que acabou de entrar ver os drops que já estão no chão.
func all_drops() -> Array:
	return drops.values()


func _weighted(entries: Array) -> Dictionary:
	var total := 0.0
	for e: Dictionary in entries:
		total += float(e["weight"])
	var r := server.rng.randf() * total
	for e: Dictionary in entries:
		r -= float(e["weight"])
		if r <= 0.0:
			return e
	return entries.back() if not entries.is_empty() else {}


func _pick(pool_id: Variant) -> String:
	var pool: Array = cfg["pools"].get(str(pool_id), [])
	return str(pool[server.rng.randi() % pool.size()]) if not pool.is_empty() else ""
