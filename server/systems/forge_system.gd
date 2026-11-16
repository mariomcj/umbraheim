class_name ForgeSystem
extends RefCounted
## Joias usadas sobre itens e a Forja do Vórtice (NPC artefato arcano).
## Tudo é sorteado aqui, no servidor; o cliente só recebe o resultado e o efeito.

var server: GameServer
var refine_cfg: Dictionary
var book: RecipeBook


func _init(game_server: GameServer, refine_table: Dictionary, recipe_table: Dictionary) -> void:
	server = game_server
	refine_cfg = refine_table
	book = RecipeBook.new(recipe_table, server.catalog)


# ---------------------------------------------------------------- joia sobre item

func use_jewel(p: ServerPlayer, jewel_uid: int, target_uid: int) -> void:
	var jewel: Dictionary = p.items.get(jewel_uid, {})
	var target: Dictionary = p.items.get(target_uid, {})
	if jewel.is_empty() or target.is_empty() or int(jewel["container"]) != ItemCatalog.CONTAINER_INVENTORY:
		return
	var role := str(server.catalog.base(jewel).get("jewel", ""))
	if not role in ["bless", "soul", "life"]:
		server.send_message(p.peer_id, "Esta joia é usada na Forja do Vórtice.")
		return
	var r := RefineRules.apply_jewel(role, target, server.catalog, refine_cfg, server.rng)
	if r["result"] == RefineRules.INVALID:
		server.send_message(p.peer_id, str(r["reason"]))
		return
	server.inventory.take(p, jewel_uid) # a joia é consumida na tentativa
	var before := server.catalog.display_name(target)
	target["level"] = int(r["level"])
	target["extra"] = int(r["extra"])
	var after := server.catalog.display_name(target)
	if r["result"] == RefineRules.SUCCESS:
		server.send_message(p.peer_id, "Sucesso! %s → %s." % [before, after])
		server.broadcast_refine_fx(p, Protocol.FX_SUCCESS, int(target["level"]))
	else:
		server.send_message(p.peer_id, "Falhou... %s → %s." % [before, after])
		server.broadcast_refine_fx(p, Protocol.FX_FAIL, int(target["level"]))


# ---------------------------------------------------------------- Forja do Vórtice
# (abrir, fechar e devolver os itens da mesa ficam no NpcSystem)

func combine(p: ServerPlayer) -> void:
	if not server.region_of(p).npcs.is_open(p, "vortex_forge"):
		server.send_message(p.peer_id, "Aproxime-se da Forja do Vórtice.")
		return
	var items := server.inventory.forge_items(p)
	var e := book.evaluate(items)
	if not e["valid"]:
		server.send_message(p.peer_id, str(e["hint"]))
		return
	if p.currency < int(e["cost"]):
		server.send_message(p.peer_id, "Óbolos insuficientes (precisa de %d)." % int(e["cost"]))
		return
	p.currency -= int(e["cost"])
	var success := server.rng.randf() < float(e["chance"])
	var recipe: Dictionary = book.recipes[e["recipe"]]
	if str(recipe["type"]) == "refine":
		var target: Dictionary = p.items[int(e["target_uid"])]
		var before := server.catalog.display_name(target)
		_consume_all_except(p, items, int(e["target_uid"]))
		if success:
			target["level"] = int(target["level"]) + 1
			server.send_message(p.peer_id, "A forja ruge! %s → %s." % [before, server.catalog.display_name(target)])
			server.broadcast_refine_fx(p, Protocol.FX_SUCCESS, int(target["level"]))
		elif bool(e["protected"]):
			server.send_message(p.peer_id, "Falhou, mas o selo preservou %s." % before)
			server.broadcast_refine_fx(p, Protocol.FX_FAIL, int(target["level"]))
		else:
			server.inventory.take(p, int(e["target_uid"]))
			server.send_message(p.peer_id, "Falhou... %s virou cinzas." % before)
			server.broadcast_refine_fx(p, Protocol.FX_DESTROYED, 0)
	elif str(recipe["type"]) == "wings":
		_consume_all_except(p, items, 0) # o equipamento sacrificado também vai
		if success:
			var results: Array = recipe["results"]
			var wings := server.factory.create(str(results[server.rng.randi() % results.size()]))
			wings["container"] = ItemCatalog.CONTAINER_FORGE
			p.items[wings["uid"]] = wings
			server.send_message(p.peer_id, "Do vórtice nascem asas: %s!" % server.catalog.display_name(wings))
			server.broadcast_refine_fx(p, Protocol.FX_SUCCESS, 0)
			server.announce("Asas forjadas!", "%s criou %s na Forja do Vórtice" % [p.char_name, server.catalog.display_name(wings)])
		else:
			server.send_message(p.peer_id, "O vórtice engoliu %s e as joias... sem asas desta vez." % e["sacrifice"])
			server.broadcast_refine_fx(p, Protocol.FX_DESTROYED, 0)
	else:
		_consume_all_except(p, items, 0)
		if success:
			var result := server.factory.create(str(e["result_base"]))
			result["container"] = ItemCatalog.CONTAINER_FORGE
			p.items[result["uid"]] = result
			server.send_message(p.peer_id, "%s: sucesso! Você obteve %s." % [e["name"], server.catalog.display_name(result)])
			server.broadcast_refine_fx(p, Protocol.FX_SUCCESS, 0)
		else:
			server.send_message(p.peer_id, "%s: falhou, os ingredientes se perderam." % e["name"])
			server.broadcast_refine_fx(p, Protocol.FX_FAIL, 0)
	server.recompute(p)


func _consume_all_except(p: ServerPlayer, items: Array, keep_uid: int) -> void:
	for item: Dictionary in items:
		if int(item["uid"]) != keep_uid:
			server.inventory.take(p, int(item["uid"]))
