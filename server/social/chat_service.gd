class_name ChatService
extends RefCounted
## Chat: geral (todos), sussurro (um jogador pelo nome), grupo e guilda.
## O servidor limpa o texto (sem caracteres de controle, tamanho máximo) e limita
## a frequência por jogador (data/social.json -> chat.rate).

var server: GameServer
var cfg: Dictionary
var _sent: Dictionary = {} # peer_id -> Array de tempos das últimas mensagens


func _init(game_server: GameServer, social_table: Dictionary) -> void:
	server = game_server
	cfg = social_table["chat"]


func handle(p: ServerPlayer, channel: int, target: String, text: String) -> void:
	text = clean(text, int(cfg["max_length"]))
	if text.is_empty():
		return
	if not _allow(p):
		system(p.peer_id, "Calma: mensagens demais em pouco tempo.")
		return
	match channel:
		Protocol.Chat.GENERAL:
			Net.broadcast(server.peers(), &"rpc_chat_message", [Protocol.Chat.GENERAL, p.char_name, text])
		Protocol.Chat.WHISPER:
			var t := server.find_player_by_name(target)
			if t == null:
				system(p.peer_id, "%s não está online." % target.strip_edges())
				return
			Net.send_to(t.peer_id, &"rpc_chat_message", [Protocol.Chat.WHISPER, p.char_name, text])
			if t != p:
				Net.send_to(p.peer_id, &"rpc_chat_message", [Protocol.Chat.WHISPER, "→ " + t.char_name, text])
		Protocol.Chat.PARTY:
			var members := server.party.members_of(p)
			if members.is_empty():
				system(p.peer_id, "Você não está num grupo.")
				return
			for m: ServerPlayer in members:
				Net.send_to(m.peer_id, &"rpc_chat_message", [Protocol.Chat.PARTY, p.char_name, text])
		Protocol.Chat.GUILD:
			var g := server.guilds.guild_of(p)
			if g == null:
				system(p.peer_id, "Você não está numa guilda.")
				return
			for m: ServerPlayer in server.guilds.online_members(g):
				Net.send_to(m.peer_id, &"rpc_chat_message", [Protocol.Chat.GUILD, p.char_name, text])
		_:
			return
	print("[chat] %s (%s%s): %s" % [p.char_name, ["geral", "sussurro", "grupo", "?", "guilda"][clampi(channel, 0, 4)],
		" para " + target if channel == Protocol.Chat.WHISPER else "", text])


func system(peer_id: int, text: String) -> void:
	Net.send_to(peer_id, &"rpc_chat_message", [Protocol.Chat.SYSTEM, "", text])


func forget(peer_id: int) -> void:
	_sent.erase(peer_id)


## Sem caracteres de controle, espaços nas pontas e no máximo `max_len` caracteres.
static func clean(text: String, max_len: int) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 32 and c != 127:
			out += String.chr(c)
	return out.strip_edges().left(max_len)


func _allow(p: ServerPlayer) -> bool:
	var rate: Dictionary = cfg["rate"]
	var times: Array = _sent.get(p.peer_id, [])
	var window := float(rate["window_s"])
	while not times.is_empty() and server.now - float(times[0]) > window:
		times.pop_front()
	if times.size() >= int(rate["messages"]):
		_sent[p.peer_id] = times
		return false
	times.append(server.now)
	_sent[p.peer_id] = times
	return true
