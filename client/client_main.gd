extends Node3D
## Raiz do cliente: conecta ao servidor, envia INTENÇÕES e mostra o mundo a partir
## dos snapshots e eventos do servidor (o cliente nunca decide dano, drop ou XP).
## Controles: clique no chão = andar | clique no monstro = ataque básico contínuo |
## clique no item = pegar | 1–9 = magias | botão direito = magia selecionada |
## WASD = andar | J = diário | C = atributos.
## Fase 1: sem predição local — o próprio personagem também é interpolado.

const PLAYER_SCENE := preload("res://client/entities/avatar.tscn")
const GROUND_PLANE := Plane(Vector3.UP, 0.0)

var _my_id: int = 0
var _entities: Dictionary = {} # id -> Avatar (jogadores e monstros vivos)
var _drops: Dictionary = {} # id -> DropView
var _last_dir: Vector2 = Vector2.ZERO
var _click_held: bool = false
var _resend_interval: float
var _resend_timer: float = 0.0
var _has_focus: bool = true
var _journal: JournalMap
var _hud: Hud
var _inventory: InventoryWindow
var _vfx: VfxPlayer
var _catalog: ItemCatalog
var _appearances: Dictionary = {} # id -> PackedInt32Array (chega antes da entidade às vezes)
var _login: LoginScreen
var _auto_login: AutoLogin
var _quests_seen: bool = false
var _friends_seen: bool = false
var _friends_online: Dictionary = {}
var _credentials: Dictionary = {} # {account, password, character} da sessão atual (só em memória)
var _reconnect_pending: bool = false
var _kick_reason: String = ""
var _region_id: String = ""
var _sound: SoundDirector
var _ambience: AmbienceDirector
var _world_loaded: bool = false
var _nav_grids: Dictionary = {} # region_id -> NavGrid (predição)
var _journal_sheets := PackedStringArray() # regiões com folha no diário (teletransporte)
var _teleport_panel: TeleportPanel
var _predictor: LocalPredictor
var _alive: bool = true
var _rtt_ms: float = -1.0
var _tick_rate: int = 15
var _names: Dictionary = {} # id do jogador -> nome do personagem
var _tags: Dictionary = {} # id do jogador -> [Fora da Lei, herói]
var _my_outlaw: int = 0
var _player_guilds: Dictionary = {} # id do jogador -> [nome da guilda, símbolo]
var _my_guild: String = ""
var _war_enemy: String = "" # guilda inimiga na guerra atual
var _social: SocialWindow
var _mastery_window: MasteryWindow
var _siege_window: SiegeWindow
var _forge_window: ForgeWindow
var _shop_window: ShopWindow
var _storage_window: StorageWindow
var _trade_window: TradeWindow
var _party_frame: PartyFrame
var _prompt: PromptDialog
var _player_menu: PopupMenu
var _menu_target: String = "" # nome do jogador clicado
var _hovered_player: Avatar = null
var _safe: SafeZones
var _area_id: String = "?" # zona segura atual ("" = fora), para a faixa de área
var _region_name: String
var _npcs: Array[Dictionary] = [] # dados da região + nó visual
var _hovered_npc: Dictionary = {}
var _spells: Array[Dictionary] = []
var _basic_index: int = 0
var _my_class: String = ""
var _my_evolution: int = 0
var _player_classes: Dictionary = {} # id do jogador -> [classe, evolução]
var _spell_cache: Dictionary = {} # classe -> Array[Dictionary]
var _summon_types: Array = [] # tipos de invocação (mesma ordem do servidor)
var _quest_window: QuestWindow
var _quests: Dictionary = {}
var _monster_ids: PackedStringArray
var _monster_defs: Dictionary
var _monster_scenes: Dictionary = {} # caminho -> PackedScene
var _rarity_colors: Dictionary = {}
var _hover_radius: float
var _drop_hover_radius: float
var _hovered: Avatar = null
var _hovered_drop: DropView = null
var _target_id: int = 0 # último monstro atacado (quadro do alvo)

@onready var _entity_root: Node3D = $Entities
@onready var _camera_rig: IsoCameraRig = $CameraRig
@onready var _overlay: DebugOverlay = $DebugOverlay


func _ready() -> void:
	_resend_interval = 1.0 / GameConfig.get_f("network", "input_send_rate_hz")
	_hover_radius = GameConfig.get_f("ui", "hover_radius_m")
	_drop_hover_radius = GameConfig.get_f("ui", "drop_hover_radius_m")
	var rarity: Dictionary = GameConfig.get_value("ui", "rarity_colors")
	_rarity_colors = {
		Protocol.RARITY_NORMAL: GameConfig.color_of(rarity.get("normal")),
		Protocol.RARITY_EXCELLENT: GameConfig.color_of(rarity.get("excellent")),
		Protocol.RARITY_JEWEL: GameConfig.color_of(rarity.get("jewel")),
		Protocol.RARITY_CURRENCY: GameConfig.color_of(rarity.get("currency")),
		Protocol.RARITY_ANCESTRAL: GameConfig.color_of(rarity.get("ancestral")),
	}
	_monster_defs = MonsterCatalog.from_config() # inclui as variantes douradas, igual ao servidor
	_monster_ids = MonsterCatalog.type_ids(_monster_defs) # mesma ordem do servidor (type_index)
	_summon_types = SummonSystem.summon_type_ids(GameConfig.table("spells"))

	_vfx = VfxPlayer.new()
	_vfx.camera_rig = _camera_rig
	add_child(_vfx)
	_ambience = AmbienceDirector.new()
	add_child(_ambience)
	_sound = SoundDirector.new()
	add_child(_sound)
	_sound.enter_menu()
	var ui_fx := UiFx.new() # janelas: animação, arrastar, som de abrir e fechar
	ui_fx.sound = _sound
	add_child(ui_fx)
	_hud = Hud.new()
	add_child(_hud)
	_set_my_class(str(GameConfig.table("classes/index")["default"]), 0)
	_hud.add_stat_pressed.connect(Net.send_add_stat)
	_catalog = ItemCatalog.from_config()
	_inventory = InventoryWindow.new()
	_hud.add_child(_inventory)
	Net.inventory_received.connect(_inventory.set_items)
	_inventory.item_gained.connect(func(item_name: String, color: Color) -> void:
		_hud.show_toast(item_name, "+", color))
	Net.friends_state_received.connect(_toast_friends)
	Net.appearance_received.connect(_on_appearance)
	Net.player_state_received.connect(_on_player_state_for_inventory)
	_forge_window = ForgeWindow.new()
	_forge_window.setup(_inventory)
	_hud.add_child(_forge_window)
	_shop_window = ShopWindow.new()
	_shop_window.setup(_inventory)
	_hud.add_child(_shop_window)
	_storage_window = StorageWindow.new()
	_storage_window.setup(_inventory)
	_hud.add_child(_storage_window)
	_trade_window = TradeWindow.new()
	_trade_window.setup(_inventory)
	_hud.add_child(_trade_window)
	_party_frame = PartyFrame.new()
	_hud.add_child(_party_frame)
	_prompt = PromptDialog.new()
	_hud.add_child(_prompt)
	_player_menu = PopupMenu.new()
	_player_menu.add_item("Sussurrar", 0)
	_player_menu.add_item("Convidar para o grupo", 1)
	_player_menu.add_item("Propor troca", 2)
	_player_menu.add_item("Convidar para a guilda", 3)
	_player_menu.add_item("Adicionar amigo", 4)
	_player_menu.id_pressed.connect(_on_player_menu)
	_hud.add_child(_player_menu)
	_quest_window = QuestWindow.new()
	_hud.add_child(_quest_window)
	Net.quest_state_received.connect(func(q: Dictionary) -> void:
		_toast_quest_change(_quests, q)
		_quests = q
		_quest_window.set_state(q)
		_hud.set_quest_text(QuestWindow.tracker_text(q)))
	Net.buffs_received.connect(_hud.set_buffs)
	Net.event_schedule_received.connect(_hud.set_event_schedule)
	Net.event_state_received.connect(_hud.set_event_state)
	Net.event_state_received.connect(_update_event_ring)
	Net.event_world_received.connect(_on_event_world)
	_siege_window = SiegeWindow.new()
	_hud.add_child(_siege_window)
	Net.castle_state_received.connect(func(s: Dictionary) -> void:
		_shop_window.tax_pct = float(s.get("tax_pct", 0.0))
		_shop_window.tax_owner = str(s.get("owner", "")))
	_mastery_window = MasteryWindow.new()
	_hud.add_child(_mastery_window)
	_hud.mastery_pressed.connect(_mastery_window.toggle)
	_hud.system_pressed.connect(_on_system_button)
	_hud.reset_pressed.connect(Net.send_reset)
	Net.player_state_received.connect(func(s: PackedInt64Array) -> void:
		if s.size() == Protocol.PS.COUNT:
			_mastery_window.set_progress(s[Protocol.PS.MASTER_LEVEL], s[Protocol.PS.MASTER_XP], s[Protocol.PS.MASTER_XP_NEXT], s[Protocol.PS.MASTER_POINTS]))
	_social = SocialWindow.new()
	_hud.add_child(_social)
	_social.whisper_requested.connect(func(n: String) -> void: _hud.chat.open("/s %s " % n))
	_social.visibility_changed.connect(func() -> void: # o chat vai para o lado enquanto a janela está aberta
		var shift := _social.get_combined_minimum_size().x + 24.0 if _social.visible else 0.0
		_hud.chat.offset_left = 14.0 + shift
		_hud.chat.offset_right = 500.0 + shift)
	Net.player_guild_received.connect(_on_player_guild)
	Net.guild_state_received.connect(_on_guild_state)
	Net.trade_closed_received.connect(func(reason: String) -> void:
		_hud.add_message(reason, Color(0.95, 0.8, 0.45))
		_update_minimap_margin())
	Net.trade_state_received.connect(func(_s: Dictionary) -> void: _update_minimap_margin.call_deferred())
	_inventory.notice.connect(func(t: String) -> void: _hud.add_message(t, Color(0.95, 0.8, 0.45)))
	_inventory.sfx.connect(_sound.ui)
	Net.inventory_received.connect(func(_items: Array) -> void: _refresh_potions())
	Net.npc_opened.connect(_on_npc_opened)
	Net.npc_closed.connect(_on_npc_closed)
	Net.refine_fx_received.connect(_on_refine_fx)
	_region_id = str(GameConfig.table("world")["home_region"])
	_setup_region_content(GameConfig.region(_region_id))
	Net.region_changed_received.connect(_load_region)
	_journal = JournalMap.new()
	_journal.page_turned.connect(_sound.ui.bind("page"))
	add_child(_journal)
	_teleport_panel = TeleportPanel.new()
	_journal.add_full_side(_teleport_panel)
	Net.journal_sheets_received.connect(func(ids: PackedStringArray) -> void:
		_journal_sheets = ids
		_teleport_panel.set_sheets(ids, _region_id))

	_login = LoginScreen.new()
	add_child(_login)
	_login.entering.connect(func(acc: String, pw: String, char_name: String) -> void:
		_credentials = {"account": acc, "password": pw, "character": char_name})
	_auto_login = AutoLogin.new()
	add_child(_auto_login)
	_auto_login.failed.connect(func(m: String) -> void:
		_login.show_login()
		_login.show_status(m, Color(1.0, 0.45, 0.35)))
	Net.player_name_received.connect(_on_player_name)
	Net.player_tag_received.connect(_on_player_tag)
	Net.announce_received.connect(func(title: String, sub: String) -> void:
		_hud.show_event(title, sub)
		_hud.add_message("%s — %s" % [title, sub], Color(1.0, 0.8, 0.35)))
	Net.pong_received.connect(_on_pong)
	_send_ping_loop()
	if GameConfig.get_value("network", "prediction_enabled"):
		var half := GameConfig.get_f("movement", "world_half_extent_m")
		_predictor = LocalPredictor.new(_nav_grid_for(_region_id), half)
	Net.kicked.connect(func(reason: String) -> void:
		_credentials = {} # não entra sozinho de novo (evita derrubar a outra sessão em ciclo)
		_kick_reason = reason)
	Net.client_connected.connect(_on_connected)
	Net.client_failed.connect(func() -> void:
		_overlay.status_text = "Falha ao conectar"
		_schedule_reconnect())
	Net.client_disconnected.connect(_on_disconnected)
	Net.welcome_received.connect(_on_welcome)
	Net.snapshot_received.connect(_on_snapshot)
	Net.journal_full_received.connect(_journal.load_full)
	Net.journal_point_received.connect(_journal.add_point)
	Net.journal_mark_received.connect(_journal.add_mark)
	Net.player_state_received.connect(_hud.set_state)
	Net.cooldown_received.connect(_hud.on_cooldown)
	Net.message_received.connect(func(t: String) -> void: _hud.add_message(t))
	Net.cast_event_received.connect(_on_cast_event)
	Net.damage_event_received.connect(_on_damage_event)
	Net.attack_event_received.connect(_on_attack_event)
	Net.died_event_received.connect(_on_died_event)
	Net.level_up_event_received.connect(_on_level_up_event)
	Net.drop_spawned_received.connect(_on_drop_spawned)
	Net.drop_removed_received.connect(_on_drop_removed)

	_setup_debug_args()
	_set_world_ui(false)
	# Espera alguns frames (shaders compilados) antes de abrir o WebSocket.
	for i in GameConfig.get_i("network", "connect_after_frames"):
		await get_tree().process_frame
	_connect()


# ---------------------------------------------------------------- conexão, login e reconexão

func _connect() -> void:
	var url := _resolve_server_url()
	_overlay.status_text = "Conectando a %s…" % url
	var err := Net.connect_to_server(url)
	if err != OK:
		_overlay.status_text = "Erro de conexão: %s" % error_string(err)
		_schedule_reconnect()


## Com credenciais da sessão (ou de --login), entra sozinho; senão mostra a tela de login.
func _on_connected(_id: int) -> void:
	_reconnect_pending = false
	_overlay.status_text = "Conectado"
	if _credentials.is_empty():
		_login.show_login()
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--login-form="): # debug: conta:senha[:create] no formulário (create = conta nova)
				var p := arg.trim_prefix("--login-form=").split(":")
				_login.fill_and_submit.call_deferred(p[0], p[1], p.size() > 2 and p[2] == "create")
		if not _kick_reason.is_empty():
			_login.show_status(_kick_reason, Color(1.0, 0.7, 0.45))
			_kick_reason = ""
		return
	_login.passive = true
	_login.show_status("Entrando como %s…" % _credentials["character"], Color(0.85, 0.82, 0.74), true)
	_auto_login.start(_credentials["account"], _credentials["password"], _credentials["character"], str(_credentials.get("class", "")))


func _schedule_reconnect() -> void:
	if _reconnect_pending:
		return
	_reconnect_pending = true
	var wait := GameConfig.get_f("network", "reconnect_delay_s")
	_login.show_status("Conexão perdida. Tentando de novo em %d s…" % roundi(wait), Color(1.0, 0.7, 0.45), true)
	await get_tree().create_timer(wait).timeout
	_reconnect_pending = false
	if not Net.is_online_client():
		_login.show_status("Reconectando…", Color(1.0, 0.7, 0.45), true)
		_connect()


func _on_player_name(entity_id: int, character_name: String, class_id: String, evolution: int) -> void:
	_names[entity_id] = character_name
	_player_classes[entity_id] = [class_id, evolution]
	if entity_id == _my_id:
		_social.my_name = character_name
		if class_id != _my_class or evolution != _my_evolution:
			_set_my_class(class_id, evolution)
	_apply_class_look(entity_id)
	var view: Avatar = _entities.get(entity_id)
	if view != null:
		view.set_player_name(character_name)
		if _tags.has(entity_id):
			view.set_pvp_tag(_tags[entity_id][0], _tags[entity_id][1])


## Status de PvP (Fora da Lei / Herói): cor e título no nome.
func _on_player_tag(entity_id: int, outlaw: int, hero: int) -> void:
	_tags[entity_id] = [outlaw, hero]
	var view: Avatar = _entities.get(entity_id)
	if view != null:
		view.set_pvp_tag(outlaw, hero)
	if entity_id == _my_id:
		_my_outlaw = outlaw


## Anel do Círculo que Encolhe: uma parede translúcida no raio atual (some fora do evento).
func _update_event_ring(state: Dictionary) -> void:
	var ring: MeshInstance3D = get_node_or_null("World/EventRing")
	if not state.has("ring"):
		if ring != null:
			ring.queue_free()
		return
	var r: Array = state["ring"]
	if ring == null:
		ring = MeshInstance3D.new()
		ring.name = "EventRing"
		var wall := CylinderMesh.new()
		wall.top_radius = 1.0
		wall.bottom_radius = 1.0
		wall.height = 3.0
		wall.cap_top = false
		wall.cap_bottom = false
		wall.radial_segments = 64
		wall.rings = 1
		ring.mesh = wall
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(0.7, 0.3, 1.0, 0.28)
		ring.material_override = mat
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_node("World").add_child(ring)
		ring.position = Vector3(float(r[0]), 1.5, float(r[1]))
		ring.scale = Vector3(float(r[2]), 1.0, float(r[2]))
	var t := create_tween()
	t.tween_property(ring, "scale", Vector3(float(r[2]), 1.0, float(r[2])), 1.0)


## Um bloqueio do evento abriu (grade, portão): o visual some e a predição passa a andar ali.
func _on_event_world(blocker_id: String) -> void:
	var data := GameConfig.region(_region_id)
	var node := get_node_or_null("World/Blockers/" + blocker_id)
	if node != null:
		var t := create_tween()
		t.tween_property(node, "position:y", -3.5, 1.2).set_ease(Tween.EASE_IN) # a grade desce no chão
		t.tween_callback(node.hide)
	if _predictor != null:
		WorldBuilder.apply_blockers(_predictor.grid, data, false, [blocker_id])
	_hud.show_event(str(data.get("name", "")), "A grade se abriu!" if blocker_id == "grade" else "O portão caiu!")


## Magias de uma classe (cópias com "id"), na ordem da rede.
func _spells_for(class_id: String) -> Array[Dictionary]:
	if not _spell_cache.has(class_id):
		var list: Array[Dictionary] = []
		var table := GameConfig.table("spells")
		if ResourceLoader.exists("res://data/classes/%s.json" % class_id):
			for id: String in GameConfig.table("classes/" + class_id)["spells"]:
				var s: Dictionary = table[id].duplicate()
				s["id"] = id
				list.append(s)
		_spell_cache[class_id] = list
	return _spell_cache[class_id]


## Classe do próprio personagem: barra de magias, título e o rótulo de dano.
func _set_my_class(class_id: String, evolution: int) -> void:
	_my_class = class_id
	_my_evolution = evolution
	_spells = _spells_for(class_id)
	_basic_index = 0
	for i in _spells.size():
		if int(_spells[i]["slot"]) == 0:
			_basic_index = i
	_hud.setup_spells(_spells)
	_hud.set_class_info(LoginScreen.class_title(class_id, evolution), str(GameConfig.table("classes/" + class_id).get("damage_label", "Dano")), class_id)
	if _inventory != null: # no _ready, a barra é montada antes das janelas
		_inventory.player_class = class_id
	if _quest_window != null:
		_quest_window.player_class = class_id
		_quest_window.evolution = evolution


func _apply_class_look(entity_id: int) -> void:
	var view: Avatar = _entities.get(entity_id)
	if view == null or view.is_monster or view.is_summon or not _player_classes.has(entity_id):
		return
	var c: Array = _player_classes[entity_id]
	if not ResourceLoader.exists("res://data/classes/%s.json" % c[0]):
		return
	view.set_class_look(GameConfig.color_of(GameConfig.table("classes/" + str(c[0])).get("color")), int(c[1]) > 0, str(c[0]))


## Guilda de um jogador (nome e símbolo sobre a cabeça).
func _on_player_guild(entity_id: int, guild_name: String, symbol: String) -> void:
	if guild_name.is_empty():
		_player_guilds.erase(entity_id)
	else:
		_player_guilds[entity_id] = [guild_name, symbol]
	_apply_guild(entity_id)


## A própria guilda mudou (ou a guerra): as cores das outras guildas podem mudar.
func _on_guild_state(state: Dictionary) -> void:
	_my_guild = str(state.get("name", ""))
	_war_enemy = str((state.get("war", {}) as Dictionary).get("enemy", ""))
	for id: int in _entities:
		_apply_guild(id)


func _apply_guild(entity_id: int) -> void:
	var view: Avatar = _entities.get(entity_id)
	if view == null or view.is_monster:
		return
	var g: Array = _player_guilds.get(entity_id, ["", ""])
	var colors: Dictionary = GameConfig.table("guilds")["tag_colors"]
	var key := "own" if g[0] == _my_guild else ("enemy" if g[0] == _war_enemy else "other")
	view.set_guild(g[0], g[1], GameConfig.color_of(colors[key]))


# ---------------------------------------------------------------- debug

## --autowalk=x1,z1;x2,z2;... percorre os pontos em loop | --autofight luta sozinho
## | --open-journal abre o diário | --open-stats abre os atributos.
## Toast quando uma missão avança ou termina (compara o estado anterior com o novo).
func _toast_quest_change(before: Dictionary, after: Dictionary) -> void:
	if before.is_empty() and _quests_seen == false:
		_quests_seen = true # primeiro estado, ao entrar: não é novidade
		return
	var table := GameConfig.table("quests")
	for quest_id: String in after:
		if not table.has(quest_id):
			continue
		var a: Dictionary = after[quest_id]
		var b: Dictionary = before.get(quest_id, {})
		var q: Dictionary = table[quest_id]
		if bool(a.get("done", false)) and not bool(b.get("done", false)):
			_hud.show_toast("%s: concluída" % q["name"], "M", UiPalette.c("spectral"))
			_sound.ui("confirm")
		elif b.is_empty():
			_hud.show_toast("Nova missão: %s" % q["name"], "M", UiPalette.c("arcane"))
		elif int(a.get("step", 0)) != int(b.get("step", 0)):
			_hud.show_toast("%s: etapa nova" % q["name"], "M", UiPalette.c("arcane"))


## Toast quando um amigo entra no jogo.
func _toast_friends(list: Array) -> void:
	var online := {}
	for f: Array in list:
		if bool(f[1]):
			online[str(f[0])] = true
	if _friends_seen:
		for n: String in online:
			if not _friends_online.has(n):
				_hud.show_toast("%s entrou no jogo" % n, "A", UiPalette.c("ok"))
	_friends_seen = true
	_friends_online = online


func _setup_debug_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--login="): # conta:senha:Personagem (cria o que não existir)
			var parts := arg.trim_prefix("--login=").split(":")
			if parts.size() >= 3:
				_credentials = {"account": parts[0], "password": parts[1], "character": parts[2], "class": parts[3] if parts.size() > 3 else ""}
		elif arg == "--quick-login": # conta e personagem novos, aleatórios
			var suffix := AutoLogin.random_suffix()
			_credentials = {"account": "teste_" + suffix, "password": "senha-de-teste", "character": "Teste" + suffix}
		elif arg == "--auto-accept": # debug: aceita convites e oferece tônicos numa troca
			Net.prompt_received.connect(func(_k: int, _f: String, _d: String) -> void:
				get_tree().create_timer(1.0).timeout.connect(_prompt.accept_current))
			Net.trade_state_received.connect(func(_s: Dictionary) -> void:
				if _inventory.items_in(ItemCatalog.CONTAINER_TRADE).is_empty():
					var uid := _inventory.best_consumable("heal_hp")
					if uid != 0:
						Net.send_trade_action(Protocol.Trade.ADD_ITEM, uid), CONNECT_ONE_SHOT)
		elif arg.begins_with("--flip-shot="): # debug: captura a virada de página (caminho.png:ms)
			var spec := arg.trim_prefix("--flip-shot=")
			var cut := spec.rfind(":")
			var shot_path := spec.left(cut)
			var shot_ms := spec.substr(cut + 1).to_int()
			var first := [true]
			Net.region_changed_received.connect(func(_id: String) -> void:
				if first[0]:
					first[0] = false # a primeira é a entrada no mundo
					return
				await get_tree().create_timer(shot_ms / 1000.0).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(shot_path)
				print("[flip-shot] %s" % shot_path)
				get_tree().quit())
		elif arg == "--prediction-report": # debug: imprime como a predição está indo
			_prediction_report_loop()
		elif arg == "--open-journal":
			_journal.toggle_full.call_deferred()
		elif arg.begins_with("--add-stat="): # debug: atributo:quantidade (0 força, 1 agilidade, 2 vitalidade, 3 energia)
			var st := arg.trim_prefix("--add-stat=").split(":")
			Net.welcome_received.connect(func(_id: int, _hz: int) -> void:
				await get_tree().create_timer(2.0).timeout
				Net.send_add_stat(st[0].to_int(), st[1].to_int()), CONNECT_ONE_SHOT)
		elif arg.begins_with("--use-item="): # debug: base:segundos — usa o item da mochila depois de entrar
			var spec := arg.trim_prefix("--use-item=").split(":")
			var base_id := spec[0]
			var delay := spec[1].to_float() if spec.size() > 1 else 2.0
			Net.welcome_received.connect(func(_id: int, _hz: int) -> void:
				await get_tree().create_timer(delay).timeout
				for item: Dictionary in _inventory.items_in(ItemCatalog.CONTAINER_INVENTORY):
					if str(item["base"]) == base_id:
						Net.send_item_action(Protocol.ITEM_USE, int(item["uid"]), 0, 0, 0)
						return, CONNECT_ONE_SHOT)
		elif arg.begins_with("--castle-enter="): # debug: segundos — vai ao Arauto e entra no cerco
			var wait_s := arg.trim_prefix("--castle-enter=").to_float()
			Net.welcome_received.connect(func(_id: int, _hz: int) -> void:
				await get_tree().create_timer(wait_s).timeout
				_intent_npc("arauto")
				await get_tree().create_timer(4.0).timeout
				Net.send_castle_action(Protocol.Castle.ENTER), CONNECT_ONE_SHOT)
		elif arg == "--open-mastery":
			Net.mastery_state_received.connect(func(_m: Dictionary) -> void:
				if not _mastery_window.visible: _mastery_window.toggle(), CONNECT_ONE_SHOT)
		elif arg == "--open-guild":
			var opened := [false] # abre quando entrar numa guilda (a primeira resposta é "sem guilda")
			Net.guild_state_received.connect(func(s: Dictionary) -> void:
				if not s.is_empty() and not opened[0]:
					opened[0] = true
					_social.toggle_tab(SocialWindow.TAB_GUILD))
		elif arg == "--open-friends":
			Net.friends_state_received.connect(func(_l: Array) -> void:
				if not _social.visible: _social.toggle_tab(SocialWindow.TAB_FRIENDS), CONNECT_ONE_SHOT)
		elif arg == "--open-stats":
			_hud.toggle_stats.call_deferred()
		elif arg.begins_with("--preview-notice="): # debug: event | toast | death | chat (capturas dos avisos)
			_run_preview_notice(arg.trim_prefix("--preview-notice="))
		elif arg == "--open-inventory":
			_toggle_inventory.call_deferred()
		elif arg.begins_with("--gm="):
			var gm_cmd := arg.trim_prefix("--gm=")
			Net.welcome_received.connect(func(_id: int, _hz: int) -> void: Net.send_gm(gm_cmd))
		elif arg.begins_with("--forge-demo"):
			_run_forge_demo(arg.ends_with("=combine"))
		elif arg.begins_with("--mouse-at="): # debug: posiciona o mouse (ex.: tooltip sobre a loja)
			var xy := arg.trim_prefix("--mouse-at=").split(",")
			_run_mouse_at(Vector2(xy[0].to_float(), xy[1].to_float()))
		elif arg.begins_with("--open-npc="):
			_run_open_npc(arg.trim_prefix("--open-npc="), "--store-demo" in OS.get_cmdline_user_args())
		elif arg.begins_with("--auto-equip-all"):
			Net.inventory_received.connect(_auto_equip_once)
		elif arg == "--autofight":
			_run_autofight()
		elif arg.begins_with("--autowalk="):
			var route := PackedVector2Array()
			for pair in arg.trim_prefix("--autowalk=").split(";"):
				var xz := pair.split(",")
				route.append(Vector2(xz[0].to_float(), xz[1].to_float()))
			_run_autowalk(route)


func _toggle_inventory() -> void:
	_inventory.toggle()
	if not _inventory.visible and _inventory.npc_mode != "":
		_close_npc_or_trade() # fechar a mochila fecha também a loja, o cofre, a forja ou a troca
	_update_minimap_margin()


## O minimapa (canto superior direito) se afasta das janelas abertas à direita.
func _update_minimap_margin() -> void:
	var margin := 0.0
	if _inventory.visible:
		margin = _inventory.get_combined_minimum_size().x + 14.0
		for w: Control in [_shop_window, _storage_window, _trade_window]:
			if w.visible:
				margin += w.get_combined_minimum_size().x + 10.0
	_journal.set_minimap_right_margin(margin)


func _close_npc_or_trade() -> void:
	if _inventory.npc_mode == "trade":
		Net.send_trade_action(Protocol.Trade.CANCEL)
	else:
		Net.send_npc_close()


## Menu do clique em outro jogador.
func _on_player_menu(id: int) -> void:
	match id:
		0:
			_hud.chat.open("/s %s " % _menu_target)
		1:
			Net.send_party_action(Protocol.Party.INVITE, _menu_target)
		2:
			Net.send_trade_action(Protocol.Trade.REQUEST, 0, _menu_target)
		3:
			Net.send_guild_action(Protocol.Guild.INVITE, _menu_target)
		4:
			Net.send_friend_action(Protocol.Friend.REQUEST, _menu_target)


func _typing() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit


# ---------------------------------------------------------------- intenções + predição local

func _intent_move_to(target: Vector2) -> void:
	Net.send_move_to(target)
	if _predicting_allowed():
		_begin_prediction()
		_predictor.on_move_to(target)


func _intent_move_dir(dir: Vector2) -> void:
	Net.send_move_dir(dir)
	if _predicting_allowed():
		if dir != Vector2.ZERO:
			_begin_prediction()
		_predictor.on_move_dir(dir)


func _intent_cast(spell_index: int, target_id: int, target_pos: Vector2, repeat: bool) -> void:
	_suspend_prediction()
	Net.send_cast(spell_index, target_id, target_pos, repeat)


func _intent_pickup(drop_id: int) -> void:
	_suspend_prediction()
	Net.send_pickup(drop_id)


func _intent_npc(npc_id: String) -> void:
	_suspend_prediction()
	Net.send_npc_interact(npc_id)


func _predicting_allowed() -> bool:
	return _predictor != null and _alive


## Começa a prever a partir de onde o personagem está DESENHADO (sem salto na tela).
func _begin_prediction() -> void:
	var me: Avatar = _entities.get(_my_id)
	if _predictor.active or me == null:
		return
	_predictor.blend_from(_xz(me.position))


func _suspend_prediction() -> void:
	if _predictor == null or not _predictor.active:
		return
	_predictor.suspend()
	var me: Avatar = _entities.get(_my_id)
	if me != null:
		me.predicted = false


## A cada frame de física: avança a previsão e põe o próprio avatar nela.
func _step_prediction(delta: float) -> void:
	if _predictor == null:
		return
	_predictor.step(delta)
	var me: Avatar = _entities.get(_my_id)
	if me == null:
		return
	me.predicted = _predictor.active
	if _predictor.active:
		var p := _predictor.render_position()
		me.position = Vector3(p.x, 0.0, p.y)
		me.rotation.y = lerp_angle(me.rotation.y, _predictor.ghost.yaw, 1.0 - exp(-20.0 * delta))


func _prediction_report_loop() -> void:
	var max_err := 0.0
	var samples := 0
	var err_sum := 0.0
	while is_inside_tree():
		await get_tree().create_timer(0.25).timeout
		var me: Avatar = _entities.get(_my_id)
		if _predictor == null or me == null or not _predictor.active:
			continue
		max_err = maxf(max_err, _predictor.last_error_m)
		err_sum += _predictor.last_error_m
		samples += 1
		if samples % 12 == 0:
			print("[predição] rtt %d ms | correções %d | erro de previsão médio %.2f m, máximo %.2f m (amostras %d)" % [
				roundi(_rtt_ms), _predictor.corrections, err_sum / samples, max_err, samples])


func _send_ping_loop() -> void:
	var interval := GameConfig.get_f("network", "ping_interval_s")
	while is_inside_tree():
		await get_tree().create_timer(interval).timeout
		if _my_id != 0:
			Net.send_ping()


func _on_pong(sent_ms: int) -> void:
	var rtt := float(Time.get_ticks_msec() - sent_ms)
	_rtt_ms = rtt if _rtt_ms < 0.0 else lerpf(_rtt_ms, rtt, 0.3)
	if _predictor != null:
		_predictor.rtt_ms = _rtt_ms
	_overlay.status_text = "Online como #%d (servidor %d Hz) · ping %d ms%s" % [_my_id, _tick_rate,
		roundi(_rtt_ms), (" · predição: %d correções" % _predictor.corrections) if _predictor != null else ""]

# ---------------------------------------------------------------- regiões

## O servidor mudou o jogador de região: troca a cena, os NPCs, as zonas seguras,
## os portais e a grade da predição. O diário vira a página quando a folha nova chega.
func _load_region(instance_id: String) -> void:
	var region_id := instance_id.get_slice("@", 0) # instância de evento: "fortaleza@1" usa os dados de "fortaleza"
	if region_id == _region_id and _world_loaded:
		return
	_world_loaded = true
	if region_id == _region_id:
		return
	_region_id = region_id
	_sound.set_region(region_id)
	var data := GameConfig.region(region_id)
	var old := get_node_or_null("World")
	if old != null:
		remove_child(old)
		old.queue_free()
	var scene: PackedScene = load(str(data["scene"]))
	var world := scene.instantiate()
	world.name = "World"
	add_child(world)
	move_child(world, 0)
	_close_npc_windows()
	for a: Avatar in _entities.values():
		a.queue_free()
	_entities.clear()
	_hovered = null
	_hovered_player = null
	for d: DropView in _drops.values():
		d.queue_free()
	_drops.clear()
	_hovered_drop = null
	_setup_region_content(data)
	_teleport_panel.set_sheets(_journal_sheets, region_id)
	if _predictor != null:
		_predictor.grid = _nav_grid_for(region_id)
		WorldBuilder.apply_blockers(_predictor.grid, data, true) # evento: grade e portão começam fechados
		_predictor.suspend()
	if not data.has("event"):
		_hud.set_event_state({})
	_area_id = "?"
	_hud.show_area(_region_name, "nível %d ou mais" % int(data.get("level_req", 1)) if int(data.get("level_req", 1)) > 1 else "")
	_hud.set_location(_region_name, "")


## NPCs, zonas seguras e portais da região atual (a cena já está em $World).
func _setup_region_content(data: Dictionary) -> void:
	_safe = SafeZones.new(data)
	_region_name = str(data.get("name", ""))
	_npcs.clear()
	_hovered_npc = {}
	var world := get_node("World")
	_ambience.apply(world, str(data.get("id", "")))
	for npc: Dictionary in data.get("npcs", []):
		var entry := npc.duplicate()
		entry["node"] = world.get_node_or_null(str(npc.get("scene_node", "")))
		if entry["node"] != null and entry["node"].has_method("set_display_name"):
			entry["node"].set_display_name(str(npc["name"]))
		_npcs.append(entry)
	for pt: Dictionary in data.get("portals", []):
		var view := PortalView.new()
		view.setup(pt, GameConfig.color_of(pt.get("color", [0.6, 0.35, 1.0])))
		world.add_child(view)


## Grade de navegação da região (para a predição), montada uma vez por região.
func _nav_grid_for(region_id: String) -> NavGrid:
	if not _nav_grids.has(region_id):
		_nav_grids[region_id] = WorldBuilder.build_nav_grid(GameConfig.region(region_id), GameConfig.get_f("movement", "world_half_extent_m"))
	return _nav_grids[region_id]

func _refresh_potions() -> void:
	_hud.set_potions(_inventory.count_consumable("heal_hp"), _inventory.count_consumable("heal_mana"))


func _use_potion(effect_type: String) -> void:
	var uid := _inventory.best_consumable(effect_type)
	if uid == 0:
		_hud.add_message("Sem %s." % ("tônicos de vida" if effect_type == "heal_hp" else "essências de mana"), Color(0.8, 0.6, 0.5))
		return
	Net.send_item_action(Protocol.ITEM_USE, uid, 0, 0, 0)


var _auto_equipped: Dictionary = {}


## Debug: equipa (uma vez cada) os itens equipáveis que chegarem ao inventário.
func _auto_equip_once(encoded: Array) -> void:
	for a: PackedInt32Array in encoded:
		var item := ItemCodec.decode(a, _catalog)
		if item.is_empty() or _auto_equipped.has(item["uid"]):
			continue
		var is_plain := int(item["level"]) == 0 and int(item["rarity"]) == ItemCatalog.RARITY_NORMAL
		if int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY and _catalog.is_equipment(item) and not is_plain:
			_auto_equipped[item["uid"]] = true
			Net.send_item_action(Protocol.ITEM_AUTO, int(item["uid"]), 0, 0, 0)
			return # um por vez: cada troca gera um novo inventário


## Debug: anda até a forja e coloca um refino +9 -> +10 na mesa (e combina, se pedido).
func _run_forge_demo(combine: bool) -> void:
	await _wait_online()
	_intent_npc("forja")
	while not _forge_window.visible:
		await get_tree().create_timer(0.2).timeout
	for base in ["vara_eclipse", "joia_consagrada", "joia_alma", "joia_vortice", "talisma_fortuna"]:
		for item: Dictionary in _inventory.items_in(ItemCatalog.CONTAINER_INVENTORY):
			if str(item["base"]) == base:
				Net.send_item_action(Protocol.ITEM_MOVE, int(item["uid"]), ItemCatalog.CONTAINER_FORGE, 0, 0)
				break
		await get_tree().create_timer(0.3).timeout
	if combine:
		await get_tree().create_timer(1.0).timeout
		Net.send_forge_combine()


func _run_mouse_at(pos: Vector2) -> void:
	await _wait_online()
	while is_inside_tree():
		get_viewport().warp_mouse(pos)
		await get_tree().create_timer(0.5).timeout


## Debug: espera entrar no mundo (e os comandos de GM chegarem) antes de agir.
func _wait_online() -> void:
	while _my_id == 0:
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(1.0).timeout


## Debug: mostra um aviso para captura (não passa pelo servidor).
func _run_preview_notice(kind: String) -> void:
	await _wait_online()
	match kind:
		"event":
			_hud.show_event("Fortaleza Sitiada", "Os portões se abrem em 5 minutos. Fale com o Arauto no Refúgio.")
		"toast":
			_hud.show_toast("Lâmina Partida +3", "+", UiPalette.c("frost"))
			_hud.show_toast("Nova missão: O Despertar", "M", UiPalette.c("arcane"))
			_hud.show_toast("Morgrath entrou no jogo", "A", UiPalette.c("ok"))
		"death":
			_hud.notices.set_death(false, 7000)
		"chat":
			_hud.add_message("Bem-vindo às Ruínas de Vel'Morth.")
			_hud.chat._on_chat(Protocol.Chat.GENERAL, "Morgrath", "alguém para a fortaleza?")
			_hud.chat._on_chat(Protocol.Chat.PARTY, "Ysra", "vou na frente, me sigam")
			_hud.chat._on_chat(Protocol.Chat.GUILD, "Halden", "guerra às 21h, todos online")
			_hud.chat._on_chat(Protocol.Chat.WHISPER, "Ysra", "tem tônico sobrando?")
			_hud.chat.open()


## Debug: fala com um NPC; com --store-demo, guarda no cofre os itens soltos da mochila.
func _run_open_npc(npc_id: String, store: bool) -> void:
	await _wait_online()
	_intent_npc(npc_id)
	if not store:
		return
	while not _storage_window.visible:
		await get_tree().create_timer(0.2).timeout
	for item: Dictionary in _inventory.items_in(ItemCatalog.CONTAINER_INVENTORY):
		if not _catalog.is_consumable(item):
			Net.send_item_action(Protocol.ITEM_MOVE, int(item["uid"]), ItemCatalog.CONTAINER_STORAGE, -1, -1)
			await get_tree().create_timer(0.15).timeout


func _run_autowalk(route: PackedVector2Array) -> void:
	var i := 0
	while is_inside_tree() and not route.is_empty():
		var me: Avatar = _entities.get(_my_id)
		if me != null:
			var target := route[i % route.size()]
			_intent_move_to(target)
			if Vector2(me.position.x, me.position.z).distance_to(target) < 0.6:
				i += 1
		await get_tree().create_timer(0.25).timeout


func _run_autofight() -> void:
	var cycle := 0
	while is_inside_tree():
		await get_tree().create_timer(1.1).timeout
		var me: Avatar = _entities.get(_my_id)
		if me == null:
			continue
		var best: Avatar = null
		for a: Avatar in _entities.values():
			if a.is_monster and not a.dying and (best == null or a.position.distance_to(me.position) < best.position.distance_to(me.position)):
				best = a
		if best == null:
			continue
		cycle += 1
		var spell: int = [_basic_index, 1, _basic_index, 3, 2][cycle % 5]
		_hud.set_selected(spell)
		_intent_cast(spell, best.entity_id, Vector2(best.position.x, best.position.z), spell == _basic_index)


## Ordem: --url=... na linha de comando; na Web, ?server=... na URL da página;
## na Web sem parâmetro, o mesmo host da página (wss:// atrás de proxy TLS em produção);
## por fim, network.default_server_url.
func _resolve_server_url() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--url="):
			return arg.trim_prefix("--url=")
	if OS.has_feature("web"):
		var param: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('server')", true)
		if param is String and not (param as String).is_empty():
			return param
		var host := str(JavaScriptBridge.eval("window.location.hostname", true))
		if str(JavaScriptBridge.eval("window.location.protocol", true)) == "https:":
			return "wss://%s/ws" % host
		return "ws://%s:%d" % [host, GameConfig.get_i("network", "port")]
	return GameConfig.get_s("network", "default_server_url")


# ---------------------------------------------------------------- input -> intenções

func _unhandled_input(event: InputEvent) -> void:
	if _my_id == 0 or _journal.is_full_open():
		return
	if event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		return
	if event.is_action_pressed("ui_cancel") and _inventory.held_uid() != 0:
		_inventory.cancel_held()
		return
	if event.is_action_pressed("ui_cancel") and _inventory.npc_mode != "":
		_close_npc_or_trade()
		return
	if event.is_action_pressed("use_potion_hp"):
		_use_potion("heal_hp")
		return
	if event.is_action_pressed("use_potion_mana"):
		_use_potion("heal_mana")
		return
	if event.is_action_pressed("click_move") and _inventory.drop_held_to_world():
		return # soltou o item segurado fora da janela: vai para o chão
	if event.is_action_pressed("click_move"):
		_update_hover()
		if _hovered != null and _hovered.is_monster:
			_target_id = _hovered.entity_id
			_intent_cast(_basic_index, _hovered.entity_id, _xz(_hovered.position), true)
		elif not _hovered_npc.is_empty():
			_intent_npc(str(_hovered_npc["id"]))
		elif _hovered_player != null and Input.is_key_pressed(KEY_CTRL):
			# Ctrl+clique: ataque básico contínuo no jogador (PvP; o servidor confere as regras)
			_intent_cast(_basic_index, _hovered_player.entity_id, _xz(_hovered_player.position), true)
		elif _hovered_player != null:
			_menu_target = _hovered_player.display_name
			_player_menu.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(8, 8)
			_player_menu.popup()
		elif _hovered_drop != null:
			_intent_pickup(_hovered_drop.drop_id)
		else:
			_click_held = true
			_resend_timer = 0.0
			_send_click_target(true)
	elif event.is_action_released("click_move"):
		_click_held = false
	elif event.is_action_pressed("cast_selected"):
		_cast(_hud.selected_index())
	elif event.is_action_pressed("toggle_stats"):
		_hud.toggle_stats()
	elif event.is_action_pressed("toggle_mastery"):
		_mastery_window.toggle()
	elif event.is_action_pressed("toggle_guild"):
		_social.toggle_tab(SocialWindow.TAB_GUILD)
	elif event.is_action_pressed("toggle_friends"):
		_social.toggle_tab(SocialWindow.TAB_FRIENDS)
	elif event.is_action_pressed("toggle_fullscreen"):
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		for slot in range(1, 10):
			if event.is_action_pressed("skill_%d" % slot):
				for i in _spells.size():
					if int(_spells[i]["slot"]) == slot:
						_hud.set_selected(i)
						_cast(i)
				break


## Botão de sistema do HUD: age como a tecla da mesma ação (cada janela já trata a sua).
func _on_system_button(action: StringName) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)


## Usa a magia no monstro sob o mouse; sem monstro, no ponto do chão.
func _cast(index: int) -> void:
	if index < 0:
		return
	_update_hover()
	if _hovered != null and _hovered.is_monster:
		_target_id = _hovered.entity_id
		_intent_cast(index, _hovered.entity_id, _xz(_hovered.position), false)
		return
	if _hovered_player != null and Input.is_key_pressed(KEY_CTRL):
		_intent_cast(index, _hovered_player.entity_id, _xz(_hovered_player.position), false)
		return
	var hit: Variant = _mouse_ground()
	if hit is Vector3:
		_intent_cast(index, 0, _xz(hit), false)


func _process(_delta: float) -> void:
	var me: Avatar = _entities.get(_my_id)
	if me != null:
		_journal.set_player(_xz(me.position), me.rotation.y)
		var zone := _safe.zone_at(_xz(me.position))
		var zone_id := str(zone.get("id", ""))
		if zone_id != _area_id:
			if zone_id != "":
				_hud.show_area(str(zone["name"]), "zona segura · sem combate")
				_hud.set_location(str(zone["name"]), "%s · zona segura" % _region_name)
			else:
				if _area_id != "?":
					_hud.show_area(_region_name, "cuidado: aqui se luta")
				_hud.set_location(_region_name, "aqui se luta")
			_area_id = zone_id
	_update_hover()
	var target: Avatar = _hovered if _hovered != null and _hovered.is_monster else _entities.get(_target_id)
	if target != null and not target.dying:
		_hud.set_target(target.display_name, target.monster_level, target.hp_frac)
	else:
		_hud.set_target("", 0, 0.0)


func _physics_process(delta: float) -> void:
	_step_prediction(delta)
	if not _has_focus or _my_id == 0 or _journal.is_full_open():
		return
	var dir := _keyboard_direction()
	if not dir.is_equal_approx(_last_dir):
		_last_dir = dir
		_intent_move_dir(dir)
	if _click_held and dir == Vector2.ZERO:
		_resend_timer -= delta
		if _resend_timer <= 0.0:
			_resend_timer = _resend_interval
			_send_click_target(false)


## WASD relativo à câmera, convertido para o plano XZ do mundo.
func _keyboard_direction() -> Vector2:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO or _typing(): # digitando no chat: WASD são letras
		return Vector2.ZERO
	var yaw := _camera_rig.yaw()
	var right := Vector2(cos(yaw), -sin(yaw))
	var forward := Vector2(-sin(yaw), -cos(yaw))
	return (right * input.x - forward * input.y).limit_length(1.0)


func _send_click_target(show_marker: bool) -> void:
	var hit: Variant = _mouse_ground()
	if hit is Vector3:
		_intent_move_to(_xz(hit))
		if show_marker:
			_vfx.click_marker(hit)


func _mouse_ground() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	return GROUND_PLANE.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))


## Monstro sob o mouse: menor distância entre o raio da câmera e o eixo do corpo.
func _update_hover() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var best: Avatar = null
	var best_d := _hover_radius
	for a: Avatar in _entities.values():
		if not a.is_monster or a.dying:
			continue
		var d := _ray_point_distance(origin, dir, a.aim_point())
		if d < best_d:
			best_d = d
			best = a
	if best != _hovered:
		if is_instance_valid(_hovered):
			_hovered.set_hovered(false)
		_hovered = best
		if best != null:
			best.set_hovered(true)
	var npc_hit: Dictionary = {}
	if best == null:
		for npc: Dictionary in _npcs:
			var p := Vector3(float(npc["pos"][0]), 1.4, float(npc["pos"][1]))
			if _ray_point_distance(origin, dir, p) < 1.0:
				npc_hit = npc
	if npc_hit != _hovered_npc:
		if not _hovered_npc.is_empty() and _hovered_npc["node"] != null:
			_hovered_npc["node"].hovered = false
		_hovered_npc = npc_hit
		if not npc_hit.is_empty() and npc_hit["node"] != null:
			npc_hit["node"].hovered = true
	# outro jogador sob o mouse (para o menu: sussurrar, grupo, troca)
	var player_hit: Avatar = null
	if best == null and npc_hit.is_empty():
		var best_pd := _hover_radius
		for a: Avatar in _entities.values():
			if a.is_monster or a.is_local or a.dying or a.is_summon:
				continue
			var d := _ray_point_distance(origin, dir, a.aim_point())
			if d < best_pd:
				best_pd = d
				player_hit = a
	if player_hit != _hovered_player:
		if is_instance_valid(_hovered_player):
			_hovered_player.set_hovered(false)
		_hovered_player = player_hit
		if player_hit != null:
			player_hit.set_hovered(true)
	var drop: DropView = null
	if best == null and npc_hit.is_empty() and player_hit == null:
		var hit: Variant = _mouse_ground()
		if hit is Vector3:
			var best_drop := _drop_hover_radius
			for dv: DropView in _drops.values():
				var dd := Vector2(dv.position.x, dv.position.z).distance_to(_xz(hit))
				if dd < best_drop:
					best_drop = dd
					drop = dv
	if drop != _hovered_drop:
		if is_instance_valid(_hovered_drop):
			_hovered_drop.set_hovered(false)
		_hovered_drop = drop
		if drop != null:
			drop.set_hovered(true)


static func _ray_point_distance(origin: Vector3, dir: Vector3, p: Vector3) -> float:
	var t := maxf(0.0, (p - origin).dot(dir))
	return p.distance_to(origin + dir * t)


static func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _notification(what: int) -> void:
	# Aba/janela perdeu o foco: para de mandar input, mas mantém a conexão.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_has_focus = false
		_click_held = false
		if _last_dir != Vector2.ZERO:
			_last_dir = Vector2.ZERO
			_intent_move_dir(Vector2.ZERO)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_has_focus = true


# ---------------------------------------------------------------- servidor -> visual

## HUD e minimapa só aparecem com um personagem no mundo.
func _set_world_ui(on: bool) -> void:
	_hud.visible = on
	_journal.set_world_visible(on)
	# o texto de depuração não cobre a arte da tela de entrada; no mundo, só com F3 (ou --debug-hud)
	_overlay.visible = on and "--debug-hud" in OS.get_cmdline_user_args()


func _on_welcome(my_id: int, tick_rate_hz: int) -> void:
	_my_id = my_id
	_login.visible = false
	_login.passive = false
	_set_world_ui(true)
	_sound.enter_world(_region_id)
	_party_frame.my_id = my_id
	_tick_rate = tick_rate_hz
	_overlay.status_text = "Online como #%d (servidor %d Hz)" % [my_id, tick_rate_hz]
	_hud.add_message("Bem-vindo às %s." % GameConfig.region(GameConfig.get_s("movement", "start_region")).get("name", ""))


func _on_disconnected() -> void:
	_overlay.status_text = "Desconectado do servidor"
	_hud.add_message("Conexão perdida.", Color(1.0, 0.4, 0.3))
	_my_id = 0
	_set_world_ui(false)
	_sound.enter_menu()
	_close_npc_windows()
	_trade_window.close()
	_party_frame.set_members([])
	_social.set_guild_state({})
	_social.set_friends([])
	_social.hide()
	_player_guilds.clear()
	_hovered_player = null
	if _inventory.visible:
		_toggle_inventory()
	for a: Avatar in _entities.values():
		a.queue_free()
	_entities.clear()
	_hovered = null
	for d: DropView in _drops.values():
		d.queue_free()
	_drops.clear()
	_hovered_drop = null
	_schedule_reconnect()


func _on_snapshot(tick: int, ids: PackedInt32Array, metas: PackedInt32Array, states: Dictionary) -> void:
	var now := float(Time.get_ticks_msec())
	var entities := states
	for i in ids.size():
		var id := ids[i]
		var s: Vector4 = entities[id]
		var view: Avatar = _entities.get(id)
		if view == null:
			view = _spawn_view(id, metas[i])
			if view == null:
				continue
		view.push_sample(now, s.x, s.y, s.z)
		if id == _my_id and _predictor != null:
			if view.predicted or _predictor.active:
				_predictor.reconcile(Vector2(s.x, s.y), now, 1000.0 / _tick_rate)
			else:
				_predictor.reset(Vector2(s.x, s.y))
		view.set_hp(s.w)
	for id: int in _entities.keys():
		if not entities.has(id):
			(_entities[id] as Avatar).queue_free()
			_entities.erase(id)
	_overlay.players_visible = _entities.size()
	_overlay.last_tick = tick


func _spawn_view(id: int, meta: int) -> Avatar:
	var view: Avatar
	if Protocol.meta_kind(meta) == Protocol.KIND_MONSTER:
		var type_index := Protocol.meta_type(meta)
		if type_index < 0 or type_index >= _monster_ids.size():
			return null
		var def: Dictionary = _monster_defs[_monster_ids[type_index]]
		var path := str(def["visual"])
		if not _monster_scenes.has(path):
			_monster_scenes[path] = load(path)
		view = (_monster_scenes[path] as PackedScene).instantiate()
		_entity_root.add_child(view)
		view.monster_type = _monster_ids[type_index]
		view.setup_monster(id, def)
	elif Protocol.meta_kind(meta) == Protocol.KIND_SUMMON:
		var type_index := Protocol.meta_type(meta)
		if type_index < 0 or type_index >= _summon_types.size():
			return null
		var spell: Dictionary = GameConfig.table("spells")[_summon_types[type_index]]
		var sdef: Dictionary = spell["summon"]
		var spath := str(sdef["visual"])
		if not _monster_scenes.has(spath):
			_monster_scenes[spath] = load(spath)
		view = (_monster_scenes[spath] as PackedScene).instantiate()
		_entity_root.add_child(view)
		view.setup_summon(id, sdef, GameConfig.color_of(spell.get("color")), "")
	else:
		view = PLAYER_SCENE.instantiate()
		_entity_root.add_child(view)
		view.setup_player(id, id == _my_id)
		if _names.has(id):
			view.set_player_name(_names[id])
		if _tags.has(id):
			view.set_pvp_tag(_tags[id][0], _tags[id][1])
		_entities[id] = view
		if _player_guilds.has(id):
			_apply_guild(id)
		_apply_class_look(id)
		if id == _my_id:
			_sound.local_avatar = view
			_ambience.follow = view
			_camera_rig.target = view
			_camera_rig.snap_to_target.call_deferred()
	_entities[id] = view
	if _appearances.has(id):
		view.set_appearance(_appearances[id], _catalog)
	return view


func _on_npc_opened(npc_id: String) -> void:
	_close_npc_windows()
	var npc: Dictionary = {}
	for n: Dictionary in _npcs:
		if str(n["id"]) == npc_id:
			npc = n
	if npc.is_empty():
		return
	if str(npc["role"]) == "siege":
		_siege_window.open()
		return
	if str(npc["role"]) == "quest":
		_quest_window.player_level = _hud.state[Protocol.PS.LEVEL] if _hud.state.size() == Protocol.PS.COUNT else 1
		_quest_window.open(npc)
		_sound.ui("page")
		return
	if not _inventory.visible:
		_inventory.toggle()
	match str(npc["role"]):
		"vortex_forge":
			_forge_window.open()
		"shop":
			_shop_window.open(str(npc.get("shop", "")))
			_hud.add_message("%s: %s" % [npc["name"], GameConfig.table("shops")["shops"].get(str(npc.get("shop", "")), {}).get("greeting", "")], Color(0.9, 0.8, 0.6))
		"storage":
			_storage_window.open()
			_sound.ui("latch")
	_update_minimap_margin.call_deferred()


func _on_npc_closed() -> void:
	_close_npc_windows()
	_update_minimap_margin()


func _close_npc_windows() -> void:
	_quest_window.close()
	_siege_window.close()
	_forge_window.close()
	_shop_window.close()
	_storage_window.close()
	_inventory.set_external_tooltip({})


func _on_refine_fx(entity_id: int, outcome: int, level: int) -> void:
	var view: Avatar = _entities.get(entity_id)
	if view != null:
		_vfx.refine(view, outcome, level)
		if view == _sound.local_avatar:
			_sound.ui("confirm" if outcome == Protocol.FX_SUCCESS else "error")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot-on-fx="): # debug: captura o efeito do refino
			await get_tree().create_timer(0.35).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--screenshot-on-fx="))
			get_tree().quit()


func _on_player_state_for_inventory(s: PackedInt64Array) -> void:
	if s.size() == Protocol.PS.COUNT:
		_inventory.set_player(int(s[Protocol.PS.LEVEL]), int(s[Protocol.PS.CURRENCY]))
		_alive = s[Protocol.PS.ALIVE] == 1
		if _predictor != null:
			_predictor.speed = s[Protocol.PS.MOVE_SPEED_CMS] / 100.0
			if not _alive:
				_suspend_prediction()


func _on_appearance(entity_id: int, appearance: PackedInt32Array) -> void:
	_appearances[entity_id] = appearance
	var view: Avatar = _entities.get(entity_id)
	if view != null:
		view.set_appearance(appearance, _catalog)


func _on_cast_event(caster_id: int, spell_index: int, target_id: int, target_pos: Vector2, chain_ids: PackedInt32Array) -> void:
	var caster_spells := _spells if caster_id == _my_id else _spells_for(str(_player_classes.get(caster_id, [_my_class, 0])[0]))
	if spell_index < 0 or spell_index >= caster_spells.size():
		return
	var chain: Array[Avatar] = []
	for cid in chain_ids:
		var v: Avatar = _entities.get(cid)
		if v != null:
			chain.append(v)
	_vfx.play_cast(caster_spells[spell_index], _entities.get(caster_id), _entities.get(target_id),
		Vector3(target_pos.x, 0.0, target_pos.y), chain, caster_id == _my_id)
	_sound.cast(caster_spells[spell_index], _entities.get(caster_id), _entities.get(target_id), Vector3(target_pos.x, 0.0, target_pos.y))


func _on_damage_event(target_id: int, amount: int, kind: int) -> void:
	if amount == 0: # portão de evento ainda protegido pelas runas
		var shielded: Avatar = _entities.get(target_id)
		if shielded != null:
			_vfx.floating_text(shielded.aim_point() + Vector3.UP * 0.8, "protegido", Color(1.0, 0.7, 0.35), 0.9)
		return
	var view: Avatar = _entities.get(target_id)
	if view != null:
		_vfx.damage_number(view, amount, kind)


func _on_attack_event(attacker_id: int, target_id: int) -> void:
	_vfx.melee_hit(_entities.get(attacker_id), _entities.get(target_id))
	_sound.attack(_entities.get(attacker_id), _entities.get(target_id))


func _on_died_event(entity_id: int) -> void:
	var view: Avatar = _entities.get(entity_id)
	if view == null:
		return
	if view.is_monster:
		_entities.erase(entity_id) # sai do snapshot; a animação de morte se remove sozinha
		if _hovered == view:
			_hovered = null
		_vfx.death(view)
		_sound.monster_died(view)
	elif entity_id == _my_id:
		_vfx.shake(0.4)
		_sound.player_died()


func _on_level_up_event(entity_id: int, level: int) -> void:
	var view: Avatar = _entities.get(entity_id)
	if view != null:
		_vfx.level_up(view, level)
		_sound.level_up(view)


func _on_drop_spawned(drop_id: int, label: String, rarity: int, pos: Vector2) -> void:
	if _drops.has(drop_id):
		return
	var dv := DropView.new()
	_entity_root.add_child(dv)
	dv.position = Vector3(pos.x, 0.0, pos.y)
	dv.setup(drop_id, label, rarity, _rarity_colors.get(rarity, Color.WHITE))
	_drops[drop_id] = dv


func _on_drop_removed(drop_id: int) -> void:
	var dv: DropView = _drops.get(drop_id)
	if dv != null:
		if _hovered_drop == dv:
			_hovered_drop = null
		dv.queue_free()
		_drops.erase(drop_id)
