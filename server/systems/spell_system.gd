class_name SpellSystem
extends RefCounted
## Conjuração autoritativa: valida alcance, recarga e mana; agenda os acertos
## (projétil = tempo de voo, corpo a corpo e área = antecipação) e aplica o dano,
## a cura, os bônus temporários e as invocações. Cada classe tem a sua lista de
## magias (data/classes/<id>.json -> spells); o índice na rede é a posição nessa lista.

enum Result { OK, OUT_OF_RANGE, COOLDOWN, NO_MANA, INVALID, NOT_LEARNED, SAFE_ZONE, PVP_DENIED }

## Magias que não precisam de alvo: acontecem em volta de quem lança.
const SELF_KINDS: PackedStringArray = ["nova", "buff", "heal", "summon"]
## Podem ser lançadas numa zona segura (não ferem ninguém).
const PEACEFUL_KINDS: PackedStringArray = ["buff", "heal"]
## Atingem um jogador (PvP).
const SINGLE_TARGET_KINDS: PackedStringArray = ["projectile", "melee"]

var server: GameServer
var by_class: Dictionary = {} # class_id -> Array[Dictionary] (cópias com "id")
var _pending: Array[Dictionary] = [] # {at, region, caster_id, spell (Dictionary), target_id, pos, chain}
var _buff_timer: float = 0.0


func _init(game_server: GameServer, classes: Dictionary, spell_table: Dictionary) -> void:
	server = game_server
	for class_id: String in classes:
		var list: Array[Dictionary] = []
		for id: String in classes[class_id]["spells"]:
			var s: Dictionary = spell_table[id].duplicate(true)
			s["id"] = id
			list.append(s)
		by_class[class_id] = list


func list_for(class_id: String) -> Array:
	return by_class.get(class_id, [])


## Magia de índice `index` da classe do jogador ({} se não existe).
func spell(p: ServerPlayer, index: int) -> Dictionary:
	var list := list_for(p.class_id)
	return list[index] if index >= 0 and index < list.size() else {}


func index_of(class_id: String, spell_id: String) -> int:
	var list := list_for(class_id)
	for i in list.size():
		if str(list[i]["id"]) == spell_id:
			return i
	return -1


func index_of_slot(class_id: String, slot: int) -> int:
	var list := list_for(class_id)
	for i in list.size():
		if int(list[i]["slot"]) == slot:
			return i
	return -1


## Máscara de bits das magias de uma lista de ids (iniciais, evolução).
func mask_of(class_id: String, spell_ids: Array) -> int:
	var mask := 0
	for id: String in spell_ids:
		var i := index_of(class_id, id)
		if i >= 0:
			mask |= 1 << i
	return mask


static func is_self_cast(s: Dictionary) -> bool:
	return str(s.get("kind", "")) in SELF_KINDS


func try_cast(p: ServerPlayer, index: int, target_id: int, target_pos: Vector2) -> Result:
	var s := spell(p, index)
	if s.is_empty() or not p.alive:
		return Result.INVALID
	if not p.knows_spell(index):
		return Result.NOT_LEARNED
	var region := server.region_of(p)
	var kind := str(s["kind"])
	if region.safe.contains(p.position) and not kind in PEACEFUL_KINDS:
		return Result.SAFE_ZONE
	if kind in SELF_KINDS:
		return _cast_self(p, index, s, region)
	if target_id > 0: # id positivo = jogador (PvP, Ctrl+clique)
		return _try_cast_on_player(p, index, s, region, server.players.get(target_id))
	var target: ServerMonster = null
	if target_id != 0:
		target = region.monsters.get_alive(target_id)
	if kind != "area" and target == null:
		target = region.monsters.nearest_alive(target_pos, float(server.combat_cfg["auto_target_radius_m"]))
		if target == null:
			return Result.INVALID
	var aim := target.position if target != null else target_pos
	if not aim.is_finite():
		return Result.INVALID
	if p.position.distance_to(aim) > float(s["range_m"]) + float(server.combat_cfg["range_tolerance_m"]):
		return Result.OUT_OF_RANGE
	var r := _pay(p, index, s)
	if r != Result.OK:
		return r
	p.face(aim)
	p.stop()
	var tid := target.id if target != null else 0
	var chain := PackedInt32Array()
	var at := server.now
	match kind:
		"projectile":
			at += p.position.distance_to(aim) / maxf(1.0, float(s.get("projectile_speed_mps", 20.0)))
		"area", "melee":
			at += float(s.get("cast_delay_s", 0.0))
		"chain":
			chain = _chain_targets(target, int(s.get("chain_count", 0)), float(s.get("chain_range_m", 0.0)))
			at += 0.05
	_pending.append({"at": at, "region": region, "caster_id": p.id, "spell": s, "target_id": tid, "pos": aim, "chain": chain})
	server.broadcast_cast(p, index, tid, aim, chain)
	return Result.OK


## Recarga e mana; desconta e avisa o cliente se puder lançar.
func _pay(p: ServerPlayer, index: int, s: Dictionary) -> Result:
	if float(p.cooldowns.get(index, 0.0)) > server.now:
		return Result.COOLDOWN
	if p.mana < float(s["mana_cost"]):
		return Result.NO_MANA
	p.mana -= float(s["mana_cost"])
	var cooldown := float(s["cooldown_s"])
	if int(s["slot"]) == 0:
		cooldown /= maxf(0.1, float(p.derived.get("attack_speed", 1.0)))
	p.cooldowns[index] = server.now + cooldown
	server.send_cooldown(p.peer_id, index, cooldown)
	return Result.OK


## Magia sem alvo: explosão em volta, bônus temporário, cura ou invocação.
func _cast_self(p: ServerPlayer, index: int, s: Dictionary, region: RegionInstance) -> Result:
	var r := _pay(p, index, s)
	if r != Result.OK:
		return r
	p.stop()
	server.broadcast_cast(p, index, 0, p.position, PackedInt32Array())
	match str(s["kind"]):
		"nova":
			_pending.append({"at": server.now + float(s.get("cast_delay_s", 0.0)), "region": region, "caster_id": p.id,
				"spell": s, "target_id": 0, "pos": p.position, "chain": PackedInt32Array()})
		"buff":
			for t in _allies_around(p, s):
				apply_buff(t, s["buff"], p)
		"heal":
			for t in _allies_around(p, s):
				_heal(p, t, s)
		"summon":
			server.summons.summon(p, s)
	return Result.OK


## Quem lança e, se a magia é de grupo, os membros vivos do grupo por perto (mesma região).
func _allies_around(p: ServerPlayer, s: Dictionary) -> Array[ServerPlayer]:
	var out: Array[ServerPlayer] = [p]
	if str(s["kind"]) == "heal" or bool(s.get("party", false)):
		for m: ServerPlayer in server.party.members_of(p):
			if m != p and m.alive and m.region_id == p.region_id and m.position.distance_to(p.position) <= float(s.get("radius_m", 0.0)):
				out.append(m)
	return out


## Bônus temporário: o mesmo id renova a duração (não acumula).
func apply_buff(t: ServerPlayer, buff: Dictionary, caster: ServerPlayer) -> void:
	t.buffs[str(buff["id"])] = {"name": str(buff["name"]), "until": server.now + float(buff["duration_s"]), "stats": buff["stats"]}
	server.recompute(t)
	server.send_buffs(t)
	if t != caster:
		server.send_message(t.peer_id, "%s lançou %s em você." % [caster.char_name, buff["name"]])


func _heal(caster: ServerPlayer, t: ServerPlayer, s: Dictionary) -> void:
	var d := caster.derived
	var roll := server.rng.randf_range(float(d.get("magic_min", 1.0)), float(d.get("magic_max", 1.0)))
	var amount := minf(roll * float(s.get("heal_mult", 1.0)) + float(s.get("heal_bonus", 0.0)), t.hp_max - t.hp)
	if amount <= 0.0:
		return
	t.hp += amount
	server.broadcast_near(server.region_of(t), t.position, &"rpc_damage_event", [t.id, roundi(amount), Protocol.DMG_HEAL])


## Magia num jogador: só as de alvo único (projétil e corpo a corpo); as regras ficam no PvpSystem.
func _try_cast_on_player(p: ServerPlayer, index: int, s: Dictionary, region: RegionInstance, target: ServerPlayer) -> Result:
	if not str(s["kind"]) in SINGLE_TARGET_KINDS:
		p.cast_error = "Essa magia não atinge jogadores."
		return Result.PVP_DENIED
	var err := server.pvp.can_attack(p, target)
	if err != "":
		p.cast_error = err
		return Result.PVP_DENIED
	if p.position.distance_to(target.position) > float(s["range_m"]) + float(server.combat_cfg["range_tolerance_m"]):
		return Result.OUT_OF_RANGE
	var r := _pay(p, index, s)
	if r != Result.OK:
		return r
	p.face(target.position)
	p.stop()
	var at := server.now + (float(s.get("cast_delay_s", 0.0)) if str(s["kind"]) == "melee"
		else p.position.distance_to(target.position) / maxf(1.0, float(s.get("projectile_speed_mps", 20.0))))
	_pending.append({"at": at, "region": region, "caster_id": p.id, "spell": s, "target_id": target.id, "pos": target.position, "chain": PackedInt32Array()})
	server.broadcast_cast(p, index, target.id, target.position, PackedInt32Array())
	return Result.OK


func update(dt: float = 0.0) -> void:
	var i := 0
	while i < _pending.size():
		var hit := _pending[i]
		if float(hit["at"]) > server.now:
			i += 1
			continue
		_pending.remove_at(i)
		_resolve(hit)
	_buff_timer += dt
	if _buff_timer >= 0.5: # bônus vencidos
		_buff_timer = 0.0
		for p: ServerPlayer in server.players.values():
			var expired := false
			for id: String in p.buffs.keys():
				if float(p.buffs[id]["until"]) <= server.now:
					p.buffs.erase(id)
					expired = true
			if expired:
				server.recompute(p)
				server.send_buffs(p)


func _resolve(hit: Dictionary) -> void:
	var caster: ServerPlayer = server.players.get(int(hit["caster_id"]))
	if caster == null:
		return
	var s: Dictionary = hit["spell"]
	var monsters: MonsterSystem = (hit["region"] as RegionInstance).monsters
	if server.region_of(caster) != hit["region"]:
		return # trocou de região antes do acerto
	match str(s["kind"]):
		"projectile", "melee":
			if int(hit["target_id"]) > 0:
				var tp: ServerPlayer = server.players.get(int(hit["target_id"]))
				if tp != null and server.pvp.can_attack(caster, tp) == "":
					_damage_player(caster, tp, s)
				return
			var t: ServerMonster = monsters.get_alive(int(hit["target_id"]))
			if t != null:
				_damage(caster, t, s, 1.0)
		"area", "nova":
			var radius := float(s.get("radius_m", 0.0))
			for m: ServerMonster in monsters.alive_in_radius(hit["pos"], radius):
				_damage(caster, m, s, 1.0)
		"chain":
			var scale := 1.0
			var t0: ServerMonster = monsters.get_alive(int(hit["target_id"]))
			if t0 != null:
				_damage(caster, t0, s, scale)
			for id in hit["chain"]:
				scale *= float(s.get("chain_falloff", 1.0))
				var t: ServerMonster = monsters.get_alive(id)
				if t != null:
					_damage(caster, t, s, scale)


func _damage(caster: ServerPlayer, target: ServerMonster, s: Dictionary, scale: float) -> void:
	var d := caster.derived
	var r := CombatRules.roll(float(d.get("magic_min", 1.0)), float(d.get("magic_max", 1.0)),
		float(s["damage_mult"]) * scale, float(s["damage_bonus"]) * scale, target.defense(), server.combat_cfg, server.rng,
		float(d.get("crit_chance", 0.0)), float(d.get("excellent_chance", 0.0)))
	var amount := roundi(r.x * (1.0 + float(d.get("damage_pct", 0.0))))
	server.damage_monster(caster, target, maxi(1, amount), r.y)


func _damage_player(caster: ServerPlayer, target: ServerPlayer, s: Dictionary) -> void:
	var d := caster.derived
	var r := CombatRules.roll(float(d.get("magic_min", 1.0)), float(d.get("magic_max", 1.0)),
		float(s["damage_mult"]), float(s["damage_bonus"]), float(target.derived.get("defense", 0.0)), server.combat_cfg, server.rng,
		float(d.get("crit_chance", 0.0)), float(d.get("excellent_chance", 0.0)))
	var amount := roundi(r.x * (1.0 + float(d.get("damage_pct", 0.0))) * float(server.pvp.cfg["damage_mult"]))
	server.damage_player_by_player(caster, target, maxi(1, amount), r.y)


## Saltos da corrente: o monstro vivo mais próximo ainda não atingido, a partir do último.
func _chain_targets(first: ServerMonster, count: int, jump_range: float) -> PackedInt32Array:
	var monsters := first.region.monsters
	var out := PackedInt32Array()
	var hit := {first.id: true}
	var from := first.position
	for i in count:
		var best: ServerMonster = null
		var best_d := jump_range
		for m: ServerMonster in monsters.alive_in_radius(from, jump_range):
			if hit.has(m.id):
				continue
			var d := from.distance_to(m.position)
			if d <= best_d:
				best_d = d
				best = m
		if best == null:
			break
		hit[best.id] = true
		out.append(best.id)
		from = best.position
	return out
