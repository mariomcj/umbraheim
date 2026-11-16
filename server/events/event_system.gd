class_name EventSystem
extends RefCounted
## Eventos com horário (data/scheduled_events.json). Cada evento segue um ciclo pelo
## relógio do servidor (UTC): parado -> portões abertos (entra quem usa o ingresso) ->
## em andamento -> resultado -> todos de volta à cidade. Cada faixa de nível ganha a
## sua instância: uma cópia da região do evento (id "<região>@<faixa>"), criada quando
## o primeiro jogador da faixa entra e destruída no fim.

enum State { IDLE, OPEN, RUNNING, ENDING }

class Instance:
	var event_id: String
	var band: int
	var region: RegionInstance
	var logic: RefCounted # FortressEvent (ou outra lógica de evento)
	var entrants: Dictionary = {} # peer_id -> nome (quem entrou)
	var opened: PackedStringArray = [] # bloqueios já abertos (grade, portão)


class Run:
	var state: State = State.IDLE
	var start_at: float = 0.0 # relógio (s, UTC) do começo
	var ends_at: float = 0.0
	var linger_until: float = 0.0
	var reminded: Dictionary = {}
	var instances: Dictionary = {} # faixa -> Instance


var server: GameServer
var cfg: Dictionary
var events: Dictionary
var runs: Dictionary = {} # event_id -> Run
var clock_offset: float = 0.0 # debug (GM): adianta o relógio dos eventos
var _announce_timer: float = 0.0
var _next_tag: int = 1000


func _init(game_server: GameServer, table: Dictionary) -> void:
	server = game_server
	cfg = table
	events = table["events"]
	for id: String in events:
		var r := Run.new()
		r.start_at = next_start(now(), int(events[id]["every_min"]), int(events[id]["at_min"]), float(events[id]["entry_s"]))
		runs[id] = r


func now() -> float:
	return Time.get_unix_time_from_system() + clock_offset


## Próximo começo (s, UTC) de um evento a cada every_min minutos, no minuto at_min do ciclo,
## cujos portões (entry_s antes) ainda não abriram. Função pura, testada.
static func next_start(t: float, every_min: int, at_min: int, entry_s: float) -> float:
	var period := every_min * 60.0
	var offset := fposmod(at_min * 60.0, period)
	var k := floorf((t + entry_s - offset) / period) + 1.0
	return k * period + offset


## Faixa de nível do jogador (índice em bands) ou -1.
static func band_for(level: int, bands: Array) -> int:
	for i in bands.size():
		if level >= int(bands[i]["min_level"]) and level <= int(bands[i]["max_level"]):
			return i
	return -1


func new_tag() -> int:
	_next_tag += 1
	return _next_tag


# ---------------------------------------------------------------- ciclo

func update(dt: float) -> void:
	var t := now()
	for id: String in events:
		var e: Dictionary = events[id]
		var r: Run = runs[id]
		match r.state:
			State.IDLE:
				for before: float in e.get("reminder_s", []):
					if not r.reminded.has(before) and t >= r.start_at - float(e["entry_s"]) - before:
						r.reminded[before] = true
						server.announce(str(e["name"]), "Os portões abrem em %d min" % roundi(before / 60.0))
				if t >= r.start_at - float(e["entry_s"]):
					_open(id, e, r)
			State.OPEN:
				if t >= r.start_at:
					_begin(id, e, r)
			State.RUNNING:
				var all_done := true
				for inst: Instance in r.instances.values():
					if not inst.logic.finished and inst.region.players.is_empty():
						inst.logic.finish(false) # todos saíram (morreram, foram embora): derrota
					inst.logic.update(dt)
					all_done = all_done and inst.logic.finished
				if t >= r.ends_at or (all_done and not r.instances.is_empty()):
					_finish(id, e, r)
				elif r.instances.is_empty():
					_finish(id, e, r) # ninguém entrou
			State.ENDING:
				if t >= r.linger_until:
					_close(id, e, r)
	_announce_timer += dt
	if _announce_timer >= float(cfg["announce_interval_s"]):
		_announce_timer = 0.0
		Net.broadcast(server.peers(), &"rpc_event_schedule", [schedule_rows()])


func _open(id: String, e: Dictionary, r: Run) -> void:
	r.state = State.OPEN
	var lv := PackedStringArray()
	for b: Dictionary in e["bands"]:
		lv.append("%d+" % int(b["min_level"]) if int(b["max_level"]) >= 400 else "%d–%d" % [int(b["min_level"]), int(b["max_level"])])
	server.announce("Os portões estão abertos!", "%s: use o %s em até %d min (níveis %s)" % [e["name"],
		server.catalog.bases.get(str(e["ticket"]), {}).get("name", "ingresso"), roundi(float(e["entry_s"]) / 60.0), ", ".join(lv)])
	print("[evento] %s: portões abertos" % id)
	Net.broadcast(server.peers(), &"rpc_event_schedule", [schedule_rows()])


func _begin(id: String, e: Dictionary, r: Run) -> void:
	r.state = State.RUNNING
	r.ends_at = r.start_at + float(e["duration_s"])
	for inst: Instance in r.instances.values():
		inst.logic.start()
	print("[evento] %s começou com %d instância(s)" % [id, r.instances.size()])
	Net.broadcast(server.peers(), &"rpc_event_schedule", [schedule_rows()])


func _finish(id: String, e: Dictionary, r: Run) -> void:
	r.state = State.ENDING
	r.linger_until = now() + float(e["linger_s"])
	for inst: Instance in r.instances.values():
		if not inst.logic.finished:
			inst.logic.finish(false)
	print("[evento] %s terminou" % id)


func _close(id: String, e: Dictionary, r: Run) -> void:
	for inst: Instance in r.instances.values():
		inst.logic.cleanup()
		for p: ServerPlayer in inst.region.players.values():
			server.send_message(p.peer_id, "O evento acabou: de volta ao Refúgio.")
			Net.send_to(p.peer_id, &"rpc_event_state", [{}])
			var home: RegionInstance = server.regions[server.home_region]
			server.transfer_player(p, home.id, home.point("return_point"))
		server.remove_instance(inst.region)
	r.instances.clear()
	r.state = State.IDLE
	r.reminded.clear()
	r.start_at = next_start(now(), int(e["every_min"]), int(e["at_min"]), float(e["entry_s"]))
	Net.broadcast(server.peers(), &"rpc_event_schedule", [schedule_rows()])


## [[id, nome, estado, segundos até a próxima mudança], ...] para o contador do cliente.
func schedule_rows() -> Array:
	var out: Array = []
	var t := now()
	for id: String in events:
		var e: Dictionary = events[id]
		var r: Run = runs[id]
		var secs := 0.0
		match r.state:
			State.IDLE:
				secs = r.start_at - float(e["entry_s"]) - t
			State.OPEN:
				secs = r.start_at - t
			State.RUNNING:
				secs = r.ends_at - t
			State.ENDING:
				secs = r.linger_until - t
		out.append([id, str(e["name"]), int(r.state), maxi(0, ceili(secs))])
	return out


# ---------------------------------------------------------------- entrada e saída

## Ingresso usado: "" se entrou; senão o motivo (o ingresso não é gasto).
## allow_running: também durante o evento (o cerco aceita reforços).
func try_enter(p: ServerPlayer, event_id: String, allow_running: bool = false) -> String:
	var e: Dictionary = events.get(event_id, {})
	if e.is_empty():
		return "Evento desconhecido."
	var r: Run = runs[event_id]
	if r.state != State.OPEN and not (allow_running and r.state == State.RUNNING):
		return "Os portões de %s não estão abertos (veja o contador de eventos)." % e["name"]
	if instance_of(server.region_of(p)) != null:
		return "Você já está num evento."
	var band := band_for(p.level, e["bands"])
	if band < 0:
		return "Seu nível não cabe em nenhuma faixa de %s." % e["name"]
	var inst: Instance = r.instances.get(band)
	if inst == null:
		inst = _create_instance(event_id, e, band)
		r.instances[band] = inst
	if inst.region.players.size() >= int(e["max_players"]):
		return "%s está cheia nesta faixa (%d)." % [e["name"], int(e["max_players"])]
	inst.entrants[p.peer_id] = p.char_name
	var arrival: Vector2 = inst.logic.respawn_point(p) if inst.logic.has_method("respawn_point") else inst.region.point("player_spawn")
	server.transfer_player(p, inst.region.id, arrival)
	for blocker in inst.opened:
		Net.send_to(p.peer_id, &"rpc_event_world", [blocker])
	inst.logic.on_enter(p)
	print("[evento] %s entrou em %s (faixa %d)" % [p.char_name, inst.region.id, band])
	return ""


func _create_instance(event_id: String, e: Dictionary, band: int) -> Instance:
	var inst := Instance.new()
	inst.event_id = event_id
	inst.band = band
	inst.region = server.create_instance(str(e["region"]), "%s@%d" % [e["region"], band + 1])
	match str(e.get("logic", "fortress")):
		"waves":
			inst.logic = ArenaEvent.new(self, inst, e, e["bands"][band])
		"circle":
			inst.logic = CircleEvent.new(self, inst, e, e["bands"][band])
		"siege":
			inst.logic = SiegeEvent.new(self, inst, e, e["bands"][band])
		_:
			inst.logic = FortressEvent.new(self, inst, e, e["bands"][band])
	return inst


func instance_of(region: RegionInstance) -> Instance:
	if region == null or not region.data.has("event"):
		return null
	for r: Run in runs.values():
		for inst: Instance in r.instances.values():
			if inst.region == region:
				return inst
	return null


## O jogador saiu da região do evento (morreu e renasceu fora, teleportou, desconectou).
func on_left(p: ServerPlayer, region: RegionInstance) -> void:
	var inst := instance_of(region)
	if inst == null:
		return
	inst.logic.on_leave(p)
	Net.send_to(p.peer_id, &"rpc_event_state", [{}])


## Abre um bloqueio (grade, portão) para quem está na instância e para quem entrar depois.
func open_blocker(inst: Instance, blocker_id: String) -> void:
	inst.region.set_blocker(blocker_id, false)
	inst.opened.append(blocker_id)
	Net.broadcast(inst.region.peers(), &"rpc_event_world", [blocker_id])


# ---------------------------------------------------------------- ganchos do servidor

func can_damage(m: ServerMonster, caster: ServerPlayer = null) -> bool:
	if m.invulnerable:
		return false
	var inst := instance_of(m.region)
	if inst != null and caster != null and inst.logic.has_method("can_damage_by"):
		return inst.logic.can_damage_by(m, caster)
	return true


## Onde o jogador renasce dentro do evento (cerco: no próprio lado); Vector2.INF = fora do evento.
func respawn_point(p: ServerPlayer) -> Vector2:
	var inst := instance_of(server.region_of(p))
	if inst != null and inst.logic.has_method("respawn_point") and not inst.logic.finished:
		return inst.logic.respawn_point(p)
	return Vector2.INF


func on_monster_killed(m: ServerMonster, killer: ServerPlayer) -> void:
	var inst := instance_of(m.region)
	if inst != null:
		inst.logic.on_kill(m, killer)


## Morte de PvP numa região de PvP livre (Círculo): pontos, sem infâmia.
func on_pvp_kill(killer: ServerPlayer, victim: ServerPlayer) -> void:
	var inst := instance_of(server.region_of(victim))
	if inst != null and inst.logic.has_method("on_pvp_kill"):
		inst.logic.on_pvp_kill(killer, victim)


func on_altar(p: ServerPlayer, npc_id: String) -> void:
	var inst := instance_of(server.region_of(p))
	if inst != null:
		inst.logic.on_altar(p, npc_id)


## Debug (GM): event <id> open | start | skip | end.
func gm(event_id: String, what: String) -> String:
	var e: Dictionary = events.get(event_id, {})
	if e.is_empty():
		return "evento desconhecido"
	var r: Run = runs[event_id]
	match what:
		"open":
			if r.state != State.IDLE:
				return "o evento não está parado"
			r.start_at = now() + float(e["entry_s"])
		"start":
			if r.state != State.OPEN:
				return "os portões não estão abertos"
			r.start_at = now()
		"skip":
			for inst: Instance in r.instances.values():
				inst.logic.gm_skip()
		"end":
			if r.state == State.RUNNING:
				r.ends_at = now()
			elif r.state == State.ENDING:
				r.linger_until = now()
		_:
			return "use open, start, skip ou end"
	return ""
