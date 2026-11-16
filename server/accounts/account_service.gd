class_name AccountService
extends RefCounted
## Login, criação de conta e de personagem, e entrada no mundo.
## Cada conexão passa por: hello -> login (ou criar conta) -> escolher/criar personagem -> mundo.
## O hash da senha (PBKDF2) roda no WorkerThreadPool para não travar o tick.
## Tudo de configuração vem de data/config/server.json.

const FAIL_MESSAGE := "Conta ou senha incorretas."

class Session:
	var peer_id: int
	var account_id: int = 0
	var account_name: String = ""
	var failures: int = 0
	var busy: bool = false # hash em andamento
	var in_game: bool = false
	var since: float = 0.0


var server: GameServer
var repo: GameRepository
var sessions: Dictionary = {} # peer_id -> Session
var _iterations: int
var _account_regex := RegEx.new()
var _name_regex := RegEx.new()


func _init(game_server: GameServer, repository: GameRepository) -> void:
	server = game_server
	repo = repository
	_iterations = GameConfig.get_i("server", "password_iterations")
	_account_regex.compile(GameConfig.get_s("server", "account_name_pattern"))
	_name_regex.compile("^[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ0-9]*$")


func on_hello(peer_id: int) -> void:
	var s := Session.new()
	s.peer_id = peer_id
	s.since = server.now
	sessions[peer_id] = s


func on_disconnect(peer_id: int) -> void:
	sessions.erase(peer_id)


## Expulsa quem ficou tempo demais na tela de login.
func update() -> void:
	var timeout := GameConfig.get_f("server", "login_timeout_s")
	for s: Session in sessions.values():
		if not s.in_game and server.now - s.since > timeout:
			print("[server] peer %d expulso: tempo de login esgotado" % s.peer_id)
			sessions.erase(s.peer_id)
			server.kick_with_reason(s.peer_id, "Tempo de login esgotado.")


# ---------------------------------------------------------------- login

func login(peer_id: int, account: String, password: String, create: bool) -> void:
	var s: Session = sessions.get(peer_id)
	if s == null or s.busy or s.in_game or s.account_id != 0:
		return
	account = account.strip_edges().to_lower()
	if _account_regex.search(account) == null:
		_reply(peer_id, false, "Nome de conta inválido: 3 a 20 letras minúsculas, números ou _.")
		return
	if password.length() < GameConfig.get_i("server", "password_min_length") or password.length() > 128:
		_reply(peer_id, false, "A senha precisa ter pelo menos %d caracteres." % GameConfig.get_i("server", "password_min_length"))
		return
	var acc := repo.find_account(account)
	if create and not acc.is_empty():
		_reply(peer_id, false, "Esta conta já existe.")
		return
	# sem conta: calcula um hash mesmo assim, para o tempo de resposta não revelar se a conta existe
	var salt := PasswordHasher.new_salt() if acc.is_empty() else str(acc["salt"]).hex_decode()
	var iterations := _iterations if acc.is_empty() else int(acc["iterations"])
	s.busy = true
	var done := _on_hashed.bind(peer_id, account, salt.hex_encode(), iterations, create, acc)
	WorkerThreadPool.add_task(func() -> void:
		done.call_deferred(PasswordHasher.hash_password(password, salt, iterations)))


func _on_hashed(hash_hex: String, peer_id: int, account: String, salt_hex: String, iterations: int, create: bool, acc: Dictionary) -> void:
	var s: Session = sessions.get(peer_id)
	if s == null:
		return # desconectou enquanto calculava
	s.busy = false
	var account_id := 0
	if create:
		account_id = repo.create_account(account, salt_hex, hash_hex, iterations)
		if account_id == 0:
			_reply(peer_id, false, "Esta conta já existe.")
			return
		print("[server] conta criada: %s (#%d)" % [account, account_id])
	elif not acc.is_empty() and PasswordHasher.equals(hash_hex, str(acc["hash"])):
		account_id = int(acc["id"])
	else:
		s.failures += 1
		print("[server] login falhou: %s (tentativa %d, peer %d)" % [account, s.failures, peer_id])
		_reply(peer_id, false, FAIL_MESSAGE)
		if s.failures >= GameConfig.get_i("server", "login_max_failures"):
			sessions.erase(peer_id)
			server.kick_with_reason(peer_id, "Tentativas demais. Conecte de novo para tentar outra vez.")
		return
	# a mesma conta em outra conexão: a sessão antiga é salva e derrubada
	for other: Session in sessions.values():
		if other != s and other.account_id == account_id:
			print("[server] conta %s entrou de novo; derrubando a conexão %d" % [account, other.peer_id])
			server.logout_player(other.peer_id)
			sessions.erase(other.peer_id)
			server.kick_with_reason(other.peer_id, "Sua conta entrou em outro lugar.")
	s.account_id = account_id
	s.account_name = account
	repo.touch_login(account_id)
	_reply(peer_id, true, "")


# ---------------------------------------------------------------- personagens

func create_character(peer_id: int, character_name: String, class_id: String) -> void:
	var s: Session = sessions.get(peer_id)
	if s == null or s.account_id == 0 or s.in_game:
		return
	character_name = character_name.strip_edges()
	var min_len := GameConfig.get_i("server", "character_name_min")
	var max_len := GameConfig.get_i("server", "character_name_max")
	if character_name.length() < min_len or character_name.length() > max_len or _name_regex.search(character_name) == null:
		_reply(peer_id, true, "Nome inválido: %d a %d letras ou números, começando com letra." % [min_len, max_len])
		return
	if repo.list_characters(s.account_id).size() >= GameConfig.get_i("server", "max_characters_per_account"):
		_reply(peer_id, true, "Limite de %d personagens por conta." % GameConfig.get_i("server", "max_characters_per_account"))
		return
	if repo.character_name_taken(character_name):
		_reply(peer_id, true, "Já existe um personagem com esse nome.")
		return
	if not server.classes.has(class_id):
		_reply(peer_id, true, "Classe desconhecida.")
		return
	var record := server.new_character_record(s.account_id, character_name, class_id)
	if repo.create_character(s.account_id, record) == 0:
		_reply(peer_id, true, "Não foi possível criar o personagem.")
		return
	print("[server] personagem criado: %s (conta %s)" % [character_name, s.account_name])
	_reply(peer_id, true, "")


func enter_world(peer_id: int, character_id: int) -> void:
	var s: Session = sessions.get(peer_id)
	if s == null or s.account_id == 0 or s.in_game:
		return
	var owned := false
	for c: Dictionary in repo.list_characters(s.account_id):
		owned = owned or int(c["id"]) == character_id
	if not owned:
		_reply(peer_id, true, "Personagem não encontrado.")
		return
	var record := repo.load_character(character_id)
	if record.is_empty():
		_reply(peer_id, true, "Não foi possível carregar o personagem.")
		return
	s.in_game = true
	server.spawn_player(peer_id, record)


func account_of(peer_id: int) -> int:
	var s: Session = sessions.get(peer_id)
	return s.account_id if s != null else 0


func _reply(peer_id: int, ok: bool, message: String) -> void:
	var list: Array = []
	var s: Session = sessions.get(peer_id)
	if ok and s != null and s.account_id != 0:
		for c: Dictionary in repo.list_characters(s.account_id):
			list.append([int(c["id"]), str(c["name"]), str(c["class_id"]), int(c["level"]), int(c.get("evolution", 0)), int(c.get("resets", 0))])
	Net.send_to(peer_id, &"rpc_login_result", [ok, message, list])
