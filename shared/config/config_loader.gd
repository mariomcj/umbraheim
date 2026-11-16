class_name ConfigLoader
extends RefCounted
## Leitura de arquivos JSON de configuração/balanceamento.
## Separado do autoload GameConfig para poder ser usado em testes e ferramentas.


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ConfigLoader: arquivo não encontrado: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("ConfigLoader: JSON inválido em %s (linha %d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not (json.data is Dictionary):
		push_error("ConfigLoader: raiz de %s precisa ser um objeto" % path)
		return {}
	return json.data
