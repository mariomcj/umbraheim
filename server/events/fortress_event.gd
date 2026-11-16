class_name FortressEvent
extends RefCounted
## Fortaleza Sitiada (uma instância, uma faixa de nível):
## 1. a grade da antessala abre na largada; o pátio enche de sentinelas (sempre courtyard_alive vivas);
## 2. com gate_kills mortes, o portão fica vulnerável; derrubado, abre o salão (sentinelas + chefe);
## 3. o chefe deixa a relíquia com quem mais o feriu; entregá-la no altar vence o evento.
## Recompensa para todos que estão dentro; quem entrega ganha itens a mais.

var es: EventSystem
var server: GameServer
var inst: EventSystem.Instance
var cfg: Dictionary
var band: Dictionary
var tag: int
var stage: int = 0 # 0 esperando, 1 pátio, 2 salão, 3 vencido, -1 derrotado
var kills: int = 0
var gate: ServerMonster
var boss: ServerMonster
var relic_holder: String = ""
var finished: bool = false
var won: bool = false
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


func _spot(key: String) -> Vector2:
	var p: Array = _region().data["spawn_points"][key]
	return Vector2(float(p[0]), float(p[1]))


func _spots(key: String) -> Array:
	return _region().data["spawn_points"][key]


func on_enter(p: ServerPlayer) -> void:
	server.send_message(p.peer_id, "Você está na antessala de %s. A grade se abre quando o evento começar." % cfg["name"])
	send_state()


func on_leave(p: ServerPlayer) -> void:
	_take_relic(p)


func start() -> void:
	stage = 1
	es.open_blocker(inst, "grade")
	for i in int(cfg["courtyard_alive"]):
		_spawn_courtyard(i)
	gate = _region().monsters.spawn_temporary(str(band["gate"]), _spot("gate"), tag)
	gate.invulnerable = true
	_tell("A grade se abriu! Derrubem %d sentinelas para enfraquecer o portão." % int(cfg["gate_kills"]))
	send_state()


func _spawn_courtyard(i: int) -> void:
	var spots := _spots("courtyard")
	var p: Array = spots[(i + kills) % spots.size()]
	_region().monsters.spawn_temporary(str(band["monster"]), Vector2(float(p[0]), float(p[1])), tag)


func update(dt: float) -> void:
	_state_timer += dt
	if _state_timer >= 1.0:
		_state_timer = 0.0
		send_state()


func on_kill(m: ServerMonster, killer: ServerPlayer) -> void:
	if finished or m.event_id != tag:
		return
	if m == gate:
		stage = 2
		es.open_blocker(inst, "portao")
		for p: Array in _spots("hall"):
			_region().monsters.spawn_temporary(str(band["monster"]), Vector2(float(p[0]), float(p[1])), tag)
		boss = _region().monsters.spawn_temporary(str(band["boss"]), _spot("boss"), tag)
		_tell("O portão caiu! %s desperta no salão." % boss.def["name"])
	elif m == boss:
		var holder: ServerPlayer = server.players.get(m.top_damager())
		if holder == null or server.region_of(holder) != _region():
			holder = killer
		var relic := server.factory.create(str(cfg["relic"]))
		if not server.inventory.give(holder, relic):
			_region().drops.spawn_item(relic, holder.position, holder.peer_id, 120.0)
		server.send_inventory(holder)
		relic_holder = holder.char_name
		_tell("%s tomou a %s! Leve-a ao Altar do Guardião." % [holder.char_name, server.catalog.display_name(relic)])
	elif stage == 1:
		kills += 1
		if kills >= int(cfg["gate_kills"]) and gate.invulnerable:
			gate.invulnerable = false
			_tell("As runas do portão se apagam: ataquem o portão!")
		_spawn_courtyard(kills)
	send_state()


func on_altar(p: ServerPlayer, _npc_id: String) -> void:
	if finished:
		return
	if stage < 2 or _relic_uid(p) == 0:
		server.send_message(p.peer_id, "O altar espera a relíquia do Guardião.")
		return
	server.inventory.consume_one(p, _relic_uid(p))
	server.send_inventory(p)
	stage = 3
	server.announce("A Fortaleza caiu!", "%s entregou a relíquia ao Altar do Guardião" % p.char_name)
	finish(true, p)


func finish(victory: bool, deliverer: ServerPlayer = null) -> void:
	if finished:
		return
	finished = true
	won = victory
	if not victory:
		stage = -1
		_tell("O tempo acabou: a Fortaleza resistiu.")
	for p: ServerPlayer in _region().players.values():
		_take_relic(p)
		if victory:
			_reward(p, p == deliverer)
	_region().monsters.remove_event(tag)
	send_state()
	print("[evento] %s: %s (%d jogador(es), %d sentinelas)" % [_region().id, "vitória" if victory else "derrota", _region().players.size(), kills])


func _reward(p: ServerPlayer, deliverer: bool) -> void:
	var xp := int(band["xp_per_level"]) * p.level
	server.give_xp(p, xp)
	p.currency += int(band["currency"])
	var got := PackedStringArray()
	var items: Array = cfg["reward_items"] + (cfg["deliverer_items"] if deliverer else [])
	for base: String in items:
		var item := server.factory.create(base)
		if not server.inventory.give(p, item):
			_region().drops.spawn_item(item, p.position, p.peer_id, 120.0)
		got.append(server.catalog.display_name(item))
	server.send_inventory(p)
	server.send_message(p.peer_id, "Recompensa: %d de XP, %d Óbolos e %s." % [xp, int(band["currency"]), ", ".join(got)])


## Debug (GM "event <id> skip"): adianta a etapa atual (a contagem do pátio, ou deixa o portão
## e o chefe com 10% da vida). Ainda é preciso derrubá-los.
func gm_skip() -> void:
	if stage == 1:
		kills = int(cfg["gate_kills"])
		gate.invulnerable = false
		gate.hp = gate.hp_max * 0.1
		_tell("(GM) O portão está vulnerável.")
	elif stage == 2 and boss != null and boss.alive:
		boss.hp = boss.hp_max * 0.1
	send_state()


func cleanup() -> void:
	_region().monsters.remove_event(tag)


func _take_relic(p: ServerPlayer) -> void:
	var uid := _relic_uid(p)
	while uid != 0:
		server.inventory.take(p, uid)
		uid = _relic_uid(p)
	server.send_inventory(p)


func _relic_uid(p: ServerPlayer) -> int:
	for item: Dictionary in p.items.values():
		if str(item["base"]) == str(cfg["relic"]):
			return int(item["uid"])
	return 0


func _tell(text: String) -> void:
	for p: ServerPlayer in _region().players.values():
		server.send_message(p.peer_id, text)


## Painel do evento no cliente.
func send_state() -> void:
	var r: EventSystem.Run = es.runs[inst.event_id]
	var left := 0
	var t := es.now()
	if r.state == EventSystem.State.OPEN:
		left = ceili(r.start_at - t)
	elif r.state == EventSystem.State.RUNNING:
		left = ceili(r.ends_at - t)
	var line := ""
	match stage:
		0:
			line = "Aguardando a largada"
		1:
			line = "Sentinelas: %d/%d" % [mini(kills, int(cfg["gate_kills"])), int(cfg["gate_kills"])] if gate == null or gate.invulnerable else "Derrubem o portão!"
		2:
			line = ("Relíquia com %s: leve ao altar" % relic_holder) if relic_holder != "" else "Vençam o Guardião"
		3:
			line = "Vitória!"
		-1:
			line = "A Fortaleza resistiu"
	var state := {"title": str(cfg["name"]), "line": line, "left_s": maxi(0, left), "waiting": stage == 0, "done": finished, "won": won}
	Net.broadcast(_region().peers(), &"rpc_event_state", [state])
