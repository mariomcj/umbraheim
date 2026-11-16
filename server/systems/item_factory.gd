class_name ItemFactory
extends RefCounted
## Cria instâncias de itens no servidor (uid único) e sorteia nível, sorte, opção extra
## e raridade dos drops conforme data/drops.json -> item_rolls.

var catalog: ItemCatalog
var rolls: Dictionary
var rng: RandomNumberGenerator
var _next_uid: int = 1


func _init(item_catalog: ItemCatalog, roll_table: Dictionary, random: RandomNumberGenerator) -> void:
	catalog = item_catalog
	rolls = roll_table
	rng = random


## Os uids continuam depois do maior já salvo no banco (nunca se repetem).
func continue_after(max_uid: int) -> void:
	_next_uid = maxi(_next_uid, max_uid + 1)


func create(base_id: String) -> Dictionary:
	var item := {"uid": _next_uid, "base": base_id, "level": 0, "rarity": ItemCatalog.RARITY_NORMAL,
		"luck": false, "extra": 0, "exc": [], "container": ItemCatalog.CONTAINER_INVENTORY, "x": 0, "y": 0}
	_next_uid += 1
	return item


## Item de drop: equipamentos ganham atributos sorteados; joias vêm puras.
func create_rolled(base_id: String) -> Dictionary:
	var item := create(base_id)
	if not catalog.is_equipment(item):
		return item
	item["level"] = _weighted_index(rolls.get("level_weights", [1]))
	item["luck"] = rng.randf() < float(rolls.get("luck_chance", 0.0))
	if rng.randf() < float(rolls.get("extra_chance", 0.0)):
		item["extra"] = rng.randi_range(1, int(rolls.get("extra_max_drop", 1)))
	if catalog.can_be_ancestral(base_id) and rng.randf() < float(rolls.get("ancestral_chance", 0.0)):
		item["rarity"] = ItemCatalog.RARITY_ANCESTRAL
	elif rng.randf() < float(rolls.get("excellent_chance", 0.0)):
		item["rarity"] = ItemCatalog.RARITY_EXCELLENT
		var pool := catalog.excellent_pool(item)
		var count := rng.randi_range(1, mini(int(rolls.get("excellent_options_max", 1)), pool.size()))
		var picked: Array[String] = []
		while picked.size() < count:
			var opt := pool[rng.randi() % pool.size()]
			if not picked.has(opt):
				picked.append(opt)
		item["exc"] = picked
	return item


func _weighted_index(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := rng.randf() * total
	for i in weights.size():
		r -= float(weights[i])
		if r <= 0.0:
			return i
	return 0
