class_name SiegeEvent
extends RefCounted
## Cerco ao Castelo (uma instância): a dona do castelo defende (nasce na sala atrás do trono),
## as inscritas atacam (nascem no acampamento). O portão da muralha cai para os atacantes
## (a dona não fere o próprio portão). Uma guilda toma o trono ficando sozinha perto dele por
## capture_s segundos; quem estiver com ele no fim fica com o castelo. Quem morre volta ao
## próprio lado, sem sair do cerco. Sem dona, Guardiões do Trono protegem o salão.

var es: EventSystem
var server: GameServer
var inst: EventSystem.Instance
var cfg: Dictionary
var band: Dictionary
var tag: int
var guard_tag: int # os Guardiões do Trono (somem quando uma guilda toma o trono)
var started: bool = false
var finished: bool = false
var won: bool = false
var holder: int = 0 # guilda com o trono agora (0 = ninguém / guardiões)
var capturing: int = 0 # guilda tomando o trono
var progress: float = 0.0
var gate: ServerMonster
var gate_down: bool = false
var kills: Dictionary = {} # guild id -> mortes de jogadores
var _tick: float = 0.0


func _init(event_system: EventSystem, instance: EventSystem.Instance, event_cfg: Dictionary, band_cfg: Dictionary) -> void:
	es = event_system
	server = event_system.server
	inst = instance
	cfg = event_cfg
	band = band_cfg
	tag = es.new_tag()
	guard_tag = es.new_tag()
	holder = server.castle.owner_guild


func _region() -> RegionInstance:
	return inst.region


func _spot(key: String) -> Vector2:
	var p: Array = _region().data["spawn_points"][key]
	return Vector2(float(p[0]), float(p[1]))


func _guild_id(p: ServerPlayer) -> int:
	var g := server.guilds.guild_of(p)
	return g.id if g != null else 0


func _guild_name(gid: int) -> String:
	var g: GuildSystem.Guild = server.guilds.guilds.get(gid)
	return g.name if g != null else "Guardiões"


# ---------------------------------------------------------------- regras puras (testadas)

## Um segundo de captura: guildas presentes perto do trono -> [quem toma, progresso].
## Só avança com uma guilda sozinha que não seja a dona do trono; qualquer disputa zera.
static func capture_step(present: Array, holder_id: int, capturing_id: int, progress_s: float) -> Array:
	if present.size() != 1 or int(present[0]) == holder_id:
		return [0, 0.0]
	var g := int(present[0])
	return [g, progress_s + 1.0 if g == capturing_id else 1.0]


# ---------------------------------------------------------------- ciclo

## Ponto de chegada e de renascimento: dona do trono na sala, os outros no acampamento.
func respawn_point(p: ServerPlayer) -> Vector2:
	return _region().grid.nearest_walkable_point(_spot("defenders") if _guild_id(p) == holder and holder != 0 else _spot("attackers"))


func on_enter(p: ServerPlayer) -> void:
	var side := "defende o castelo" if _guild_id(p) == holder and holder != 0 else "ataca o castelo"
	server.send_message(p.peer_id, "%s: sua guilda %s. Fique sozinho com a sua guilda perto do trono por %d s para tomá-lo." % [cfg["name"], side, int(cfg["capture_s"])])
	send_state()


func on_leave(_p: ServerPlayer) -> void:
	pass


func start() -> void:
	started = true
	gate = _region().monsters.spawn_temporary(str(cfg["gate"]), _spot("gate"), tag)
	if holder == 0:
		var spots: Array = _region().data["spawn_points"]["guards"]
		for i in int(cfg["guards"]):
			var s: Array = spots[i % spots.size()]
			_region().monsters.spawn_temporary(str(cfg["guard"]), Vector2(float(s[0]), float(s[1])), guard_tag)
	server.announce("O cerco começou!", "%s defende o %s" % [_guild_name(holder), server.castle.cfg["name"]])
	send_state()


func can_damage_by(m: ServerMonster, p: ServerPlayer) -> bool:
	return not (m == gate and holder != 0 and _guild_id(p) == holder) # a dona não derruba o próprio portão


func update(dt: float) -> void:
	if finished or not started:
		return
	_tick += dt
	if _tick < 1.0:
		return
	_tick = 0.0
	var present: Array = []
	var throne := _spot("throne")
	for p: ServerPlayer in _region().players.values():
		if p.alive and p.position.distance_to(throne) <= float(cfg["capture_radius_m"]):
			var gid := _guild_id(p)
			if gid != 0 and not gid in present:
				present.append(gid)
	var step := capture_step(present, holder, capturing, progress)
	capturing = int(step[0])
	progress = float(step[1])
	if capturing != 0 and progress >= float(cfg["capture_s"]):
		holder = capturing
		capturing = 0
		progress = 0.0
		server.announce("O trono mudou de mãos!", "%s tomou o trono do %s" % [_guild_name(holder), server.castle.cfg["name"]])
		_region().monsters.remove_event(guard_tag)
	send_state()


func on_kill(m: ServerMonster, _killer: ServerPlayer) -> void:
	if m == gate:
		gate_down = true
		es.open_blocker(inst, "portao")
		_tell("O portão do castelo caiu!")


func on_pvp_kill(killer: ServerPlayer, victim: ServerPlayer) -> void:
	var gid := _guild_id(killer)
	kills[gid] = int(kills.get(gid, 0)) + 1
	_tell("%s (%s) derrubou %s." % [killer.char_name, _guild_name(gid), victim.char_name])


func on_altar(_p: ServerPlayer, _npc_id: String) -> void:
	pass


func finish(_victory: bool, _who: ServerPlayer = null) -> void:
	if finished:
		return
	finished = true
	won = holder != 0
	var before := server.castle.owner_guild
	server.castle.set_owner(holder)
	_region().monsters.remove_event(tag)
	_region().monsters.remove_event(guard_tag)
	if holder != 0:
		server.announce("%s conquistou o castelo!" % _guild_name(holder) if holder != before else "%s defendeu o castelo!" % _guild_name(holder),
			"%s fica com o %s e cobra os impostos até o próximo cerco" % [_guild_name(holder), server.castle.cfg["name"]])
		for p: ServerPlayer in _region().players.values():
			if _guild_id(p) == holder:
				var xp := int(cfg["winner_xp_per_level"]) * p.level
				server.give_xp(p, xp)
				var got := PackedStringArray()
				for base: String in cfg["winner_items"]:
					var item := server.factory.create(base)
					if not server.inventory.give(p, item):
						_region().drops.spawn_item(item, p.position, p.peer_id, 120.0)
					got.append(server.catalog.display_name(item))
				server.send_inventory(p)
				server.send_message(p.peer_id, "Vitória no cerco: %d de XP e %s." % [xp, ", ".join(got)])
	else:
		server.announce("O cerco terminou", "ninguém tomou o trono do %s" % server.castle.cfg["name"])
	send_state()
	print("[evento] cerco: trono com %s (antes %s), mortes %s" % [_guild_name(holder), _guild_name(before), kills])


func cleanup() -> void:
	_region().monsters.remove_event(tag)
	_region().monsters.remove_event(guard_tag)


## Debug (GM "event cerco skip"): o portão fica com 5% da vida.
func gm_skip() -> void:
	if gate != null and gate.alive:
		gate.hp = gate.hp_max * 0.05


func _tell(text: String) -> void:
	for p: ServerPlayer in _region().players.values():
		server.send_message(p.peer_id, text)


func send_state() -> void:
	var r: EventSystem.Run = es.runs[inst.event_id]
	var t := es.now()
	var left := ceili(r.start_at - t) if r.state == EventSystem.State.OPEN else (ceili(r.ends_at - t) if r.state == EventSystem.State.RUNNING else 0)
	var line := "Aguardando a largada"
	if finished:
		line = ("Castelo de %s!" % _guild_name(holder)) if holder != 0 else "Ninguém tomou o trono"
	elif started:
		line = "Trono: %s · portão %s" % [_guild_name(holder), "derrubado" if gate_down else "de pé"]
	var extra := ("Tomando o trono: %s %d/%d s" % [_guild_name(capturing), roundi(progress), int(cfg["capture_s"])]) if capturing != 0 else ""
	var throne := _spot("throne")
	for p: ServerPlayer in _region().players.values():
		var mine := extra
		if mine == "" and started and not finished:
			mine = "Sua guilda defende o trono" if _guild_id(p) == holder and holder != 0 else "Leve a sua guilda ao trono"
		Net.send_to(p.peer_id, &"rpc_event_state", [{"title": str(cfg["name"]), "line": line, "extra": mine,
			"left_s": maxi(0, left), "waiting": not started, "done": finished, "won": won,
			"ring": [throne.x, throne.y, float(cfg["capture_radius_m"])]}])
