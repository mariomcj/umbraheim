class_name CombatRules
extends RefCounted
## Rolagem de dano (data/combat.json):
##   excelente -> dano máximo * excellent_mult
##   crítico   -> dano máximo
##   normal    -> sorteio entre mínimo e máximo
## dano final = rolagem * mult + bônus - defesa * defense_factor (no mínimo min_damage).


## Retorna Vector2i(dano, tipo) com tipo em Protocol.DMG_*.
## crit_bonus/excellent_bonus somam às chances base (sorte e opções excelentes do equipamento).
static func roll(min_dmg: float, max_dmg: float, mult: float, bonus: float, defense: float,
		cfg: Dictionary, rng: RandomNumberGenerator, crit_bonus: float = 0.0, excellent_bonus: float = 0.0) -> Vector2i:
	var lo := minf(min_dmg, max_dmg)
	var hi := maxf(min_dmg, max_dmg)
	var excellent := float(cfg.get("excellent_chance", 0.0)) + excellent_bonus
	var crit := float(cfg.get("crit_chance", 0.0)) + crit_bonus
	var r := rng.randf()
	var kind := Protocol.DMG_NORMAL
	var base: float
	if r < excellent:
		kind = Protocol.DMG_EXCELLENT
		base = hi * float(cfg.get("excellent_mult", 1.0))
	elif r < excellent + crit:
		kind = Protocol.DMG_CRITICAL
		base = hi
	else:
		base = rng.randf_range(lo, hi)
	var dmg := base * mult + bonus - defense * float(cfg.get("defense_factor", 1.0))
	return Vector2i(maxi(int(cfg.get("min_damage", 1)), roundi(dmg)), kind)
