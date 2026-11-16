class_name ItemUseSystem
extends RefCounted
## Uso de consumíveis (botão direito ou atalhos Z/X): poções, Pergaminho do Retorno
## e grimórios. Recarga por tipo de efeito, definida no próprio item (use.cooldown_s).

var server: GameServer


func _init(game_server: GameServer) -> void:
	server = game_server


func use(p: ServerPlayer, uid: int) -> void:
	var item: Dictionary = p.items.get(uid, {})
	if item.is_empty() or int(item["container"]) != ItemCatalog.CONTAINER_INVENTORY:
		return
	var effect := server.catalog.use_effect(item)
	if effect.is_empty():
		server.send_message(p.peer_id, "Este item não pode ser usado.")
		return
	if not p.alive:
		return
	if p.level < server.catalog.level_req(item):
		server.send_message(p.peer_id, "Nível insuficiente (precisa de %d)." % server.catalog.level_req(item))
		return
	if not server.catalog.allowed_for(item, p.class_id):
		server.send_message(p.peer_id, "Sua classe não usa este item.")
		return
	if bool(server.region_of(p).data.get("no_items", false)):
		server.send_message(p.peer_id, "Itens de fora não funcionam aqui dentro.")
		return
	var kind := str(effect["type"])
	if float(p.use_ready_at.get(kind, 0.0)) > server.now:
		return # recarga: ignora em silêncio (o atalho costuma ser apertado várias vezes)
	match kind:
		"heal_hp":
			if p.hp >= p.hp_max:
				server.send_message(p.peer_id, "Sua vida já está cheia.")
				return
			var healed := minf(float(effect["amount"]), p.hp_max - p.hp)
			p.hp += healed
			server.broadcast_near(server.region_of(p), p.position, &"rpc_damage_event", [p.id, roundi(healed), Protocol.DMG_HEAL])
		"heal_mana":
			if p.mana >= p.mana_max():
				server.send_message(p.peer_id, "Sua mana já está cheia.")
				return
			p.mana = minf(p.mana_max(), p.mana + float(effect["amount"]))
		"event_ticket":
			var why := server.events.try_enter(p, str(effect["event"]))
			if why != "":
				server.send_message(p.peer_id, why)
				return
		"return":
			if server.region_of(p).is_event():
				server.send_message(p.peer_id, "O pergaminho não funciona dentro de um evento.")
				return
			server.teleport_to_return_point(p)
			server.send_message(p.peer_id, "O pergaminho se desfaz em cinzas e você volta ao Refúgio.")
		"learn_spell":
			var index := server.spells.index_of(p.class_id, str(effect["spell"]))
			if index < 0:
				server.send_message(p.peer_id, "Sua classe não aprende esta magia.")
				return
			if p.knows_spell(index):
				server.send_message(p.peer_id, "Você já conhece esta magia.")
				return
			p.learned_spells |= 1 << index
			var learned := server.spells.spell(p, index)
			server.send_message(p.peer_id, "Você aprendeu %s! (tecla %d)" % [learned["name"], int(learned["slot"])])
			server.broadcast_near(server.region_of(p), p.position, &"rpc_level_up_event", [p.id, -1]) # brilho de aprendizado
		_:
			return
	p.use_ready_at[kind] = server.now + float(effect.get("cooldown_s", 0.0))
	server.inventory.consume_one(p, uid)
