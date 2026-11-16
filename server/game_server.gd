class_name GameServer
extends Node
## Servidor autoritativo (roda headless). A tick fixo: executa as ações dos jogadores,
## resolve magias, roda a IA dos monstros de TODAS as regiões, regenera, alimenta o
## diário e replica snapshots (cada jogador só recebe a própria região, perto dele).
## O cliente só envia intenções; dano, drops, XP e atributos são decididos aqui.

var now: float = 0.0
var rng := RandomNumberGenerator.new()
var combat_cfg: Dictionary
var players: Dictionary = {} # peer_id -> ServerPlayer (o id da entidade é o peer_id)
var regions: Dictionary = {} # region_id -> RegionInstance
var home_region: String
var spells: SpellSystem
var catalog: ItemCatalog
var factory: ItemFactory
var inventory: InventoryService
var forge: ForgeSystem
var shops: ShopSystem
var item_use: ItemUseSystem
var classes: Dictionary = {} # class_id -> dados (data/classes/<id>.json)
var default_class: String
var summons: SummonSystem
var events: EventSystem
var mastery: MasterySystem
var castle: CastleSystem
var quests: QuestSystem
var repo: GameRepository
var accounts: AccountService
var chat: ChatService
var party: PartySystem
var trades: TradeSystem
var invasions: InvasionSystem
var pvp: PvpSystem
var guilds: GuildSystem
var friends: FriendSystem

var _tick: int = 0
var _accumulator: float = 0.0
var _tick_interval: float
var _max_ticks_per_frame: int
var _tick_rate_hz: int
var _spawn_radius: float
var _half_extent: float
var _stats_interval: float
var _stats_timer: float = 0.0
var _world: Dictionary
var _journal: JournalService
var _calcs: Dictionary = {} # class_id -> StatCalculator
var _progression: Progression
var _player_respawn_s: float
var _autosave_interval: float = 60.0
var _autosave_timer: float = 0.0
var _encoders: Dictionary = {} # peer_id -> SnapshotCodec.Encoder
var _interest_radius: float
var _interest_hysteresis: float
var _bytes_mark: int = 0
var _next_monster_id: int = -1
var _next_drop_id: int = 1


func _ready() -> void:
	rng.randomize()
	_tick_rate_hz = GameConfig.get_i("network", "tick_rate_hz")
	_tick_interval = 1.0 / float(_tick_rate_hz)
	_max_ticks_per_frame = GameConfig.get_i("network", "max_ticks_per_frame")
	_stats_interval = GameConfig.get_f("network", "stats_log_interval_s")
	_spawn_radius = GameConfig.get_f("movement", "spawn_radius_m")
	_half_extent = GameConfig.get_f("movement", "world_half_extent_m")
	_world = GameConfig.table("world")
	home_region = str(_world["home_region"])
	combat_cfg = GameConfig.table("combat")
	var class_index := GameConfig.table("classes/index")
	default_class = str(class_index["default"])
	for class_id: String in class_index["order"]:
		classes[class_id] = GameConfig.table("classes/" + class_id)
		_calcs[class_id] = StatCalculator.new(classes[class_id]["derived"])
	_progression = Progression.new(GameConfig.table("progression"))
	_player_respawn_s = float(GameConfig.table("progression")["player_respawn_s"])
	_interest_radius = GameConfig.get_f("network", "interest_radius_m")
	_interest_hysteresis = GameConfig.get_f("network", "interest_hysteresis_m")

	catalog = ItemCatalog.from_config()
	factory = ItemFactory.new(catalog, GameConfig.table("drops")["item_rolls"], rng)
	inventory = InventoryService.new(catalog)
	spells = SpellSystem.new(self, classes, GameConfig.table("spells"))
	summons = SummonSystem.new(self, GameConfig.table("spells"))
	quests = QuestSystem.new(self, GameConfig.table("quests"))
	for region_id: String in _world["regions"]:
		regions[region_id] = RegionInstance.new(self, region_id, _half_extent, GameConfig.get_f("network", "interest_cell_m"))
	invasions = InvasionSystem.new(self, GameConfig.table("events"))
	events = EventSystem.new(self, GameConfig.table("scheduled_events"))
	mastery = MasterySystem.new(self, GameConfig.table("mastery"), GameConfig.table("reset"))
	pvp = PvpSystem.new(self, GameConfig.table("pvp"))
	forge = ForgeSystem.new(self, GameConfig.table("refine"), GameConfig.table("recipes"))
	shops = ShopSystem.new(self, GameConfig.table("shops"))
	item_use = ItemUseSystem.new(self)
	_journal = JournalService.new()
	add_child(_journal)

	var db_path := GameConfig.get_s("server", "db_path")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--db="):
			db_path = arg.trim_prefix("--db=")
	repo = SqliteRepository.new(db_path)
	if not repo.open():
		push_error("[server] não foi possível abrir o banco em %s" % db_path)
		get_tree().quit(1)
		return
	factory.continue_after(repo.max_item_uid())
	accounts = AccountService.new(self, repo)
	var social := GameConfig.table("social")
	chat = ChatService.new(self, social)
	party = PartySystem.new(self, social)
	trades = TradeSystem.new(self, social)
	guilds = GuildSystem.new(self, GameConfig.table("guilds"), repo)
	friends = FriendSystem.new(self, social, repo)
	castle = CastleSystem.new(self, GameConfig.table("castle"), repo)
	_autosave_interval = GameConfig.get_f("server", "autosave_interval_s")
	print("[server] banco: %s" % (db_path if db_path == ":memory:" else ProjectSettings.globalize_path(db_path)))

	var port := GameConfig.get_i("network", "port")
	var bind := GameConfig.get_s("network", "bind_address")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--bind="):
			bind = arg.trim_prefix("--bind=")
	var err := Net.start_server(port, bind if bind != "" else "*")
	if err != OK:
		push_error("[server] falha ao abrir WebSocket em %s:%d: %s" % [bind, port, error_string(err)])
		get_tree().quit(1)
		return
	print("[server] escutando ws://%s:%d | tick %d Hz | protocolo v%d | regiões: %s" % [bind if bind != "" else "*", port, _tick_rate_hz, Protocol.VERSION, ", ".join(regions.keys())])

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Net.hello_received.connect(_on_hello)
	Net.move_to_requested.connect(_on_move_to)
	Net.move_dir_requested.connect(_on_move_dir)
	Net.cast_requested.connect(_on_cast)
	Net.pickup_requested.connect(_on_pickup)
	Net.add_stat_requested.connect(_on_add_stat)
	Net.item_action_requested.connect(_on_item_action)
	Net.npc_interact_requested.connect(_on_npc_interact)
	Net.npc_close_requested.connect(func(peer_id: int) -> void: _with_player(peer_id, _close_npc))
	Net.forge_combine_requested.connect(func(peer_id: int) -> void: _with_player(peer_id, _forge_combine))
	Net.shop_buy_requested.connect(_on_shop_buy)
	Net.shop_sell_requested.connect(_on_shop_sell)
	Net.teleport_requested.connect(func(peer_id: int, region_id: String) -> void:
		_with_player(peer_id, func(p: ServerPlayer) -> void: _teleport(p, region_id)))
	Net.login_requested.connect(func(peer_id: int, account: String, password: String, create: bool) -> void:
		accounts.login(peer_id, account, password, create))
	Net.create_character_requested.connect(func(peer_id: int, n: String, c: String) -> void: accounts.create_character(peer_id, n, c))
	Net.castle_action_requested.connect(func(peer_id: int, action: int, value: int) -> void:
		_with_player(peer_id, func(p: ServerPlayer) -> void: castle.handle(p, action, value)))
	Net.reset_requested.connect(func(peer_id: int) -> void: _with_player(peer_id, mastery.do_reset))
	Net.mastery_spend_requested.connect(func(peer_id: int, node_id: String) -> void:
		_with_player(peer_id, func(p: ServerPlayer) -> void: mastery.spend(p, node_id)))
	Net.quest_action_requested.connect(func(peer_id: int, action: int, quest_id: String) -> void:
		_with_player(peer_id, func(p: ServerPlayer) -> void: quests.handle(p, action, quest_id)))
	Net.enter_world_requested.connect(func(peer_id: int, id: int) -> void: accounts.enter_world(peer_id, id))
	Net.ping_requested.connect(func(peer_id: int, sent_ms: int) -> void: Net.send_to(peer_id, &"rpc_pong", [sent_ms]))
	Net.chat_requested.connect(func(peer_id: int, channel: int, target: String, text: String) -> void:
		_with_player(peer_id, func(p: ServerPlayer) -> void: chat.handle(p, channel, target, text)))
	Net.party_action_requested.connect(func(peer_id: int, action: int, target: String) -> void:
		_with_player(peer_id, func(p: ServerPlayer) -> void: party.handle(p, action, target)))
	Net.trade_action_requested.connect(func(peer_id: int, action: int, value: int, target: String) -> void:
		_with_player(peer_id, func(p: ServerPlayer) -> void: trades.handle(p, action, value, target)))
	Net.guild_action_requested.connect(func(peer_id: int, action: int, target: String, extra: String) -> void:
		_with_player(peer_id, func(p: ServerPlayer) -> void: guilds.handle(p, action, target, extra)))
	Net.friend_action_requested.connect(func(peer_id: int, action: int, target: String) -> void:
		_with_player(peer_id, func(p: ServerPlayer) -> void: friends.handle(p, action, target)))
	if "--allow-gm" in OS.get_cmdline_user_args():
		Net.gm_requested.connect(_on_gm)
		print("[server] comandos de GM habilitados")


func _process(delta: float) -> void:
	_accumulator += delta
	var ticks := 0
	while _accumulator >= _tick_interval and ticks < _max_ticks_per_frame:
		_accumulator -= _tick_interval
		now += _tick_interval
		_simulate(_tick_interval)
		_tick += 1
		ticks += 1
		_broadcast_snapshot()
		_send_player_states()
	if ticks == _max_ticks_per_frame:
		_accumulator = 0.0 # servidor atrasado: descarta em vez de entrar em espiral

	_stats_timer += delta
	if _stats_timer >= _stats_interval:
		_stats_timer = 0.0
		_log_stats()
	_autosave_timer += delta
	if _autosave_timer >= _autosave_interval:
		_autosave_timer = 0.0
		save_all()
		accounts.update()


func peers() -> Array:
	return players.keys()


func region_of(p: ServerPlayer) -> RegionInstance:
	return regions.get(p.region_id, regions[home_region])


func next_monster_id() -> int:
	_next_monster_id -= 1
	return _next_monster_id + 1


func next_drop_id() -> int:
	_next_drop_id += 1
	return _next_drop_id - 1


# ---------------------------------------------------------------- conexões

func _on_peer_connected(peer_id: int) -> void:
	print("[server] peer %d conectou (aguardando hello)" % peer_id)


func _with_player(peer_id: int, fn: Callable) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null:
		fn.call(p)


func _close_npc(p: ServerPlayer) -> void:
	region_of(p).npcs.close(p)
	send_inventory(p)


func _on_shop_buy(peer_id: int, stock_index: int, quantity: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null:
		shops.buy(p, stock_index, quantity)
		send_inventory(p)


func _on_shop_sell(peer_id: int, uid: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null and p.items.has(uid):
		shops.sell(p, uid)
		recompute(p)
		send_inventory(p)


## Cópia de uma região para um evento (fica em `regions` enquanto o evento dura).
func create_instance(region_id: String, instance_id: String) -> RegionInstance:
	var inst := RegionInstance.new(self, region_id, _half_extent, GameConfig.get_f("network", "interest_cell_m"), instance_id)
	regions[instance_id] = inst
	return inst


func remove_instance(region: RegionInstance) -> void:
	region.drops.drops.clear() # ninguém mais está lá dentro
	region.monsters.monsters.clear() # quebra o ciclo região <-> monstro
	regions.erase(region.id)


## Pergaminho do Retorno: leva ao ponto de retorno da cidade (região inicial).
func teleport_to_return_point(p: ServerPlayer) -> void:
	transfer_player(p, home_region, regions[home_region].point("return_point"))


func _forge_combine(p: ServerPlayer) -> void:
	forge.combine(p)
	send_inventory(p)
	broadcast_appearance(p)


func _on_npc_interact(peer_id: int, npc_id: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or not p.alive or not region_of(p).npcs.has(npc_id):
		return
	if trades.is_trading(p):
		send_message(peer_id, "Termine a troca primeiro.")
		return
	p.move_dir = Vector2.ZERO
	p.action = {"type": "npc", "npc_id": npc_id}
	p.next_repath = 0.0


func _on_peer_disconnected(peer_id: int) -> void:
	_encoders.erase(peer_id)
	logout_player(peer_id)
	accounts.on_disconnect(peer_id)


## Hello só confere a versão; o personagem entra depois do login (AccountService).
func _on_hello(peer_id: int, protocol_version: int) -> void:
	if protocol_version != Protocol.VERSION:
		print("[server] peer %d recusado: protocolo v%d (esperado v%d)" % [peer_id, protocol_version, Protocol.VERSION])
		Net.kick(peer_id)
		return
	if not accounts.sessions.has(peer_id):
		accounts.on_hello(peer_id)


## Estado inicial de um personagem novo (atributos, itens e magias da classe).
func new_character_record(account_id: int, character_name: String, class_id: String) -> Dictionary:
	var p := ServerPlayer.new()
	p.account_id = account_id
	p.char_name = character_name
	p.class_id = class_id if classes.has(class_id) else default_class
	p.region_id = home_region
	var cls: Dictionary = classes[p.class_id]
	for s in Protocol.STAT_KEYS:
		p.stats[s] = int(cls["base_stats"][s])
	inventory.init_player(p)
	for start: Dictionary in cls.get("starting_items", []):
		var item := factory.create(str(start["base"]))
		item["count"] = int(start.get("count", 1))
		if not (bool(start.get("equip", false)) and inventory.equip_direct(p, item)):
			inventory.give(p, item)
	p.learned_spells = spells.mask_of(p.class_id, cls.get("starting_spells", cls["spells"]))
	recompute(p)
	p.full_restore()
	p.position = regions[home_region].point("player_spawn")
	return CharacterCodec.to_record(p, {})


## Coloca no mundo um personagem carregado do banco.
func spawn_player(peer_id: int, record: Dictionary) -> void:
	if players.has(peer_id):
		return
	var p := ServerPlayer.new()
	p.id = peer_id
	p.peer_id = peer_id
	p.kind = Protocol.KIND_PLAYER
	CharacterCodec.apply(p, record, inventory)
	if not classes.has(p.class_id):
		p.class_id = default_class
	p.mastery_bonuses = MasterySystem.bonuses_for(p.mastery, mastery.nodes)
	recompute(p)
	if not regions.has(p.region_id) or regions[p.region_id].is_event() or p.hp <= 0.0 or not p.position.is_finite():
		p.region_id = home_region
		p.position = _spawn_point(regions[home_region])
		p.full_restore()
	var region := region_of(p)
	p.position = region.grid.nearest_walkable_point(p.position)
	p.hp = clampf(p.hp, 1.0, p.hp_max)
	p.mana = clampf(p.mana, 0.0, p.mana_max())
	players[peer_id] = p
	region.players[peer_id] = p
	Net.send_to(peer_id, &"rpc_region_changed", [p.region_id])
	Net.send_welcome(peer_id, _tick_rate_hz)
	_journal.player_joined(peer_id, p.region_id, p.position, record.get("journals", {}))
	_send_region_drops(p)
	send_inventory(p)
	broadcast_appearance(p)
	broadcast_identity(p)
	Net.send_to(peer_id, &"rpc_event_schedule", [events.schedule_rows()])
	pvp.broadcast_tag(p)
	pvp.send_tags_to(peer_id)
	guilds.on_enter(p)
	friends.on_enter(p)
	quests.send_state(p)
	mastery.send_state(p)
	castle.send_state(p)
	send_buffs(p)
	for other: ServerPlayer in players.values():
		if other != p:
			Net.send_to(peer_id, &"rpc_appearance", [other.id, inventory.appearance(other)])
			Net.send_to(peer_id, &"rpc_player_name", [other.id, other.char_name, other.class_id, other.evolution])
	print("[server] %s (personagem #%d, peer %d) entrou em %s (%.1f, %.1f) | online: %d" % [p.char_name, p.character_id, peer_id, p.region_id, p.position.x, p.position.y, players.size()])


## Salva e tira o personagem do mundo (desconexão ou a mesma conta entrando de novo).
func logout_player(peer_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	trades.on_disconnect(p) # devolve os itens oferecidos
	party.on_disconnect(p)
	summons.remove(peer_id, "")
	chat.forget(peer_id)
	var region := region_of(p)
	region.npcs.close(p) # devolve os itens da mesa da forja
	save_player(p)
	_journal.player_left(peer_id)
	region.monsters.forget_player(peer_id)
	region.players.erase(peer_id)
	players.erase(peer_id)
	events.on_left(p, region)
	guilds.on_leave(p)
	friends.on_leave(p)
	print("[server] %s saiu (salvo) | online: %d" % [p.char_name, players.size()])


## Leva o jogador para outra região (portal, teletransporte, pergaminho, renascimento)
## ou para outro ponto da mesma região. O cliente troca a cena e o diário vira a página.
func transfer_player(p: ServerPlayer, region_id: String, pos: Vector2) -> void:
	var from := region_of(p)
	var to: RegionInstance = regions.get(region_id)
	if to == null:
		return
	from.npcs.close(p)
	trades.cancel(p, "%s saiu da região; a troca foi cancelada." % p.char_name)
	from.monsters.forget_player(p.id)
	p.action = {}
	p.move_dir = Vector2.ZERO
	p.stop()
	p.position = to.grid.nearest_walkable_point(pos)
	if to == from:
		_journal.player_respawned(p.peer_id, p.position) # o lápis levanta e recomeça no destino
		return
	from.players.erase(p.peer_id)
	to.players[p.peer_id] = p
	p.region_id = to.id
	if from.is_event():
		events.on_left(p, from)
	_encoders.erase(p.peer_id) # o cliente zera o decodificador: tudo da nova região vai completo
	Net.send_to(p.peer_id, &"rpc_region_changed", [to.id])
	_journal.player_changed_region(p.peer_id, to.data_id, p.position) # o diário é por região (não por instância)
	_send_region_drops(p)
	send_message(p.peer_id, "Você chegou a %s." % to.display_name())
	print("[server] %s: %s -> %s em (%.1f, %.1f)" % [p.char_name, from.id, to.id, p.position.x, p.position.y])


## Teletransporte pelo diário: só para regiões cujas folhas o personagem já tem, com custo.
func _teleport(p: ServerPlayer, region_id: String) -> void:
	var to: RegionInstance = regions.get(region_id)
	if to == null or not p.alive or to.is_event():
		return
	if not _journal.has_sheet(p.peer_id, region_id):
		send_message(p.peer_id, "Você não conhece esse lugar: não há folha dele no seu diário.")
		return
	if p.level < to.level_req():
		send_message(p.peer_id, "%s exige nível %d." % [to.display_name(), to.level_req()])
		return
	if trades.is_trading(p):
		send_message(p.peer_id, "Termine a troca primeiro.")
		return
	var cost := int(to.data.get("teleport_cost", 0))
	if p.currency < cost:
		send_message(p.peer_id, "O teletransporte custa %d Óbolos." % cost)
		return
	p.currency -= cost
	transfer_player(p, region_id, to.point("teleport_point"))
	broadcast_near(region_of(p), p.position, &"rpc_level_up_event", [p.id, -3]) # brilho de chegada (sem texto)


## Portais: entrar no raio de um portal leva à região de destino (se o nível permitir).
func _check_portals(p: ServerPlayer) -> void:
	if _tick % int(_world["portal_check_interval_ticks"]) != 0 or not p.alive:
		return
	var region := region_of(p)
	for pt: Dictionary in region.portals():
		var pos := Vector2(float(pt["pos"][0]), float(pt["pos"][1]))
		if p.position.distance_to(pos) > float(pt["radius_m"]):
			continue
		var to: RegionInstance = regions.get(str(pt["to_region"]))
		if to == null:
			return
		if p.level < to.level_req():
			if now >= p.portal_message_at:
				p.portal_message_at = now + float(_world["portal_message_cooldown_s"])
				send_message(p.peer_id, "O portal resiste: %s exige nível %d." % [to.display_name(), to.level_req()])
			return
		var arrival := to.portal(str(pt["to_portal"]))
		var at: Vector2 = Vector2(float(arrival["arrival"][0]), float(arrival["arrival"][1])) if not arrival.is_empty() else to.point("teleport_point")
		transfer_player(p, to.id, at)
		return


func _send_region_drops(p: ServerPlayer) -> void:
	for drop: Dictionary in region_of(p).drops.all_drops():
		Net.send_to(p.peer_id, &"rpc_drop_spawned", [drop["id"], drop["label"], drop["rarity"], drop["pos"]])


## Avisa o motivo e derruba a conexão logo depois (dá tempo da mensagem sair).
func kick_with_reason(peer_id: int, reason: String) -> void:
	Net.send_to(peer_id, &"rpc_kicked", [reason])
	get_tree().create_timer(0.3).timeout.connect(Net.kick.bind(peer_id))


## Jogador online pelo nome do personagem (sem diferenciar maiúsculas).
func find_player_by_name(character_name: String) -> ServerPlayer:
	var key := character_name.strip_edges().to_lower()
	for p: ServerPlayer in players.values():
		if p.char_name.to_lower() == key:
			return p
	return null


func save_players(list: Array) -> bool:
	var records: Array = []
	for p: ServerPlayer in list:
		records.append(CharacterCodec.to_record(p, _journal.export_player(p.peer_id)))
	return repo.save_characters(records)


func save_player(p: ServerPlayer) -> bool:
	if p.character_id == 0:
		return false
	return repo.save_character(CharacterCodec.to_record(p, _journal.export_player(p.peer_id)))


func save_all() -> void:
	var t := Time.get_ticks_msec()
	var n := 0
	for p: ServerPlayer in players.values():
		if save_player(p):
			n += 1
	if n > 0:
		print("[server] salvamento automático: %d personagem(ns) em %d ms" % [n, Time.get_ticks_msec() - t])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if repo != null:
			save_all()
			repo.close()
			repo = null
		for region: RegionInstance in regions.values():
			region.monsters.monsters.clear() # quebra o ciclo região <-> monstro
			region.players.clear()
		regions.clear()


func _spawn_point(region: RegionInstance) -> Vector2:
	var base := region.point("player_spawn")
	return region.grid.nearest_walkable_point(base + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * _spawn_radius)


# ---------------------------------------------------------------- intenções (validadas)

func _on_move_to(peer_id: int, target: Vector2) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or not p.alive or not target.is_finite():
		return
	p.move_dir = Vector2.ZERO
	p.action = {"type": "move"}
	p.set_path(region_of(p).grid.find_path(p.position, target.clamp(Vector2(-_half_extent, -_half_extent), Vector2(_half_extent, _half_extent))))


func _on_move_dir(peer_id: int, direction: Vector2) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or not direction.is_finite():
		return
	p.move_dir = direction.limit_length(1.0)
	if p.move_dir != Vector2.ZERO:
		p.action = {}
		p.stop()


func _on_cast(peer_id: int, spell_index: int, target_id: int, target_pos: Vector2, repeat: bool) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or not p.alive or spells.spell(p, spell_index).is_empty() or not target_pos.is_finite():
		return
	p.move_dir = Vector2.ZERO
	p.action = {"type": "cast", "spell": spell_index, "target_id": target_id, "target_pos": target_pos, "repeat": repeat}
	p.next_repath = 0.0


func _on_pickup(peer_id: int, drop_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or not p.alive or region_of(p).drops.get_drop(drop_id).is_empty():
		return
	p.move_dir = Vector2.ZERO
	p.action = {"type": "pickup", "drop_id": drop_id}
	p.next_repath = 0.0


func _on_add_stat(peer_id: int, stat_index: int, amount: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or stat_index < 0 or stat_index >= Protocol.STAT_KEYS.size():
		return
	var n := clampi(amount, 0, p.points)
	if n == 0:
		return
	var key := Protocol.STAT_KEYS[stat_index]
	p.stats[key] = int(p.stats[key]) + n
	p.points -= n
	recompute(p)


## Comandos de GM (debug): "item <base> [nível] [raridade 0/1/2] [sorte 0/1] [extra] [quantidade]",
## "level <n>", "currency <n>", "goto <região> [x z]". Vários separados por ';'.
func _on_gm(peer_id: int, command: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	for cmd in command.split(";", false):
		var a := cmd.strip_edges().split(" ", false)
		if a.is_empty():
			continue
		match a[0]:
			"item":
				if a.size() < 2 or not catalog.bases.has(a[1]):
					send_message(peer_id, "GM: item desconhecido.")
					continue
				var item := factory.create(a[1])
				item["level"] = clampi(a[2].to_int() if a.size() > 2 else 0, 0, int(catalog.options["max_level"]))
				item["rarity"] = clampi(a[3].to_int() if a.size() > 3 else 0, 0, 2)
				item["luck"] = a.size() > 4 and a[4] == "1"
				item["extra"] = clampi(a[5].to_int() if a.size() > 5 else 0, 0, int(catalog.options["extra_max"]))
				item["count"] = clampi(a[6].to_int() if a.size() > 6 else 1, 1, catalog.stack_max(item))
				if not catalog.is_equipment(item):
					item["level"] = 0
				if int(item["rarity"]) == ItemCatalog.RARITY_EXCELLENT:
					var pool := catalog.excellent_pool(item)
					item["exc"] = Array(pool.slice(0, 2))
				if not inventory.give(p, item):
					send_message(peer_id, "GM: inventário cheio.")
			"level":
				p.level = clampi(a[1].to_int() if a.size() > 1 else 1, 1, _progression.max_level)
				p.points = (p.level - 1) * points_per_level(p) + p.resets * int(mastery.reset_cfg["points_per_reset"])
				recompute(p)
				p.full_restore()
			"currency":
				p.currency += a[1].to_int() if a.size() > 1 else 0
			"infamy":
				p.infamy = maxi(0, a[1].to_int() if a.size() > 1 else 0)
				pvp.broadcast_tag(p)
			"event": # event <id> open | start | end
				var why := events.gm(a[1] if a.size() > 1 else "", a[2] if a.size() > 2 else "")
				if why != "":
					send_message(peer_id, "GM: " + why)
			"quest": # quest <id> <passo> [contagem] | quest <id> done | quest <id> reset
				if a.size() > 2 and quests.quests.has(a[1]):
					if a[2] == "reset":
						p.quests.erase(a[1])
					elif a[2] == "done":
						p.quests[a[1]] = {"done": true}
					else:
						p.quests[a[1]] = {"step": a[2].to_int(), "count": a[3].to_int() if a.size() > 3 else 0}
					quests.send_state(p)
			"evolve":
				evolve(p)
			"castleowner": # a guilda do jogador fica com o castelo (ou "none")
				var cg := guilds.guild_of(p)
				castle.set_owner(cg.id if cg != null and (a.size() < 2 or a[1] != "none") else 0)
			"masterxp": # masterxp <n>: XP de maestria (no nível máximo)
				mastery.gain_xp(p, a[1].to_int() if a.size() > 1 else 0)
			"guildwar": # a guerra da guilda do jogador acaba em N s
				guilds.gm_end_war_in(p, a[1].to_float() if a.size() > 1 else 0.0)
			"invasion":
				var why := invasions.start(a[1] if a.size() > 1 else p.region_id)
				if why != "":
					send_message(peer_id, "GM: " + why)
			"boss": # chefe da região renasce agora
				for m: ServerMonster in region_of(p).monsters.monsters.values():
					if bool(m.def.get("boss", false)) and not m.alive:
						m.respawn_at = now
			"goto":
				if a.size() > 1 and regions.has(a[1]):
					var dest: RegionInstance = regions[a[1]]
					var at := Vector2(a[2].to_float(), a[3].to_float()) if a.size() > 3 else dest.point("teleport_point")
					transfer_player(p, a[1], at)
	print("[server] GM de %d: %s" % [peer_id, command])
	send_inventory(p)


func _on_item_action(peer_id: int, action: int, uid: int, dest: int, x: int, y: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or not p.items.has(uid):
		return
	var npcs := region_of(p).npcs
	var before := inventory.appearance(p)
	var err := ""
	if int(p.items[uid]["container"]) == ItemCatalog.CONTAINER_TRADE:
		send_message(peer_id, "Este item está na troca.")
		send_inventory(p)
		return
	var in_storage := int(p.items[uid]["container"]) == ItemCatalog.CONTAINER_STORAGE
	if in_storage and not (npcs.is_open(p, "storage") and action == Protocol.ITEM_MOVE
			and dest in [ItemCatalog.CONTAINER_INVENTORY, ItemCatalog.CONTAINER_STORAGE]):
		send_message(peer_id, "O cofre não está aberto.")
		send_inventory(p)
		return
	match action:
		Protocol.ITEM_MOVE:
			if dest == ItemCatalog.CONTAINER_INVENTORY:
				err = inventory.move_to_inventory(p, uid, x, y)
			elif dest == ItemCatalog.CONTAINER_STORAGE:
				err = inventory.to_storage(p, uid, x, y) if npcs.is_open(p, "storage") else "O cofre não está aberto."
			elif dest == ItemCatalog.CONTAINER_FORGE:
				err = inventory.to_forge(p, uid) if npcs.is_open(p, "vortex_forge") else "A forja não está aberta."
			elif dest >= 1 and dest <= ItemCatalog.EQUIP_SLOTS.size():
				err = inventory.equip(p, uid, ItemCatalog.EQUIP_SLOTS[dest - 1])
			else:
				err = "Destino inválido."
		Protocol.ITEM_AUTO:
			err = inventory.auto(p, uid)
		Protocol.ITEM_DROP:
			if not p.alive:
				err = "Agora não."
			else:
				var item := inventory.take(p, uid)
				region_of(p).drops.spawn_item(item, p.position, p.peer_id)
		Protocol.ITEM_USE_ON:
			forge.use_jewel(p, uid, dest)
		Protocol.ITEM_USE:
			item_use.use(p, uid)
		_:
			err = "Ação desconhecida."
	if not err.is_empty():
		send_message(peer_id, err)
	recompute(p)
	send_inventory(p)
	if inventory.appearance(p) != before:
		broadcast_appearance(p)


# ---------------------------------------------------------------- simulação

func _simulate(dt: float) -> void:
	for p: ServerPlayer in players.values():
		_update_player(p, dt)
	spells.update(dt)
	summons.update(dt)
	party.update(dt)
	trades.update()
	for region: RegionInstance in regions.values():
		region.monsters.update(dt)
		region.drops.update()
	invasions.update(dt)
	pvp.update(dt)
	events.update(dt)
	guilds.update(dt)
	friends.update(dt)


func _update_player(p: ServerPlayer, dt: float) -> void:
	if not p.alive:
		if now >= p.respawn_at:
			_respawn_player(p)
		return
	var region := region_of(p)
	p.hp = minf(p.hp_max, p.hp + float(p.derived.get("hp_regen_s", 0.0)) * dt)
	p.mana = minf(p.mana_max(), p.mana + float(p.derived.get("mana_regen_s", 0.0)) * dt)
	var speed := float(p.derived.get("move_speed_mps", 5.0))
	if p.move_dir != Vector2.ZERO:
		var step := p.move_dir * speed * dt
		p.position = region.grid.slide(p.position, step)
		p.yaw = atan2(p.move_dir.x, p.move_dir.y)
	elif not p.action.is_empty():
		match str(p.action["type"]):
			"move":
				p.follow_path(dt, speed)
				if not p.has_path():
					p.action = {}
			"cast":
				_update_cast(p, dt, speed)
			"pickup":
				_update_pickup(p, dt, speed)
			"npc":
				var npc_id := str(p.action["npc_id"])
				if region.npcs.in_range(p, npc_id):
					p.stop()
					p.action = {}
					region.npcs.open(p, npc_id)
				else:
					if now >= p.next_repath:
						p.next_repath = now + float(combat_cfg["repath_interval_s"])
						p.set_path(region.grid.find_path(p.position, region.npcs.npc_pos(npc_id)))
					p.follow_path(dt, speed)
					if not p.has_path():
						p.action = {}
	region.npcs.update(p)
	_journal.player_moved(p.peer_id, p.position, _tick)
	_check_portals(p)


func _update_cast(p: ServerPlayer, dt: float, speed: float) -> void:
	var region := region_of(p)
	var a := p.action
	var result := spells.try_cast(p, int(a["spell"]), int(a["target_id"]), a["target_pos"])
	match result:
		SpellSystem.Result.OK:
			if not bool(a["repeat"]):
				p.action = {}
		SpellSystem.Result.PVP_DENIED:
			send_message(p.peer_id, p.cast_error)
			p.action = {}
		SpellSystem.Result.OUT_OF_RANGE:
			var goal: Vector2 = a["target_pos"]
			var tid := int(a["target_id"])
			var chased: ServerEntity = players.get(tid) if tid > 0 else region.monsters.get_alive(tid)
			if chased != null:
				goal = chased.position
			if now >= p.next_repath:
				p.next_repath = now + float(combat_cfg["repath_interval_s"])
				p.set_path(region.grid.find_path(p.position, goal))
			p.follow_path(dt, speed)
		SpellSystem.Result.SAFE_ZONE:
			# dentro de uma zona segura: se o alvo está lá fora, anda até sair; senão, avisa
			var target_m: ServerMonster = region.monsters.get_alive(int(a["target_id"]))
			var aim: Vector2 = target_m.position if target_m != null else a["target_pos"]
			if region.safe.contains(aim) or not aim.is_finite() or SpellSystem.is_self_cast(spells.spell(p, int(a["spell"]))):
				send_message(p.peer_id, "Não se luta numa zona segura.")
				p.action = {}
			else:
				if now >= p.next_repath:
					p.next_repath = now + float(combat_cfg["repath_interval_s"])
					p.set_path(region.grid.find_path(p.position, aim))
				p.follow_path(dt, speed)
		SpellSystem.Result.NOT_LEARNED:
			var unknown := spells.spell(p, int(a["spell"]))
			send_message(p.peer_id, "Esta magia vem com a evolução de classe (Ancião Varek, no Refúgio)." if bool(unknown.get("evolution", false))
				else "Você ainda não conhece esta magia (grimório na loja da Alquimista).")
			p.action = {}
		SpellSystem.Result.COOLDOWN:
			p.stop()
		SpellSystem.Result.NO_MANA:
			send_message(p.peer_id, "Mana insuficiente.")
			p.action = {}
		SpellSystem.Result.INVALID:
			# alvo morto num ataque contínuo: para em silêncio; magia lançada no vazio: avisa
			if int(a["target_id"]) == 0:
				send_message(p.peer_id, "Nenhum alvo.")
			p.action = {}


func _update_pickup(p: ServerPlayer, dt: float, speed: float) -> void:
	var region := region_of(p)
	var drop := region.drops.get_drop(int(p.action["drop_id"]))
	if drop.is_empty():
		p.action = {}
		return
	if p.position.distance_to(drop["pos"]) <= region.drops.pickup_range():
		var err := region.drops.try_pickup(p, int(drop["id"]))
		if not err.is_empty():
			send_message(p.peer_id, err)
		p.action = {}
		p.stop()
		return
	if now >= p.next_repath:
		p.next_repath = now + float(combat_cfg["repath_interval_s"])
		p.set_path(region.grid.find_path(p.position, drop["pos"]))
	p.follow_path(dt, speed)


## Renasce na cidade da região (respawn_region) ou na própria região.
func _respawn_player(p: ServerPlayer) -> void:
	p.alive = true
	p.full_restore()
	var inside := events.respawn_point(p) # cerco: volta ao próprio lado, sem sair do evento
	if inside != Vector2.INF:
		transfer_player(p, region_of(p).id, inside)
		return
	var target: RegionInstance = regions.get(str(region_of(p).data.get("respawn_region", p.region_id)), region_of(p))
	transfer_player(p, target.id, _spawn_point(target))


# ---------------------------------------------------------------- combate

func damage_monster(caster: ServerPlayer, m: ServerMonster, amount: int, kind: int) -> void:
	if not m.alive:
		return
	if not events.can_damage(m, caster):
		broadcast_near(m.region, m.position, &"rpc_damage_event", [m.id, 0, kind]) # runas protegem: 0
		return
	var region := m.region
	m.hp -= amount
	broadcast_near(region, m.position, &"rpc_damage_event", [m.id, amount, kind])
	region.monsters.on_damaged(m, caster, amount)
	if m.hp <= 0.0:
		region.monsters.kill(m)
		broadcast_near(region, m.position, &"rpc_died_event", [m.id])
		var killer: ServerPlayer = players.get(m.top_damager())
		if killer != null:
			killer.hp = minf(killer.hp_max, killer.hp + killer.hp_max * float(killer.derived.get("hp_on_kill_frac", 0.0)))
			killer.mana = minf(killer.mana_max(), killer.mana + killer.mana_max() * float(killer.derived.get("mana_on_kill_frac", 0.0)))
			party.distribute_xp(killer, m.position, roundi(_progression.monster_xp(m.level()) * float(m.def.get("xp_mult", 1.0))))
			region.drops.roll_for(m, killer.peer_id)
			pvp.on_monster_kill(killer)
			quests.on_monster_kill(killer, m)
			events.on_monster_killed(m, killer)
			if bool(m.def.get("boss", false)) and not bool(m.def.get("event_boss", false)): # chefe de evento: o evento avisa
				_on_boss_killed(m, killer)


func damage_player(attacker: ServerMonster, p: ServerPlayer, raw_amount: int, kind: int) -> void:
	var region := region_of(p)
	if not p.alive or region.safe.contains(p.position):
		return
	var amount := maxi(1, roundi(raw_amount * (1.0 - float(p.derived.get("damage_reduction_pct", 0.0)))))
	p.hp -= amount
	broadcast_near(region, p.position, &"rpc_damage_event", [p.id, amount, kind])
	var reflected := roundi(amount * float(p.derived.get("reflect_pct", 0.0)))
	if reflected > 0 and attacker.alive:
		damage_monster(p, attacker, reflected, Protocol.DMG_NORMAL)
	if p.hp <= 0.0:
		_kill_player(p, str(attacker.def["name"]))


## Dano de jogador em jogador (PvP). As regras (quem pode, autodefesa) já foram
## conferidas no PvpSystem; aqui só se aplica o golpe e, se for o caso, a morte.
func damage_player_by_player(attacker: ServerPlayer, p: ServerPlayer, raw_amount: int, kind: int) -> void:
	var region := region_of(p)
	if not p.alive or region.safe.contains(p.position):
		return
	var amount := maxi(1, roundi(raw_amount * (1.0 - float(p.derived.get("damage_reduction_pct", 0.0)))))
	p.hp -= amount
	broadcast_near(region, p.position, &"rpc_damage_event", [p.id, amount, kind])
	pvp.on_hit(attacker, p)
	var reflected := roundi(amount * float(p.derived.get("reflect_pct", 0.0)))
	if reflected > 0 and attacker.alive:
		attacker.hp -= reflected # reflexo não reflete de volta
		broadcast_near(region, attacker.position, &"rpc_damage_event", [attacker.id, reflected, Protocol.DMG_NORMAL])
		if attacker.hp <= 0.0:
			_kill_player(attacker, p.char_name)
	if p.hp <= 0.0:
		pvp.on_kill(attacker, p)
		_kill_player(p, attacker.char_name)


## Dano sem atacante (o anel do Círculo).
func damage_player_env(p: ServerPlayer, amount: int, cause: String) -> void:
	if not p.alive:
		return
	p.hp -= amount
	broadcast_near(region_of(p), p.position, &"rpc_damage_event", [p.id, amount, Protocol.DMG_NORMAL])
	if p.hp <= 0.0:
		_kill_player(p, cause)


func _kill_player(p: ServerPlayer, killer_name: String) -> void:
	var region := region_of(p)
	p.hp = 0.0
	p.alive = false
	p.action = {}
	p.move_dir = Vector2.ZERO
	p.stop()
	p.respawn_at = now + _player_respawn_s
	region.monsters.forget_player(p.id)
	broadcast_near(region, p.position, &"rpc_died_event", [p.id])
	send_message(p.peer_id, "Você foi derrotado por %s." % killer_name)
	_journal.player_died(p.peer_id, p.position)


func xp_to_next(level: int) -> int:
	return _progression.xp_to_next(level)


func max_level() -> int:
	return _progression.max_level


func give_xp(p: ServerPlayer, amount: int) -> void:
	if p.level >= _progression.max_level: # no nível máximo, a XP vai para a maestria
		mastery.gain_xp(p, amount)
		return
	var r := _progression.apply_xp(p.level, p.xp, amount)
	p.xp = r[1]
	if r[2] > 0:
		p.level = r[0]
		p.points += r[2] * points_per_level(p)
		recompute(p)
		p.full_restore()
		broadcast_near(region_of(p), p.position, &"rpc_level_up_event", [p.id, p.level])
		send_message(p.peer_id, "Nível %d! Você tem %d ponto(s) para distribuir (C)." % [p.level, p.points])


# ---------------------------------------------------------------- eventos do mundo

## Aviso para todos os jogadores (faixa no alto da tela e linha no chat).
func announce(title: String, subtitle: String) -> void:
	Net.broadcast(peers(), &"rpc_announce", [title, subtitle])


func on_boss_spawned(m: ServerMonster) -> void:
	announce("Um chefe despertou", "%s ronda %s" % [m.def["name"], m.region.display_name()])


## Chefe derrotado: aviso geral e marca no diário de quem ajudou a derrubá-lo.
func _on_boss_killed(m: ServerMonster, killer: ServerPlayer) -> void:
	announce("Chefe derrotado!", "%s caiu diante de %s" % [m.def["name"], killer.char_name])
	for peer_id: int in m.damage_by:
		var p: ServerPlayer = players.get(peer_id)
		if p != null and p.region_id == m.region.id:
			_journal.mark_here(peer_id, "skull", m.position, str(m.def["name"]))
	quests.on_boss_killed(m)
	print("[evento] chefe %s derrotado por %s (%d participante(s))" % [m.def_id, killer.char_name, m.damage_by.size()])

# ---------------------------------------------------------------- envio

func send_inventory(p: ServerPlayer) -> void:
	Net.send_to(p.peer_id, &"rpc_inventory", [inventory.encode_all(p)])


func recompute(p: ServerPlayer) -> void:
	p.recompute(calc_for(p), catalog)


func class_data(p: ServerPlayer) -> Dictionary:
	return classes.get(p.class_id, classes[default_class])


func calc_for(p: ServerPlayer) -> StatCalculator:
	return _calcs.get(p.class_id, _calcs[default_class])


## Pontos por nível da classe (+ o bônus da evolução, depois de evoluir).
func points_per_level(p: ServerPlayer) -> int:
	var cls := class_data(p)
	var n := int(cls["points_per_level"])
	if p.evolution > 0:
		n += int(cls.get("evolution", {}).get("points_per_level_bonus", 0))
	return n


## Nome do personagem com classe e evolução (rótulo e cor no cliente, magias dos outros).
func broadcast_identity(p: ServerPlayer) -> void:
	Net.broadcast(peers(), &"rpc_player_name", [p.id, p.char_name, p.class_id, p.evolution])


## Evolução de classe (recompensa da missão): título novo, magias da evolução e pontos.
func evolve(p: ServerPlayer) -> void:
	if p.evolution > 0:
		return
	var evo: Dictionary = class_data(p).get("evolution", {})
	p.evolution = 1
	p.learned_spells |= spells.mask_of(p.class_id, evo.get("spells", []))
	p.points += int(evo.get("points_bonus", 0))
	recompute(p)
	p.full_restore()
	broadcast_identity(p)
	broadcast_near(region_of(p), p.position, &"rpc_level_up_event", [p.id, -2]) # brilho de evolução
	announce("Evolução de classe!", "%s agora é %s" % [p.char_name, evo.get("name", "?")])
	send_message(p.peer_id, "Você evoluiu para %s: +%d pontos e uma magia nova (tecla %d)." % [evo.get("name", "?"),
		int(evo.get("points_bonus", 0)), _first_slot(p, evo.get("spells", []))])
	print("[classe] %s evoluiu para %s" % [p.char_name, evo.get("name", "?")])


func _first_slot(p: ServerPlayer, spell_ids: Array) -> int:
	for id: String in spell_ids:
		var i := spells.index_of(p.class_id, id)
		if i >= 0:
			return int(spells.spell(p, i)["slot"])
	return 0


## Bônus temporários do próprio jogador: [[nome, segundos restantes], ...].
func send_buffs(p: ServerPlayer) -> void:
	var list: Array = []
	for b: Dictionary in p.buffs.values():
		list.append([b["name"], maxf(0.0, float(b["until"]) - now)])
	Net.send_to(p.peer_id, &"rpc_buffs", [list])


func broadcast_refine_fx(p: ServerPlayer, outcome: int, level: int) -> void:
	broadcast_near(region_of(p), p.position, &"rpc_refine_fx", [p.id, outcome, level])


func broadcast_appearance(p: ServerPlayer) -> void:
	Net.broadcast(peers(), &"rpc_appearance", [p.id, inventory.appearance(p)])


func send_cooldown(peer_id: int, spell_index: int, seconds: float) -> void:
	Net.send_to(peer_id, &"rpc_cooldown", [spell_index, seconds])


func send_message(peer_id: int, text: String) -> void:
	Net.send_to(peer_id, &"rpc_message", [text])


func broadcast_cast(caster: ServerPlayer, spell_index: int, target_id: int, pos: Vector2, chain: PackedInt32Array) -> void:
	broadcast_near(region_of(caster), caster.position, &"rpc_cast_event", [caster.id, spell_index, target_id, pos, chain])


func broadcast_attack(attacker: ServerMonster, target_id: int) -> void:
	broadcast_near(attacker.region, attacker.position, &"rpc_attack_event", [attacker.id, target_id])


func broadcast_drop(region: RegionInstance, drop: Dictionary) -> void:
	Net.broadcast(region.peers(), &"rpc_drop_spawned", [drop["id"], drop["label"], drop["rarity"], drop["pos"]])


func broadcast_drop_removed(region: RegionInstance, drop_id: int) -> void:
	Net.broadcast(region.peers(), &"rpc_drop_removed", [drop_id])


## Interesse por área, por região: cada jogador recebe só as entidades da própria
## região a até interest_radius_m dele (com folga para quem já estava visível, para
## não piscar na borda). Snapshot binário com delta por jogador (SnapshotCodec.Encoder).
func _broadcast_snapshot() -> void:
	if players.is_empty():
		return
	for region: RegionInstance in regions.values():
		if region.players.is_empty():
			continue
		region.spatial.clear()
		for e: ServerEntity in region.players.values() + region.monsters.monsters.values() + summons.in_region(region):
			if e.kind == Protocol.KIND_MONSTER and not e.alive:
				continue
			region.spatial.insert(e, e.position)
		for p: ServerPlayer in region.players.values():
			var enc: SnapshotCodec.Encoder = _encoders.get(p.peer_id)
			if enc == null:
				enc = SnapshotCodec.Encoder.new()
				_encoders[p.peer_id] = enc
			var list: Array = []
			for e: ServerEntity in region.spatial.query(p.position, _interest_radius + _interest_hysteresis):
				if e != p and not enc.known.has(e.id) and e.position.distance_to(p.position) > _interest_radius:
					continue # na folga só fica quem já estava visível
				list.append([e.id, e.meta(), e.position, e.yaw, e.hp_frac()])
			Net.send_snapshot(p.peer_id, enc.encode(_tick, list))


## Peers que enxergam um ponto da região (para eventos de combate e efeitos).
func peers_near(region: RegionInstance, pos: Vector2) -> Array:
	var out: Array = []
	var r := _interest_radius + _interest_hysteresis
	for p: ServerPlayer in region.players.values():
		if p.position.distance_to(pos) <= r:
			out.append(p.peer_id)
	return out


func broadcast_near(region: RegionInstance, pos: Vector2, method: StringName, args: Array) -> void:
	Net.broadcast(peers_near(region, pos), method, args)


## Estado do próprio jogador: só envia quando muda.
func _send_player_states() -> void:
	for p: ServerPlayer in players.values():
		var respawn_ms := 0 if p.alive else int(maxf(0.0, p.respawn_at - now) * 1000.0)
		var s := p.state_array(_progression.xp_to_next(p.level), respawn_ms, mastery.xp_to_next(p.master_level) if p.level >= _progression.max_level else 0)
		if s != p.last_state:
			p.last_state = s
			Net.send_to(p.peer_id, &"rpc_player_state", [s])


func _log_stats() -> void:
	var parts := PackedStringArray()
	for p: ServerPlayer in players.values():
		parts.append("#%d nv%d hp%d/%d %s(%.1f,%.1f)" % [p.peer_id, p.level, ceili(p.hp), roundi(p.hp_max), p.region_id, p.position.x, p.position.y])
	var per_region := PackedStringArray()
	for region: RegionInstance in regions.values():
		var alive := 0
		for m: ServerMonster in region.monsters.monsters.values():
			if m.alive:
				alive += 1
		per_region.append("%s %dj/%dm" % [region.id, region.players.size(), alive])
	var kbps := (Net.snapshot_bytes_sent - _bytes_mark) / 1024.0 / _stats_interval
	_bytes_mark = Net.snapshot_bytes_sent
	print("[server] tick %d | online %d | %s | snapshots %.2f KB/s (%.0f B/s por jogador) | %s" % [_tick,
		players.size(), " · ".join(per_region), kbps, kbps * 1024.0 / maxi(1, players.size()), " ".join(parts)])
