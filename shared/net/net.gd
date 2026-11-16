extends Node
## Autoload de rede compartilhado por cliente e servidor.
## Transporte: WebSocketMultiplayerPeer — o único da Godot que funciona no navegador
## (sem UDP/ENet na Web). Clientes Web e desktop usam o mesmo protocolo.
## Todos os RPCs ficam neste nó para que o caminho (/root/Net) seja idêntico nos dois lados.
## O cliente envia apenas INTENÇÕES; o servidor valida, simula e replica.

# --- Cliente ---
signal client_connected(my_id: int)
signal client_failed
signal client_disconnected
signal welcome_received(my_id: int, tick_rate_hz: int)
signal snapshot_received(tick: int, ids: PackedInt32Array, metas: PackedInt32Array, states: Dictionary) # states: id -> Vector4(x, z, yaw, vida)
signal pong_received(sent_ms: int)
signal ping_requested(peer_id: int, sent_ms: int)
signal player_state_received(state: PackedInt64Array)
signal cast_event_received(caster_id: int, spell_index: int, target_id: int, target_pos: Vector2, chain_ids: PackedInt32Array)
signal damage_event_received(target_id: int, amount: int, kind: int)
signal attack_event_received(attacker_id: int, target_id: int)
signal died_event_received(entity_id: int)
signal level_up_event_received(entity_id: int, level: int)
signal drop_spawned_received(drop_id: int, label: String, rarity: int, pos: Vector2)
signal drop_removed_received(drop_id: int)
signal cooldown_received(spell_index: int, seconds: float)
signal message_received(text: String)
signal inventory_received(items: Array)
signal appearance_received(entity_id: int, appearance: PackedInt32Array)
signal journal_full_received(region_id: String, strokes: Array, marks: Array)
signal journal_point_received(region_id: String, point: Vector2, new_stroke: bool)
signal journal_mark_received(region_id: String, symbol: String, point: Vector2, label: String)

# --- Servidor ---
signal hello_received(peer_id: int, protocol_version: int)
signal move_to_requested(peer_id: int, target: Vector2)
signal move_dir_requested(peer_id: int, direction: Vector2)
signal cast_requested(peer_id: int, spell_index: int, target_id: int, target_pos: Vector2, repeat: bool)
signal pickup_requested(peer_id: int, drop_id: int)
signal add_stat_requested(peer_id: int, stat_index: int, amount: int)
signal item_action_requested(peer_id: int, action: int, uid: int, dest: int, x: int, y: int)

var is_server: bool = false
var snapshot_bytes_sent: int = 0 # medição de banda (servidor)
var _decoder := SnapshotCodec.Decoder.new()


## bind: interface de escuta ("*" = todas; em produção "127.0.0.1", atrás do proxy TLS).
func start_server(port: int, bind: String = "*") -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port, bind)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	return OK


func connect_to_server(url: String) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	# Na Web, a compilação de shaders do primeiro frame pode travar a página por segundos;
	# o padrão de 3 s da Godot derrubava o handshake.
	peer.handshake_timeout = GameConfig.get_f("network", "handshake_timeout_s")
	var err := peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK


func is_online_client() -> bool:
	return not is_server \
		and multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Fecha a conexão de forma limpa (frame de close do WebSocket) antes de sair.
func disconnect_from_server() -> void:
	if not is_server and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null


func kick(peer_id: int) -> void:
	if is_server and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func _on_connected() -> void:
	_decoder.reset()
	client_connected.emit(multiplayer.get_unique_id())
	rpc_hello.rpc_id(Protocol.SERVER_PEER_ID, Protocol.VERSION)


func _on_connection_failed() -> void:
	client_failed.emit()


func _on_server_disconnected() -> void:
	client_disconnected.emit()


# ---------------------------------------------------------------- cliente -> servidor

func send_move_to(target: Vector2) -> void:
	if is_online_client():
		_lagged(func() -> void: rpc_move_to.rpc_id(Protocol.SERVER_PEER_ID, target))


func send_move_dir(direction: Vector2) -> void:
	if is_online_client():
		_lagged(func() -> void: rpc_move_dir.rpc_id(Protocol.SERVER_PEER_ID, direction))


func send_cast(spell_index: int, target_id: int, target_pos: Vector2, repeat: bool) -> void:
	if is_online_client():
		_lagged(func() -> void: rpc_cast.rpc_id(Protocol.SERVER_PEER_ID, spell_index, target_id, target_pos, repeat))


func send_pickup(drop_id: int) -> void:
	if is_online_client():
		rpc_pickup.rpc_id(Protocol.SERVER_PEER_ID, drop_id)


func send_add_stat(stat_index: int, amount: int) -> void:
	if is_online_client():
		rpc_add_stat.rpc_id(Protocol.SERVER_PEER_ID, stat_index, amount)


signal gm_requested(peer_id: int, command: String)
signal npc_interact_requested(peer_id: int, npc_id: String)
signal npc_close_requested(peer_id: int)
signal forge_combine_requested(peer_id: int)
signal npc_opened(npc_id: String)
signal npc_closed
signal refine_fx_received(entity_id: int, outcome: int, level: int)


# --- Contas e personagens (Fase 3) ---
signal login_requested(peer_id: int, account: String, password: String, create: bool)
signal create_character_requested(peer_id: int, character_name: String, class_id: String)
signal enter_world_requested(peer_id: int, character_id: int)
signal login_result_received(ok: bool, message: String, characters: Array)
signal player_name_received(entity_id: int, character_name: String, class_id: String, evolution: int)


## Login (create = criar a conta). Em produção a conexão é wss:// (TLS no proxy).
func send_login(account: String, password: String, create: bool) -> void:
	if is_online_client():
		rpc_login.rpc_id(Protocol.SERVER_PEER_ID, account, password, create)


func send_create_character(character_name: String, class_id: String) -> void:
	if is_online_client():
		rpc_create_character.rpc_id(Protocol.SERVER_PEER_ID, character_name, class_id)


func send_enter_world(character_id: int) -> void:
	if is_online_client():
		rpc_enter_world.rpc_id(Protocol.SERVER_PEER_ID, character_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_login(account: String, password: String, create: bool) -> void:
	if is_server:
		login_requested.emit(multiplayer.get_remote_sender_id(), account, password, create)


@rpc("any_peer", "call_remote", "reliable")
func rpc_create_character(character_name: String, class_id: String) -> void:
	if is_server:
		create_character_requested.emit(multiplayer.get_remote_sender_id(), character_name, class_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_enter_world(character_id: int) -> void:
	if is_server:
		enter_world_requested.emit(multiplayer.get_remote_sender_id(), character_id)


## Resposta do login e da criação de personagem: lista [[id, nome, classe, nível], ...].
@rpc("authority", "call_remote", "reliable")
func rpc_login_result(ok: bool, message: String, characters: Array) -> void:
	login_result_received.emit(ok, message, characters)


# --- Social (Fase 3, parte 2) ---
signal chat_requested(peer_id: int, channel: int, target: String, text: String)
signal party_action_requested(peer_id: int, action: int, target: String)
signal trade_action_requested(peer_id: int, action: int, value: int, target: String)
signal chat_received(channel: int, from_name: String, text: String)
signal prompt_received(kind: int, from_name: String, detail: String)
signal party_state_received(members: Array)
signal trade_state_received(state: Dictionary)
signal trade_closed_received(reason: String)


func send_chat(channel: int, target: String, text: String) -> void:
	if is_online_client():
		rpc_chat.rpc_id(Protocol.SERVER_PEER_ID, channel, target, text)


func send_party_action(action: int, target: String = "") -> void:
	if is_online_client():
		rpc_party_action.rpc_id(Protocol.SERVER_PEER_ID, action, target)


func send_trade_action(action: int, value: int = 0, target: String = "") -> void:
	if is_online_client():
		rpc_trade_action.rpc_id(Protocol.SERVER_PEER_ID, action, value, target)


@rpc("any_peer", "call_remote", "reliable")
func rpc_chat(channel: int, target: String, text: String) -> void:
	if is_server:
		chat_requested.emit(multiplayer.get_remote_sender_id(), channel, target, text)


@rpc("any_peer", "call_remote", "reliable")
func rpc_party_action(action: int, target: String) -> void:
	if is_server:
		party_action_requested.emit(multiplayer.get_remote_sender_id(), action, target)


@rpc("any_peer", "call_remote", "reliable")
func rpc_trade_action(action: int, value: int, target: String) -> void:
	if is_server:
		trade_action_requested.emit(multiplayer.get_remote_sender_id(), action, value, target)


@rpc("authority", "call_remote", "reliable")
func rpc_chat_message(channel: int, from_name: String, text: String) -> void:
	chat_received.emit(channel, from_name, text)


## Convite que pede resposta (grupo, troca, guilda, guerra, amizade). detail: nome da guilda, se houver.
@rpc("authority", "call_remote", "reliable")
func rpc_prompt(kind: int, from_name: String, detail: String) -> void:
	prompt_received.emit(kind, from_name, detail)


## Membros do grupo: [[id, nome, nível, vida (0..1), líder?], ...]; vazio = sem grupo.
@rpc("authority", "call_remote", "reliable")
func rpc_party_state(members: Array) -> void:
	party_state_received.emit(members)


## Estado da troca: partner, their_items (ItemCodec), their_currency, my_currency,
## my_locked, their_locked, my_confirmed, their_confirmed.
@rpc("authority", "call_remote", "reliable")
func rpc_trade_state(state: Dictionary) -> void:
	trade_state_received.emit(state)


@rpc("authority", "call_remote", "reliable")
func rpc_trade_closed(reason: String) -> void:
	trade_closed_received.emit(reason)


# --- Guildas e amigos (Fase 5, parte 2) ---
signal guild_action_requested(peer_id: int, action: int, target: String, extra: String)
signal friend_action_requested(peer_id: int, action: int, target: String)
signal guild_state_received(state: Dictionary)
signal player_guild_received(entity_id: int, guild_name: String, symbol: String)
signal friends_state_received(friends: Array)


func send_guild_action(action: int, target: String = "", extra: String = "") -> void:
	if is_online_client():
		rpc_guild_action.rpc_id(Protocol.SERVER_PEER_ID, action, target, extra)


func send_friend_action(action: int, target: String = "") -> void:
	if is_online_client():
		rpc_friend_action.rpc_id(Protocol.SERVER_PEER_ID, action, target)


@rpc("any_peer", "call_remote", "reliable")
func rpc_guild_action(action: int, target: String, extra: String) -> void:
	if is_server:
		guild_action_requested.emit(multiplayer.get_remote_sender_id(), action, target, extra)


@rpc("any_peer", "call_remote", "reliable")
func rpc_friend_action(action: int, target: String) -> void:
	if is_server:
		friend_action_requested.emit(multiplayer.get_remote_sender_id(), action, target)


## A própria guilda (vazio = sem guilda): name, symbol, role, wins, max_members,
## members [[nome, cargo, nível, classe, online?, região]], war {} ou
## {enemy, enemy_symbol, mine, theirs, goal, left_s}.
@rpc("authority", "call_remote", "reliable")
func rpc_guild_state(state: Dictionary) -> void:
	guild_state_received.emit(state)


## Guilda de um jogador (nome sobre a cabeça); nome vazio = sem guilda.
@rpc("authority", "call_remote", "reliable")
func rpc_player_guild(entity_id: int, guild_name: String, symbol: String) -> void:
	player_guild_received.emit(entity_id, guild_name, symbol)


## Lista de amigos: [[nome, online?, nível, classe, região], ...].
@rpc("authority", "call_remote", "reliable")
func rpc_friends_state(friends: Array) -> void:
	friends_state_received.emit(friends)


# --- Mundo (Fase 4) ---
signal region_changed_received(region_id: String)
signal journal_sheets_received(region_ids: PackedStringArray)
signal teleport_requested(peer_id: int, region_id: String)


## Intenção: teletransportar para uma região cuja folha já está no diário.
func send_teleport(region_id: String) -> void:
	if is_online_client():
		rpc_teleport.rpc_id(Protocol.SERVER_PEER_ID, region_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_teleport(region_id: String) -> void:
	if is_server:
		teleport_requested.emit(multiplayer.get_remote_sender_id(), region_id)


## O jogador está agora nesta região (o cliente troca a cena). Vem antes dos snapshots dela.
@rpc("authority", "call_remote", "reliable")
func rpc_region_changed(region_id: String) -> void:
	_decoder.reset()
	region_changed_received.emit(region_id)


## Regiões com folha no diário (as que o teletransporte pode listar).
@rpc("authority", "call_remote", "reliable")
func rpc_journal_sheets(region_ids: PackedStringArray) -> void:
	journal_sheets_received.emit(region_ids)


signal player_tag_received(entity_id: int, outlaw_level: int, hero_level: int)


## Status de PvP de um jogador (cor do nome): nível de Fora da Lei e de herói.
@rpc("authority", "call_remote", "reliable")
func rpc_player_tag(entity_id: int, outlaw_level: int, hero_level: int) -> void:
	player_tag_received.emit(entity_id, outlaw_level, hero_level)


signal announce_received(title: String, subtitle: String)


## Aviso de evento do mundo para todos (invasão, chefe).
@rpc("authority", "call_remote", "reliable")
func rpc_announce(title: String, subtitle: String) -> void:
	announce_received.emit(title, subtitle)


signal kicked(reason: String)


## O servidor vai fechar a conexão por este motivo (o cliente não deve reconectar sozinho).
@rpc("authority", "call_remote", "reliable")
func rpc_kicked(reason: String) -> void:
	kicked.emit(reason)


## Nome, classe e evolução do personagem de um jogador (para todos; reenviado ao evoluir).
@rpc("authority", "call_remote", "reliable")
func rpc_player_name(entity_id: int, character_name: String, class_id: String, evolution: int) -> void:
	player_name_received.emit(entity_id, character_name, class_id, evolution)


# --- Cerco ao castelo (Fase 6, parte 4) ---
signal castle_action_requested(peer_id: int, action: int, value: int)
signal castle_state_received(state: Dictionary)


func send_castle_action(action: int, value: int = 0) -> void:
	if is_online_client():
		rpc_castle_action.rpc_id(Protocol.SERVER_PEER_ID, action, value)


@rpc("any_peer", "call_remote", "reliable")
func rpc_castle_action(action: int, value: int) -> void:
	if is_server:
		castle_action_requested.emit(multiplayer.get_remote_sender_id(), action, value)


## Castelo: name, owner, owner_symbol, tax_pct, tax_max_pct, treasury (-1 se não é o mestre dono),
## registered, fee, my_guild, my_role, mine_in, is_owner.
@rpc("authority", "call_remote", "reliable")
func rpc_castle_state(state: Dictionary) -> void:
	castle_state_received.emit(state)


# --- Reset e maestria (Fase 6, parte 3) ---
signal reset_requested(peer_id: int)
signal mastery_spend_requested(peer_id: int, node_id: String)
signal mastery_state_received(mastery: Dictionary)


func send_reset() -> void:
	if is_online_client():
		rpc_reset.rpc_id(Protocol.SERVER_PEER_ID)


func send_mastery_spend(node_id: String) -> void:
	if is_online_client():
		rpc_mastery_spend.rpc_id(Protocol.SERVER_PEER_ID, node_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_reset() -> void:
	if is_server:
		reset_requested.emit(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func rpc_mastery_spend(node_id: String) -> void:
	if is_server:
		mastery_spend_requested.emit(multiplayer.get_remote_sender_id(), node_id)


## Pontos do personagem em cada nó da maestria: {nó: pontos}.
@rpc("authority", "call_remote", "reliable")
func rpc_mastery_state(mastery: Dictionary) -> void:
	mastery_state_received.emit(mastery)


# --- Eventos com horário (Fase 6) ---
signal event_schedule_received(rows: Array)
signal event_state_received(state: Dictionary)
signal event_world_received(blocker_id: String)


## Calendário: [[id, nome, estado (EventSystem.State), segundos até a próxima mudança], ...].
@rpc("authority", "call_remote", "reliable")
func rpc_event_schedule(rows: Array) -> void:
	event_schedule_received.emit(rows)


## Painel do evento em que o jogador está ({} = fora de evento): title, line, left_s, waiting, done, won.
@rpc("authority", "call_remote", "reliable")
func rpc_event_state(state: Dictionary) -> void:
	event_state_received.emit(state)


## Um bloqueio da região do evento abriu (grade, portão): some o visual e libera a predição.
@rpc("authority", "call_remote", "reliable")
func rpc_event_world(blocker_id: String) -> void:
	event_world_received.emit(blocker_id)


# --- Classes, missões e bônus (Fase 5, parte 3) ---
signal quest_action_requested(peer_id: int, action: int, quest_id: String)
signal quest_state_received(quests: Dictionary)
signal buffs_received(buffs: Array)


func send_quest_action(action: int, quest_id: String) -> void:
	if is_online_client():
		rpc_quest_action.rpc_id(Protocol.SERVER_PEER_ID, action, quest_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_quest_action(action: int, quest_id: String) -> void:
	if is_server:
		quest_action_requested.emit(multiplayer.get_remote_sender_id(), action, quest_id)


## Progresso das missões do próprio personagem: {quest_id: {step, count} | {done: true}}.
@rpc("authority", "call_remote", "reliable")
func rpc_quest_state(quests: Dictionary) -> void:
	quest_state_received.emit(quests)


## Bônus temporários ativos no próprio personagem: [[nome, segundos restantes], ...].
@rpc("authority", "call_remote", "reliable")
func rpc_buffs(buffs: Array) -> void:
	buffs_received.emit(buffs)


signal shop_buy_requested(peer_id: int, stock_index: int, quantity: int)
signal shop_sell_requested(peer_id: int, uid: int)


## Intenção: comprar o item `stock_index` da loja aberta (quantidade para empilháveis).
func send_shop_buy(stock_index: int, quantity: int) -> void:
	if is_online_client():
		rpc_shop_buy.rpc_id(Protocol.SERVER_PEER_ID, stock_index, quantity)


func send_shop_sell(uid: int) -> void:
	if is_online_client():
		rpc_shop_sell.rpc_id(Protocol.SERVER_PEER_ID, uid)


@rpc("any_peer", "call_remote", "reliable")
func rpc_shop_buy(stock_index: int, quantity: int) -> void:
	if is_server:
		shop_buy_requested.emit(multiplayer.get_remote_sender_id(), stock_index, quantity)


@rpc("any_peer", "call_remote", "reliable")
func rpc_shop_sell(uid: int) -> void:
	if is_server:
		shop_sell_requested.emit(multiplayer.get_remote_sender_id(), uid)


func send_npc_interact(npc_id: String) -> void:
	if is_online_client():
		rpc_npc_interact.rpc_id(Protocol.SERVER_PEER_ID, npc_id)


func send_npc_close() -> void:
	if is_online_client():
		rpc_npc_close.rpc_id(Protocol.SERVER_PEER_ID)


func send_forge_combine() -> void:
	if is_online_client():
		rpc_forge_combine.rpc_id(Protocol.SERVER_PEER_ID)


## Intenção: falar com um NPC (o servidor anda até ele e abre a janela).
@rpc("any_peer", "call_remote", "reliable")
func rpc_npc_interact(npc_id: String) -> void:
	if is_server:
		npc_interact_requested.emit(multiplayer.get_remote_sender_id(), npc_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_npc_close() -> void:
	if is_server:
		npc_close_requested.emit(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func rpc_forge_combine() -> void:
	if is_server:
		forge_combine_requested.emit(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func rpc_npc_opened(npc_id: String) -> void:
	npc_opened.emit(npc_id)


@rpc("authority", "call_remote", "reliable")
func rpc_npc_closed() -> void:
	npc_closed.emit()


## Efeito de refino/forja para todos verem (sucesso, falha, item destruído).
@rpc("authority", "call_remote", "reliable")
func rpc_refine_fx(entity_id: int, outcome: int, level: int) -> void:
	refine_fx_received.emit(entity_id, outcome, level)


## Comando de GM (o servidor só aceita se foi iniciado com --allow-gm).
func send_gm(command: String) -> void:
	if is_online_client():
		rpc_gm.rpc_id(Protocol.SERVER_PEER_ID, command)


@rpc("any_peer", "call_remote", "reliable")
func rpc_gm(command: String) -> void:
	if is_server:
		gm_requested.emit(multiplayer.get_remote_sender_id(), command)


## Intenção de item: ação (Protocol.ITEM_*), item, destino (container ou uid alvo) e célula.
func send_item_action(action: int, uid: int, dest: int, x: int, y: int) -> void:
	if is_online_client():
		rpc_item_action.rpc_id(Protocol.SERVER_PEER_ID, action, uid, dest, x, y)


@rpc("any_peer", "call_remote", "reliable")
func rpc_item_action(action: int, uid: int, dest: int, x: int, y: int) -> void:
	if is_server:
		item_action_requested.emit(multiplayer.get_remote_sender_id(), action, uid, dest, x, y)


## Inventário completo do próprio jogador (lista de ItemCodec), enviado quando muda.
@rpc("authority", "call_remote", "reliable")
func rpc_inventory(items: Array) -> void:
	inventory_received.emit(items)


## Aparência (equipamento visível) de um jogador, para todos.
@rpc("authority", "call_remote", "reliable")
func rpc_appearance(entity_id: int, appearance: PackedInt32Array) -> void:
	appearance_received.emit(entity_id, appearance)


## Intenção: usar a magia `spell_index` no alvo (ou no ponto). repeat = ataque contínuo.
@rpc("any_peer", "call_remote", "reliable")
func rpc_cast(spell_index: int, target_id: int, target_pos: Vector2, repeat: bool) -> void:
	if is_server:
		cast_requested.emit(multiplayer.get_remote_sender_id(), spell_index, target_id, target_pos, repeat)


@rpc("any_peer", "call_remote", "reliable")
func rpc_pickup(drop_id: int) -> void:
	if is_server:
		pickup_requested.emit(multiplayer.get_remote_sender_id(), drop_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_add_stat(stat_index: int, amount: int) -> void:
	if is_server:
		add_stat_requested.emit(multiplayer.get_remote_sender_id(), stat_index, amount)


@rpc("any_peer", "call_remote", "reliable")
func rpc_hello(protocol_version: int) -> void:
	if is_server:
		hello_received.emit(multiplayer.get_remote_sender_id(), protocol_version)


@rpc("any_peer", "call_remote", "reliable")
func rpc_move_to(target: Vector2) -> void:
	if is_server:
		move_to_requested.emit(multiplayer.get_remote_sender_id(), target)


@rpc("any_peer", "call_remote", "reliable")
func rpc_move_dir(direction: Vector2) -> void:
	if is_server:
		move_dir_requested.emit(multiplayer.get_remote_sender_id(), direction)


# ---------------------------------------------------------------- servidor -> clientes

func send_welcome(peer_id: int, tick_rate_hz: int) -> void:
	rpc_welcome.rpc_id(peer_id, peer_id, tick_rate_hz)


## Envia por peer (e não em broadcast) para pular sockets que já estão fechando
## e para servir de base ao interest management (cada peer receberá só o que está perto).
func send_snapshot(peer_id: int, data: PackedByteArray) -> void:
	if _peer_open(peer_id):
		snapshot_bytes_sent += data.size()
		rpc_snapshot.rpc_id(peer_id, data)


func _peer_open(peer_id: int) -> bool:
	var ws := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	if ws == null:
		return false
	var socket := ws.get_peer(peer_id)
	return socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN


## Eventos de combate vão para todos os jogadores (Fase 3: só para quem está perto).
func broadcast(peers: Array, method: StringName, args: Array) -> void:
	for peer_id: int in peers:
		send_to(peer_id, method, args)


func send_to(peer_id: int, method: StringName, args: Array) -> void:
	if _peer_open(peer_id):
		callv("rpc_id", [peer_id, method] + args)


@rpc("authority", "call_remote", "reliable")
func rpc_player_state(state: PackedInt64Array) -> void:
	player_state_received.emit(state)


@rpc("authority", "call_remote", "reliable")
func rpc_cast_event(caster_id: int, spell_index: int, target_id: int, target_pos: Vector2, chain_ids: PackedInt32Array) -> void:
	cast_event_received.emit(caster_id, spell_index, target_id, target_pos, chain_ids)


@rpc("authority", "call_remote", "reliable")
func rpc_damage_event(target_id: int, amount: int, kind: int) -> void:
	damage_event_received.emit(target_id, amount, kind)


@rpc("authority", "call_remote", "reliable")
func rpc_attack_event(attacker_id: int, target_id: int) -> void:
	attack_event_received.emit(attacker_id, target_id)


@rpc("authority", "call_remote", "reliable")
func rpc_died_event(entity_id: int) -> void:
	died_event_received.emit(entity_id)


@rpc("authority", "call_remote", "reliable")
func rpc_level_up_event(entity_id: int, level: int) -> void:
	level_up_event_received.emit(entity_id, level)


@rpc("authority", "call_remote", "reliable")
func rpc_drop_spawned(drop_id: int, label: String, rarity: int, pos: Vector2) -> void:
	drop_spawned_received.emit(drop_id, label, rarity, pos)


@rpc("authority", "call_remote", "reliable")
func rpc_drop_removed(drop_id: int) -> void:
	drop_removed_received.emit(drop_id)


@rpc("authority", "call_remote", "reliable")
func rpc_cooldown(spell_index: int, seconds: float) -> void:
	cooldown_received.emit(spell_index, seconds)


@rpc("authority", "call_remote", "reliable")
func rpc_message(text: String) -> void:
	message_received.emit(text)


func send_journal_full(peer_id: int, region_id: String, strokes: Array[PackedVector2Array], marks: Array[Array]) -> void:
	rpc_journal_full.rpc_id(peer_id, region_id, strokes, marks)


func send_journal_point(peer_id: int, region_id: String, point: Vector2, new_stroke: bool) -> void:
	rpc_journal_point.rpc_id(peer_id, region_id, point, new_stroke)


func send_journal_mark(peer_id: int, region_id: String, symbol: String, point: Vector2, label: String) -> void:
	rpc_journal_mark.rpc_id(peer_id, region_id, symbol, point, label)


## Diário: estado completo de uma folha (ao entrar no mundo / trocar de região).
@rpc("authority", "call_remote", "reliable")
func rpc_journal_full(region_id: String, strokes: Array, marks: Array) -> void:
	journal_full_received.emit(region_id, strokes, marks)


## Diário: nova amostra do caminho (1 a cada journal.sample_distance_m).
@rpc("authority", "call_remote", "reliable")
func rpc_journal_point(region_id: String, point: Vector2, new_stroke: bool) -> void:
	journal_point_received.emit(region_id, point, new_stroke)


## Diário: nova marcação (marco descoberto, entrada, etc.).
@rpc("authority", "call_remote", "reliable")
func rpc_journal_mark(region_id: String, symbol: String, point: Vector2, label: String) -> void:
	journal_mark_received.emit(region_id, symbol, point, label)


@rpc("authority", "call_remote", "reliable")
func rpc_welcome(my_id: int, tick_rate_hz: int) -> void:
	welcome_received.emit(my_id, tick_rate_hz)


## "unreliable_ordered" é tratado como confiável no WebSocket; fica assim
## para um futuro transporte WebRTC poder descartar snapshots velhos.
@rpc("authority", "call_remote", "reliable") # delta por jogador: precisa chegar tudo, em ordem
func rpc_snapshot(data: PackedByteArray) -> void:
	var s := _decoder.decode(data)
	if not s.is_empty():
		_lagged(func() -> void: snapshot_received.emit(int(s["tick"]), s["ids"], s["metas"], s["states"]))


## Medição de latência: o cliente manda o próprio relógio; o servidor devolve igual.
func send_ping() -> void:
	if is_online_client():
		var sent := Time.get_ticks_msec()
		_lagged(func() -> void: rpc_ping.rpc_id(Protocol.SERVER_PEER_ID, sent))


@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_ping(sent_ms: int) -> void:
	if is_server:
		ping_requested.emit(multiplayer.get_remote_sender_id(), sent_ms)


@rpc("authority", "call_remote", "unreliable_ordered")
func rpc_pong(sent_ms: int) -> void:
	_lagged(func() -> void: pong_received.emit(sent_ms))


## Debug (--sim-lag-ms=N, só no cliente): atrasa as intenções de movimento/magia, o ping
## e os snapshots em N ms cada, simulando uma ida e volta de 2N ms. Mantém a ordem.
var sim_lag_ms: int = -1


func _lagged(fn: Callable) -> void:
	if sim_lag_ms < 0:
		sim_lag_ms = 0
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--sim-lag-ms="):
				sim_lag_ms = arg.trim_prefix("--sim-lag-ms=").to_int()
	if sim_lag_ms == 0:
		fn.call()
	else:
		get_tree().create_timer(sim_lag_ms / 1000.0).timeout.connect(fn)
