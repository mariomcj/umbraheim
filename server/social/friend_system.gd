class_name FriendSystem
extends RefCounted
## Lista de amigos (data/social.json -> friends). A amizade é mútua: um pede, o outro
## aceita, e os dois entram na lista um do outro (gravado na hora). Amigos veem quem
## está online, o nível e a região, e recebem aviso quando o outro entra ou sai.

var server: GameServer
var cfg: Dictionary
var repo: GameRepository
var _lists: Dictionary = {} # character_id (online) -> {friend character_id -> {name, class_id, level}}
var _requests: Dictionary = {} # peer convidado -> {from: peer_id, until}
var _state_timer: float = 0.0


func _init(game_server: GameServer, social_table: Dictionary, repository: GameRepository) -> void:
	server = game_server
	cfg = social_table["friends"]
	repo = repository


func handle(p: ServerPlayer, action: int, target: String) -> void:
	match action:
		Protocol.Friend.REQUEST:
			request(p, target)
		Protocol.Friend.ACCEPT:
			accept(p)
		Protocol.Friend.DECLINE:
			decline(p)
		Protocol.Friend.REMOVE:
			remove(p, target)


func is_friend(p: ServerPlayer, other_character_id: int) -> bool:
	return (_lists.get(p.character_id, {}) as Dictionary).has(other_character_id)


func request(p: ServerPlayer, target_name: String) -> void:
	var t := server.find_player_by_name(target_name)
	if t == null:
		server.chat.system(p.peer_id, "%s não está online." % target_name.strip_edges())
		return
	if t == p:
		return
	if is_friend(p, t.character_id):
		server.chat.system(p.peer_id, "%s já é seu amigo." % t.char_name)
		return
	var limit := int(cfg["max"])
	if (_lists.get(p.character_id, {}) as Dictionary).size() >= limit:
		server.chat.system(p.peer_id, "Sua lista de amigos está cheia (%d)." % limit)
		return
	if (_lists.get(t.character_id, {}) as Dictionary).size() >= limit:
		server.chat.system(p.peer_id, "A lista de amigos de %s está cheia." % t.char_name)
		return
	_requests[t.peer_id] = {"from": p.peer_id, "until": server.now + float(cfg["request_timeout_s"])}
	Net.send_to(t.peer_id, &"rpc_prompt", [Protocol.Prompt.FRIEND_REQUEST, p.char_name, ""])
	server.chat.system(p.peer_id, "Pedido de amizade enviado a %s." % t.char_name)


func accept(p: ServerPlayer) -> void:
	var req: Dictionary = _requests.get(p.peer_id, {})
	_requests.erase(p.peer_id)
	var from: ServerPlayer = server.players.get(int(req.get("from", 0)))
	if req.is_empty() or from == null or server.now > float(req["until"]):
		server.chat.system(p.peer_id, "O pedido de amizade expirou.")
		return
	if is_friend(p, from.character_id) or not repo.add_friendship(p.character_id, from.character_id):
		return
	_add_local(p, from)
	_add_local(from, p)
	server.chat.system(p.peer_id, "%s agora é seu amigo." % from.char_name)
	server.chat.system(from.peer_id, "%s aceitou sua amizade." % p.char_name)
	send_state(p)
	send_state(from)


func decline(p: ServerPlayer) -> void:
	var req: Dictionary = _requests.get(p.peer_id, {})
	_requests.erase(p.peer_id)
	var from: ServerPlayer = server.players.get(int(req.get("from", 0)))
	if from != null:
		server.chat.system(from.peer_id, "%s recusou a amizade." % p.char_name)


## Remove pelo nome (o amigo pode estar offline); some das duas listas.
func remove(p: ServerPlayer, friend_name: String) -> void:
	var list: Dictionary = _lists.get(p.character_id, {})
	var key := friend_name.strip_edges().to_lower()
	for fid: int in list.keys():
		if str(list[fid]["name"]).to_lower() != key:
			continue
		if not repo.remove_friendship(p.character_id, fid):
			return
		var gone := str(list[fid]["name"])
		list.erase(fid)
		server.chat.system(p.peer_id, "%s saiu da sua lista de amigos." % gone)
		send_state(p)
		var other := _online(fid)
		if other != null:
			(_lists.get(fid, {}) as Dictionary).erase(p.character_id)
			send_state(other)
		return
	server.chat.system(p.peer_id, "%s não está na sua lista." % friend_name.strip_edges())


func on_enter(p: ServerPlayer) -> void:
	var list := {}
	for f: Dictionary in repo.list_friends(p.character_id):
		list[int(f["id"])] = {"name": str(f["name"]), "class_id": str(f["class_id"]), "level": int(f["level"])}
	_lists[p.character_id] = list
	send_state(p)
	for fid: int in list:
		var other := _online(fid)
		if other != null and other != p:
			server.chat.system(other.peer_id, "Seu amigo %s entrou no jogo." % p.char_name)
			send_state(other)


## Chamado depois que o jogador já saiu de server.players.
func on_leave(p: ServerPlayer) -> void:
	_requests.erase(p.peer_id)
	var list: Dictionary = _lists.get(p.character_id, {})
	_lists.erase(p.character_id)
	for fid: int in list:
		var other := _online(fid)
		if other != null:
			var theirs: Dictionary = _lists.get(fid, {})
			if theirs.has(p.character_id):
				theirs[p.character_id]["level"] = p.level
			server.chat.system(other.peer_id, "Seu amigo %s saiu do jogo." % p.char_name)
			send_state(other)


func update(dt: float) -> void:
	_state_timer += dt
	if _state_timer < float(cfg["state_interval_s"]):
		return
	_state_timer = 0.0
	for p: ServerPlayer in server.players.values():
		if not (_lists.get(p.character_id, {}) as Dictionary).is_empty():
			send_state(p)


## [[nome, online?, nível, classe, região], ...] — online primeiro, depois por nome.
func send_state(p: ServerPlayer) -> void:
	var rows: Array = []
	var list: Dictionary = _lists.get(p.character_id, {})
	for fid: int in list:
		var f: Dictionary = list[fid]
		var other := _online(fid)
		if other != null:
			f["level"] = other.level
		rows.append([f["name"], other != null, int(f["level"]), f["class_id"], other.region_id if other != null else ""])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		return bool(a[1]) and not bool(b[1]) if bool(a[1]) != bool(b[1]) else str(a[0]).to_lower() < str(b[0]).to_lower())
	Net.send_to(p.peer_id, &"rpc_friends_state", [rows])


func _add_local(p: ServerPlayer, friend: ServerPlayer) -> void:
	if not _lists.has(p.character_id):
		_lists[p.character_id] = {}
	_lists[p.character_id][friend.character_id] = {"name": friend.char_name, "class_id": friend.class_id, "level": friend.level}


func _online(character_id: int) -> ServerPlayer:
	for t: ServerPlayer in server.players.values():
		if t.character_id == character_id:
			return t
	return null
