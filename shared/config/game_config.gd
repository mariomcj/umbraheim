extends Node
## Autoload: carrega as configurações de res://data/config/*.json.
## Regra do projeto: nenhum valor de ajuste/balanceamento fica no código —
## os scripts leem tudo daqui (GameConfig.get_f("movement", "player_speed_mps")).

const CONFIG_DIR := "res://data/config/"
const SECTIONS: PackedStringArray = ["network", "movement", "camera", "input", "journal", "ui", "vfx", "server", "models", "audio", "ambience", "login_scene"]
const REGIONS_DIR := "res://data/regions/"
const SYMBOLS_PATH := "res://data/journal/symbols.json"

var _data: Dictionary = {}
var _regions: Dictionary = {} # id -> Dictionary (cache)
var _symbols: Dictionary = {}
var _tables: Dictionary = {} # caminho relativo -> Dictionary (cache)


## Tabela de jogo em res://data/<name>.json (ex.: "spells", "monsters", "classes/feiticeiro").
## A chave "_doc" (documentação) é removida.
func table(name: String) -> Dictionary:
	if not _tables.has(name):
		var t := ConfigLoader.load_json("res://data/%s.json" % name)
		t.erase("_doc")
		_tables[name] = t
	return _tables[name]


## Cor [r, g, b] de um JSON.
static func color_of(values: Variant, fallback: Color = Color.WHITE) -> Color:
	if values is Array and (values as Array).size() >= 3:
		return Color(float(values[0]), float(values[1]), float(values[2]))
	return fallback


## Dados de uma região (data/regions/<id>.json), com cache.
func region(region_id: String) -> Dictionary:
	if not _regions.has(region_id):
		_regions[region_id] = ConfigLoader.load_json(REGIONS_DIR + region_id + ".json")
	return _regions[region_id]


## Símbolos do diário: { nome: Array[traço] }, traço = Array de [x, y] em [-1, 1].
func journal_symbols() -> Dictionary:
	if _symbols.is_empty():
		_symbols = ConfigLoader.load_json(SYMBOLS_PATH)
		_symbols.erase("_doc")
	return _symbols


func _enter_tree() -> void:
	for section_name in SECTIONS:
		_data[section_name] = ConfigLoader.load_json(CONFIG_DIR + section_name + ".json")
	InputSetup.register(section("input"))


func section(section_name: String) -> Dictionary:
	if not _data.has(section_name):
		push_error("GameConfig: seção desconhecida '%s'" % section_name)
		return {}
	return _data[section_name]


func get_value(section_name: String, key: String) -> Variant:
	var values := section(section_name)
	if not values.has(key):
		push_error("GameConfig: chave ausente '%s.%s'" % [section_name, key])
		return null
	return values[key]


func get_f(section_name: String, key: String) -> float:
	var v: Variant = get_value(section_name, key)
	return float(v) if v != null else 0.0


func get_i(section_name: String, key: String) -> int:
	var v: Variant = get_value(section_name, key)
	return int(v) if v != null else 0


func get_s(section_name: String, key: String) -> String:
	var v: Variant = get_value(section_name, key)
	return str(v) if v != null else ""
