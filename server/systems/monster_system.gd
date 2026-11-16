class_name MonsterSystem
extends RefCounted
## Monstros de UMA região: spawn por zona (dados da região), IA, ataque e respawn.
## Os ids são globais (negativos, do GameServer) para não colidirem entre regiões.

var server: GameServer
var region: RegionInstance
var defs: Dictionary
var type_ids: PackedStringArray # ordenado: índice = type_index no snapshot (igual no cliente)
var monsters: Dictionary = {} # id (negativo) -> ServerMonster


func _init(game_server: GameServer, region_instance: RegionInstance, monster_table: Dictionary) -> void:
	server = game_server
	region = region_instance
	defs = monster_table
	type_ids = MonsterCatalog.type_ids(monster_table)


func spawn_region(region_data: Dictionary) -> void:
	for sp: Dictionary in region_data.get("monster_spawns", []):
		var def_id := str(sp["monster"])
		var center := Vector2(float(sp["pos"][0]), float(sp["pos"][1]))
		for i in int(sp["count"]):
			var m := ServerMonster.new()
			m.id = server.next_monster_id()
			m.region = region
			m.kind = Protocol.KIND_MONSTER
			m.def_id = def_id
			m.def = defs[def_id]
			m.type_index = type_ids.find(def_id)
			m.spawn_radius = float(sp["radius_m"])
			m.home = region.grid.nearest_walkable_point(center + _random_offset(m.spawn_radius))
			_respawn(m)
			monsters[m.id] = m
	print("[server] %s: %d monstros" % [region.id, monsters.size()])


## Monstro de evento (invasão): nasce em pos, não renasce e some ao morrer.
func spawn_temporary(def_id: String, pos: Vector2, event_id: int) -> ServerMonster:
	var m := ServerMonster.new()
	m.id = server.next_monster_id()
	m.region = region
	m.kind = Protocol.KIND_MONSTER
	m.def_id = def_id
	m.def = defs[def_id]
	m.type_index = type_ids.find(def_id)
	m.spawn_radius = 0.0
	m.home = region.grid.nearest_walkable_point(pos)
	m.temporary = true
	m.event_id = event_id
	_respawn(m)
	monsters[m.id] = m
	return m


## Remove os monstros vivos de um evento (fim da invasão). Retorna quantos saíram.
func remove_event(event_id: int) -> int:
	var n := 0
	for m: ServerMonster in monsters.values():
		if m.event_id == event_id:
			monsters.erase(m.id)
			n += 1
	return n


func count_event(event_id: int) -> int:
	var n := 0
	for m: ServerMonster in monsters.values():
		if m.event_id == event_id and m.alive:
			n += 1
	return n


func get_alive(id: int) -> ServerMonster:
	var m: ServerMonster = monsters.get(id)
	return m if m != null and m.alive else null


func alive_in_radius(center: Vector2, radius: float) -> Array[ServerMonster]:
	var out: Array[ServerMonster] = []
	for m: ServerMonster in monsters.values():
		if m.alive and m.position.distance_to(center) <= radius:
			out.append(m)
	return out


func nearest_alive(center: Vector2, radius: float) -> ServerMonster:
	var best: ServerMonster = null
	var best_d := radius
	for m in alive_in_radius(center, radius):
		var d := m.position.distance_to(center)
		if d <= best_d:
			best_d = d
			best = m
	return best


func on_damaged(m: ServerMonster, attacker: ServerPlayer, amount: int) -> void:
	m.damage_by[attacker.peer_id] = float(m.damage_by.get(attacker.peer_id, 0.0)) + amount
	if m.state == ServerMonster.State.IDLE and not region.safe.contains(attacker.position):
		m.state = ServerMonster.State.CHASE
		m.target_id = attacker.id


func kill(m: ServerMonster) -> void:
	m.alive = false
	m.stop()
	m.respawn_at = server.now + float(m.def["respawn_s"])
	if m.temporary:
		monsters.erase(m.id) # monstro de evento não volta


func forget_player(player_id: int) -> void:
	for m: ServerMonster in monsters.values():
		if m.target_id == player_id:
			m.target_id = 0
			m.state = ServerMonster.State.RETURN
			m.next_repath = 0.0


func update(dt: float) -> void:
	for m: ServerMonster in monsters.values():
		if not m.alive:
			if server.now >= m.respawn_at:
				_respawn(m)
			continue
		if bool(m.def.get("structure", false)):
			continue # portão de evento: não anda nem ataca
		match m.state:
			ServerMonster.State.IDLE:
				_think_idle(m, dt)
			ServerMonster.State.CHASE:
				_think_chase(m, dt)
			ServerMonster.State.ATTACK:
				_think_attack(m)
			ServerMonster.State.RETURN:
				_think_return(m, dt)


func _think_idle(m: ServerMonster, dt: float) -> void:
	var target := _nearest_player(m.position, float(m.def["aggro_m"]))
	if target != null:
		m.state = ServerMonster.State.CHASE
		m.target_id = target.id
		m.next_repath = 0.0
		return
	if server.now >= m.next_wander:
		m.next_wander = server.now + server.rng.randf_range(3.0, 7.0)
		var dest := region.grid.nearest_walkable_point(m.home + _random_offset(float(m.def["wander_radius_m"])))
		m.set_path(region.grid.find_path(m.position, dest))
	m.follow_path(dt, float(m.def["speed_mps"]) * 0.4)


func _think_chase(m: ServerMonster, dt: float) -> void:
	var target: ServerPlayer = region.players.get(m.target_id)
	if target == null or not target.alive or m.position.distance_to(m.home) > float(m.def["leash_m"]) \
			or region.safe.contains(target.position):
		_go_home(m) # alvo fugiu para a cidade: monstro desiste
		return
	if m.position.distance_to(target.position) <= float(m.def["attack_range_m"]):
		m.stop()
		m.state = ServerMonster.State.ATTACK
		return
	if server.now >= m.next_repath:
		m.next_repath = server.now + float(server.combat_cfg["repath_interval_s"])
		m.set_path(region.grid.find_path(m.position, target.position))
	m.follow_path(dt, float(m.def["speed_mps"]))


func _think_attack(m: ServerMonster) -> void:
	var target: ServerPlayer = region.players.get(m.target_id)
	if target == null or not target.alive or region.safe.contains(target.position):
		_go_home(m)
		return
	m.face(target.position)
	if m.position.distance_to(target.position) > float(m.def["attack_range_m"]) * 1.15:
		m.state = ServerMonster.State.CHASE
		m.next_repath = 0.0
		return
	if server.now >= m.attack_ready_at:
		m.attack_ready_at = server.now + float(m.def["attack_cooldown_s"])
		server.broadcast_attack(m, target.id)
		var r := CombatRules.roll(float(m.def["damage_min"]), float(m.def["damage_max"]), 1.0, 0.0,
			float(target.derived.get("defense", 0.0)), server.combat_cfg, server.rng)
		server.damage_player(m, target, r.x, r.y)


func _think_return(m: ServerMonster, dt: float) -> void:
	m.hp = minf(m.hp_max, m.hp + m.hp_max * 0.5 * dt)
	if m.position.distance_to(m.home) < 0.5:
		m.hp = m.hp_max
		m.damage_by.clear()
		m.state = ServerMonster.State.IDLE
		return
	if not m.has_path() or server.now >= m.next_repath:
		m.next_repath = server.now + 2.0
		m.set_path(region.grid.find_path(m.position, m.home))
	m.follow_path(dt, float(m.def["speed_mps"]) * 1.2)


func _go_home(m: ServerMonster) -> void:
	m.state = ServerMonster.State.RETURN
	m.target_id = 0
	m.next_repath = 0.0


func _respawn(m: ServerMonster) -> void:
	if bool(m.def.get("boss", false)) and m.spawned_once:
		server.on_boss_spawned(m)
	m.spawned_once = true
	m.alive = true
	m.hp_max = float(m.def["hp"])
	m.hp = m.hp_max
	m.position = m.home
	m.state = ServerMonster.State.IDLE
	m.target_id = 0
	m.damage_by.clear()
	m.next_wander = server.now + server.rng.randf_range(1.0, 4.0)
	m.stop()


func _nearest_player(center: Vector2, radius: float) -> ServerPlayer:
	var best: ServerPlayer = null
	var best_d := radius
	for p: ServerPlayer in region.players.values():
		if not p.alive or region.safe.contains(p.position):
			continue
		var d := p.position.distance_to(center)
		if d <= best_d:
			best_d = d
			best = p
	return best


func _random_offset(radius: float) -> Vector2:
	return Vector2.from_angle(server.rng.randf() * TAU) * sqrt(server.rng.randf()) * radius
