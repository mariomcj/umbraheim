class_name RefineRules
extends RefCounted
## Regras de refino com joias usadas diretamente sobre um item (data/refine.json).
## Lógica pura: o servidor chama apply_jewel() e aplica o resultado; os testes
## simulam milhares de tentativas para conferir as chances.
##
## Resultado: {result: "invalid"|"success"|"fail", reason: String, level: int, extra: int}

const INVALID := "invalid"
const SUCCESS := "success"
const FAIL := "fail"


## Chance de sucesso de uma joia sobre o item (0 se não se aplica).
static func jewel_chance(role: String, item: Dictionary, catalog: ItemCatalog, cfg: Dictionary) -> float:
	if validate(role, item, catalog, cfg) != "":
		return 0.0
	var rule: Dictionary = cfg.get(role, {})
	var chance := float(rule.get("chance", 0.0))
	if bool(item.get("luck", false)):
		chance += float(rule.get("luck_bonus", 0.0))
	return clampf(chance, 0.0, 1.0)


## "" se a joia pode ser usada no item; senão o motivo.
static func validate(role: String, item: Dictionary, catalog: ItemCatalog, cfg: Dictionary) -> String:
	if not catalog.is_equipment(item):
		return "Joias só funcionam em equipamentos."
	var level := int(item.get("level", 0))
	match role:
		"bless", "soul":
			var max_level := int(cfg[role]["max_level"])
			if level >= max_level:
				return "Este item já passou do limite desta joia (+%d). Use a Forja do Vórtice." % max_level if level >= 9 \
					else "Esta joia só refina até +%d." % max_level
			return ""
		"life":
			if int(item.get("extra", 0)) >= int(catalog.options.get("extra_max", 0)):
				return "A opção extra já está no máximo."
			if str(catalog.base(item).get("main", "")) == "":
				return "Este item não tem opção extra."
			return ""
	return "Esta joia não se usa assim."


static func apply_jewel(role: String, item: Dictionary, catalog: ItemCatalog, cfg: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var level := int(item.get("level", 0))
	var extra := int(item.get("extra", 0))
	var reason := validate(role, item, catalog, cfg)
	if reason != "":
		return {"result": INVALID, "reason": reason, "level": level, "extra": extra}
	var success := rng.randf() < jewel_chance(role, item, catalog, cfg)
	if role == "life":
		return {"result": SUCCESS if success else FAIL, "reason": "", "level": level,
			"extra": extra + 1 if success else 0}
	if success:
		return {"result": SUCCESS, "reason": "", "level": level + 1, "extra": extra}
	return {"result": FAIL, "reason": "", "level": _fail_level(level, cfg[role]), "extra": extra}


static func _fail_level(level: int, rule: Dictionary) -> int:
	for r: Dictionary in rule.get("fail_rules", []):
		if level >= int(r["from"]) and level <= int(r["to"]):
			match str(r["result"]):
				"down1":
					return maxi(0, level - 1)
				"zero":
					return 0
	return level
