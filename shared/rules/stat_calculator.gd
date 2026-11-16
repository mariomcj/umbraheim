class_name StatCalculator
extends RefCounted
## Atributos derivados (vida, mana, dano mágico, defesa...) a partir de fórmulas
## escritas nos dados da classe (data/classes/<id>.json -> "derived").
## As fórmulas são expressões da Godot (Expression) com as variáveis:
## level, str, agi, vit, ene.

const STATS: PackedStringArray = ["str", "agi", "vit", "ene"]
## "str" é também uma função da Expression; nas fórmulas ele vira "strength" antes de compilar.
const INPUTS: PackedStringArray = ["level", "strength", "agi", "vit", "ene"]

var _expressions: Dictionary = {} # nome -> Expression
var errors: PackedStringArray = []


func _init(formulas: Dictionary) -> void:
	for key: String in formulas:
		var e := Expression.new()
		var err := e.parse(_rename_str(str(formulas[key])), INPUTS)
		if err != OK:
			errors.append("%s: %s" % [key, e.get_error_text()])
			push_error("StatCalculator: fórmula inválida '%s': %s" % [key, e.get_error_text()])
			continue
		_expressions[key] = e


func compute(level: int, stats: Dictionary) -> Dictionary:
	var inputs := [float(level)]
	for s in STATS:
		inputs.append(float(stats.get(s, 0)))
	var out := {}
	for key: String in _expressions:
		var e: Expression = _expressions[key]
		var v: Variant = e.execute(inputs, null, false)
		if e.has_execute_failed() or not (v is float or v is int):
			push_error("StatCalculator: falha ao calcular '%s'" % key)
			v = 0.0
		out[key] = float(v)
	return out


static func _rename_str(formula: String) -> String:
	var re := RegEx.create_from_string("\\bstr\\b(?!\\s*\\()")
	return re.sub(formula, "strength", true)
