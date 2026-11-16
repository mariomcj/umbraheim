class_name TradeSystem
extends RefCounted
## Troca direta entre dois jogadores, com confirmação dupla:
##   1. cada um oferece itens da mochila (container 400) e Óbolos;
##   2. os dois marcam "Pronto" (a oferta trava);
##   3. os dois "Confirmam" -> o servidor confere espaço e saldo e troca tudo de uma vez.
## Qualquer mudança na oferta desmarca Pronto e Confirmar dos DOIS lados.
## Cancelar, se afastar, morrer ou cair devolve os itens a quem ofereceu.

class Deal:
	var a: int # peer_id
	var b: int
	var currency: Dictionary = {} # peer_id -> Óbolos oferecidos
	var locked: Dictionary = {} # peer_id -> bool
	var confirmed: Dictionary = {}

	func other(peer_id: int) -> int:
		return b if peer_id == a else a

	func reset_flags() -> void:
		locked.clear()
		confirmed.clear()


var server: GameServer
var cfg: Dictionary
var deals: Dictionary = {} # peer_id -> Deal (os dois lados apontam para o mesmo)
var _requests: Dictionary = {} # peer convidado -> {from, until}


func _init(game_server: GameServer, social_table: Dictionary) -> void:
	server = game_server
	cfg = social_table["trade"]


func is_trading(p: ServerPlayer) -> bool:
	return deals.has(p.peer_id)


func handle(p: ServerPlayer, action: int, value: int, target: String) -> void:
	match action:
		Protocol.Trade.REQUEST:
			request(p, target)
		Protocol.Trade.ACCEPT:
			accept(p)
		Protocol.Trade.DECLINE:
			decline(p)
		Protocol.Trade.ADD_ITEM:
			add_item(p, value)
		Protocol.Trade.REMOVE_ITEM:
			remove_item(p, value)
		Protocol.Trade.SET_CURRENCY:
			set_currency(p, value)
		Protocol.Trade.LOCK:
			lock(p)
		Protocol.Trade.CONFIRM:
			confirm(p)
		Protocol.Trade.CANCEL:
			cancel(p, "%s cancelou a troca." % p.char_name)


func request(p: ServerPlayer, target_name: String) -> void:
	var t := server.find_player_by_name(target_name)
	var err := _can_trade(p, t)
	if err != "":
		server.chat.system(p.peer_id, err)
		return
	_requests[t.peer_id] = {"from": p.peer_id, "until": server.now + float(cfg["request_timeout_s"])}
	Net.send_to(t.peer_id, &"rpc_prompt", [Protocol.Prompt.TRADE_REQUEST, p.char_name, ""])
	server.chat.system(p.peer_id, "Pedido de troca enviado a %s." % t.char_name)


func accept(p: ServerPlayer) -> void:
	var req: Dictionary = _requests.get(p.peer_id, {})
	_requests.erase(p.peer_id)
	var from: ServerPlayer = server.players.get(int(req.get("from", 0)))
	if req.is_empty() or server.now > float(req["until"]) or from == null:
		server.chat.system(p.peer_id, "O pedido de troca expirou.")
		return
	var err := _can_trade(from, p)
	if err != "":
		server.chat.system(p.peer_id, err)
		return
	var d := Deal.new()
	d.a = from.peer_id
	d.b = p.peer_id
	d.currency = {d.a: 0, d.b: 0}
	deals[d.a] = d
	deals[d.b] = d
	for who: ServerPlayer in [from, p]:
		server.region_of(who).npcs.close(who)
		who.action = {}
		who.stop()
	print("[troca] aberta: %s <-> %s" % [from.char_name, p.char_name])
	_send_state(d)


func decline(p: ServerPlayer) -> void:
	var req: Dictionary = _requests.get(p.peer_id, {})
	_requests.erase(p.peer_id)
	var from: ServerPlayer = server.players.get(int(req.get("from", 0)))
	if from != null:
		server.chat.system(from.peer_id, "%s recusou a troca." % p.char_name)


func add_item(p: ServerPlayer, uid: int) -> void:
	var d: Deal = deals.get(p.peer_id)
	if d == null:
		return
	var err := server.inventory.to_trade(p, uid)
	if err != "":
		server.chat.system(p.peer_id, err)
		return
	_changed(d)


func remove_item(p: ServerPlayer, uid: int) -> void:
	var d: Deal = deals.get(p.peer_id)
	var item: Dictionary = p.items.get(uid, {})
	if d == null or item.is_empty() or int(item["container"]) != ItemCatalog.CONTAINER_TRADE:
		return
	var err := server.inventory.move_to_inventory(p, uid, -1, -1)
	if err != "":
		server.chat.system(p.peer_id, err)
		return
	_changed(d)


func set_currency(p: ServerPlayer, amount: int) -> void:
	var d: Deal = deals.get(p.peer_id)
	if d == null:
		return
	d.currency[p.peer_id] = clampi(amount, 0, p.currency)
	_changed(d)


func lock(p: ServerPlayer) -> void:
	var d: Deal = deals.get(p.peer_id)
	if d == null:
		return
	d.locked[p.peer_id] = true
	_send_state(d)


func confirm(p: ServerPlayer) -> void:
	var d: Deal = deals.get(p.peer_id)
	if d == null or not (d.locked.get(d.a, false) and d.locked.get(d.b, false)):
		return
	d.confirmed[p.peer_id] = true
	if d.confirmed.get(d.a, false) and d.confirmed.get(d.b, false):
		_execute(d)
	else:
		_send_state(d)


## Fecha a troca devolvendo tudo (o que não couber vai ao chão, com posse do dono).
func cancel(p: ServerPlayer, reason: String) -> void:
	var d: Deal = deals.get(p.peer_id)
	if d == null:
		return
	_close(d, reason, true)


## A cada tick: cancela se alguém se afastou, morreu ou saiu.
func update() -> void:
	for d: Deal in _unique_deals():
		var pa: ServerPlayer = server.players.get(d.a)
		var pb: ServerPlayer = server.players.get(d.b)
		if pa == null or pb == null:
			_close(d, "A troca foi cancelada (o outro jogador saiu).", true)
		elif not pa.alive or not pb.alive:
			_close(d, "A troca foi cancelada.", true)
		elif pa.region_id != pb.region_id or pa.position.distance_to(pb.position) > float(cfg["range_m"]) + 1.0:
			_close(d, "Vocês se afastaram; a troca foi cancelada.", true)


func on_disconnect(p: ServerPlayer) -> void:
	_requests.erase(p.peer_id)
	cancel(p, "%s saiu do jogo; a troca foi cancelada." % p.char_name)


# ---------------------------------------------------------------- execução

func _execute(d: Deal) -> void:
	var pa: ServerPlayer = server.players[d.a]
	var pb: ServerPlayer = server.players[d.b]
	var items_a := server.inventory.items_in(pa, ItemCatalog.CONTAINER_TRADE)
	var items_b := server.inventory.items_in(pb, ItemCatalog.CONTAINER_TRADE)
	var ca := int(d.currency[d.a])
	var cb := int(d.currency[d.b])
	var problem := ""
	if ca > pa.currency or cb > pb.currency:
		problem = "Óbolos insuficientes para a troca."
	elif not server.inventory.fits_all(pb, items_a):
		problem = "Não há espaço na mochila de %s." % pb.char_name
	elif not server.inventory.fits_all(pa, items_b):
		problem = "Não há espaço na mochila de %s." % pa.char_name
	if problem != "":
		d.reset_flags()
		for peer_id in [d.a, d.b]:
			server.chat.system(peer_id, problem)
		_send_state(d)
		return
	var summary := PackedStringArray()
	for pair: Array in [[pa, pb, items_a], [pb, pa, items_b]]:
		var from: ServerPlayer = pair[0]
		var to: ServerPlayer = pair[1]
		for item: Dictionary in pair[2]:
			server.inventory.take(from, int(item["uid"]))
			item["container"] = ItemCatalog.CONTAINER_INVENTORY
			server.inventory.give(to, item)
			summary.append("%s -> %s: %s (uid %d)" % [from.char_name, to.char_name, server.catalog.display_name(item), int(item["uid"])])
	pa.currency += cb - ca
	pb.currency += ca - cb
	summary.append("Óbolos: %s deu %d, %s deu %d" % [pa.char_name, ca, pb.char_name, cb])
	print("[troca] concluída | " + " | ".join(summary))
	for who: ServerPlayer in [pa, pb]:
		server.recompute(who)
	server.save_players([pa, pb]) # os dois lados no banco, numa transação só
	_close(d, "Troca concluída.", false)


func _close(d: Deal, reason: String, give_back: bool) -> void:
	deals.erase(d.a)
	deals.erase(d.b)
	for peer_id in [d.a, d.b]:
		var p: ServerPlayer = server.players.get(peer_id)
		if p == null:
			continue
		if give_back:
			for item: Dictionary in server.inventory.return_container(p, ItemCatalog.CONTAINER_TRADE):
				server.region_of(p).drops.spawn_item(item, p.position, p.peer_id, 60.0)
				server.chat.system(peer_id, "Sem espaço: %s ficou no chão." % server.catalog.display_name(item))
		Net.send_to(peer_id, &"rpc_trade_closed", [reason])
		server.send_inventory(p)


func _changed(d: Deal) -> void:
	d.reset_flags()
	for peer_id in [d.a, d.b]:
		var p: ServerPlayer = server.players.get(peer_id)
		if p != null:
			server.send_inventory(p)
	_send_state(d)


func _send_state(d: Deal) -> void:
	for peer_id in [d.a, d.b]:
		var me: ServerPlayer = server.players.get(peer_id)
		var them: ServerPlayer = server.players.get(d.other(peer_id))
		if me == null or them == null:
			continue
		var their_items: Array = []
		for item: Dictionary in server.inventory.items_in(them, ItemCatalog.CONTAINER_TRADE):
			their_items.append(ItemCodec.encode(item, server.catalog))
		Net.send_to(peer_id, &"rpc_trade_state", [{
			"partner": them.char_name, "their_items": their_items,
			"their_currency": int(d.currency[them.peer_id]), "my_currency": int(d.currency[peer_id]),
			"my_locked": bool(d.locked.get(peer_id, false)), "their_locked": bool(d.locked.get(them.peer_id, false)),
			"my_confirmed": bool(d.confirmed.get(peer_id, false)), "their_confirmed": bool(d.confirmed.get(them.peer_id, false)),
		}])


func _can_trade(p: ServerPlayer, t: ServerPlayer) -> String:
	if t == null:
		return "Esse jogador não está online."
	if t == p:
		return "Você não pode trocar consigo mesmo."
	if not p.alive or not t.alive:
		return "Agora não."
	if is_trading(p) or is_trading(t):
		return "Um de vocês já está numa troca."
	if p.region_id != t.region_id or p.position.distance_to(t.position) > float(cfg["range_m"]):
		return "Chegue mais perto de %s para trocar." % t.char_name
	return ""


func _unique_deals() -> Array:
	var out: Array = []
	for d: Deal in deals.values():
		if not out.has(d):
			out.append(d)
	return out
