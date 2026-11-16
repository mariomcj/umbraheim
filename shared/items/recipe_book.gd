class_name RecipeBook
extends RefCounted
## Receitas da Forja do Vórtice (data/recipes.json). Dado o conteúdo da forja,
## descobre qual receita ele forma, a chance, o custo e o que falta. O cliente usa
## para a prévia; o servidor usa para decidir (mesmo código, mesmos dados).
##
## evaluate() retorna:
## {valid: bool, recipe: String, name: String, chance: float, cost: int,
##  target_uid: int (refino), result_base: String (craft), protected: bool, hint: String}

var recipes: Dictionary
var catalog: ItemCatalog


func _init(recipe_table: Dictionary, item_catalog: ItemCatalog) -> void:
	recipes = recipe_table
	catalog = item_catalog


func evaluate(items: Array) -> Dictionary:
	if items.is_empty():
		return _invalid("Coloque itens e joias na forja.")
	var counts := {}
	var equipment: Array = []
	for item: Dictionary in items:
		if catalog.is_equipment(item):
			equipment.append(item)
		else:
			counts[str(item["base"])] = int(counts.get(str(item["base"]), 0)) + 1
	if equipment.size() == 1:
		var wings := _evaluate_wings(equipment[0], counts)
		if not wings.is_empty():
			return wings
		return _evaluate_refine(equipment[0], counts)
	if equipment.size() > 1:
		return _invalid("Apenas um equipamento por vez.")
	for id: String in recipes:
		var r: Dictionary = recipes[id]
		if str(r["type"]) == "craft" and _same_counts(counts, r["ingredients"]):
			return {"valid": true, "recipe": id, "name": str(r["name"]), "chance": float(r["chance"]),
				"cost": int(r["cost"]), "target_uid": 0, "result_base": str(r["result"]), "protected": false, "hint": ""}
	return _invalid("Combinação desconhecida.")


## Criar asas: equipamento sacrificado + joias exatas. {} se as joias não são as das asas
## (aí a forja tenta o refino superior).
func _evaluate_wings(item: Dictionary, counts: Dictionary) -> Dictionary:
	for id: String in recipes:
		var r: Dictionary = recipes[id]
		if str(r["type"]) != "wings" or not _same_counts(counts, r["ingredients"]):
			continue
		if str(catalog.base(item).get("slot", "")) == "wings":
			return _invalid("Asas não servem de sacrifício para criar asas.")
		var level := int(item.get("level", 0))
		var min_level := int(r["item_min_level"])
		if level < min_level:
			return _invalid("O equipamento sacrificado precisa estar +%d ou mais (está +%d)." % [min_level, level])
		var chance := float(r["base_chance"]) + float(r["per_level"]) * (level - min_level)
		if bool(item.get("luck", false)):
			chance += float(r["luck_bonus"])
		if int(item.get("rarity", 0)) != ItemCatalog.RARITY_NORMAL:
			chance += float(r["excellent_bonus"])
		chance = clampf(chance, 0.0, float(r["max_chance"]))
		return {"valid": true, "recipe": id, "name": str(r["name"]), "chance": chance, "cost": int(r["cost"]),
			"target_uid": 0, "result_base": "", "protected": false, "hint": "", "sacrifice": catalog.display_name(item)}
	return {}


func _evaluate_refine(item: Dictionary, counts: Dictionary) -> Dictionary:
	for id: String in recipes:
		var r: Dictionary = recipes[id]
		if str(r["type"]) != "refine":
			continue
		var level := int(item.get("level", 0))
		var levels: Dictionary = r["levels"]
		if not levels.has(str(level)):
			return _invalid("O refino superior vai de +9 a +15 (item está +%d)." % level)
		var need: Dictionary = levels[str(level)].duplicate()
		var base_chance := float(need["chance"])
		var cost := int(need["cost"])
		need.erase("chance")
		need.erase("cost")
		var charm := str(r["charm"])
		var protector := str(r["protector"])
		var charms := int(counts.get(charm, 0))
		var protectors := int(counts.get(protector, 0))
		if charms > int(r["charm_max"]):
			return _invalid("No máximo %d talismãs." % int(r["charm_max"]))
		if protectors > 1:
			return _invalid("Apenas um selo de preservação.")
		var rest := counts.duplicate()
		rest.erase(charm)
		rest.erase(protector)
		var required := {}
		for k: String in need:
			if int(need[k]) > 0:
				required[k] = int(need[k])
		if not _same_counts(rest, required):
			return _invalid("Para +%d: %s." % [level + 1, _describe(required)])
		var chance := base_chance
		if bool(item.get("luck", false)):
			chance += float(r["luck_bonus"])
		if int(item.get("rarity", 0)) != ItemCatalog.RARITY_NORMAL:
			chance -= float(r["rarity_penalty"])
		chance += charms * float(r["charm_bonus"])
		chance = clampf(chance, 0.0, float(r["max_chance"]))
		return {"valid": true, "recipe": id, "name": "%s: +%d → +%d" % [r["name"], level, level + 1], "chance": chance,
			"cost": cost, "target_uid": int(item["uid"]), "result_base": "", "protected": protectors == 1, "hint": ""}
	return _invalid("Sem receita de refino.")


func _describe(required: Dictionary) -> String:
	var parts := PackedStringArray()
	for k: String in required:
		parts.append("%d× %s" % [int(required[k]), catalog.bases.get(k, {}).get("name", k)])
	return ", ".join(parts)


static func _same_counts(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k: String in b:
		if int(a.get(k, 0)) != int(b[k]):
			return false
	return true


static func _invalid(hint: String) -> Dictionary:
	return {"valid": false, "recipe": "", "name": "", "chance": 0.0, "cost": 0, "target_uid": 0,
		"result_base": "", "protected": false, "hint": hint}
