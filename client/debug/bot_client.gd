class_name BotClient
extends Node
## Cliente-robô (sem gráficos) para testar rede e combate.
## Argumentos: --url=ws://... --bot-seconds=N --bot-move-every=S --bot-range=M
##             --bot-fight  (ataca o monstro mais próximo e usa as magias 1–3)

var _url: String
var _lifetime_s: float = 20.0
var _move_every_s: float = 1.5
var _range_m: float = 10.0
var _fight: bool = false

var _my_id: int = 0
var _elapsed: float = 0.0
var _move_timer: float = 0.0
var _snapshots: int = 0
var _seen: Dictionary = {} # id de jogador -> Vector4
var _monsters: Dictionary = {} # id -> Vector4
var _my_pos := Vector2.ZERO
var _stats := {"casts": 0, "hits_dealt": 0, "damage_dealt": 0, "hits_taken": 0, "kills": 0, "drops": 0, "deaths": 0}
var _state := PackedInt64Array()
var _messages := PackedStringArray()
var _spell_cycle: int = 0
var _drops: Dictionary = {} # id -> pos
var _catalog: ItemCatalog
var _inventory: Array = [] # itens decodificados
var _tried_equip: Dictionary = {}
var _forge: bool = false
var _city: bool = false
var _goto := Vector2.INF
var _travel: bool = false
var _events: bool = false
var _wings: bool = false
var _pvp: String = ""
var _summons_seen: Dictionary = {} # id -> Vector4 (invocações aliadas vistas)
var _siege: String = "" # "a:Outro" (dono, defende) ou "b:Outro" (ataca)
var _endgame: String = "" # "write" ou "check" (reset e maestria)
var _event_role: String = "" # "lead" ou "help"
var _event_id: String = "fortaleza" # fortaleza, arena ou circulo
var _class_test: String = "" # "support" ou "evolve"
var _guild_role: String = "" # "a:Outro" (funda, convida, declara guerra) ou "b:Outro"
var _monster_types: Dictionary = {} # id -> índice do tipo
var _region: String = ""
var _sheets := PackedStringArray()
var _players_now: Array = [] # jogadores no último snapshot
var _persist: String = "" # "write" ou "check"
var _social: String = "" # "lead:Outro" ou "member"
var _trade: Dictionary = {}
var _trade_added: bool = false
var _party: Array = []
var _chat_log := PackedStringArray()
var _journal_info: String = ""
var _npc_open: String = ""
var _fx_log := PackedStringArray()


func _ready() -> void:
	_url = GameConfig.get_s("network", "default_server_url")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--url="):
			_url = arg.trim_prefix("--url=")
		elif arg.begins_with("--bot-seconds="):
			_lifetime_s = arg.trim_prefix("--bot-seconds=").to_float()
		elif arg.begins_with("--bot-move-every="):
			_move_every_s = arg.trim_prefix("--bot-move-every=").to_float()
		elif arg.begins_with("--bot-range="):
			_range_m = arg.trim_prefix("--bot-range=").to_float()
		elif arg == "--bot-fight":
			_fight = true
		elif arg.begins_with("--bot-goto="): # anda até x,z e fica parado lá
			_forge = true
			var xz := arg.trim_prefix("--bot-goto=").split(",")
			_goto = Vector2(xz[0].to_float(), xz[1].to_float())
		elif arg == "--bot-forge":
			_forge = true
		elif arg == "--bot-city":
			_forge = true # sem andar a esmo
			_city = true
		elif arg.begins_with("--bot-pvp="):
			_forge = true
			_city = true
			_pvp = arg.trim_prefix("--bot-pvp=")
		elif arg.begins_with("--bot-siege="):
			_forge = true
			_city = true
			_siege = arg.trim_prefix("--bot-siege=")
		elif arg.begins_with("--bot-endgame="):
			_forge = true
			_city = true
			_endgame = arg.trim_prefix("--bot-endgame=")
		elif arg.begins_with("--bot-event="):
			_forge = true
			_city = true
			_event_role = arg.trim_prefix("--bot-event=").get_slice(":", 0) # lead|help[:evento]
			if arg.contains(":"):
				_event_id = arg.get_slice(":", 1)
		elif arg.begins_with("--bot-classtest="):
			_forge = true
			_city = true
			_class_test = arg.trim_prefix("--bot-classtest=")
		elif arg.begins_with("--bot-guild="):
			_forge = true
			_city = true
			_guild_role = arg.trim_prefix("--bot-guild=")
		elif arg == "--bot-wings":
			_forge = true
			_city = true
			_wings = true
		elif arg == "--bot-events":
			_forge = true
			_city = true
			_events = true
		elif arg == "--bot-travel":
			_forge = true
			_city = true
			_travel = true
		elif arg.begins_with("--bot-social="): # lead:NomeDoOutro | member
			_forge = true
			_city = true
			_social = arg.trim_prefix("--bot-social=")
		elif arg.begins_with("--bot-persist="):
			_forge = true
			_city = true # sem equipar sozinho
			_persist = arg.trim_prefix("--bot-persist=")

	var account := "bot_" + AutoLogin.random_suffix()
	var character := ""
	var new_class := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bot-account="):
			account = arg.trim_prefix("--bot-account=")
		elif arg.begins_with("--bot-character="):
			character = arg.trim_prefix("--bot-character=")
		elif arg.begins_with("--bot-class="): # classe do personagem, se ele for criado agora
			new_class = arg.trim_prefix("--bot-class=")
	if character.is_empty():
		character = "Robo" + account.right(6).replace("_", "")
	var login := AutoLogin.new()
	add_child(login)
	login.failed.connect(func(m: String) -> void: _finish("login falhou: %s" % m, 1))
	Net.client_connected.connect(func(id: int) -> void:
		print("[bot] conectado como %d; entrando na conta %s com %s" % [id, account, character])
		login.start(account, "senha-do-bot", character, new_class))
	Net.client_failed.connect(func() -> void: _finish("falha ao conectar em %s" % _url, 1))
	Net.client_disconnected.connect(func() -> void: _finish("servidor desconectou", 1))
	Net.welcome_received.connect(_on_welcome)
	Net.region_changed_received.connect(func(id: String) -> void:
		_region = id
		if _travel: print("[bot %d] -> região %s" % [_my_id, id]))
	Net.snapshot_received.connect(_on_snapshot)
	Net.cast_event_received.connect(func(caster: int, _s: int, _t: int, _p: Vector2, _c: PackedInt32Array) -> void:
		if caster == _my_id: _stats["casts"] += 1)
	Net.damage_event_received.connect(_on_damage)
	Net.died_event_received.connect(func(id: int) -> void:
		if id == _my_id: _stats["deaths"] += 1
		elif _monsters.has(id): _stats["kills"] += 1)
	Net.drop_spawned_received.connect(_on_drop)
	Net.player_state_received.connect(func(s: PackedInt64Array) -> void: _state = s)
	Net.message_received.connect(func(t: String) -> void: _messages.append(t))
	Net.drop_removed_received.connect(func(id: int) -> void: _drops.erase(id))
	Net.inventory_received.connect(_on_inventory)
	_catalog = ItemCatalog.from_config()
	var err := Net.connect_to_server(_url)
	if err != OK:
		_finish("erro ao criar cliente: %s" % error_string(err), 1)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _lifetime_s:
		_finish("tempo esgotado", 0)
		return
	if _my_id == 0 or _forge:
		return
	_move_timer -= delta
	if _move_timer > 0.0:
		return
	_move_timer = _move_every_s
	if _fight and _state.size() == Protocol.PS.COUNT and _state[Protocol.PS.HP] * 5 < _state[Protocol.PS.HP_MAX] * 2:
		var potion := _find("pocao_vida", true)
		if potion == 0:
			potion = _find("pocao_vida_menor", true)
		if potion != 0:
			Net.send_item_action(Protocol.ITEM_USE, potion, 0, 0, 0)
	if _fight and not _drops.is_empty() and _spell_cycle % 3 == 0:
		_spell_cycle += 1
		Net.send_pickup(_drops.keys()[0])
	elif _fight and not _monsters.is_empty():
		var target := _nearest_monster()
		var tp: Vector4 = _monsters[target]
		_spell_cycle += 1
		# alterna ataque básico contínuo com as magias 1, 2 e 3
		var spell: int = [0, 1, 0, 3, 0, 2][_spell_cycle % 6]
		Net.send_cast(spell, target, Vector2(tp.x, tp.y), spell == 0)
	else:
		Net.send_move_to(Vector2(randf_range(-_range_m, _range_m), randf_range(-_range_m, _range_m)))


func _nearest_monster() -> int:
	var best := 0
	var best_d := INF
	for id: int in _monsters:
		var v: Vector4 = _monsters[id]
		var d := _my_pos.distance_to(Vector2(v.x, v.y))
		if d < best_d:
			best_d = d
			best = id
	return best


func _on_welcome(my_id: int, tick_rate_hz: int) -> void:
	_my_id = my_id
	print("[bot %d] bem-vindo (servidor a %d Hz)" % [my_id, tick_rate_hz])
	if _siege != "":
		_run_siege_script()
	elif _endgame != "":
		_run_endgame_script()
	elif _event_role != "" and _event_id == "arena":
		_run_arena_script()
	elif _event_role != "" and _event_id == "circulo":
		_run_circle_script()
	elif _event_role != "":
		_run_event_script()
	elif _class_test != "":
		_run_class_script()
	elif _guild_role != "":
		_run_guild_script()
	elif _pvp != "":
		_run_pvp_script()
	elif _wings:
		_run_wings_script()
	elif _events:
		_run_events_script()
	elif _travel:
		_run_travel_script()
	elif _goto != Vector2.INF:
		await get_tree().create_timer(0.5).timeout
		Net.send_move_to(_goto)
	elif _social != "":
		_run_social_script()
	elif _persist != "":
		_run_persist_script()
	elif _city:
		_run_city_script()
	elif _forge:
		_run_forge_script()


func _open_npc(npc_id: String) -> bool:
	Net.send_npc_interact(npc_id)
	for i in 40:
		if _npc_open == npc_id:
			return true
		await get_tree().create_timer(0.25).timeout
	return false


func _count(base: String, container: int = ItemCatalog.CONTAINER_INVENTORY) -> int:
	var n := 0
	for item: Dictionary in _inventory:
		if str(item["base"]) == base and int(item["container"]) == container:
			n += int(item.get("count", 1))
	return n


func _stock_index(shop_id: String, base: String) -> int:
	return ShopRules.new(GameConfig.table("shops"), _catalog).stock(shop_id).find(base)


func _say(text: String) -> void:
	print("[bot %d] %s" % [_my_id, text])


## Roteiro da cidade (servidor precisa de --allow-gm): lojas, grimório, poções, cofre e retorno.
func _run_city_script() -> void:
	Net.npc_opened.connect(func(id: String) -> void: _npc_open = id)
	Net.npc_closed.connect(func() -> void: _npc_open = "")
	var safe := SafeZones.new(GameConfig.region(GameConfig.get_s("movement", "start_region")))
	await get_tree().create_timer(0.8).timeout
	_say("nasci em (%.1f, %.1f), zona segura: %s" % [_my_pos.x, _my_pos.y, safe.contains(_my_pos)])
	Net.send_gm("currency 4000;level 10;item vara_eclipse 9 1 1")
	await get_tree().create_timer(0.8).timeout
	_say("óbolos: %d, tônicos de vida: %d" % [_state[Protocol.PS.CURRENCY], _count("pocao_vida_menor")])
	# 1) magia não aprendida e magia dentro da cidade
	Net.send_cast(4, 0, _my_pos + Vector2(2, 0), false)
	await get_tree().create_timer(0.4).timeout
	Net.send_cast(1, 0, _my_pos + Vector2(2, 0), false)
	await get_tree().create_timer(0.4).timeout
	# 2) alquimista: 10 tônicos (Shift), grimório, pergaminho
	_say("alquimista aberta: %s" % await _open_npc("mago"))
	Net.send_shop_buy(_stock_index("mago", "pocao_vida_menor"), 10)
	await get_tree().create_timer(0.3).timeout
	Net.send_shop_buy(_stock_index("mago", "grimorio_brasas"), 1)
	await get_tree().create_timer(0.3).timeout
	Net.send_shop_buy(_stock_index("mago", "pergaminho_retorno"), 1)
	await get_tree().create_timer(0.4).timeout
	_say("depois da alquimista: óbolos %d, tônicos %d (pilhas: %s), grimório %d, pergaminho %d" % [
		_state[Protocol.PS.CURRENCY], _count("pocao_vida_menor"), _stack_sizes("pocao_vida_menor"), _count("grimorio_brasas"), _count("pergaminho_retorno")])
	Net.send_item_action(Protocol.ITEM_USE, _find("grimorio_brasas"), 0, 0, 0)
	await get_tree().create_timer(0.4).timeout
	_say("magias aprendidas (máscara): %d" % _state[Protocol.PS.SPELLS])
	Net.send_item_action(Protocol.ITEM_USE, _find("pocao_vida_menor"), 0, 0, 0) # vida cheia: recusa
	await get_tree().create_timer(0.3).timeout
	# 3) ferreiro: vender a vara +9 e comprar um broquel
	_say("ferreiro aberto: %s" % await _open_npc("ferreiro"))
	var vara := _find("vara_eclipse", true)
	var price := ShopRules.new(GameConfig.table("shops"), _catalog).sell_price(_item_by_uid(vara))
	var before := int(_state[Protocol.PS.CURRENCY])
	Net.send_shop_sell(vara)
	await get_tree().create_timer(0.4).timeout
	_say("vendi a vara: prévia %d, recebi %d" % [price, int(_state[Protocol.PS.CURRENCY]) - before])
	Net.send_shop_buy(_stock_index("ferreiro", "broquel_cinzas"), 1)
	await get_tree().create_timer(0.4).timeout
	# 4) cofre: guardar o broquel e os tônicos; tentar mexer com o cofre fechado
	_say("cofre aberto: %s" % await _open_npc("armazem"))
	Net.send_item_action(Protocol.ITEM_MOVE, _find("broquel_cinzas", true), ItemCatalog.CONTAINER_STORAGE, -1, -1)
	await get_tree().create_timer(0.3).timeout
	Net.send_item_action(Protocol.ITEM_MOVE, _find("pocao_mana_menor", true), ItemCatalog.CONTAINER_STORAGE, 5, 5)
	await get_tree().create_timer(0.3).timeout
	_say("no cofre: broquel %d, essências %d" % [_count("broquel_cinzas", ItemCatalog.CONTAINER_STORAGE), _count("pocao_mana_menor", ItemCatalog.CONTAINER_STORAGE)])
	Net.send_npc_close()
	await get_tree().create_timer(0.3).timeout
	Net.send_item_action(Protocol.ITEM_MOVE, _find_in("broquel_cinzas", ItemCatalog.CONTAINER_STORAGE), ItemCatalog.CONTAINER_INVENTORY, -1, -1)
	await get_tree().create_timer(0.3).timeout
	_say("com o cofre fechado o broquel continua lá: %d" % _count("broquel_cinzas", ItemCatalog.CONTAINER_STORAGE))
	await _open_npc("armazem")
	Net.send_item_action(Protocol.ITEM_MOVE, _find_in("broquel_cinzas", ItemCatalog.CONTAINER_STORAGE), ItemCatalog.CONTAINER_INVENTORY, -1, -1)
	await get_tree().create_timer(0.3).timeout
	_say("retirado: broquel na mochila %d" % _count("broquel_cinzas"))
	# 5) forja na cidade
	_say("forja aberta: %s" % await _open_npc("forja"))
	Net.send_npc_close()
	# 6) sair da cidade e voltar com o pergaminho
	Net.send_move_to(Vector2(0.0, 12.0))
	for i in 40:
		if not safe.contains(_my_pos) and _my_pos.y < 13.0:
			break
		await get_tree().create_timer(0.25).timeout
	_say("fora da cidade em (%.1f, %.1f), zona segura: %s" % [_my_pos.x, _my_pos.y, safe.contains(_my_pos)])
	Net.send_item_action(Protocol.ITEM_USE, _find("pergaminho_retorno"), 0, 0, 0)
	await get_tree().create_timer(0.6).timeout
	_say("depois do pergaminho: (%.1f, %.1f), zona segura: %s" % [_my_pos.x, _my_pos.y, safe.contains(_my_pos)])
	_finish("roteiro da cidade concluído", 0)


## Viagem (servidor com --allow-gm): portal barrado pelo nível, portais, folhas do diário
## e teletransporte (inclusive recusado para região sem folha).
func _run_travel_script() -> void:
	Net.journal_sheets_received.connect(func(ids: PackedStringArray) -> void: _sheets = ids)
	await get_tree().create_timer(1.0).timeout
	_say("comecei em %s (%.1f, %.1f), folhas %s" % [_region, _my_pos.x, _my_pos.y, _sheets])
	await _walk_to(Vector2(0.0, -33.5), 40.0) # portal do bosque com nível 1
	_say("no portal com nível 1: região %s" % _region)
	Net.send_gm("level 25;currency 3000") # ainda dentro do raio do portal: passa assim que o nível permite
	await get_tree().create_timer(1.5).timeout
	_say("depois do portal: região %s em (%.1f, %.1f), folhas %s" % [_region, _my_pos.x, _my_pos.y, _sheets])
	Net.send_teleport("geleira") # ainda sem folha: deve recusar
	await get_tree().create_timer(0.6).timeout
	Net.send_teleport("ruinas")
	await get_tree().create_timer(1.2).timeout
	_say("teletransporte para as ruínas: região %s em (%.1f, %.1f), óbolos %d" % [_region, _my_pos.x, _my_pos.y, _state[Protocol.PS.CURRENCY]])
	Net.send_teleport("bosque")
	await get_tree().create_timer(1.2).timeout
	_say("teletransporte para o bosque: região %s em (%.1f, %.1f), óbolos %d" % [_region, _my_pos.x, _my_pos.y, _state[Protocol.PS.CURRENCY]])
	await _walk_to(Vector2(0.0, -34.5), 60.0) # atravessa o bosque até o portal da geleira
	await get_tree().create_timer(1.0).timeout
	_say("depois de atravessar o bosque: região %s em (%.1f, %.1f), folhas %s, monstros visíveis %d" % [_region, _my_pos.x, _my_pos.y, _sheets, _monsters.size()])
	_finish("viagem concluída", 0)


## PvP com dois bots (servidor com --allow-gm):
## attacker:Vitima — tenta atacar na cidade (recusado), mata a vítima lá fora (vira Fora da Lei),
##                   depois apanha dela; no fim, com infâmia 6, a loja recusa atendimento.
## victim:Agressor  — apanha parada; ao renascer, volta e derruba o Fora da Lei (vira Herói).
func _run_pvp_script() -> void:
	var attacker := _pvp.begins_with("attacker")
	var other_name := _pvp.get_slice(":", 1)
	var names := {}
	var tags := {}
	var deaths := [0]
	Net.player_name_received.connect(func(id: int, n: String, _c: String, _e: int) -> void: names[n.to_lower()] = id)
	Net.player_tag_received.connect(func(id: int, o: int, h: int) -> void: tags[id] = [o, h])
	Net.died_event_received.connect(func(id: int) -> void:
		if id == _my_id:
			deaths[0] += 1)
	Net.npc_opened.connect(func(id: String) -> void: _npc_open = id)
	await get_tree().create_timer(1.0).timeout
	Net.send_gm("level 20;item cetro_abissal 9 0 1")
	await get_tree().create_timer(0.6).timeout
	Net.send_add_stat(3, int(_state[Protocol.PS.POINTS]))
	Net.send_item_action(Protocol.ITEM_AUTO, _find("cetro_abissal", true), 0, 0, 0)
	await get_tree().create_timer(0.6).timeout
	var other := func() -> int: return int(names.get(other_name.to_lower(), 0))
	if attacker:
		Net.send_cast(1, other.call(), _my_pos, false) # ainda na cidade: deve ser recusado
		await get_tree().create_timer(0.6).timeout
	Net.send_move_to(Vector2(0.0, 12.0) if attacker else Vector2(1.5, 12.0))
	await get_tree().create_timer(5.0).timeout
	if attacker:
		var t := 0.0
		while t < 30.0 and int(tags.get(_my_id, [0, 0])[0]) == 0:
			var v: Vector4 = _seen.get(other.call(), Vector4.ZERO)
			Net.send_cast([1, 0][int(t) % 2], other.call(), Vector2(v.x, v.y), false)
			await get_tree().create_timer(0.7).timeout
			t += 0.7
		_say("depois de matar: Fora da Lei nível %d" % int(tags.get(_my_id, [0, 0])[0]))
		Net.send_move_to(Vector2(0.0, 12.0))
		var w := 0.0
		while w < 40.0 and deaths[0] == 0: # espera a vítima voltar e se vingar
			await get_tree().create_timer(0.5).timeout
			w += 0.5
		await get_tree().create_timer(5.0).timeout # renasce na cidade
		_say("depois de morrer: xp %d, itens %d, Fora da Lei nível %d" % [_state[Protocol.PS.XP], _state[Protocol.PS.ITEMS], int(tags.get(_my_id, [0, 0])[0])])
		Net.send_gm("infamy 6")
		await get_tree().create_timer(0.5).timeout
		await _open_npc("mago")
		Net.send_shop_buy(0, 1)
		await get_tree().create_timer(0.6).timeout
	else:
		var t2 := 0.0
		while t2 < 40.0 and deaths[0] == 0: # fica parado apanhando
			await get_tree().create_timer(0.5).timeout
			t2 += 0.5
		_say("morri (%d); o agressor está com status %s" % [deaths[0], tags.get(other.call(), [0, 0])])
		await get_tree().create_timer(5.0).timeout
		await _walk_to(Vector2(1.0, 11.0), 20.0)
		var t3 := 0.0
		while t3 < 30.0 and int(tags.get(_my_id, [0, 0])[1]) == 0:
			var v2: Vector4 = _seen.get(other.call(), Vector4.ZERO)
			Net.send_cast([1, 0][int(t3) % 2], other.call(), Vector2(v2.x, v2.y), false)
			await get_tree().create_timer(0.7).timeout
			t3 += 0.7
		_say("depois da vingança: herói nível %d" % int(tags.get(_my_id, [0, 0])[1]))
	_say("mensagens: %s" % " | ".join(_messages))
	_finish("pvp (%s) concluído" % ("agressor" if attacker else "vítima"), 0)


## Asas (servidor com --allow-gm): sacrifica um manto +12 na Forja do Vórtice até sair um par.
func _run_wings_script() -> void:
	Net.npc_opened.connect(func(id: String) -> void: _npc_open = id)
	Net.npc_closed.connect(func() -> void: _npc_open = "")
	Net.refine_fx_received.connect(func(_e: int, outcome: int, _l: int) -> void:
		_fx_log.append(["sucesso", "falha", "destruído"][outcome]))
	await get_tree().create_timer(1.0).timeout
	Net.send_gm("level 20;currency 60000")
	await get_tree().create_timer(0.5).timeout
	var defense_before := int(_state[Protocol.PS.DEFENSE])
	var book := RecipeBook.new(GameConfig.table("recipes"), _catalog)
	_say("forja aberta: %s" % await _open_npc("forja"))
	for attempt in 6:
		Net.send_gm("item manto_acolito 12 1 1;item joia_vortice;item joia_vortice;item joia_genese;item joia_alma")
		await get_tree().create_timer(0.6).timeout
		for base in ["manto_acolito", "joia_vortice", "joia_vortice", "joia_genese", "joia_alma"]:
			var uid := 0
			for item: Dictionary in _inventory:
				if str(item["base"]) == base and int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY and (base != "manto_acolito" or int(item["level"]) == 12):
					uid = int(item["uid"])
			Net.send_item_action(Protocol.ITEM_MOVE, uid, ItemCatalog.CONTAINER_FORGE, 0, 0)
			await get_tree().create_timer(0.2).timeout
		var table: Array = []
		for item: Dictionary in _inventory:
			if int(item["container"]) == ItemCatalog.CONTAINER_FORGE:
				table.append(item)
		var preview := book.evaluate(table)
		_say("tentativa %d: %s, chance %.0f%%, custo %d — %s" % [attempt + 1, preview["name"], preview["chance"] * 100.0, preview["cost"], preview.get("sacrifice", preview["hint"])])
		Net.send_forge_combine()
		await get_tree().create_timer(0.8).timeout
		if _fx_log[-1] == "sucesso":
			break
	var wings := 0
	for item: Dictionary in _inventory:
		if str(_catalog.base(item).get("slot", "")) == "wings":
			wings = int(item["uid"])
	Net.send_npc_close()
	await get_tree().create_timer(0.5).timeout
	if wings != 0:
		Net.send_item_action(Protocol.ITEM_AUTO, wings, 0, 0, 0)
		await get_tree().create_timer(0.6).timeout
	var equipped := PackedStringArray()
	for item: Dictionary in _inventory:
		if int(item["container"]) >= 1 and int(item["container"]) <= ItemCatalog.EQUIP_SLOTS.size():
			equipped.append("%s[%s]" % [_catalog.display_name(item), ItemCatalog.EQUIP_SLOTS[int(item["container"]) - 1]])
	_say("resultados: %s" % " ".join(_fx_log))
	_say("equipado: %s" % ", ".join(equipped))
	_say("defesa %d -> %d, óbolos %d" % [defense_before, _state[Protocol.PS.DEFENSE], _state[Protocol.PS.CURRENCY]])
	_finish("asas concluídas", 0)


## Eventos (servidor com --allow-gm): invasão dourada forçada e chefe das Ruínas.
func _run_events_script() -> void:
	var defs := MonsterCatalog.from_config()
	var ids := MonsterCatalog.type_ids(defs)
	var announces := PackedStringArray()
	var marks := PackedStringArray()
	var golden_killed := [0]
	Net.announce_received.connect(func(t: String, s: String) -> void:
		announces.append("%s (%s)" % [t, s])
		_say("AVISO: %s — %s" % [t, s]))
	Net.journal_mark_received.connect(func(_r: String, symbol: String, _p: Vector2, label: String) -> void:
		if symbol == "skull":
			marks.append(label))
	Net.died_event_received.connect(func(id: int) -> void:
		if _monster_types.has(id) and bool(defs[ids[_monster_types[id]]].get("golden", false)):
			golden_killed[0] += 1)
	await get_tree().create_timer(1.0).timeout
	Net.send_gm("level 60;item cetro_abissal 13 1 1;item pocao_vida 0 0 0 0 20")
	await get_tree().create_timer(0.8).timeout
	Net.send_add_stat(3, int(_state[Protocol.PS.POINTS]) - 40) # quase tudo em energia
	Net.send_add_stat(2, 40) # e um pouco de vitalidade
	Net.send_item_action(Protocol.ITEM_AUTO, _find("cetro_abissal", true), 0, 0, 0)
	await get_tree().create_timer(0.5).timeout
	Net.send_gm("invasion ruinas")
	await get_tree().create_timer(1.0).timeout
	var golden_alive := func() -> int:
		var n := 0
		for id: int in _monsters:
			if bool(defs[ids[_monster_types[id]]].get("golden", false)):
				n += 1
		return n
	_say("dourados visíveis: %d" % golden_alive.call())
	# caça: vai atrás do dourado mais perto (a invasão espalha pela região inteira)
	var t := 0.0
	while t < 120.0 and not "Invasão contida" in " ".join(announces):
		var best := 0
		var best_d := INF
		for id: int in _monsters:
			if bool(defs[ids[_monster_types[id]]].get("golden", false)):
				var v: Vector4 = _monsters[id]
				var d := _my_pos.distance_to(Vector2(v.x, v.y))
				if d < best_d:
					best_d = d
					best = id
		if best != 0:
			var v2: Vector4 = _monsters[best]
			Net.send_cast([0, 1, 3, 2][int(t) % 4], best, Vector2(v2.x, v2.y), true)
		else:
			Net.send_move_to(Vector2(randf_range(-25, 25), randf_range(-25, 15))) # procura
		if _state[Protocol.PS.HP] < _state[Protocol.PS.HP_MAX] / 2:
			Net.send_item_action(Protocol.ITEM_USE, _find("pocao_vida", true), 0, 0, 0)
		await get_tree().create_timer(1.0).timeout
		t += 1.0
	_say("dourados mortos por mim: %d em %d s" % [golden_killed[0], int(t)])
	# chefe das Ruínas
	var boss := 0
	await _walk_to(Vector2(-15.0, 15.0), 20.0)
	for id: int in _monsters:
		if bool(defs[ids[_monster_types[id]]].get("boss", false)):
			boss = id
	_say("chefe visível: %s" % (defs[ids[_monster_types[boss]]]["name"] if boss != 0 else "não"))
	t = 0.0
	while boss != 0 and _monsters.has(boss) and t < 90.0:
		var v3: Vector4 = _monsters[boss]
		Net.send_cast([0, 1, 3, 2][int(t) % 4], boss, Vector2(v3.x, v3.y), true)
		if _state[Protocol.PS.HP] < _state[Protocol.PS.HP_MAX] / 2:
			Net.send_item_action(Protocol.ITEM_USE, _find("pocao_vida", true), 0, 0, 0)
		await get_tree().create_timer(1.0).timeout
		t += 1.0
	await get_tree().create_timer(1.5).timeout
	_say("marcas de chefe no diário: %s" % [marks])
	_say("avisos: %s" % " | ".join(announces))
	_say("estado: nível %d, vida %d/%d, óbolos %d, drops vistos %d" % [_state[Protocol.PS.LEVEL], _state[Protocol.PS.HP], _state[Protocol.PS.HP_MAX], _state[Protocol.PS.CURRENCY], _stats["drops"]])
	_finish("eventos concluídos", 0)


## Guildas com dois bots (servidor com --allow-gm):
## a: nome e símbolo inválidos (recusados), funda "Corvos da Cinza", convida b, promove a Oficial,
##    chat da guilda, pede amizade; depois que b sai e funda "Lobos do Véu", declara guerra, derruba
##    b fora da cidade (conta no placar, sem infâmia) e encerra a guerra pelo GM.
## b: aceita tudo, conversa na guilda, sai, funda a própria guilda, aceita a guerra, apanha e desfaz.
func _run_guild_script() -> void:
	var is_a := _guild_role.begins_with("a")
	var other := _guild_role.get_slice(":", 1)
	var names := {}
	var tags := {}
	var guild_tags := {}
	var gstate := [{}]
	var friend_list := [[]]
	var deaths := [0]
	Net.player_name_received.connect(func(id: int, n: String, _c: String, _e: int) -> void: names[n.to_lower()] = id)
	Net.player_tag_received.connect(func(id: int, o: int, h: int) -> void: tags[id] = [o, h])
	Net.player_guild_received.connect(func(id: int, g: String, _s: String) -> void: guild_tags[id] = g)
	Net.guild_state_received.connect(func(s: Dictionary) -> void: gstate[0] = s)
	Net.friends_state_received.connect(func(l: Array) -> void: friend_list[0] = l)
	Net.died_event_received.connect(func(id: int) -> void:
		if id == _my_id:
			deaths[0] += 1)
	Net.chat_received.connect(func(ch: int, from: String, text: String) -> void:
		_chat_log.append("[%s] %s%s" % [["geral", "sussurro", "grupo", "sistema", "guilda"][ch], from + ": " if from != "" else "", text]))
	Net.prompt_received.connect(func(kind: int, from: String, detail: String) -> void:
		_say("convite (%d) de %s %s: aceito" % [kind, from, detail])
		await get_tree().create_timer(0.3).timeout
		if kind == Protocol.Prompt.GUILD_INVITE:
			Net.send_guild_action(Protocol.Guild.ACCEPT)
		elif kind == Protocol.Prompt.GUILD_WAR:
			Net.send_guild_action(Protocol.Guild.WAR_ACCEPT)
		elif kind == Protocol.Prompt.FRIEND_REQUEST:
			Net.send_friend_action(Protocol.Friend.ACCEPT))
	var sym := "00066000" + "00666600" + "06644660" + "66444466" + "66444466" + "06644660" + "00666600" + "00066000"
	await get_tree().create_timer(1.0).timeout
	Net.send_gm("level 20;currency 20000")
	await get_tree().create_timer(0.6).timeout
	Net.send_add_stat(3, int(_state[Protocol.PS.POINTS]))
	if is_a:
		Net.send_gm("item cetro_abissal 9 0 1")
		await get_tree().create_timer(0.5).timeout
		Net.send_item_action(Protocol.ITEM_AUTO, _find("cetro_abissal", true), 0, 0, 0)
		Net.send_guild_action(Protocol.Guild.CREATE, "x!", sym) # nome inválido
		Net.send_guild_action(Protocol.Guild.CREATE, "Corvos da Cinza", "0".repeat(64)) # símbolo vazio
		await get_tree().create_timer(0.5).timeout
		Net.send_guild_action(Protocol.Guild.CREATE, "  Corvos   da Cinza ", sym)
		await _wait_until(func() -> bool: return not gstate[0].is_empty(), 5.0)
		_say("guilda fundada: %s (cargo %d), óbolos %d" % [gstate[0].get("name", "?"), int(gstate[0].get("role", -1)), _state[Protocol.PS.CURRENCY]])
		await _wait_until(func() -> bool: return names.has(other.to_lower()), 10.0)
		Net.send_guild_action(Protocol.Guild.INVITE, other)
		await _wait_until(func() -> bool: return (gstate[0].get("members", []) as Array).size() == 2, 8.0)
		Net.send_guild_action(Protocol.Guild.PROMOTE, other)
		await get_tree().create_timer(0.5).timeout
		Net.send_chat(Protocol.Chat.GUILD, "", "bem-vindo aos Corvos")
		Net.send_friend_action(Protocol.Friend.REQUEST, other)
		await _wait_until(func() -> bool: return not (friend_list[0] as Array).is_empty(), 6.0)
		_say("membros: %s" % [gstate[0].get("members", [])])
		_say("amigos: %s" % [friend_list[0]])
		Net.send_guild_action(Protocol.Guild.LEAVE) # o mestre não pode sair
		# espera b sair e fundar a própria guilda
		await _wait_until(func() -> bool: return str(guild_tags.get(names.get(other.to_lower(), 0), "")) == "Lobos do Véu", 25.0)
		var other_id := int(names.get(other.to_lower(), 0))
		Net.send_guild_action(Protocol.Guild.WAR_DECLARE, "lobos do véu")
		await _wait_until(func() -> bool: return not (gstate[0].get("war", {}) as Dictionary).is_empty(), 8.0)
		_say("guerra: %s" % [gstate[0].get("war", {})])
		Net.send_move_to(Vector2(0.0, 12.0))
		await get_tree().create_timer(5.0).timeout
		var t := 0.0
		while t < 30.0 and int((gstate[0].get("war", {}) as Dictionary).get("mine", 0)) == 0:
			var v: Vector4 = _seen.get(other_id, Vector4.ZERO)
			Net.send_cast([1, 0][int(t) % 2], other_id, Vector2(v.x, v.y), false)
			await get_tree().create_timer(0.7).timeout
			t += 0.7
		_say("placar depois da morte: %s · meu status PvP %s (deve ser [0, 0])" % [gstate[0].get("war", {}), tags.get(_my_id, [0, 0])])
		Net.send_gm("guildwar 1")
		await _wait_until(func() -> bool: return (gstate[0].get("war", {}) as Dictionary).is_empty(), 6.0)
		_say("depois da guerra: vitórias %d" % int(gstate[0].get("wins", 0)))
	else:
		await _wait_until(func() -> bool: return not gstate[0].is_empty(), 15.0)
		_say("entrei na guilda %s (cargo %d)" % [gstate[0].get("name", "?"), int(gstate[0].get("role", -1))])
		await get_tree().create_timer(2.0).timeout
		_say("meu cargo agora: %d" % int(gstate[0].get("role", -1)))
		Net.send_chat(Protocol.Chat.GUILD, "", "obrigado, mestre")
		await _wait_until(func() -> bool: return not (friend_list[0] as Array).is_empty(), 8.0)
		await get_tree().create_timer(1.0).timeout
		Net.send_guild_action(Protocol.Guild.LEAVE)
		await _wait_until(func() -> bool: return gstate[0].is_empty(), 5.0)
		Net.send_guild_action(Protocol.Guild.CREATE, "Lobos do Véu", sym.replace("6", "b").replace("4", "2"))
		await _wait_until(func() -> bool: return not gstate[0].is_empty(), 5.0)
		_say("fundei %s" % gstate[0].get("name", "?"))
		await _wait_until(func() -> bool: return not (gstate[0].get("war", {}) as Dictionary).is_empty(), 15.0)
		Net.send_move_to(Vector2(1.5, 12.0))
		await _wait_until(func() -> bool: return deaths[0] > 0, 40.0)
		_say("morri na guerra (%d)" % deaths[0])
		await _wait_until(func() -> bool: return (gstate[0].get("war", {}) as Dictionary).is_empty(), 15.0)
		Net.send_guild_action(Protocol.Guild.DISBAND)
		await _wait_until(func() -> bool: return gstate[0].is_empty(), 5.0)
		_say("guilda desfeita: %s" % ("sim" if gstate[0].is_empty() else "não"))
	_say("chat: %s" % " | ".join(_chat_log))
	_say("mensagens: %s" % " | ".join(_messages))
	_finish("guilda (%s) concluído" % ("a" if is_a else "b"), 0)


## Classes (servidor com --allow-gm). --bot-classtest=support: Vidente aprende a invocação,
## sai da cidade, lança cura, Véu Protetor e o Espírito, que luta por ela.
## --bot-classtest=evolve: missão de evolução inteira com o Ancião Varek (contagem acelerada pelo GM).
func _run_class_script() -> void:
	var my_class := [""]
	var my_evo := [0]
	var buffs := [[]]
	var quests := [{}]
	var kills_by_summon := [0]
	Net.player_name_received.connect(func(id: int, _n: String, c: String, e: int) -> void:
		if id == _my_id:
			my_class[0] = c
			my_evo[0] = e)
	Net.buffs_received.connect(func(l: Array) -> void: buffs[0] = l)
	Net.quest_state_received.connect(func(q: Dictionary) -> void: quests[0] = q)
	Net.npc_opened.connect(func(id: String) -> void: _npc_open = id)
	Net.npc_closed.connect(func() -> void: _npc_open = "")
	Net.attack_event_received.connect(func(attacker: int, _t: int) -> void:
		if _summons_seen.has(attacker):
			kills_by_summon[0] += 1)
	await get_tree().create_timer(1.0).timeout
	_say("classe: %s (evolução %d)" % [my_class[0], my_evo[0]])
	if _class_test == "support":
		Net.send_gm("level 12;item grimorio_espirito")
		await get_tree().create_timer(0.8).timeout
		Net.send_add_stat(3, int(_state[Protocol.PS.POINTS]))
		Net.send_item_action(Protocol.ITEM_USE, _find("grimorio_espirito", true), 0, 0, 0)
		await get_tree().create_timer(0.6).timeout
		Net.send_cast(3, 0, _my_pos, false) # Véu Protetor: pode na cidade
		await get_tree().create_timer(0.6).timeout
		_say("bônus na cidade: %s" % [buffs[0]])
		Net.send_cast(4, 0, _my_pos, false) # invocar na cidade: recusado
		await get_tree().create_timer(0.5).timeout
		await _walk_to(Vector2(-8.0, 12.0), 15.0)
		Net.send_cast(4, 0, _my_pos, false)
		await _wait_until(func() -> bool: return not _summons_seen.is_empty(), 4.0)
		_say("espíritos vistos: %d" % _summons_seen.size())
		var t := 0.0
		while t < 20.0:
			var target := _nearest_monster()
			if target != 0 and int(t * 10) % 30 == 0:
				var tp: Vector4 = _monsters[target]
				Net.send_cast(1, target, Vector2(tp.x, tp.y), false)
			if int(t * 10) % 60 == 0:
				Net.send_cast(2, 0, _my_pos, false) # cura
			await get_tree().create_timer(0.5).timeout
			t += 0.5
		_say("ataques do espírito: %d · vida %d/%d · monstros mortos %d" % [kills_by_summon[0], _state[Protocol.PS.HP], _state[Protocol.PS.HP_MAX], _stats["kills"]])
	else:
		Net.send_gm("level 40;item montante_eclipse 9 0 1;item pocao_vida 0 0 0 0 10")
		await get_tree().create_timer(0.8).timeout
		var pts := int(_state[Protocol.PS.POINTS])
		Net.send_add_stat(0, pts / 2)
		Net.send_add_stat(2, pts - pts / 2)
		Net.send_item_action(Protocol.ITEM_AUTO, _find("montante_eclipse", true), 0, 0, 0)
		await get_tree().create_timer(0.5).timeout
		var points_before := int(_state[Protocol.PS.POINTS])
		Net.send_cast(5, 0, _my_pos, false) # magia da evolução: ainda não
		await get_tree().create_timer(0.4).timeout
		if not await _open_npc("anciao"):
			_finish("não abriu o Ancião", 1)
			return
		Net.send_quest_action(Protocol.Quest.TURN_IN, "evolucao") # sem aceitar: nada
		Net.send_quest_action(Protocol.Quest.ACCEPT, "evolucao")
		await _wait_until(func() -> bool: return quests[0].has("evolucao"), 3.0)
		_say("missão aceita: %s" % [quests[0]])
		Net.send_npc_close()
		Net.send_gm("quest evolucao 0 29;goto geleira")
		await _wait_until(func() -> bool: return _region == "geleira", 6.0)
		await get_tree().create_timer(1.0).timeout
		_fight = true
		_forge = false
		var w := 0.0
		while w < 60.0 and int(quests[0].get("evolucao", {}).get("step", 0)) < 1:
			if _state.size() == Protocol.PS.COUNT and _state[Protocol.PS.HP] * 2 < _state[Protocol.PS.HP_MAX]:
				var potion := _find("pocao_vida", true)
				if potion != 0:
					Net.send_item_action(Protocol.ITEM_USE, potion, 0, 0, 0)
			await get_tree().create_timer(0.5).timeout
			w += 0.5
		_fight = false
		_forge = true
		_say("depois de lutar na Geleira: %s" % [quests[0]])
		Net.send_gm("item selo_juramento;goto ruinas 0 30")
		await _wait_until(func() -> bool: return _region == "ruinas", 6.0)
		await get_tree().create_timer(1.0).timeout
		await _open_npc("anciao")
		Net.send_quest_action(Protocol.Quest.TURN_IN, "evolucao")
		await _wait_until(func() -> bool: return my_evo[0] > 0, 5.0)
		await get_tree().create_timer(0.5).timeout
		var mask := int(_state[Protocol.PS.SPELLS])
		_say("evoluído: %d · missão %s · pontos %d (antes %d) · magia 5 aprendida: %s · selo na mochila: %d" % [my_evo[0], quests[0],
			_state[Protocol.PS.POINTS], points_before, "sim" if mask & (1 << 5) else "não", _count("selo_juramento")])
		Net.send_npc_close()
		Net.send_gm("level 41")
		await get_tree().create_timer(0.8).timeout
		_say("nível 41 evoluído: %d pontos livres (7 por nível)" % _state[Protocol.PS.POINTS])
	_say("mensagens: %s" % " | ".join(_messages))
	_finish("classes (%s) concluído" % _class_test, 0)


## Fortaleza Sitiada (servidor com --allow-gm). --bot-event=lead: abre os portões pelo GM,
## entra, começa o evento pelo GM, luta e entrega a relíquia; --bot-event=help: entra e luta.
func _run_event_script() -> void:
	var lead := _event_role == "lead"
	var sched := [[]]
	var state := [{}]
	var lines := PackedStringArray()
	var my_class := [""]
	Net.player_name_received.connect(func(id: int, _n: String, c: String, _e: int) -> void:
		if id == _my_id:
			my_class[0] = c)
	Net.event_schedule_received.connect(func(rows: Array) -> void: sched[0] = rows)
	Net.event_state_received.connect(func(s: Dictionary) -> void:
		state[0] = s
		var l := str(s.get("line", "(fora)"))
		if lines.is_empty() or lines[-1] != l:
			lines.append(l))
	Net.event_world_received.connect(func(b: String) -> void: _say("bloqueio aberto: %s" % b))
	var open_state := func() -> int:
		for r: Array in sched[0]:
			if str(r[0]) == "fortaleza":
				return int(r[2])
		return -1
	await get_tree().create_timer(1.0).timeout
	var knight: bool = my_class[0] == "cavaleiro"
	Net.send_gm("level 39;item %s 9 0 1;item pocao_vida 0 0 0 0 20;item pocao_mana_menor 0 0 0 0 10" % ("montante_eclipse" if knight else "cetro_abissal"))
	await get_tree().create_timer(0.8).timeout
	var pts := int(_state[Protocol.PS.POINTS])
	Net.send_add_stat(0 if knight else 3, pts / 2) # força (cavaleiro) ou energia
	Net.send_add_stat(2, pts - pts / 2)
	Net.send_item_action(Protocol.ITEM_AUTO, _find("montante_eclipse" if knight else "cetro_abissal", true), 0, 0, 0)
	if lead:
		_say("antes de abrir: estado %d · usar o selo agora deve falhar" % open_state.call())
		Net.send_gm("item selo_fortaleza")
		await _wait_until(func() -> bool: return _count("selo_fortaleza") > 0, 3.0)
		Net.send_item_action(Protocol.ITEM_USE, _find("selo_fortaleza", true), 0, 0, 0)
		await get_tree().create_timer(0.5).timeout
		Net.send_gm("event fortaleza open")
	else:
		Net.send_gm("item selo_fortaleza")
	await _wait_until(func() -> bool: return open_state.call() == 1 and _count("selo_fortaleza") > 0, 12.0)
	_say("portões: estado %d" % open_state.call())
	Net.send_item_action(Protocol.ITEM_USE, _find("selo_fortaleza", true), 0, 0, 0)
	await _wait_until(func() -> bool: return _region.begins_with("fortaleza"), 6.0)
	_say("região: %s · selos restantes %d" % [_region, _count("selo_fortaleza")])
	if lead:
		await get_tree().create_timer(12.0).timeout # os outros entram
		Net.send_gm("event fortaleza start")
	await _wait_until(func() -> bool: return open_state.call() == 2, 10.0)
	var xp_before := int(_state[Protocol.PS.XP])
	var cur_before := int(_state[Protocol.PS.CURRENCY])
	var ids := MonsterCatalog.type_ids(MonsterCatalog.from_config())
	var t := 0.0
	var skipped := {}
	var cycle := 0
	while t < 300.0 and not bool(state[0].get("done", false)) and _region.begins_with("fortaleza"):
		var line := str(state[0].get("line", ""))
		if lead and t > 60.0 and line.begins_with("Sentinelas") and not skipped.has(1):
			skipped[1] = true
			Net.send_gm("event fortaleza skip")
		if lead and line == "Vençam o Guardião" and not skipped.has(2):
			skipped[2] = true
			Net.send_gm("event fortaleza skip")
		if _state.size() == Protocol.PS.COUNT and _state[Protocol.PS.HP] * 2 < _state[Protocol.PS.HP_MAX] and _find("pocao_vida", true) != 0:
			Net.send_item_action(Protocol.ITEM_USE, _find("pocao_vida", true), 0, 0, 0)
		if _count("reliquia_ardente") > 0:
			Net.send_npc_interact("altar_guardiao")
		else:
			var want := "portao_fortaleza" if line == "Derrubem o portão!" else ("guardiao_profanado" if line == "Vençam o Guardião" else "")
			var target := 0
			for id: int in _monsters:
				if want != "" and int(_monster_types.get(id, -1)) >= 0 and ids[int(_monster_types[id])] == want:
					target = id
			if target == 0:
				target = _nearest_monster()
				if target != 0 and ids[int(_monster_types.get(target, 0))] == "portao_fortaleza" and want == "":
					target = 0 # o portão protegido não vale o golpe
			if target != 0:
				var tp: Vector4 = _monsters[target]
				cycle += 1
				var spell: int = [0, 1, 0, 3, 0, 1][cycle % 6]
				Net.send_cast(spell, target, Vector2(tp.x, tp.y), spell == 0)
			else:
				Net.send_move_to(Vector2(randf_range(-6.0, 6.0), randf_range(-8.0, 18.0)))
		await get_tree().create_timer(0.6).timeout
		t += 0.6
	_say("etapas vistas: %s" % " → ".join(lines))
	_say("resultado: %s · xp %d → %d (nível %d) · óbolos %d → %d · mochila: %s" % [state[0], xp_before, _state[Protocol.PS.XP],
		_state[Protocol.PS.LEVEL], cur_before, _state[Protocol.PS.CURRENCY], ", ".join(_bag_names())])
	if lead:
		Net.send_gm("event fortaleza end")
	await _wait_until(func() -> bool: return not _region.begins_with("fortaleza"), 30.0)
	_say("de volta a: %s · calendário %s" % [_region, sched[0]])
	_say("mensagens: %s" % " | ".join(_messages))
	_finish("evento (%s) concluído" % _event_role, 0)


## Preparo comum dos eventos: nível 39, arma da classe, poções e o ingresso; o líder abre
## os portões pelo GM, todos entram e o líder larga o evento. Retorna os sinais em `ctx`.
func _event_setup(event_id: String, ticket: String, ctx: Dictionary) -> void:
	var lead := _event_role == "lead"
	ctx["sched"] = []
	ctx["state"] = {}
	ctx["lines"] = [] # Array (por referência): PackedStringArray seria copiado
	ctx["class"] = ""
	Net.player_name_received.connect(func(id: int, _n: String, c: String, _e: int) -> void:
		if id == _my_id:
			ctx["class"] = c)
	Net.event_schedule_received.connect(func(rows: Array) -> void: ctx["sched"] = rows)
	Net.event_state_received.connect(func(s: Dictionary) -> void:
		ctx["state"] = s
		var l := "%s | %s" % [s.get("line", "(fora)"), s.get("extra", "")]
		if (ctx["lines"] as Array).is_empty() or ctx["lines"][-1] != l:
			(ctx["lines"] as Array).append(l))
	ctx["open_state"] = func() -> int:
		for r: Array in ctx["sched"]:
			if str(r[0]) == event_id:
				return int(r[2])
		return -1
	await get_tree().create_timer(1.0).timeout
	var knight: bool = ctx["class"] == "cavaleiro"
	Net.send_gm("level 39;item %s 9 0 1;item pocao_vida 0 0 0 0 20;item pocao_mana_menor 0 0 0 0 10;item %s" % ["montante_eclipse" if knight else "cetro_abissal", ticket])
	await _wait_until(func() -> bool: return _count(ticket) > 0, 4.0)
	var pts := int(_state[Protocol.PS.POINTS])
	Net.send_add_stat(0 if knight else 3, pts / 2)
	Net.send_add_stat(2, pts - pts / 2)
	Net.send_item_action(Protocol.ITEM_AUTO, _find("montante_eclipse" if knight else "cetro_abissal", true), 0, 0, 0)
	await get_tree().create_timer(0.6).timeout
	ctx["magic_outside"] = int(_state[Protocol.PS.MAGIC_MAX])
	if lead:
		Net.send_item_action(Protocol.ITEM_USE, _find(ticket, true), 0, 0, 0) # antes de abrir: recusado
		await get_tree().create_timer(0.5).timeout
		Net.send_gm("event %s open" % event_id)
	await _wait_until(func() -> bool: return (ctx["open_state"] as Callable).call() == 1, 12.0)
	Net.send_item_action(Protocol.ITEM_USE, _find(ticket, true), 0, 0, 0)
	await _wait_until(func() -> bool: return _region.begins_with(event_id), 6.0)
	_say("região: %s · ingressos restantes %d" % [_region, _count(ticket)])
	if lead:
		await get_tree().create_timer(12.0).timeout # os outros entram
		Net.send_gm("event %s start" % event_id)
	await _wait_until(func() -> bool: return (ctx["open_state"] as Callable).call() == 2, 15.0)


func _event_fight_step(cycle: int, target_players: bool = false) -> void:
	if not _region.begins_with("circulo") and _state.size() == Protocol.PS.COUNT and _state[Protocol.PS.HP] * 2 < _state[Protocol.PS.HP_MAX] and _find("pocao_vida", true) != 0:
		Net.send_item_action(Protocol.ITEM_USE, _find("pocao_vida", true), 0, 0, 0)
	var target := _nearest_monster()
	var pos := Vector2.ZERO
	if target != 0:
		var tp: Vector4 = _monsters[target]
		pos = Vector2(tp.x, tp.y)
	elif target_players and not _players_now.is_empty():
		target = int(_players_now[0])
		var pp: Vector4 = _seen.get(target, Vector4.ZERO)
		pos = Vector2(pp.x, pp.y)
	if target != 0:
		var spell: int = [0, 1, 0, 3, 0, 1][cycle % 6]
		Net.send_cast(spell, target, pos, spell == 0)
	else:
		Net.send_move_to(Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0)))


## Arena das Ondas: luta nas ondas (o líder adianta pelo GM as ondas que demoram), ranking no fim.
func _run_arena_script() -> void:
	var ctx := {}
	await _event_setup("arena", "emblema_arena", ctx)
	var xp0 := int(_state[Protocol.PS.XP])
	var t := 0.0
	var cycle := 0
	var wave_seen := ""
	var wave_since := 0.0
	while t < 420.0 and not bool((ctx["state"] as Dictionary).get("done", false)) and _region.begins_with("arena"):
		var line := str((ctx["state"] as Dictionary).get("line", ""))
		if line.begins_with("Onda"):
			var w := line.get_slice(" ·", 0)
			if w != wave_seen:
				wave_seen = w
				wave_since = 0.0
			wave_since += 0.6
			if _event_role == "lead" and wave_since > 20.0:
				wave_since = -999.0
				Net.send_gm("event arena skip")
		cycle += 1
		_event_fight_step(cycle)
		await get_tree().create_timer(0.6).timeout
		t += 0.6
	await get_tree().create_timer(1.0).timeout
	_say("painel: %s" % " → ".join(PackedStringArray(ctx["lines"])).substr(0, 900))
	_say("resultado: %s · xp %d → %d · mochila: %s" % [ctx["state"], xp0, _state[Protocol.PS.XP], ", ".join(_bag_names())])
	if _event_role == "lead":
		Net.send_gm("event arena end")
	await _wait_until(func() -> bool: return not _region.begins_with("arena"), 40.0)
	_say("de volta a: %s" % _region)
	_say("mensagens: %s" % " | ".join(_messages))
	_finish("arena (%s) concluído" % _event_role, 0)


## Círculo que Encolhe: sem equipamento de fora, poção recusada, guardas, o anel fecha (GM) e
## os dois lutam até sobrar um. "solo": só o líder entra, e o evento é cancelado.
func _run_circle_script() -> void:
	var ctx := {}
	await _event_setup("circulo", "marca_circulo", ctx)
	await get_tree().create_timer(1.0).timeout
	if _event_id == "circulo" and OS.get_cmdline_user_args().has("--bot-solo"):
		await _wait_until(func() -> bool: return bool((ctx["state"] as Dictionary).get("done", false)), 6.0)
		_say("solo: %s · ingressos de volta: %d" % [(ctx["state"] as Dictionary).get("line", "?"), _count("marca_circulo")])
		Net.send_gm("event circulo end")
		await _wait_until(func() -> bool: return not _region.begins_with("circulo"), 40.0)
		_say("de volta a: %s" % _region)
		_finish("círculo (solo) concluído", 0)
		return
	_say("dano máximo: fora %d, dentro %d (o equipamento não vale)" % [ctx["magic_outside"], _state[Protocol.PS.MAGIC_MAX]])
	Net.send_item_action(Protocol.ITEM_USE, _find("pocao_vida", true), 0, 0, 0) # recusada
	var t := 0.0
	var cycle := 0
	var deaths := [0]
	Net.died_event_received.connect(func(id: int) -> void:
		if id == _my_id:
			deaths[0] += 1)
	while t < 150.0 and not bool((ctx["state"] as Dictionary).get("done", false)) and _region.begins_with("circulo") and deaths[0] == 0:
		if t > 15.0 and _event_role == "lead" and t < 15.7:
			Net.send_gm("event circulo skip") # o anel fecha de vez
		cycle += 1
		if t > 15.0:
			Net.send_move_to(Vector2(0.0, 0.0)) if _my_pos.length() > 2.5 else _event_fight_step(cycle, true)
		else:
			_event_fight_step(cycle)
		await get_tree().create_timer(0.6).timeout
		t += 0.6
	await get_tree().create_timer(2.0).timeout
	_say("painel: %s" % " → ".join(PackedStringArray(ctx["lines"])).substr(0, 900))
	_say("resultado: %s · morri %d · ingressos %d" % [ctx["state"], deaths[0], _count("marca_circulo")])
	if _event_role == "lead":
		Net.send_gm("event circulo end")
	await _wait_until(func() -> bool: return not _region.begins_with("circulo"), 40.0)
	await get_tree().create_timer(1.0).timeout
	_say("de volta a: %s · dano máximo %d" % [_region, _state[Protocol.PS.MAGIC_MAX]])
	_say("mensagens: %s" % " | ".join(_messages))
	_finish("círculo (%s) concluído" % _event_role, 0)


## Endgame (servidor com --allow-gm). --bot-endgame=write: nível 400, maestria (XP pelo GM),
## pontos nas árvores, reset recusado fora da cidade e feito no Refúgio.
## --bot-endgame=check: o mesmo personagem, outra sessão: confere o que ficou salvo.
func _run_endgame_script() -> void:
	var mastery := [{}]
	Net.mastery_state_received.connect(func(m: Dictionary) -> void: mastery[0] = m)
	await get_tree().create_timer(1.5).timeout
	var st := func() -> String:
		return "nível %d · maestria %d (xp %d/%d, %d livres) · renasc. %d · pontos %d · for/agi/vit/ene %d/%d/%d/%d · defesa %d · vida %d" % [
			_state[Protocol.PS.LEVEL], _state[Protocol.PS.MASTER_LEVEL], _state[Protocol.PS.MASTER_XP], _state[Protocol.PS.MASTER_XP_NEXT],
			_state[Protocol.PS.MASTER_POINTS], _state[Protocol.PS.RESETS], _state[Protocol.PS.POINTS], _state[Protocol.PS.STR],
			_state[Protocol.PS.AGI], _state[Protocol.PS.VIT], _state[Protocol.PS.ENE], _state[Protocol.PS.DEFENSE], _state[Protocol.PS.HP_MAX]]
	if _endgame == "check":
		_say("depois de entrar de novo: %s · árvore %s" % [st.call(), mastery[0]])
		_finish("endgame (check) concluído", 0)
		return
	_say("início: %s" % st.call())
	Net.send_gm("level 399")
	await get_tree().create_timer(0.6).timeout
	Net.send_gm("masterxp 999999") # antes do nível máximo: não faz nada
	Net.send_reset() # nível 399: recusado
	await get_tree().create_timer(0.6).timeout
	Net.send_gm("level 400;currency 300000")
	await get_tree().create_timer(0.6).timeout
	Net.send_gm("masterxp 31200000") # 12 níveis de maestria (400 mil × 1..12)
	await get_tree().create_timer(0.8).timeout
	_say("no nível máximo: %s" % st.call())
	Net.send_mastery_spend("golpe_preciso") # sem os 5 em fúria: recusado
	for i in 5:
		Net.send_mastery_spend("furia")
	Net.send_mastery_spend("golpe_preciso")
	for i in 5:
		Net.send_mastery_spend("pele_pedra")
	Net.send_mastery_spend("vigor")
	Net.send_mastery_spend("furia") # sem pontos: recusado
	await get_tree().create_timer(1.0).timeout
	_say("depois da árvore: %s · árvore %s" % [st.call(), mastery[0]])
	Net.send_gm("goto ruinas 0 10") # fora do Refúgio
	await get_tree().create_timer(1.0).timeout
	Net.send_reset()
	await get_tree().create_timer(0.6).timeout
	Net.send_gm("goto ruinas 0 28")
	await get_tree().create_timer(1.0).timeout
	Net.send_reset()
	await get_tree().create_timer(1.0).timeout
	_say("depois do reset: %s · óbolos %d" % [st.call(), _state[Protocol.PS.CURRENCY]])
	Net.send_gm("level 3")
	await get_tree().create_timer(0.6).timeout
	_say("nível 3 renascido: %s" % st.call())
	_say("mensagens: %s" % " | ".join(_messages))
	_finish("endgame (write) concluído", 0)


## Cerco ao Castelo com dois bots (servidor com --allow-gm). --bot-siege=a:Outro: funda Corvos,
## que fica dono do castelo pelo GM e defende; abre e larga o cerco pelo GM; volta ao trono depois.
## --bot-siege=b:Outro: funda Lobos, inscreve no Arauto, ataca, derruba o portão e toma o trono.
## Depois: o dono define o imposto, o outro compra na loja pagando imposto, o dono saca o tesouro.
func _run_siege_script() -> void:
	var is_a := _siege.begins_with("a")
	var castle := [{}]
	var sched := [[]]
	var state := [{}]
	var lines: Array = []
	Net.castle_state_received.connect(func(s: Dictionary) -> void: castle[0] = s)
	Net.event_schedule_received.connect(func(r: Array) -> void: sched[0] = r)
	Net.event_state_received.connect(func(s: Dictionary) -> void:
		state[0] = s
		var l := "%s | %s" % [s.get("line", "(fora)"), s.get("extra", "")]
		if lines.is_empty() or lines[-1] != l:
			lines.append(l))
	Net.npc_opened.connect(func(id: String) -> void: _npc_open = id)
	Net.npc_closed.connect(func() -> void: _npc_open = "")
	var siege_state := func() -> int:
		for r: Array in sched[0]:
			if str(r[0]) == "cerco":
				return int(r[2])
		return -1
	var sym := "00066000" + "00666600" + "06644660" + "66444466" + "66444466" + "06644660" + "00666600" + "00066000"
	await get_tree().create_timer(1.0).timeout
	Net.send_gm("level 50;currency 300000;item cetro_abissal 9 0 1;item pocao_vida 0 0 0 0 20")
	await get_tree().create_timer(0.8).timeout
	var pts := int(_state[Protocol.PS.POINTS])
	Net.send_add_stat(3, pts / 2)
	Net.send_add_stat(2, pts - pts / 2)
	Net.send_item_action(Protocol.ITEM_AUTO, _find("cetro_abissal", true), 0, 0, 0)
	Net.send_guild_action(Protocol.Guild.CREATE, "Corvos da Cinza" if is_a else "Lobos do Véu", sym if is_a else sym.replace("6", "b").replace("4", "2"))
	await get_tree().create_timer(1.0).timeout
	for arg in OS.get_cmdline_user_args():
		if is_a and arg.begins_with("--bot-siege-invite="): # um terceiro (o cliente gráfico) entra na guilda dona
			await get_tree().create_timer(3.0).timeout
			Net.send_guild_action(Protocol.Guild.INVITE, arg.trim_prefix("--bot-siege-invite="))
	if is_a:
		Net.send_gm("castleowner")
		await get_tree().create_timer(0.5).timeout
		await _open_npc("arauto")
		Net.send_castle_action(Protocol.Castle.REGISTER) # dona: não precisa
		await get_tree().create_timer(0.6).timeout
		_say("castelo: dono %s, imposto %d%%" % [castle[0].get("owner", "?"), roundi(float(castle[0].get("tax_pct", 0)) * 100.0)])
		await _wait_until(func() -> bool: return (castle[0].get("registered", []) as Array).size() > 0, 20.0)
		Net.send_npc_close()
		Net.send_gm("event cerco open")
	else:
		await get_tree().create_timer(2.0).timeout
		await _open_npc("arauto")
		Net.send_castle_action(Protocol.Castle.ENTER) # ainda fechado: recusado
		Net.send_castle_action(Protocol.Castle.REGISTER)
		await get_tree().create_timer(0.8).timeout
		_say("inscritas: %s · óbolos %d" % [castle[0].get("registered", []), _state[Protocol.PS.CURRENCY]])
	await _wait_until(func() -> bool: return siege_state.call() == 1, 15.0)
	if _npc_open != "arauto":
		await _open_npc("arauto")
	Net.send_castle_action(Protocol.Castle.ENTER)
	await _wait_until(func() -> bool: return _region.begins_with("castelo"), 6.0)
	await get_tree().create_timer(0.5).timeout
	_say("no cerco: %s em (%.1f, %.1f)" % [_region, _my_pos.x, _my_pos.y])
	if is_a:
		await get_tree().create_timer(6.0).timeout
		Net.send_gm("event cerco start")
	await _wait_until(func() -> bool: return siege_state.call() == 2, 12.0)
	var ids := MonsterCatalog.type_ids(MonsterCatalog.from_config())
	var t := 0.0
	var phase := 0
	var other_id := 0
	while t < 160.0 and not bool(state[0].get("done", false)):
		var line := str(state[0].get("line", ""))
		if is_a:
			if t > 4.0 and t < 4.7:
				Net.send_gm("event cerco skip") # o portão fica com 5%
			if line.begins_with("Trono: Lobos") and phase == 0:
				phase = 1
				_say("Lobos tomou o trono; os Corvos voltam a lutar")
			if phase >= 1:
				if _my_pos.distance_to(Vector2(0, -20)) > 3.0 and phase == 1:
					Net.send_move_to(Vector2(0.0, -19.0))
				else:
					phase = 2
					for id: int in _players_now:
						other_id = id
					if other_id != 0:
						var v: Vector4 = _seen.get(other_id, Vector4.ZERO)
						Net.send_cast(1, other_id, Vector2(v.x, v.y), false)
				if t > 120.0 or phase == 2 and int(fmod(t, 30.0)) == 29:
					Net.send_gm("event cerco end")
		else:
			if _state.size() == Protocol.PS.COUNT and _state[Protocol.PS.HP] * 2 < _state[Protocol.PS.HP_MAX] and _find("pocao_vida", true) != 0:
				Net.send_item_action(Protocol.ITEM_USE, _find("pocao_vida", true), 0, 0, 0)
			if line.contains("portão de pé"):
				var gate := 0
				for id: int in _monsters:
					if ids[int(_monster_types.get(id, 0))] == "portao_castelo":
						gate = id
				if gate != 0:
					var g: Vector4 = _monsters[gate]
					if _my_pos.distance_to(Vector2(g.x, g.y)) > 8.0:
						Net.send_move_to(Vector2(0.0, 4.0))
					else:
						Net.send_cast([0, 1][int(t * 2) % 2], gate, Vector2(g.x, g.y), false)
				else:
					Net.send_move_to(Vector2(0.0, 4.0))
			else:
				Net.send_move_to(Vector2(0.0, -21.0)) # o trono
		await get_tree().create_timer(0.6).timeout
		t += 0.6
	_say("painel: %s" % " → ".join(PackedStringArray(lines)).substr(0, 1400))
	await _wait_until(func() -> bool: return _region == "ruinas", 45.0)
	await get_tree().create_timer(1.5).timeout
	_say("depois do cerco: dono %s · imposto %d%% · eu dono? %s" % [castle[0].get("owner", "?"), roundi(float(castle[0].get("tax_pct", 0)) * 100.0), castle[0].get("is_owner", false)])
	if bool(castle[0].get("is_owner", false)):
		await _open_npc("arauto")
		Net.send_castle_action(Protocol.Castle.SET_TAX, 100) # 10%
		await get_tree().create_timer(8.0).timeout # o outro compra
		Net.send_castle_action(Protocol.Castle.WITHDRAW)
		await get_tree().create_timer(0.8).timeout
		_say("tesouro sacado · óbolos %d" % _state[Protocol.PS.CURRENCY])
	else:
		await get_tree().create_timer(3.0).timeout
		await _open_npc("mago")
		var before := int(_state[Protocol.PS.CURRENCY])
		Net.send_shop_buy(0, 1)
		await get_tree().create_timer(0.8).timeout
		_say("compra com imposto: óbolos %d → %d" % [before, _state[Protocol.PS.CURRENCY]])
	_say("mensagens: %s" % " | ".join(_messages))
	_finish("cerco (%s) concluído" % ("a" if is_a else "b"), 0)


func _wait_until(cond: Callable, timeout_s: float) -> void:
	var t := 0.0
	while t < timeout_s and not cond.call():
		await get_tree().create_timer(0.25).timeout
		t += 0.25


func _walk_to(target: Vector2, timeout_s: float) -> void:
	var start_region := _region
	var t := 0.0
	while t < timeout_s and _region == start_region and _my_pos.distance_to(target) > 0.8:
		Net.send_move_to(target)
		await get_tree().create_timer(0.5).timeout
		t += 0.5


## Social com dois bots (servidor com --allow-gm):
## lead: chat, convida o outro ao grupo, propõe troca (vara +9 e 100 Óbolos) e caça para dividir XP;
## member: aceita tudo e oferece 7 tônicos. Os dois confirmam em duas etapas.
func _run_social_script() -> void:
	var lead := _social.begins_with("lead")
	var other := _social.get_slice(":", 1)
	Net.chat_received.connect(func(ch: int, from: String, text: String) -> void:
		_chat_log.append("[%s] %s%s" % [["geral", "sussurro", "grupo", "sistema", "guilda"][ch], from + ": " if from != "" else "", text]))
	Net.party_state_received.connect(func(m: Array) -> void: _party = m)
	Net.prompt_received.connect(func(kind: int, from: String, _detail: String) -> void:
		_say("convite de %s (%s): aceito" % [from, "grupo" if kind == Protocol.Prompt.PARTY_INVITE else "troca"])
		if kind == Protocol.Prompt.PARTY_INVITE:
			Net.send_party_action(Protocol.Party.ACCEPT)
		else:
			Net.send_trade_action(Protocol.Trade.ACCEPT))
	Net.trade_state_received.connect(_on_trade_state)
	Net.trade_closed_received.connect(func(reason: String) -> void:
		_say("troca fechada: %s" % reason)
		_trade = {})
	Net.send_gm("currency 500;item vara_eclipse 9 1 1" if lead else "item pocao_vida_menor 0 0 0 0 7")
	Net.send_move_to(Vector2(-1.0 if lead else 1.0, 23.0)) # ficam a 2 m um do outro
	await get_tree().create_timer(2.5 if lead else 30.0).timeout
	if lead:
		Net.send_chat(Protocol.Chat.GENERAL, "", "Olá, Refúgio!")
		Net.send_chat(Protocol.Chat.WHISPER, other, "psst, quer entrar no grupo?")
		Net.send_chat(Protocol.Chat.WHISPER, "Ninguém", "teste")
		await get_tree().create_timer(0.5).timeout
		Net.send_party_action(Protocol.Party.INVITE, other)
		await get_tree().create_timer(1.0).timeout
		Net.send_chat(Protocol.Chat.PARTY, "", "bem-vindo ao grupo")
		for i in 8: # flood: o servidor deve barrar
			Net.send_chat(Protocol.Chat.GENERAL, "", "spam %d" % i)
		await get_tree().create_timer(0.5).timeout
		_say("grupo: %s" % [_party])
		Net.send_trade_action(Protocol.Trade.REQUEST, 0, other)
		await get_tree().create_timer(1.0).timeout
		for i in 40: # espera a troca terminar
			if _trade.is_empty():
				break
			await get_tree().create_timer(0.25).timeout
		_say("caçando para dividir XP (nível %d, xp %d)" % [_state[Protocol.PS.LEVEL], _state[Protocol.PS.XP]])
		_fight = true
		_forge = false
		await get_tree().create_timer(18.0).timeout
		_fight = false
		_forge = true
		_say("xp depois da caça: %d (nível %d)" % [_state[Protocol.PS.XP], _state[Protocol.PS.LEVEL]])
		Net.send_party_action(Protocol.Party.LEAVE)
		await get_tree().create_timer(0.5).timeout
	else:
		_say("xp do membro (sem lutar): %d, nível %d" % [_state[Protocol.PS.XP], _state[Protocol.PS.LEVEL]])
	_say("chat recebido: %s" % " | ".join(_chat_log))
	_say("mochila: %s" % ", ".join(_bag_names()))
	_say("óbolos: %d" % _state[Protocol.PS.CURRENCY])
	_finish("social (%s) concluído" % ("líder" if lead else "membro"), 0)


func _on_trade_state(s: Dictionary) -> void:
	var lead := _social.begins_with("lead")
	var first := _trade.is_empty()
	_trade = s
	if first:
		_say("troca aberta com %s" % s["partner"])
	if not _trade_added:
		_trade_added = true
		if lead:
			Net.send_trade_action(Protocol.Trade.ADD_ITEM, _find("vara_eclipse", true))
			Net.send_trade_action(Protocol.Trade.SET_CURRENCY, 100)
		else:
			Net.send_trade_action(Protocol.Trade.ADD_ITEM, _find("pocao_vida_menor", true))
		return
	var theirs: Array = s["their_items"]
	if not bool(s["my_locked"]) and not theirs.is_empty() and (lead or int(s["their_currency"]) > 0):
		_say("oferta do outro: %d item(ns) e %d Óbolos -> pronto" % [theirs.size(), int(s["their_currency"])])
		Net.send_trade_action(Protocol.Trade.LOCK)
	elif bool(s["my_locked"]) and bool(s["their_locked"]) and not bool(s["my_confirmed"]):
		_say("os dois prontos -> confirmo")
		Net.send_trade_action(Protocol.Trade.CONFIRM)


func _bag_names() -> PackedStringArray:
	var out := PackedStringArray()
	for item: Dictionary in _inventory:
		if int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY:
			out.append(_catalog.display_name(item) + (" ×%d" % int(item["count"]) if int(item.get("count", 1)) > 1 else ""))
	return out


## Persistência em duas execuções com a mesma conta:
## write = muda o personagem e sai; check = entra de novo e imprime o que voltou.
func _run_persist_script() -> void:
	Net.npc_opened.connect(func(id: String) -> void: _npc_open = id)
	Net.npc_closed.connect(func() -> void: _npc_open = "")
	Net.journal_full_received.connect(func(region: String, strokes: Array, marks: Array) -> void:
		var points := 0
		for s: PackedVector2Array in strokes:
			points += s.size()
		var labels := PackedStringArray()
		for m: Array in marks:
			labels.append(str(m[3]))
		_journal_info = "%s: %d traço(s), %d ponto(s), marcas [%s]" % [region, strokes.size(), points, ", ".join(labels)])
	await get_tree().create_timer(1.0).timeout
	if _persist == "write":
		Net.send_gm("currency 1234;level 12;item vara_eclipse 9 1 1;item joia_alma 0 0 0 0;item pocao_vida_menor 0 0 0 0 7;item grimorio_brasas")
		await get_tree().create_timer(0.8).timeout
		Net.send_item_action(Protocol.ITEM_USE, _find("grimorio_brasas"), 0, 0, 0)
		Net.send_add_stat(3, 20)
		await _open_npc("armazem")
		Net.send_item_action(Protocol.ITEM_MOVE, _find("joia_alma", true), ItemCatalog.CONTAINER_STORAGE, 3, 4)
		await get_tree().create_timer(0.4).timeout
		Net.send_npc_close()
		Net.send_move_to(Vector2(0.0, 8.0)) # sai da cidade: risca o diário e descobre o Círculo Rúnico
		for i in 60:
			if _my_pos.y < 9.0:
				break
			await get_tree().create_timer(0.25).timeout
		Net.send_move_to(Vector2(1.0, 1.0))
		await get_tree().create_timer(2.5).timeout
	_say("estado: nível %d, pontos %d, energia %d, óbolos %d, magias %d, posição (%.1f, %.1f)" % [_state[Protocol.PS.LEVEL],
		_state[Protocol.PS.POINTS], _state[Protocol.PS.ENE], _state[Protocol.PS.CURRENCY], _state[Protocol.PS.SPELLS], _my_pos.x, _my_pos.y])
	var bag := PackedStringArray()
	for item: Dictionary in _inventory:
		var where := "mochila" if int(item["container"]) == 0 else ("cofre@%d,%d" % [item["x"], item["y"]] if int(item["container"]) == ItemCatalog.CONTAINER_STORAGE else ItemCatalog.EQUIP_SLOTS[int(item["container"]) - 1])
		bag.append("%s%s [%s] uid %d" % [_catalog.display_name(item), " ×%d" % int(item["count"]) if int(item["count"]) > 1 else "", where, int(item["uid"])])
	_say("itens: %s" % " | ".join(bag))
	_say("diário ao entrar: %s" % _journal_info)
	_finish("persistência (%s) concluída" % _persist, 0)


func _find_in(base: String, container: int) -> int:
	for item: Dictionary in _inventory:
		if str(item["base"]) == base and int(item["container"]) == container:
			return int(item["uid"])
	return 0


func _item_by_uid(uid: int) -> Dictionary:
	for item: Dictionary in _inventory:
		if int(item["uid"]) == uid:
			return item
	return {}


func _stack_sizes(base: String) -> String:
	var s := PackedStringArray()
	for item: Dictionary in _inventory:
		if str(item["base"]) == base and int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY:
			s.append(str(item["count"]))
	return "+".join(s)


## Roteiro de teste do refino (servidor precisa de --allow-gm).
func _run_forge_script() -> void:
	Net.npc_opened.connect(func(id: String) -> void: _npc_open = id)
	Net.npc_closed.connect(func() -> void: _npc_open = "")
	Net.refine_fx_received.connect(func(_e: int, outcome: int, level: int) -> void:
		_fx_log.append(["sucesso", "falha", "destruído"][outcome] + "(+%d)" % level))
	Net.send_gm("currency 5000;item vara_eclipse 9 0 1;item joia_consagrada;item joia_consagrada;item joia_alma;item joia_alma;item joia_alma;item joia_alma;item joia_vortice;item talisma_fortuna;item talisma_fortuna;item selo_preservacao;item joia_vida")
	await get_tree().create_timer(1.0).timeout
	# 1) bênção no cajado equipado (+0 -> +1, sempre)
	var staff := _find("cajado_osso")
	_use(_find("joia_consagrada"), staff)
	await get_tree().create_timer(0.6).timeout
	# 2) três almas no manto equipado
	for i in 3:
		_use(_find("joia_alma"), _find("manto_acolito"))
		await get_tree().create_timer(0.6).timeout
	# 3) seiva vital no cajado (opção extra)
	_use(_find("joia_vida"), _find("cajado_osso"))
	await get_tree().create_timer(0.6).timeout
	print("[bot %d] depois das joias: %s" % [_my_id, ", ".join(_names(["cajado_osso", "manto_acolito"]))])
	# 4) forja: vara +9 + bênção + alma + vórtice + 2 talismãs + selo
	Net.send_npc_interact("forja")
	for i in 30:
		if _npc_open != "":
			break
		await get_tree().create_timer(0.3).timeout
	print("[bot %d] forja aberta: %s" % [_my_id, _npc_open])
	for base in ["vara_eclipse", "joia_consagrada", "joia_alma", "joia_vortice", "talisma_fortuna", "talisma_fortuna", "selo_preservacao"]:
		var uid := _find(base, true)
		if uid != 0:
			Net.send_item_action(Protocol.ITEM_MOVE, uid, ItemCatalog.CONTAINER_FORGE, 0, 0)
			await get_tree().create_timer(0.25).timeout
	var in_forge: Array = []
	for item: Dictionary in _inventory:
		if int(item["container"]) == ItemCatalog.CONTAINER_FORGE:
			in_forge.append(item)
	var book := RecipeBook.new(GameConfig.table("recipes"), _catalog)
	var preview := book.evaluate(in_forge)
	print("[bot %d] prévia da forja: %s, chance %.0f%%, custo %d, protegido %s" % [_my_id, preview["name"], preview["chance"] * 100.0, preview["cost"], preview["protected"]])
	Net.send_forge_combine()
	await get_tree().create_timer(0.8).timeout
	Net.send_npc_close()
	await get_tree().create_timer(0.6).timeout
	print("[bot %d] efeitos: %s" % [_my_id, " ".join(_fx_log)])
	print("[bot %d] depois da forja: %s" % [_my_id, ", ".join(_names(["vara_eclipse"]))])
	_finish("roteiro da forja concluído", 0)


## uid do primeiro item com essa base (na mochila, se only_bag).
func _find(base: String, only_bag: bool = false) -> int:
	for item: Dictionary in _inventory:
		if str(item["base"]) == base and (not only_bag or int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY):
			return int(item["uid"])
	return 0


func _use(jewel_uid: int, target_uid: int) -> void:
	if jewel_uid != 0 and target_uid != 0:
		Net.send_item_action(Protocol.ITEM_USE_ON, jewel_uid, target_uid, 0, 0)


func _names(bases: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for item: Dictionary in _inventory:
		if bases.has(str(item["base"])):
			out.append(_catalog.display_name(item) + (" (extra %d)" % int(item["extra"]) if int(item["extra"]) > 0 else ""))
	return out


func _on_snapshot(_tick: int, ids: PackedInt32Array, metas: PackedInt32Array, states: Dictionary) -> void:
	_snapshots += 1
	var entities := states
	_monsters.clear()
	_players_now.clear()
	for i in ids.size():
		var id := ids[i]
		var v: Vector4 = entities[id]
		if id == _my_id:
			_my_pos = Vector2(v.x, v.y)
		elif Protocol.meta_kind(metas[i]) == Protocol.KIND_SUMMON:
			_summons_seen[id] = v
		elif Protocol.meta_kind(metas[i]) == Protocol.KIND_MONSTER:
			_monsters[id] = v
			_monster_types[id] = Protocol.meta_type(metas[i])
		else:
			_players_now.append(id)
			if not _seen.has(id):
				print("[bot %d] enxergo o jogador %d em (%.1f, %.1f)" % [_my_id, id, v.x, v.y])
			_seen[id] = v


func _on_damage(target_id: int, amount: int, _kind: int) -> void:
	if target_id == _my_id:
		_stats["hits_taken"] += 1
	elif target_id < 0:
		_stats["hits_dealt"] += 1
		_stats["damage_dealt"] += amount


func _on_drop(id: int, label: String, _rarity: int, pos: Vector2) -> void:
	_stats["drops"] += 1
	_drops[id] = pos
	print("[bot %d] drop no chão: %s" % [_my_id, label])


## Equipa automaticamente (uma tentativa por item) tudo que for equipável.
func _on_inventory(encoded: Array) -> void:
	_inventory.clear()
	for a: PackedInt32Array in encoded:
		var item := ItemCodec.decode(a, _catalog)
		_inventory.append(item)
		if not _city and int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY and _catalog.is_equipment(item) and not _tried_equip.has(item["uid"]):
			_tried_equip[item["uid"]] = true
			Net.send_item_action(Protocol.ITEM_AUTO, int(item["uid"]), 0, 0, 0)


func _finish(reason: String, code: int) -> void:
	var others := PackedStringArray()
	for id: int in _seen:
		var p: Vector4 = _seen[id]
		others.append("#%d(%.1f,%.1f)" % [id, p.x, p.y])
	print("[bot %d] fim: %s | snapshots: %d | jogadores vistos: %s | visíveis agora: %d jogador(es), %d monstro(s) | posição (%.1f, %.1f)" % [
		_my_id, reason, _snapshots, " ".join(others) if not others.is_empty() else "nenhum", _players_now.size(), _monsters.size(), _my_pos.x, _my_pos.y])
	if _forge:
		print("[bot %d] mensagens: %s" % [_my_id, " | ".join(_messages)])
	if _fight:
		print("[bot %d] combate: %s" % [_my_id, _stats])
		if _state.size() == Protocol.PS.COUNT:
			print("[bot %d] estado: nível %d, xp %d/%d, pontos %d, vida %d/%d, mana %d/%d, óbolos %d, itens %d" % [_my_id,
				_state[Protocol.PS.LEVEL], _state[Protocol.PS.XP], _state[Protocol.PS.XP_NEXT], _state[Protocol.PS.POINTS],
				_state[Protocol.PS.HP], _state[Protocol.PS.HP_MAX], _state[Protocol.PS.MANA], _state[Protocol.PS.MANA_MAX],
				_state[Protocol.PS.CURRENCY], _state[Protocol.PS.ITEMS]])
		print("[bot %d] mensagens: %s" % [_my_id, " | ".join(_messages.slice(-8))])
		var equipped := PackedStringArray()
		var bag := PackedStringArray()
		for item: Dictionary in _inventory:
			var n := _catalog.display_name(item)
			if int(item["container"]) == ItemCatalog.CONTAINER_INVENTORY:
				bag.append("%s@%d,%d" % [n, item["x"], item["y"]])
			else:
				equipped.append("%s[%s]" % [n, ItemCatalog.EQUIP_SLOTS[int(item["container"]) - 1]])
		print("[bot %d] equipado: %s" % [_my_id, ", ".join(equipped)])
		print("[bot %d] mochila: %s" % [_my_id, ", ".join(bag)])
		if _state.size() == Protocol.PS.COUNT:
			print("[bot %d] dano mágico %d~%d, defesa %d" % [_my_id, _state[Protocol.PS.MAGIC_MIN], _state[Protocol.PS.MAGIC_MAX], _state[Protocol.PS.DEFENSE]])
	set_process(false)
	Net.disconnect_from_server()
	get_tree().quit(code)
