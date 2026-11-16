class_name QuestSystem
extends RefCounted
## Missões (data/quests.json), usadas para a evolução de classe. Aceitar e entregar
## só com a janela do NPC aberta (papel quest). O progresso fica em p.quests:
## {quest_id: {step, count}} enquanto ativa, {done: true} quando entregue.

var server: GameServer
var quests: Dictionary


func _init(game_server: GameServer, quest_table: Dictionary) -> void:
	server = game_server
	quests = quest_table


# ---------------------------------------------------------------- regras puras (testadas)

## Morte de um monstro na região: avança o passo "kill" atual. true se mudou algo.
static func apply_kill(state: Dictionary, quest: Dictionary, region_id: String) -> bool:
	if state.is_empty() or bool(state.get("done", false)):
		return false
	var steps: Array = quest["steps"]
	var i := int(state["step"])
	if i >= steps.size():
		return false
	var step: Dictionary = steps[i]
	if str(step["type"]) != "kill" or str(step.get("region", region_id)) != region_id:
		return false
	state["count"] = int(state["count"]) + 1
	if int(state["count"]) >= int(step["count"]):
		state["step"] = i + 1
		state["count"] = 0
	return true


## Pode entregar? Todos os passos de matar feitos e, se o último é de item, o item na mochila.
static func can_turn_in(state: Dictionary, quest: Dictionary, item_counts: Dictionary) -> bool:
	if state.is_empty() or bool(state.get("done", false)):
		return false
	var steps: Array = quest["steps"]
	var i := int(state["step"])
	if i >= steps.size():
		return true
	var step: Dictionary = steps[i]
	return i == steps.size() - 1 and str(step["type"]) == "item" and int(item_counts.get(str(step["item"]), 0)) >= int(step["count"])


# ---------------------------------------------------------------- ações

func handle(p: ServerPlayer, action: int, quest_id: String) -> void:
	var quest: Dictionary = quests.get(quest_id, {})
	if quest.is_empty():
		return
	var npcs := server.region_of(p).npcs
	if not npcs.is_open(p, "quest") or not quest_id in (npcs.get_npc(p.npc_open).get("quests", []) as Array):
		server.send_message(p.peer_id, "Fale com %s." % _npc_name(quest))
		return
	match action:
		Protocol.Quest.ACCEPT:
			_accept(p, quest_id, quest)
		Protocol.Quest.TURN_IN:
			_turn_in(p, quest_id, quest)
		Protocol.Quest.ABANDON:
			if p.quests.has(quest_id) and not bool(p.quests[quest_id].get("done", false)):
				p.quests.erase(quest_id)
				server.send_message(p.peer_id, "Você desistiu de %s." % quest["name"])
	send_state(p)


func _accept(p: ServerPlayer, quest_id: String, quest: Dictionary) -> void:
	if p.quests.has(quest_id):
		return
	if bool(quest.get("reward", {}).get("evolve", false)) and p.evolution > 0:
		return
	if p.level < int(quest["level_req"]):
		server.send_message(p.peer_id, "%s exige nível %d." % [quest["name"], int(quest["level_req"])])
		return
	p.quests[quest_id] = {"step": 0, "count": 0}
	server.send_message(p.peer_id, "Missão aceita: %s." % quest["name"])


func _turn_in(p: ServerPlayer, quest_id: String, quest: Dictionary) -> void:
	var state: Dictionary = p.quests.get(quest_id, {})
	if not can_turn_in(state, quest, _item_counts(p)):
		server.send_message(p.peer_id, "A missão ainda não está completa.")
		return
	var steps: Array = quest["steps"]
	var last: Dictionary = steps[steps.size() - 1]
	if str(last["type"]) == "item":
		for k in int(last["count"]):
			var uid := _find_item(p, str(last["item"]))
			if uid != 0:
				server.inventory.consume_one(p, uid)
		server.send_inventory(p)
	p.quests[quest_id] = {"done": true}
	server.send_message(p.peer_id, "Missão concluída: %s." % quest["name"])
	if bool(quest.get("reward", {}).get("evolve", false)):
		server.evolve(p)
	server.save_player(p)


# ---------------------------------------------------------------- eventos

## Monstro morto: conta para quem matou e para o grupo na mesma região (vivos).
func on_monster_kill(killer: ServerPlayer, m: ServerMonster) -> void:
	var who: Array[ServerPlayer] = [killer]
	for member: ServerPlayer in server.party.members_of(killer):
		if member != killer and member.alive and member.region_id == killer.region_id:
			who.append(member)
	for p in who:
		for quest_id: String in p.quests:
			var state: Dictionary = p.quests[quest_id]
			var before := int(state.get("step", 0))
			if apply_kill(state, quests.get(quest_id, {"steps": []}), m.region.id):
				if int(state["step"]) != before:
					server.send_message(p.peer_id, "%s: etapa concluída!" % quests[quest_id]["name"])
				send_state(p)


## Chefe derrotado: quem ajudou e está no passo de item desse chefe recebe o item.
func on_boss_killed(m: ServerMonster) -> void:
	var base_id := m.def_id.trim_suffix("_dourado")
	for peer_id: int in m.damage_by:
		var p: ServerPlayer = server.players.get(peer_id)
		if p == null or p.region_id != m.region.id:
			continue
		for quest_id: String in p.quests:
			var state: Dictionary = p.quests[quest_id]
			var quest: Dictionary = quests.get(quest_id, {})
			if quest.is_empty() or bool(state.get("done", false)):
				continue
			var steps: Array = quest["steps"]
			var i := int(state["step"])
			if i >= steps.size() or str(steps[i]["type"]) != "item" or str(steps[i].get("from_monster", "")) != base_id:
				continue
			if int(_item_counts(p).get(str(steps[i]["item"]), 0)) >= int(steps[i]["count"]):
				continue
			var item := server.factory.create(str(steps[i]["item"]))
			if not server.inventory.give(p, item):
				m.region.drops.spawn_item(item, p.position, p.peer_id, 120.0)
			server.send_inventory(p)
			server.send_message(p.peer_id, "Você obteve %s. Leve-o a %s." % [server.catalog.display_name(item), _npc_name(quest)])
			send_state(p)


func send_state(p: ServerPlayer) -> void:
	Net.send_to(p.peer_id, &"rpc_quest_state", [p.quests.duplicate(true)])


func _item_counts(p: ServerPlayer) -> Dictionary:
	var out := {}
	for item: Dictionary in p.items.values():
		if int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY:
			out[str(item["base"])] = int(out.get(str(item["base"]), 0)) + int(item.get("count", 1))
	return out


func _find_item(p: ServerPlayer, base_id: String) -> int:
	for item: Dictionary in p.items.values():
		if str(item["base"]) == base_id and int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY:
			return int(item["uid"])
	return 0


func _npc_name(quest: Dictionary) -> String:
	for region: RegionInstance in server.regions.values():
		var npc := region.npcs.get_npc(str(quest.get("npc", "")))
		if not npc.is_empty():
			return str(npc["name"])
	return "o mestre da missão"
