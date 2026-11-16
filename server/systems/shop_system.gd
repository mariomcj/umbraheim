class_name ShopSystem
extends RefCounted
## Compra e venda nas lojas dos NPCs (ferreiro, alquimista). Preços de ShopRules,
## os mesmos que o cliente mostra. A loja precisa estar aberta e o jogador perto.

var server: GameServer
var rules: ShopRules


func _init(game_server: GameServer, shop_table: Dictionary) -> void:
	server = game_server
	rules = ShopRules.new(shop_table, server.catalog)


func _open_shop(p: ServerPlayer) -> String:
	var npcs := server.region_of(p).npcs
	if not npcs.is_open(p, "shop"):
		return ""
	if server.pvp.shop_refuses(p):
		server.send_message(p.peer_id, "O mercador cruza os braços: não atende Fora da Lei.")
		return "refused"
	return str(npcs.get_npc(p.npc_open).get("shop", ""))


func buy(p: ServerPlayer, stock_index: int, quantity: int) -> void:
	var shop_id := _open_shop(p)
	if shop_id == "refused":
		return
	if shop_id == "":
		server.send_message(p.peer_id, "Aproxime-se de um mercador.")
		return
	var stock := rules.stock(shop_id)
	if stock_index < 0 or stock_index >= stock.size():
		return
	var base_id := stock[stock_index]
	var item := server.factory.create(base_id)
	var count := clampi(quantity, 1, server.catalog.stack_max(item))
	item["count"] = count
	var base_total := rules.buy_price(base_id) * count
	var total := base_total + CastleSystem.tax_on(base_total, server.castle.current_tax())
	if p.currency < total:
		server.send_message(p.peer_id, "Óbolos insuficientes (custa %d)." % total)
		return
	if not server.inventory.has_room(p, item):
		server.send_message(p.peer_id, "Inventário cheio.")
		return
	p.currency -= total
	var tax := server.castle.collect(base_total) # o imposto vai para o tesouro do castelo
	server.inventory.give(p, item)
	var label := server.catalog.display_name(item) + (" ×%d" % count if count > 1 else "")
	server.send_message(p.peer_id, "Comprou %s por %d Óbolos%s." % [label, total, (" (%d de imposto do castelo)" % tax) if tax > 0 else ""])


func sell(p: ServerPlayer, uid: int) -> void:
	var shop := _open_shop(p)
	if shop == "refused":
		return
	if shop == "":
		server.send_message(p.peer_id, "Aproxime-se de um mercador.")
		return
	var item: Dictionary = p.items.get(uid, {})
	if item.is_empty() or int(item["container"]) != ItemCatalog.CONTAINER_INVENTORY:
		server.send_message(p.peer_id, "Só itens da mochila podem ser vendidos.")
		return
	if server.catalog.is_quest_item(item):
		server.send_message(p.peer_id, "Ninguém compra um item de missão.")
		return
	var price := rules.sell_price(item)
	server.inventory.take(p, uid)
	p.currency += price
	var label := server.catalog.display_name(item) + (" ×%d" % int(item["count"]) if int(item.get("count", 1)) > 1 else "")
	server.send_message(p.peer_id, "Vendeu %s por %d Óbolos." % [label, price])
