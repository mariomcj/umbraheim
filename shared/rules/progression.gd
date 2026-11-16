class_name Progression
extends RefCounted
## Tabela de XP e XP por monstro, a partir de data/progression.json.

var max_level: int
var _xp_to_next := Expression.new()
var _monster_xp := Expression.new()


func _init(data: Dictionary) -> void:
	max_level = int(data.get("max_level", 1))
	if _xp_to_next.parse(str(data.get("xp_to_next", "0")), ["level"]) != OK:
		push_error("Progression: xp_to_next inválida: %s" % _xp_to_next.get_error_text())
	if _monster_xp.parse(str(data.get("monster_xp", "0")), ["mlevel"]) != OK:
		push_error("Progression: monster_xp inválida: %s" % _monster_xp.get_error_text())


## XP necessária para sair de `level` e ir ao próximo. 0 no nível máximo.
func xp_to_next(level: int) -> int:
	if level >= max_level:
		return 0
	return maxi(1, int(_xp_to_next.execute([level])))


func monster_xp(monster_level: int) -> int:
	return maxi(0, int(_monster_xp.execute([monster_level])))


## Aplica XP: retorna [novo_nivel, xp_restante, niveis_ganhos].
func apply_xp(level: int, xp: int, gained: int) -> Array[int]:
	var lv := level
	var total := xp + gained
	var ups := 0
	while lv < max_level and total >= xp_to_next(lv):
		total -= xp_to_next(lv)
		lv += 1
		ups += 1
	if lv >= max_level:
		total = 0
	return [lv, total, ups]
