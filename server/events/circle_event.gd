class_name CircleEvent
extends RefCounted
## Círculo que Encolhe (uma instância, uma faixa): todos contra todos, sem infâmia; o
## equipamento e as poções de fora não valem aqui (no_items). O anel encolhe com o tempo e
## quem está fora perde vida a cada segundo. Vence o último de pé (ou, no fim do tempo, quem
## tiver mais pontos entre os vivos). Sem min_players na largada, é cancelado e o ingresso volta.

var es: EventSystem
var server: GameServer
var inst: EventSystem.Instance
var cfg: Dictionary
var band: Dictionary
var tag: int
var started: bool = false
var started_at: float = 0.0
var finished: bool = false
var won: bool = false
var cancelled: bool = false
var winner: String = ""
var fighters: Dictionary = {} # peer_id -> nome (quem largou)
var points: Dictionary = {} # peer_id -> pontos
var radius: float = 0.0
var _tick: float = 0.0


func _init(event_system: EventSystem, instance: EventSystem.Instance, event_cfg: Dictionary, band_cfg: Dictionary) -> void:
	es = event_system
	server = event_system.server
	inst = instance
	cfg = event_cfg
	band = band_cfg
	tag = es.new_tag()
	radius = float(cfg["ring"]["start_radius"])


func _region() -> RegionInstance:
	return inst.region


func _center() -> Vector2:
	var c: Array = cfg["ring"]["center"]
	return Vector2(float(c[0]), float(c[1]))


# ---------------------------------------------------------------- regras puras (testadas)

## Raio do anel `t` segundos depois da largada.
static func radius_at(t: float, ring: Dictionary) -> float:
	var a := float(ring["shrink_start_s"])
	var b := float(ring["shrink_end_s"])
	var k := clampf((t - a) / maxf(0.01, b - a), 0.0, 1.0)
	return lerpf(float(ring["start_radius"]), float(ring["end_radius"]), k)


# ---------------------------------------------------------------- ciclo

func on_enter(p: ServerPlayer) -> void:
	p.ignore_equipment = true
	server.recompute(p)
	server.send_message(p.peer_id, "Você está no %s. Aqui o equipamento e as poções de fora não valem: só os seus atributos e magias. Todos contra todos." % cfg["name"])
	send_state()


func on_leave(p: ServerPlayer) -> void:
	if p.ignore_equipment:
		p.ignore_equipment = false
		server.recompute(p)
	if started and not finished and fighters.has(p.peer_id):
		_tell("%s está fora do Círculo." % p.char_name)


func start() -> void:
	if _region().players.size() < int(cfg["min_players"]):
		cancelled = true
		for p: ServerPlayer in _region().players.values():
			var ticket := server.factory.create(str(cfg["ticket"]))
			if server.inventory.give(p, ticket):
				server.send_inventory(p)
			server.send_message(p.peer_id, "%s precisa de pelo menos %d lutadores: cancelado, o ingresso voltou para você." % [cfg["name"], int(cfg["min_players"])])
		finished = true
		send_state()
		print("[evento] %s cancelado (%d jogador(es))" % [_region().id, _region().players.size()])
		return
	started = true
	started_at = server.now
	for p: ServerPlayer in _region().players.values():
		fighters[p.peer_id] = p.char_name
	es.open_blocker(inst, "grade")
	var spots: Array = _region().data["spawn_points"]["guards"]
	for i in int(cfg["guards"]):
		var s: Array = spots[i % spots.size()]
		_region().monsters.spawn_temporary(str(band["guard"]), Vector2(float(s[0]), float(s[1])), tag)
	_tell("A grade se abriu! O anel começa a fechar em %d s. Vence o último de pé." % int(cfg["ring"]["shrink_start_s"]))
	send_state()


func update(dt: float) -> void:
	if finished or not started:
		return
	radius = radius_at(server.now - started_at, cfg["ring"])
	_tick += dt
	if _tick < 1.0:
		return
	_tick = 0.0
	var alive: Array[ServerPlayer] = []
	for p: ServerPlayer in _region().players.values():
		if not p.alive or not fighters.has(p.peer_id):
			continue
		if p.position.distance_to(_center()) > radius: # fora do anel: até a antessala queima
			server.damage_player_env(p, maxi(1, roundi(p.hp_max * float(cfg["ring"]["damage_pct_s"]))), "o anel do Círculo")
		if p.alive:
			alive.append(p)
	if alive.size() <= 1:
		finish(alive.size() == 1, alive[0] if alive.size() == 1 else null)
		return
	send_state()


func on_kill(m: ServerMonster, killer: ServerPlayer) -> void:
	if m.event_id != tag or finished:
		return
	points[killer.peer_id] = int(points.get(killer.peer_id, 0)) + int(cfg["guard_points"])


## Um jogador derrubou outro aqui dentro (PvP livre).
func on_pvp_kill(killer: ServerPlayer, victim: ServerPlayer) -> void:
	if finished:
		return
	points[killer.peer_id] = int(points.get(killer.peer_id, 0)) + int(cfg["player_points"])
	_tell("%s derrubou %s." % [killer.char_name, victim.char_name])


func on_altar(_p: ServerPlayer, _npc_id: String) -> void:
	pass


## Fim: vitória com um último de pé; no fim do tempo, quem tem mais pontos entre os vivos.
func finish(victory: bool, who: ServerPlayer = null) -> void:
	if finished:
		return
	finished = true
	if who == null and not victory and started:
		var best := -1
		for p: ServerPlayer in _region().players.values():
			if p.alive and fighters.has(p.peer_id) and int(points.get(p.peer_id, 0)) > best:
				best = int(points.get(p.peer_id, 0))
				who = p
	won = who != null
	_region().monsters.remove_event(tag)
	for peer_id: int in fighters:
		var p: ServerPlayer = server.players.get(peer_id)
		if p == null:
			continue
		var pts := int(points.get(peer_id, 0))
		var xp := int(cfg["points_xp_per_level"]) * pts * p.level
		var cur := 0
		var got := PackedStringArray()
		if p == who:
			xp += int(band["xp_per_level"]) * p.level
			cur = int(band["currency"])
			for base: String in cfg["winner_items"]:
				var item := server.factory.create(base)
				if not server.inventory.give(p, item):
					server.region_of(p).drops.spawn_item(item, p.position, p.peer_id, 120.0)
				got.append(server.catalog.display_name(item))
		if xp <= 0:
			continue
		server.give_xp(p, xp)
		p.currency += cur
		server.send_inventory(p)
		server.send_message(p.peer_id, "Círculo: %s %d ponto(s). Recompensa: %d de XP%s%s." % ["você venceu com" if p == who else "você fez",
			pts, xp, (", %d Óbolos" % cur) if cur > 0 else "", (" e " + ", ".join(got)) if not got.is_empty() else ""])
	if who != null:
		winner = who.char_name
		server.announce("%s: vitória de %s" % [cfg["name"], who.char_name], "o último de pé, com %d ponto(s)" % int(points.get(who.peer_id, 0)))
	else:
		_tell("Ninguém ficou de pé no Círculo.")
	send_state()
	print("[evento] %s: vencedor %s, pontos %s" % [_region().id, winner if winner != "" else "nenhum", points])


func cleanup() -> void:
	_region().monsters.remove_event(tag)


## Debug (GM "event circulo skip"): o anel fecha de vez (raio final na hora).
func gm_skip() -> void:
	if started:
		started_at = server.now - float(cfg["ring"]["shrink_end_s"])


func _tell(text: String) -> void:
	for p: ServerPlayer in _region().players.values():
		server.send_message(p.peer_id, text)


func send_state() -> void:
	var r: EventSystem.Run = es.runs[inst.event_id]
	var t := es.now()
	var left := ceili(r.start_at - t) if r.state == EventSystem.State.OPEN else (ceili(r.ends_at - t) if r.state == EventSystem.State.RUNNING else 0)
	var alive := 0
	for p: ServerPlayer in _region().players.values():
		if p.alive and fighters.has(p.peer_id):
			alive += 1
	var line := "Aguardando a largada"
	if cancelled:
		line = "Cancelado: lutadores de menos"
	elif finished:
		line = ("Vitória de %s!" % winner) if winner != "" else "Ninguém ficou de pé"
	elif started:
		line = "De pé: %d · anel de %d m" % [alive, roundi(radius)]
	var c := _center()
	for p: ServerPlayer in _region().players.values():
		var extra := "Seus pontos: %d" % int(points.get(p.peer_id, 0))
		if started and not finished and p.position.distance_to(c) > radius:
			extra = "FORA DO ANEL: volte para o centro!"
		Net.send_to(p.peer_id, &"rpc_event_state", [{"title": str(cfg["name"]), "line": line, "extra": extra,
			"left_s": maxi(0, left), "waiting": not started, "done": finished, "won": won,
			"ring": [c.x, c.y, radius]}])
