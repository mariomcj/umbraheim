class_name InvasionSystem
extends RefCounted
## Invasões douradas (data/events.json -> invasion): de tempos em tempos (intervalo
## sorteado) uma região, escolhida por peso, recebe monstros dourados espalhados fora
## das zonas seguras. Termina quando todos morrem ("contida") ou quando o tempo acaba
## (os que sobraram somem). Avisada para todos os jogadores.

var server: GameServer
var cfg: Dictionary
var active: Dictionary = {} # {} ou {id, region_id, ends_at, spawned}
var next_at: float
var _next_event_id: int = 1
var _check_timer: float = 0.0


func _init(game_server: GameServer, events_table: Dictionary) -> void:
	server = game_server
	cfg = events_table["invasion"]
	next_at = server.now + float(cfg["first_delay_s"])


func update(dt: float) -> void:
	_check_timer += dt
	if _check_timer < 1.0:
		return
	_check_timer = 0.0
	if active.is_empty():
		if server.now >= next_at:
			start(_pick_region())
		return
	var region: RegionInstance = server.regions[active["region_id"]]
	if region.monsters.count_event(int(active["id"])) == 0:
		_finish(true)
	elif server.now >= float(active["ends_at"]):
		_finish(false)


## Começa uma invasão (também pelo GM). Retorna "" ou o motivo de não começar.
func start(region_id: String) -> String:
	if not active.is_empty():
		return "Já há uma invasão em andamento."
	var rcfg: Dictionary = cfg["regions"].get(region_id, {})
	var region: RegionInstance = server.regions.get(region_id)
	if rcfg.is_empty() or region == null:
		return "Região sem invasão configurada."
	var event_id := _next_event_id
	_next_event_id += 1
	var spots := _spawn_spots(region, int(rcfg["count"]))
	var kinds: Array = rcfg["monsters"]
	for i in spots.size():
		var base_id := str(kinds[i % kinds.size()])
		region.monsters.spawn_temporary(base_id + MonsterCatalog.GOLDEN_SUFFIX_ID, spots[i], event_id)
	active = {"id": event_id, "region_id": region_id, "ends_at": server.now + float(cfg["duration_s"]), "spawned": spots.size()}
	server.announce("Invasão dourada!", "Monstros dourados surgiram em %s" % region.display_name())
	print("[evento] invasão #%d em %s: %d monstros" % [event_id, region_id, spots.size()])
	return ""


func _finish(contained: bool) -> void:
	var region: RegionInstance = server.regions[active["region_id"]]
	var left := region.monsters.remove_event(int(active["id"]))
	if contained:
		server.announce("Invasão contida", "%s está em paz de novo" % region.display_name())
	else:
		server.announce("Os invasores se foram", "%d monstro(s) dourado(s) sumiram na névoa de %s" % [left, region.display_name()])
	print("[evento] invasão #%d terminou (%s, restavam %d)" % [int(active["id"]), "contida" if contained else "tempo esgotado", left])
	active = {}
	next_at = server.now + server.rng.randf_range(float(cfg["interval_min_s"]), float(cfg["interval_max_s"]))


func _pick_region() -> String:
	var total := 0.0
	for id: String in cfg["regions"]:
		total += float(cfg["regions"][id]["weight"])
	var r := server.rng.randf() * total
	for id: String in cfg["regions"]:
		r -= float(cfg["regions"][id]["weight"])
		if r <= 0.0:
			return id
	return str(cfg["regions"].keys()[0])


## Pontos andáveis espalhados pela região, longe das zonas seguras e dos portais.
func _spawn_spots(region: RegionInstance, count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var half := float(GameConfig.get_f("movement", "world_half_extent_m")) - float(cfg["spawn_margin_m"])
	var tries := 0
	while out.size() < count and tries < count * 40:
		tries += 1
		var p := region.grid.nearest_walkable_point(Vector2(server.rng.randf_range(-half, half), server.rng.randf_range(-half, half)))
		if region.safe.contains(p):
			continue
		var near_portal := false
		for pt: Dictionary in region.portals():
			near_portal = near_portal or p.distance_to(Vector2(float(pt["pos"][0]), float(pt["pos"][1]))) < 8.0
		if near_portal:
			continue
		out.append(p)
	return out
