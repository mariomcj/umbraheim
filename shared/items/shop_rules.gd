class_name ShopRules
extends RefCounted
## Preços das lojas (data/shops.json), compartilhados: o cliente mostra exatamente
## o que o servidor vai cobrar ou pagar.

var cfg: Dictionary
var catalog: ItemCatalog


func _init(shop_table: Dictionary, item_catalog: ItemCatalog) -> void:
	cfg = shop_table
	catalog = item_catalog


static func from_config() -> ShopRules:
	return ShopRules.new(GameConfig.table("shops"), ItemCatalog.from_config())


func shop(shop_id: String) -> Dictionary:
	return (cfg.get("shops", {}) as Dictionary).get(shop_id, {})


## Bases à venda (só as que existem no catálogo).
func stock(shop_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for base_id: String in shop(shop_id).get("stock", []):
		if catalog.bases.has(base_id):
			out.append(base_id)
	return out


func buy_price(base_id: String) -> int:
	return maxi(1, int(catalog.bases.get(base_id, {}).get("price", 1)))


## Valor de UMA unidade do item, considerando refino, raridade, sorte e opções.
func unit_value(item: Dictionary) -> float:
	var v: Dictionary = cfg.get("value", {})
	var value := float(catalog.base(item).get("price", 0))
	var lvl := int(item.get("level", 0))
	value *= 1.0 + lvl * lvl * float(v.get("level_sq_mult", 0.0))
	var rarity_mult: Array = v.get("rarity_mult", [1.0])
	value *= float(rarity_mult[clampi(int(item.get("rarity", 0)), 0, rarity_mult.size() - 1)])
	if bool(item.get("luck", false)):
		value *= float(v.get("luck_mult", 1.0))
	value *= 1.0 + int(item.get("extra", 0)) * float(v.get("extra_mult", 0.0))
	value *= 1.0 + (item.get("exc", []) as Array).size() * float(v.get("exc_option_mult", 0.0))
	return value


## Quanto a loja paga pelo item (a pilha inteira).
func sell_price(item: Dictionary) -> int:
	return floori(unit_value(item) * float(cfg.get("sell_fraction", 0.0))) * maxi(1, int(item.get("count", 1)))


func needs_sell_confirm(item: Dictionary) -> bool:
	return sell_price(item) >= int(cfg.get("confirm_sell_min", 0)) or int(item.get("rarity", 0)) != ItemCatalog.RARITY_NORMAL \
		or int(item.get("level", 0)) >= 7
