class_name SummonSystem
extends RefCounted
## Invocações (magia de tipo summon, ex.: Espírito do Véu da Vidente): uma por jogador,
## segue o dono, ataca o monstro vivo mais próximo no alcance e some quando o tempo
## acaba, o dono morre, sai ou troca de região. Não recebe dano (os monstros caçam
## o dono). O dano usa a rolagem do dono e conta para ele (XP e drops).

class Summon extends ServerEntity:
	var owner_peer: int
	var region: RegionInstance
	var def: Dictionary
	var until: float
	var next_attack: float = 0.0


var server: GameServer
var by_owner: Dictionary = {} # peer_id do dono -> Summon
var type_ids: Array = [] # ids das magias de invocação (o índice é o tipo no snapshot)


func _init(game_server: GameServer, spell_table: Dictionary) -> void:
	server = game_server
	type_ids = SummonSystem.summon_type_ids(spell_table)


## Ordem fixa dos tipos de invocação: a ordem das magias summon em spells.json (cliente igual).
static func summon_type_ids(spell_table: Dictionary) -> Array:
	var out: Array = []
	for id: String in spell_table:
		if id.begins_with("_"):
			continue
		if str((spell_table[id] as Dictionary).get("kind", "")) == "summon":
			out.append(id)
	return out


func summon(p: ServerPlayer, s: Dictionary) -> void:
	remove(p.peer_id, "")
	var e := Summon.new()
	e.id = server.next_monster_id()
	e.kind = Protocol.KIND_SUMMON
	e.type_index = maxi(0, type_ids.find(str(s["id"])))
	e.owner_peer = p.peer_id
	e.region = server.region_of(p)
	e.def = s["summon"]
	e.until = server.now + float(e.def["duration_s"])
	e.position = e.region.grid.nearest_walkable_point(p.position + Vector2(1.2, -1.2).rotated(p.yaw))
	e.yaw = p.yaw
	e.hp = 1.0
	e.hp_max = 1.0
	by_owner[p.peer_id] = e
	server.send_message(p.peer_id, "%s atende ao seu chamado (%d s)." % [e.def["name"], int(e.def["duration_s"])])


func remove(owner_peer: int, message: String) -> void:
	var e: Summon = by_owner.get(owner_peer)
	if e == null:
		return
	by_owner.erase(owner_peer)
	e.alive = false
	if message != "":
		server.send_message(owner_peer, message)


func in_region(region: RegionInstance) -> Array:
	var out: Array = []
	for e: Summon in by_owner.values():
		if e.region == region:
			out.append(e)
	return out


func update(dt: float) -> void:
	for owner_peer: int in by_owner.keys():
		var e: Summon = by_owner[owner_peer]
		var owner: ServerPlayer = server.players.get(owner_peer)
		if owner == null or not owner.alive or server.region_of(owner) != e.region:
			remove(owner_peer, "")
			continue
		if server.now >= e.until:
			remove(owner_peer, "%s volta para o Véu." % e.def["name"])
			continue
		_follow(e, owner, dt)
		_attack(e, owner)


func _follow(e: Summon, owner: ServerPlayer, dt: float) -> void:
	var d := e.position.distance_to(owner.position)
	if d > 15.0: # ficou para trás (portal curto, teleporte na mesma região): reaparece ao lado
		e.position = e.region.grid.nearest_walkable_point(owner.position + Vector2(1.0, 1.0))
		return
	if d <= float(e.def["follow_distance_m"]):
		return
	var dir := (owner.position - e.position).normalized()
	e.position = e.region.grid.slide(e.position, dir * float(e.def["move_speed_mps"]) * dt)
	e.yaw = atan2(dir.x, dir.y)


func _attack(e: Summon, owner: ServerPlayer) -> void:
	if server.now < e.next_attack:
		return
	if e.region.safe.contains(e.position):
		return
	var target := e.region.monsters.nearest_alive(e.position, float(e.def["attack_range_m"]))
	if target == null or e.region.safe.contains(target.position):
		return
	e.next_attack = server.now + float(e.def["attack_interval_s"])
	e.face(target.position)
	var d := owner.derived
	var r := CombatRules.roll(float(d.get("magic_min", 1.0)), float(d.get("magic_max", 1.0)),
		float(e.def["damage_mult"]), float(e.def["damage_bonus"]), target.defense(), server.combat_cfg, server.rng, 0.0, 0.0)
	server.broadcast_near(e.region, e.position, &"rpc_attack_event", [e.id, target.id])
	server.damage_monster(owner, target, maxi(1, roundi(r.x)), r.y)
