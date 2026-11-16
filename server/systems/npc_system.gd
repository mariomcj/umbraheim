class_name NpcSystem
extends RefCounted
## NPCs da região (dados em data/regions/*.json -> npcs): alcance de interação,
## janela aberta por jogador e fechamento automático ao se afastar ou morrer.
## Cada papel (role) tem seu sistema: shop -> ShopSystem, storage -> armazém,
## vortex_forge -> ForgeSystem, quest -> QuestSystem.

var server: GameServer
var region: RegionInstance
var npcs: Dictionary = {} # id -> dados do NPC


func _init(game_server: GameServer, region_instance: RegionInstance) -> void:
	server = game_server
	region = region_instance
	for npc: Dictionary in region.data.get("npcs", []):
		npcs[str(npc["id"])] = npc


func has(npc_id: String) -> bool:
	return npcs.has(npc_id)


func get_npc(npc_id: String) -> Dictionary:
	return npcs.get(npc_id, {})


func role_of(npc_id: String) -> String:
	return str(get_npc(npc_id).get("role", ""))


func npc_pos(npc_id: String) -> Vector2:
	var n := get_npc(npc_id)
	return Vector2(float(n["pos"][0]), float(n["pos"][1])) if not n.is_empty() else Vector2.INF


func in_range(p: ServerPlayer, npc_id: String) -> bool:
	var n := get_npc(npc_id)
	return not n.is_empty() and p.position.distance_to(npc_pos(npc_id)) <= float(n["interact_range_m"])


## O jogador está com a janela de um NPC deste papel aberta (e ainda perto dele)?
func is_open(p: ServerPlayer, role: String) -> bool:
	return p.npc_open != "" and role_of(p.npc_open) == role and in_range(p, p.npc_open)


func open(p: ServerPlayer, npc_id: String) -> void:
	if role_of(npc_id) == "event_altar": # não abre janela: entrega a relíquia na hora
		server.events.on_altar(p, npc_id)
		return
	if p.npc_open != "" and p.npc_open != npc_id:
		close(p)
	p.npc_open = npc_id
	Net.send_to(p.peer_id, &"rpc_npc_opened", [npc_id])
	if role_of(npc_id) == "quest":
		server.quests.send_state(p)
	elif role_of(npc_id) == "siege":
		server.castle.send_state(p)


func close(p: ServerPlayer) -> void:
	if p.npc_open == "":
		return
	var role := role_of(p.npc_open)
	p.npc_open = ""
	if role == "vortex_forge":
		for item: Dictionary in server.inventory.return_forge(p):
			region.drops.spawn_item(item, p.position, p.peer_id, 60.0)
			server.send_message(p.peer_id, "Sem espaço: %s ficou no chão." % server.catalog.display_name(item))
	Net.send_to(p.peer_id, &"rpc_npc_closed", [])
	server.recompute(p)


## Chamado a cada tick: fecha a janela se o jogador se afastou ou morreu.
func update(p: ServerPlayer) -> void:
	if p.npc_open != "" and (not p.alive or not in_range(p, p.npc_open)):
		close(p)
		server.send_inventory(p)
