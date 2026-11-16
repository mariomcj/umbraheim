class_name ArenaEvent
extends RefCounted
## Arena das Ondas (uma instância, uma faixa): ondas de monstros em sequência, a última com
## o campeão. Cada morte vale os event_points do monstro para quem matou. No fim (todas as
## ondas vencidas ou o tempo acabou), ranking: XP e Óbolos por ponto e itens para o pódio.

var es: EventSystem
var server: GameServer
var inst: EventSystem.Instance
var cfg: Dictionary
var band: Dictionary
var tag: int
var wave: int = 0 # quantas ondas já vieram
var wave_active: bool = false
var wave_started_at: float = 0.0
var next_wave_at: float = INF
var started: bool = false
var finished: bool = false
var won: bool = false
var points: Dictionary = {} # peer_id -> pontos
var names: Dictionary = {} # peer_id -> nome (quem pontuou, mesmo que tenha saído)
var podium: Array = [] # [[nome, pontos], ...] no fim
var _state_timer: float = 0.0


func _init(event_system: EventSystem, instance: EventSystem.Instance, event_cfg: Dictionary, band_cfg: Dictionary) -> void:
	es = event_system
	server = event_system.server
	inst = instance
	cfg = event_cfg
	band = band_cfg
	tag = es.new_tag()


func _region() -> RegionInstance:
	return inst.region


# ---------------------------------------------------------------- regras puras (testadas)

## Ranking: [[peer_id, pontos], ...] do maior para o menor (empate: quem entrou antes).
static func ranking(pts: Dictionary) -> Array:
	var out: Array = []
	for peer_id: int in pts:
		out.append([peer_id, int(pts[peer_id])])
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	return out


# ---------------------------------------------------------------- ciclo

func on_enter(p: ServerPlayer) -> void:
	server.send_message(p.peer_id, "Você está na antessala da %s. A grade abre na largada; cada monstro vale pontos." % cfg["name"])
	send_state()


func on_leave(_p: ServerPlayer) -> void:
	pass


func start() -> void:
	started = true
	es.open_blocker(inst, "grade")
	next_wave_at = server.now + 3.0
	_tell("A grade se abriu! A primeira onda vem aí.")
	send_state()


func update(dt: float) -> void:
	if finished or not started:
		return
	var waves: Array = cfg["waves"]
	if wave_active and _region().monsters.count_event(tag) == 0:
		wave_active = false
		if wave >= waves.size():
			won = true
			_tell("Todas as ondas foram vencidas!")
			finish(true)
			return
		next_wave_at = server.now + float(cfg["wave_gap_s"])
		_tell("Onda %d vencida! A próxima vem em %d s." % [wave, int(cfg["wave_gap_s"])])
	elif wave_active and wave < waves.size() and server.now - wave_started_at >= float(cfg["wave_max_s"]):
		next_wave_at = server.now # demorou demais: a próxima chega por cima
	if wave < waves.size() and server.now >= next_wave_at:
		_spawn_wave(waves[wave])
	_state_timer += dt
	if _state_timer >= 1.0:
		_state_timer = 0.0
		send_state()


func _spawn_wave(w: Dictionary) -> void:
	wave += 1
	wave_active = true
	wave_started_at = server.now
	next_wave_at = INF
	var spots: Array = _region().data["spawn_points"]["waves"]
	var monsters: Array = band["monsters"]
	for i in int(w["count"]):
		var p: Array = spots[i % spots.size()]
		var off := Vector2(server.rng.randf_range(-1.5, 1.5), server.rng.randf_range(-1.5, 1.5))
		_region().monsters.spawn_temporary(str(monsters[clampi(int(w["monster"]), 0, monsters.size() - 1)]), Vector2(float(p[0]), float(p[1])) + off, tag)
	if bool(w.get("boss", false)):
		var b: Array = _region().data["spawn_points"]["boss"]
		var boss := _region().monsters.spawn_temporary(str(band["boss"]), Vector2(float(b[0]), float(b[1])), tag)
		_tell("Onda %d: %s entra na arena!" % [wave, boss.def["name"]])
	else:
		_tell("Onda %d de %d!" % [wave, (cfg["waves"] as Array).size()])
	send_state()


func on_kill(m: ServerMonster, killer: ServerPlayer) -> void:
	if m.event_id != tag or finished:
		return
	points[killer.peer_id] = int(points.get(killer.peer_id, 0)) + int(m.def.get("event_points", 1))
	names[killer.peer_id] = killer.char_name


func on_altar(_p: ServerPlayer, _npc_id: String) -> void:
	pass


func finish(victory: bool, _who: ServerPlayer = null) -> void:
	if finished:
		return
	finished = true
	won = victory
	_region().monsters.remove_event(tag)
	var rank := ranking(points)
	var rank_items: Array = cfg["rank_items"]
	var top := PackedStringArray()
	for i in rank.size():
		var peer_id := int(rank[i][0])
		var pts := int(rank[i][1])
		podium.append([str(names.get(peer_id, "?")), pts])
		if i < 3:
			top.append("%dº %s (%d)" % [i + 1, names.get(peer_id, "?"), pts])
		var p: ServerPlayer = server.players.get(peer_id)
		if p == null or pts <= 0:
			continue
		var xp := int(band["xp_per_point"]) * pts
		var cur := int(band["currency_per_point"]) * pts
		server.give_xp(p, xp)
		p.currency += cur
		var got := PackedStringArray()
		if i < rank_items.size():
			for base: String in rank_items[i]:
				var item := server.factory.create(base)
				if not server.inventory.give(p, item):
					server.region_of(p).drops.spawn_item(item, p.position, p.peer_id, 120.0)
				got.append(server.catalog.display_name(item))
		server.send_inventory(p)
		server.send_message(p.peer_id, "Arena: %dº lugar com %d pontos. Recompensa: %d de XP, %d Óbolos%s." % [i + 1, pts, xp, cur,
			(" e " + ", ".join(got)) if not got.is_empty() else ""])
	if not top.is_empty():
		server.announce("%s: %s" % [cfg["name"], "todas as ondas vencidas!" if victory else "fim do tempo"], " · ".join(top))
	else:
		_tell("Ninguém pontuou na arena.")
	send_state()
	print("[evento] %s: %s, %d onda(s), ranking %s" % [_region().id, "vitória" if victory else "fim do tempo", wave, podium])


func cleanup() -> void:
	_region().monsters.remove_event(tag)


func gm_skip() -> void:
	# acaba a onda atual na hora (os monstros somem); na última, a arena é vencida
	_region().monsters.remove_event(tag)
	if not wave_active:
		next_wave_at = server.now


func _tell(text: String) -> void:
	for p: ServerPlayer in _region().players.values():
		server.send_message(p.peer_id, text)


## Painel: onda, monstros restantes, os seus pontos e o líder (cada jogador recebe o seu).
func send_state() -> void:
	var r: EventSystem.Run = es.runs[inst.event_id]
	var t := es.now()
	var left := ceili(r.start_at - t) if r.state == EventSystem.State.OPEN else (ceili(r.ends_at - t) if r.state == EventSystem.State.RUNNING else 0)
	var waves := (cfg["waves"] as Array).size()
	var line := "Aguardando a largada"
	if finished:
		line = "Todas as ondas vencidas!" if won else "Fim do tempo"
	elif started:
		line = ("Onda %d/%d · restam %d" % [wave, waves, _region().monsters.count_event(tag)]) if wave_active \
			else ("Próxima onda em %d s" % maxi(0, ceili(next_wave_at - server.now)) if next_wave_at < INF else "")
	var rank := ranking(points)
	var leader := "%s (%d)" % [names.get(int(rank[0][0]), "?"), int(rank[0][1])] if not rank.is_empty() else "ninguém"
	for p: ServerPlayer in _region().players.values():
		var mine := int(points.get(p.peer_id, 0))
		var extra := "Seus pontos: %d · 1º %s" % [mine, leader]
		if finished and not podium.is_empty():
			var parts := PackedStringArray()
			for i in mini(3, podium.size()):
				parts.append("%dº %s %d" % [i + 1, podium[i][0], int(podium[i][1])])
			extra = " · ".join(parts)
		Net.send_to(p.peer_id, &"rpc_event_state", [{"title": str(cfg["name"]), "line": line, "extra": extra,
			"left_s": maxi(0, left), "waiting": not started, "done": finished, "won": won}])
