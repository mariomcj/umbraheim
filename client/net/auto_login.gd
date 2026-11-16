class_name AutoLogin
extends Node
## Login sem tela: entra na conta (criando, se não existir), escolhe o personagem pelo
## nome (criando, se não existir) e entra no mundo. Usado pelos bots, pelos argumentos
## de debug (--login, --quick-login) e pela reconexão automática.

signal failed(message: String)

var account: String
var password: String
var character_name: String
var class_id: String = ""
var _tried_create_account: bool = false
var _tried_create_character: bool = false
var _entering: bool = false


static func random_suffix() -> String:
	return str(randi() % 1000000).pad_zeros(6)


## new_class: classe do personagem se ele precisar ser criado (vazio = a padrão).
func start(acc: String, pw: String, char_name: String, new_class: String = "") -> void:
	account = acc
	password = pw
	character_name = char_name
	class_id = new_class if new_class != "" else str(GameConfig.table("classes/index")["default"])
	_tried_create_account = false
	_tried_create_character = false
	_entering = false
	if not Net.login_result_received.is_connected(_on_result):
		Net.login_result_received.connect(_on_result)
	Net.send_login.call_deferred(account, password, false) # depois do hello


func _on_result(ok: bool, message: String, characters: Array) -> void:
	if _entering:
		return
	if not ok:
		if not _tried_create_account and message == "Conta ou senha incorretas.":
			_tried_create_account = true # talvez a conta ainda não exista
			Net.send_login(account, password, true)
			return
		failed.emit(message)
		return
	for c: Array in characters:
		if character_name.is_empty() or str(c[1]).to_lower() == character_name.to_lower():
			_entering = true
			Net.send_enter_world(int(c[0]))
			return
	if _tried_create_character:
		failed.emit(message if not message.is_empty() else "Personagem não encontrado.")
		return
	_tried_create_character = true
	Net.send_create_character(character_name, class_id)
