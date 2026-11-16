class_name ItemCatalog
extends RefCounted
## Catálogo de itens compartilhado por cliente e servidor: bases (data/items.json),
## opções (data/item_options.json) e conjuntos (data/sets.json).
##
## Instância de item (Dictionary):
##   uid: int, base: String, level: int (0..15), rarity: int (RARITY_*),
##   luck: bool, extra: int (níveis da opção extra), exc: Array[String] (opções excelentes),
##   container: int (CONTAINER_INVENTORY ou 1 + índice do slot), x: int, y: int
## Bônus de um item: Dictionary com as mesmas chaves dos atributos derivados
## (magic_min, magic_max, defense, hp_max, mana_max, hp_max_pct, attack_speed, crit_chance,
## excellent_chance, damage_pct, damage_reduction_pct, reflect_pct, hp_on_kill_frac,
## mana_on_kill_frac, currency_pct) e stat_str/stat_agi/stat_vit/stat_ene.

const RARITY_NORMAL := 0
const RARITY_EXCELLENT := 1
const RARITY_ANCESTRAL := 2

const CONTAINER_INVENTORY := 0
const CONTAINER_FORGE := 200 # itens colocados na Forja do Vórtice
const CONTAINER_STORAGE := 300 # armazém (cofre) do personagem
const CONTAINER_TRADE := 400 # oferta numa troca com outro jogador
## Slots de equipamento (container = 1 + índice).
const EQUIP_SLOTS: PackedStringArray = ["weapon", "shield", "helm", "armor", "pants", "gloves", "boots",
	"wings", "amulet", "ring1", "ring2", "pet"]
## Slots que aparecem no personagem (aparência replicada para os outros jogadores).
const VISIBLE_SLOTS: PackedStringArray = ["weapon", "shield", "helm", "armor", "pants", "gloves", "boots", "wings"]

var bases: Dictionary
var base_ids: PackedStringArray # ordenado: índice usado na rede
var options: Dictionary
var exc_ids: PackedStringArray # ordenado: bit da máscara de opções excelentes
var sets: Dictionary
var _set_of_base: Dictionary = {}


func _init(item_table: Dictionary, option_table: Dictionary, set_table: Dictionary) -> void:
	bases = item_table
	base_ids = PackedStringArray(bases.keys())
	base_ids.sort()
	options = option_table
	exc_ids = PackedStringArray((options.get("excellent", {}) as Dictionary).keys())
	exc_ids.sort()
	sets = set_table
	for set_id: String in sets:
		for piece: String in sets[set_id]["pieces"]:
			_set_of_base[piece] = set_id


static func from_config() -> ItemCatalog:
	return ItemCatalog.new(GameConfig.table("items"), GameConfig.table("item_options"), GameConfig.table("sets"))


func base(item: Dictionary) -> Dictionary:
	return bases.get(str(item.get("base", "")), {})


func size_of(item: Dictionary) -> Vector2i:
	var s: Array = base(item).get("size", [1, 1])
	return Vector2i(int(s[0]), int(s[1]))


func is_equipment(item: Dictionary) -> bool:
	return str(base(item).get("kind", "")) == "equip"


func is_consumable(item: Dictionary) -> bool:
	return str(base(item).get("kind", "")) == "consumable"


## Quantos cabem numa pilha (1 = não empilha).
func stack_max(item: Dictionary) -> int:
	return maxi(1, int(base(item).get("stack_max", 1)))


## Efeito de uso ({} se o item não é usável).
func use_effect(item: Dictionary) -> Dictionary:
	return base(item).get("use", {})


## Slot de equipamento (nome em EQUIP_SLOTS) aceita este item?
func fits_slot(item: Dictionary, slot_name: String) -> bool:
	var s := str(base(item).get("slot", ""))
	if s == "ring":
		return slot_name == "ring1" or slot_name == "ring2"
	return s != "" and s == slot_name


## Primeiro slot compatível (para equipar com o botão direito).
func default_slot(item: Dictionary) -> String:
	var s := str(base(item).get("slot", ""))
	if s == "ring":
		return "ring1"
	return s if EQUIP_SLOTS.has(s) else ""


## Classes que podem usar o item (vazio = todas).
func classes_of(item: Dictionary) -> Array:
	return base(item).get("classes", [])


func allowed_for(item: Dictionary, class_id: String) -> bool:
	var list := classes_of(item)
	return list.is_empty() or class_id in list


func is_quest_item(item: Dictionary) -> bool:
	return str(base(item).get("kind", "")) == "quest"


func level_req(item: Dictionary) -> int:
	return int(base(item).get("level_req", 0))


func set_id_of(item: Dictionary) -> String:
	if int(item.get("rarity", 0)) != RARITY_ANCESTRAL:
		return ""
	return str(_set_of_base.get(str(item.get("base", "")), ""))


func can_be_ancestral(base_id: String) -> bool:
	return _set_of_base.has(base_id)


func is_weapon_like(item: Dictionary) -> bool:
	return (options.get("weapon_slots", []) as Array).has(str(base(item).get("slot", "")))


## Opções excelentes que podem cair neste item.
func excellent_pool(item: Dictionary) -> PackedStringArray:
	var kind := "weapon" if is_weapon_like(item) else "armor"
	var out := PackedStringArray()
	for id in exc_ids:
		if str(options["excellent"][id]["applies_to"]) == kind:
			out.append(id)
	return out


## "Cajado de Osso +7", com prefixo de raridade.
func display_name(item: Dictionary) -> String:
	var b := base(item)
	var n := str(b.get("name", "?"))
	if is_equipment(item) and int(item.get("level", 0)) > 0:
		n += " +%d" % int(item["level"])
	match int(item.get("rarity", 0)):
		RARITY_EXCELLENT:
			n = "Excelente " + n
		RARITY_ANCESTRAL:
			var set_id := set_id_of(item)
			if set_id != "":
				n = "%s · %s" % [sets[set_id]["name"], n]
	return n


## Bônus que o item dá enquanto equipado.
func item_bonuses(item: Dictionary) -> Dictionary:
	var out := {}
	if not is_equipment(item):
		return out
	var b := base(item)
	for k: String in b.get("stats", {}):
		_add(out, k, float(b["stats"][k]))
	var main := str(b.get("main", ""))
	var refine: Array = options.get("refine_main", [0])
	var lvl := clampi(int(item.get("level", 0)), 0, refine.size() - 1)
	var main_bonus := float(refine[lvl]) + int(item.get("extra", 0)) * float(options.get("extra_per_level", 0))
	if main == "magic":
		_add(out, "magic_min", main_bonus)
		_add(out, "magic_max", main_bonus)
	elif main == "defense":
		_add(out, "defense", main_bonus)
	if bool(item.get("luck", false)):
		_add(out, "crit_chance", float(options.get("luck_crit_bonus", 0.0)))
	for opt_id: String in item.get("exc", []):
		var opt: Dictionary = options["excellent"].get(opt_id, {})
		if not opt.is_empty():
			_add(out, str(opt["effect"]), float(opt["value"]))
	var set_id := set_id_of(item)
	if set_id != "":
		_add(out, "stat_" + str(sets[set_id]["stat"]), float(options.get("ancestral_stat_bonus", 0)))
	return out


## Soma dos bônus de todos os itens equipados, incluindo bônus de conjunto.
func equipment_bonuses(equipped: Array) -> Dictionary:
	var out := {}
	var set_counts := {}
	for item: Dictionary in equipped:
		var b := item_bonuses(item)
		for k: String in b:
			_add(out, k, float(b[k]))
		var set_id := set_id_of(item)
		if set_id != "":
			set_counts[set_id] = int(set_counts.get(set_id, 0)) + 1
	for set_id: String in set_counts:
		var tiers: Dictionary = sets[set_id]["bonuses"]
		for need: String in tiers:
			if int(set_counts[set_id]) >= int(need):
				for k: String in tiers[need]:
					_add(out, k, float(tiers[need][k]))
	return out


## Linhas do tooltip: [texto, cor] (cor como nome: "name", "normal", "excellent", "ancestral", "blue", "red", "dim").
func tooltip_lines(item: Dictionary, player_level: int, player_class: String = "") -> Array:
	var b := base(item)
	var lines: Array = []
	var name_color := "normal"
	match int(item.get("rarity", 0)):
		RARITY_EXCELLENT:
			name_color = "excellent"
		RARITY_ANCESTRAL:
			name_color = "ancestral"
	if str(b.get("kind", "")) in ["jewel", "charm"]:
		name_color = "jewel"
	lines.append([display_name(item), name_color])
	if is_equipment(item):
		var bonus := item_bonuses(item)
		if bonus.has("magic_min"):
			lines.append(["Dano mágico: +%d ~ +%d" % [roundi(bonus["magic_min"]), roundi(bonus["magic_max"])], "normal"])
		if bonus.has("defense"):
			lines.append(["Defesa: +%d" % roundi(bonus["defense"]), "normal"])
		if bonus.has("hp_max"):
			lines.append(["Vida: +%d" % roundi(bonus["hp_max"]), "normal"])
		if bonus.has("mana_max"):
			lines.append(["Mana: +%d" % roundi(bonus["mana_max"]), "normal"])
		var base_stats: Dictionary = b.get("stats", {})
		if base_stats.has("damage_pct"):
			lines.append(["Dano: +%d%%" % roundi(float(base_stats["damage_pct"]) * 100.0), "normal"])
		if base_stats.has("damage_reduction_pct"):
			lines.append(["Absorve %d%% do dano recebido" % roundi(float(base_stats["damage_reduction_pct"]) * 100.0), "normal"])
		if int(b.get("tier", 0)) > 0:
			lines.append(["Asas de nível %d" % int(b["tier"]), "dim"])
		_class_line(lines, item, player_class)
		var req := level_req(item)
		if req > 0:
			lines.append(["Nível necessário: %d" % req, "red" if player_level < req else "dim"])
		if bool(item.get("luck", false)):
			lines.append(["Sorte (+5% de crítico, +25% no refino)", "blue"])
		if int(item.get("extra", 0)) > 0:
			var what := "dano mágico" if str(b.get("main", "")) == "magic" else "defesa"
			lines.append(["Opção extra: +%d de %s" % [int(item["extra"]) * int(options.get("extra_per_level", 0)), what], "blue"])
		for opt_id: String in item.get("exc", []):
			lines.append([str(options["excellent"].get(opt_id, {}).get("label", opt_id)), "excellent"])
		var set_id := set_id_of(item)
		if set_id != "":
			lines.append(["+%d de %s (ancestral)" % [int(options.get("ancestral_stat_bonus", 0)), _stat_label(str(sets[set_id]["stat"]))], "ancestral"])
			lines.append(["Conjunto %s:" % sets[set_id]["name"], "ancestral"])
			var tiers: Dictionary = sets[set_id]["bonuses"]
			for need: String in tiers:
				lines.append(["  %s peças: %s" % [need, _bonus_text(tiers[need])], "dim"])
	elif str(b.get("kind", "")) == "jewel":
		lines.append([_jewel_help(str(b.get("jewel", ""))), "dim"])
		lines.append(["Clique na joia e depois no item para usar.", "dim"] if str(b.get("jewel", "")) in ["bless", "soul", "life"] else ["Coloque na Forja do Vórtice.", "dim"])
	elif str(b.get("kind", "")) == "charm":
		lines.append([str(b.get("help", "")), "dim"])
	elif is_consumable(item):
		if int(item.get("count", 1)) > 1:
			lines.append(["Quantidade: %d" % int(item["count"]), "normal"])
		var req := level_req(item)
		if req > 0:
			lines.append(["Nível necessário: %d" % req, "red" if player_level < req else "dim"])
		_class_line(lines, item, player_class)
		lines.append([str(b.get("help", "")), "dim"])
		lines.append(["Botão direito: usar.", "dim"])
	elif str(b.get("kind", "")) == "material":
		if int(item.get("count", 1)) > 1:
			lines.append(["Quantidade: %d" % int(item["count"]), "normal"])
		lines.append([str(b.get("help", "")), "dim"])
		lines.append(["Coloque na Forja do Vórtice.", "dim"])
	elif is_quest_item(item):
		lines.append(["Item de missão", "jewel"])
		lines.append([str(b.get("help", "")), "dim"])
	return lines


## "Classe: ..." em vermelho quando o item não é da classe do jogador.
func _class_line(lines: Array, item: Dictionary, player_class: String) -> void:
	var list := classes_of(item)
	if list.is_empty():
		return
	var names := PackedStringArray()
	for c: String in list:
		var data := ConfigLoader.load_json("res://data/classes/%s.json" % c)
		names.append(str(data.get("name", c)))
	lines.append(["Classe: %s" % ", ".join(names), "red" if player_class != "" and not player_class in list else "dim"])


func _jewel_help(role: String) -> String:
	match role:
		"bless": return "Refina um item de +0 a +6 (100%)."
		"soul": return "Refina até +9 (chance; a falha pode rebaixar)."
		"vortex": return "Combustível da Forja do Vórtice."
		"life": return "Adiciona ou eleva a opção extra."
		"genesis": return "Usada em receitas avançadas."
	return ""


static func _stat_label(stat: String) -> String:
	match stat:
		"str": return "Força"
		"agi": return "Agilidade"
		"vit": return "Vitalidade"
		"ene": return "Energia"
	return stat


static func _bonus_text(bonus: Dictionary) -> String:
	var parts := PackedStringArray()
	for k: String in bonus:
		var v := float(bonus[k])
		if k.ends_with("_pct"):
			parts.append("+%d%% %s" % [roundi(v * 100.0), k.trim_suffix("_pct").replace("_", " ")])
		elif k.begins_with("stat_"):
			parts.append("+%d %s" % [roundi(v), _stat_label(k.trim_prefix("stat_"))])
		else:
			parts.append("+%d %s" % [roundi(v), k.replace("_", " ")])
	return ", ".join(parts)


static func _add(out: Dictionary, key: String, value: float) -> void:
	out[key] = float(out.get(key, 0.0)) + value
