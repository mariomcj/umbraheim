class_name MonsterCatalog
extends RefCounted
## Definições de monstros = data/monsters.json + variantes douradas geradas a partir de
## data/events.json -> golden (id + "_dourado"). Servidor e cliente montam a mesma lista,
## então o índice do tipo no snapshot continua batendo sem mudar o protocolo.

const GOLDEN_SUFFIX_ID := "_dourado"


static func from_config() -> Dictionary:
	return build(GameConfig.table("monsters"), GameConfig.table("events"))


static func build(monsters: Dictionary, events: Dictionary) -> Dictionary:
	var out := {}
	for id: String in monsters:
		if id.begins_with("_"):
			continue
		out[id] = monsters[id]
	var golden: Dictionary = events.get("golden", {})
	for base_id: String in golden.get("monsters", []):
		if not out.has(base_id):
			continue
		var d: Dictionary = (out[base_id] as Dictionary).duplicate(true)
		d["name"] = str(d["name"]) + str(golden.get("suffix", " Dourado"))
		d["golden"] = true
		d["hp"] = float(d["hp"]) * float(golden.get("hp_mult", 1.0))
		d["damage_min"] = float(d["damage_min"]) * float(golden.get("damage_mult", 1.0))
		d["damage_max"] = float(d["damage_max"]) * float(golden.get("damage_mult", 1.0))
		d["xp_mult"] = float(d.get("xp_mult", 1.0)) * float(golden.get("xp_mult", 1.0))
		d["drop_table"] = str(golden.get("drop_table", d["drop_table"]))
		d["drop_rolls"] = int(golden.get("drop_rolls", 1))
		out[base_id + GOLDEN_SUFFIX_ID] = d
	return out


## Ids ordenados: o índice nesta lista é o tipo no snapshot.
static func type_ids(defs: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray(defs.keys())
	ids.sort()
	return ids
