class_name MasterySystem
extends RefCounted
## Endgame (data/mastery.json e data/reset.json):
## - maestria: no nível máximo, a XP enche níveis de maestria; cada um dá pontos para as
##   árvores Ataque, Defesa e Utilidade (nós com pré-requisito);
## - reset: no nível exigido, na cidade e pagando, volta ao nível 1 com os atributos da
##   classe e pontos de bônus que acumulam a cada reset.

var server: GameServer
var cfg: Dictionary
var reset_cfg: Dictionary
var nodes: Dictionary = {} # id -> nó (com "tree")
var _xp_expr := Expression.new()


func _init(game_server: GameServer, mastery_table: Dictionary, reset_table: Dictionary) -> void:
	server = game_server
	cfg = mastery_table
	reset_cfg = reset_table
	nodes = MasterySystem.index_nodes(cfg)
	if _xp_expr.parse(str(cfg["xp_to_next"]), ["mlevel"]) != OK:
		push_error("MasterySystem: xp_to_next inválida")


# ---------------------------------------------------------------- regras puras (testadas)

static func index_nodes(table: Dictionary) -> Dictionary:
	var out := {}
	for tree: Dictionary in table["trees"]:
		for n: Dictionary in tree["nodes"]:
			var copy := n.duplicate(true)
			copy["tree"] = tree["id"]
			out[str(n["id"])] = copy
	return out


## Bônus somados de todos os nós: {stat: valor}.
static func bonuses_for(mastery: Dictionary, all_nodes: Dictionary) -> Dictionary:
	var out := {}
	for id: String in mastery:
		var n: Dictionary = all_nodes.get(id, {})
		if n.is_empty():
			continue
		var stat := str(n["stat"])
		out[stat] = float(out.get(stat, 0.0)) + float(n["per_point"]) * int(mastery[id])
	return out


## "" se pode pôr 1 ponto no nó; senão o motivo.
static func can_spend(mastery: Dictionary, node_id: String, all_nodes: Dictionary, free_points: int) -> String:
	var n: Dictionary = all_nodes.get(node_id, {})
	if n.is_empty():
		return "Nó desconhecido."
	if free_points <= 0:
		return "Sem pontos de maestria livres."
	if int(mastery.get(node_id, 0)) >= int(n["max"]):
		return "%s já está no máximo." % n["name"]
	for req: Array in n.get("requires", []):
		if int(mastery.get(str(req[0]), 0)) < int(req[1]):
			return "Antes, %d pontos em %s." % [int(req[1]), all_nodes.get(str(req[0]), {}).get("name", req[0])]
	return ""


## Custo do próximo reset.
static func reset_cost(resets: int, table: Dictionary) -> int:
	return int(table["cost_base"]) + int(table["cost_per_reset"]) * resets


# ---------------------------------------------------------------- maestria

func xp_to_next(master_level: int) -> int:
	if master_level >= int(cfg["max_level"]):
		return 0
	return maxi(1, int(_xp_expr.execute([master_level])))


## XP ganha no nível máximo: vai para a maestria.
func gain_xp(p: ServerPlayer, amount: int) -> void:
	if p.level < server.max_level() or p.master_level >= int(cfg["max_level"]):
		return # maestria só no nível máximo
	p.master_xp += amount
	var ups := 0
	while p.master_level < int(cfg["max_level"]) and p.master_xp >= xp_to_next(p.master_level):
		p.master_xp -= xp_to_next(p.master_level)
		p.master_level += 1
		p.master_points += int(cfg["points_per_level"])
		ups += 1
	if p.master_level >= int(cfg["max_level"]):
		p.master_xp = 0
	if ups > 0:
		server.broadcast_near(server.region_of(p), p.position, &"rpc_level_up_event", [p.id, -4]) # brilho de maestria
		server.send_message(p.peer_id, "Maestria %d! Você tem %d ponto(s) de maestria (K)." % [p.master_level, p.master_points])


func spend(p: ServerPlayer, node_id: String) -> void:
	var why := can_spend(p.mastery, node_id, nodes, p.master_points)
	if why != "":
		server.send_message(p.peer_id, why)
		return
	p.mastery[node_id] = int(p.mastery.get(node_id, 0)) + 1
	p.master_points -= 1
	refresh(p)
	send_state(p)


## Recalcula os bônus da maestria (no login e a cada ponto) e os atributos.
func refresh(p: ServerPlayer) -> void:
	p.mastery_bonuses = bonuses_for(p.mastery, nodes)
	server.recompute(p)


func send_state(p: ServerPlayer) -> void:
	Net.send_to(p.peer_id, &"rpc_mastery_state", [p.mastery.duplicate()])


# ---------------------------------------------------------------- reset

## "" se pode renascer; senão o motivo.
func reset_check(p: ServerPlayer) -> String:
	if not bool(reset_cfg["enabled"]):
		return "O renascimento está desligado neste servidor."
	if p.resets >= int(reset_cfg["max_resets"]):
		return "Você já renasceu o máximo de vezes (%d)." % int(reset_cfg["max_resets"])
	if p.level < int(reset_cfg["level_req"]):
		return "Renascer exige nível %d." % int(reset_cfg["level_req"])
	if server.region_of(p).id != server.home_region or not server.region_of(p).safe.contains(p.position):
		return "Só se renasce no Refúgio."
	if server.trades.is_trading(p):
		return "Termine a troca primeiro."
	var cost := reset_cost(p.resets, reset_cfg)
	if p.currency < cost:
		return "Renascer custa %d Óbolos." % cost
	return ""


func do_reset(p: ServerPlayer) -> void:
	var why := reset_check(p)
	if why != "":
		server.send_message(p.peer_id, why)
		return
	p.currency -= reset_cost(p.resets, reset_cfg)
	p.resets += 1
	p.level = 1
	p.xp = 0
	var base: Dictionary = server.class_data(p)["base_stats"]
	for s: String in Protocol.STAT_KEYS:
		p.stats[s] = int(base[s])
	p.points = p.resets * int(reset_cfg["points_per_reset"])
	server.recompute(p)
	p.full_restore()
	server.save_player(p)
	server.broadcast_near(server.region_of(p), p.position, &"rpc_level_up_event", [p.id, -5]) # brilho de renascimento
	server.announce("Renascimento!", "%s renasceu pela %dª vez" % [p.char_name, p.resets])
	server.send_message(p.peer_id, "Você renasceu (%dª vez): nível 1 e %d pontos para distribuir (C)." % [p.resets, p.points])
	print("[reset] %s renasceu (%d)" % [p.char_name, p.resets])
