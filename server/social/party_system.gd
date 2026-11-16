class_name PartySystem
extends RefCounted
## Grupos: convite (com resposta), saída, expulsão pelo líder, estado replicado aos
## membros e divisão de XP (data/social.json -> party). O líder é quem convida;
## se ele sai, o próximo da lista assume.

class Group:
	var id: int
	var leader: int # peer_id
	var members: Array[int] = [] # peer_ids, na ordem de entrada


var server: GameServer
var cfg: Dictionary
var groups: Dictionary = {} # id -> Group
var _group_of: Dictionary = {} # peer_id -> id
var _invites: Dictionary = {} # peer convidado -> {from: peer_id, until: float}
var _next_id: int = 1
var _state_timer: float = 0.0


func _init(game_server: GameServer, social_table: Dictionary) -> void:
	server = game_server
	cfg = social_table["party"]


func group_of(p: ServerPlayer) -> Group:
	return groups.get(_group_of.get(p.peer_id, -1))


## Membros online do grupo do jogador (inclui ele mesmo); vazio se não está num grupo.
func members_of(p: ServerPlayer) -> Array[ServerPlayer]:
	var out: Array[ServerPlayer] = []
	var g := group_of(p)
	if g != null:
		for peer_id in g.members:
			var m: ServerPlayer = server.players.get(peer_id)
			if m != null:
				out.append(m)
	return out


func same_group(peer_a: int, peer_b: int) -> bool:
	return peer_a == peer_b or (_group_of.has(peer_a) and _group_of.get(peer_a) == _group_of.get(peer_b))


func handle(p: ServerPlayer, action: int, target: String) -> void:
	match action:
		Protocol.Party.INVITE:
			invite(p, target)
		Protocol.Party.ACCEPT:
			accept(p)
		Protocol.Party.DECLINE:
			decline(p)
		Protocol.Party.LEAVE:
			leave(p, "%s saiu do grupo.")
		Protocol.Party.KICK:
			kick(p, target)


func invite(p: ServerPlayer, target_name: String) -> void:
	var t := server.find_player_by_name(target_name)
	if t == null:
		server.chat.system(p.peer_id, "%s não está online." % target_name.strip_edges())
		return
	if t == p:
		return
	var g := group_of(p)
	if g != null and g.leader != p.peer_id:
		server.chat.system(p.peer_id, "Só o líder pode convidar.")
		return
	if g != null and g.members.size() >= int(cfg["max_members"]):
		server.chat.system(p.peer_id, "O grupo está cheio (%d)." % int(cfg["max_members"]))
		return
	if group_of(t) != null:
		server.chat.system(p.peer_id, "%s já está num grupo." % t.char_name)
		return
	_invites[t.peer_id] = {"from": p.peer_id, "until": server.now + float(cfg["invite_timeout_s"])}
	Net.send_to(t.peer_id, &"rpc_prompt", [Protocol.Prompt.PARTY_INVITE, p.char_name, ""])
	server.chat.system(p.peer_id, "Convite enviado a %s." % t.char_name)


func accept(p: ServerPlayer) -> void:
	var inv: Dictionary = _invites.get(p.peer_id, {})
	_invites.erase(p.peer_id)
	var from: ServerPlayer = server.players.get(int(inv.get("from", 0)))
	if inv.is_empty() or server.now > float(inv["until"]) or from == null:
		server.chat.system(p.peer_id, "O convite expirou.")
		return
	if group_of(p) != null:
		return
	var g := group_of(from)
	if g == null:
		g = Group.new()
		g.id = _next_id
		_next_id += 1
		g.leader = from.peer_id
		g.members.append(from.peer_id)
		groups[g.id] = g
		_group_of[from.peer_id] = g.id
	if g.members.size() >= int(cfg["max_members"]):
		server.chat.system(p.peer_id, "O grupo já está cheio.")
		return
	g.members.append(p.peer_id)
	_group_of[p.peer_id] = g.id
	_tell_group(g, "%s entrou no grupo." % p.char_name)
	send_state(g)


func decline(p: ServerPlayer) -> void:
	var inv: Dictionary = _invites.get(p.peer_id, {})
	_invites.erase(p.peer_id)
	var from: ServerPlayer = server.players.get(int(inv.get("from", 0)))
	if from != null:
		server.chat.system(from.peer_id, "%s recusou o convite." % p.char_name)


## `message` recebe o nome de quem saiu (%s).
func leave(p: ServerPlayer, message: String) -> void:
	_invites.erase(p.peer_id)
	var g := group_of(p)
	if g == null:
		return
	g.members.erase(p.peer_id)
	_group_of.erase(p.peer_id)
	Net.send_to(p.peer_id, &"rpc_party_state", [[]])
	if g.members.size() <= 1:
		for rest in g.members:
			_group_of.erase(rest)
			Net.send_to(rest, &"rpc_party_state", [[]])
			server.chat.system(rest, (message % p.char_name) + " O grupo se desfez.")
		groups.erase(g.id)
		return
	if g.leader == p.peer_id:
		g.leader = g.members[0]
	_tell_group(g, message % p.char_name)
	send_state(g)


func kick(p: ServerPlayer, target_name: String) -> void:
	var g := group_of(p)
	var t := server.find_player_by_name(target_name)
	if g == null or g.leader != p.peer_id:
		server.chat.system(p.peer_id, "Só o líder pode expulsar.")
		return
	if t == null or t == p or group_of(t) != g:
		server.chat.system(p.peer_id, "%s não está no seu grupo." % target_name.strip_edges())
		return
	server.chat.system(t.peer_id, "Você foi expulso do grupo.")
	leave(t, "%s foi expulso do grupo.")


func on_disconnect(p: ServerPlayer) -> void:
	leave(p, "%s desconectou.")


## Reenvia vida e nível dos membros de tempos em tempos.
func update(dt: float) -> void:
	_state_timer += dt
	if _state_timer < float(cfg["state_interval_s"]):
		return
	_state_timer = 0.0
	for g: Group in groups.values():
		send_state(g)


func send_state(g: Group) -> void:
	var list: Array = []
	for peer_id in g.members:
		var m: ServerPlayer = server.players.get(peer_id)
		if m != null:
			list.append([m.id, m.char_name, m.level, snappedf(m.hp_frac(), 0.01), peer_id == g.leader])
	for peer_id in g.members:
		Net.send_to(peer_id, &"rpc_party_state", [list])


## XP de um monstro morto: dividida no grupo (por nível) com bônus; sem grupo, tudo para quem matou.
func distribute_xp(killer: ServerPlayer, monster_pos: Vector2, amount: int) -> void:
	var g := group_of(killer)
	if g == null:
		server.give_xp(killer, amount)
		return
	for share: Array in shares(members_of(killer), killer, monster_pos, amount, cfg):
		server.give_xp(share[0], share[1])


## [[jogador, XP], ...] — função pura, testada em tests/test_social.gd.
static func shares(members: Array[ServerPlayer], killer: ServerPlayer, monster_pos: Vector2, amount: int, party_cfg: Dictionary) -> Array:
	var eligible: Array[ServerPlayer] = []
	var classes := {}
	for m in members:
		if m.alive and (m == killer or (m.region_id == killer.region_id and m.position.distance_to(monster_pos) <= float(party_cfg["share_radius_m"]))):
			eligible.append(m)
			classes[m.class_id] = true
	if eligible.is_empty():
		return []
	var total := amount * (1.0 + float(party_cfg["bonus_per_member"]) * (eligible.size() - 1)
		+ float(party_cfg["bonus_per_distinct_class"]) * (classes.size() - 1))
	var level_sum := 0
	for m in eligible:
		level_sum += m.level
	var out: Array = []
	for m in eligible:
		out.append([m, maxi(1, roundi(total * m.level / float(level_sum)))])
	return out


func _tell_group(g: Group, text: String) -> void:
	for peer_id in g.members:
		server.chat.system(peer_id, text)
