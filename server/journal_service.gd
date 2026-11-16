class_name JournalService
extends Node
## Servidor: diário de cada personagem (autoritativo).
## Amostra o caminho a partir da posição REAL simulada pelo servidor, descobre marcos
## por proximidade e envia ao dono só o que deve ser desenhado. Como o diário define
## para onde o jogador pode se teletransportar (Fase 4), ele não pode vir do cliente.
## Fase 1: guardado em memória por conexão. Persistência no banco: Fase 3.


class PlayerJournal:
	var region_id: String
	var journals: Dictionary = {} # region_id -> RegionJournal
	var last_sample: Vector2
	var has_sample: bool = false


var _players: Dictionary = {} # peer_id -> PlayerJournal
var _sample_distance: float
var _break_distance: float
var _epsilon: float
var _chunk: int
var _check_interval: int


func _ready() -> void:
	_sample_distance = GameConfig.get_f("journal", "sample_distance_m")
	_break_distance = GameConfig.get_f("journal", "stroke_break_distance_m")
	_epsilon = GameConfig.get_f("journal", "rdp_epsilon_m")
	_chunk = GameConfig.get_i("journal", "simplify_chunk_points")
	_check_interval = GameConfig.get_i("journal", "landmark_check_interval_ticks")


## Diários salvos do personagem, para o banco: {region_id: dict}.
func export_player(peer_id: int) -> Dictionary:
	var out := {}
	var pj: PlayerJournal = _players.get(peer_id)
	if pj != null:
		for region_id: String in pj.journals:
			out[region_id] = (pj.journals[region_id] as RegionJournal).to_dict()
	return out


func player_joined(peer_id: int, region_id: String, position: Vector2, saved: Dictionary = {}) -> void:
	var pj := PlayerJournal.new()
	pj.region_id = region_id
	_players[peer_id] = pj
	for rid: String in saved:
		_journal_for(pj, rid).load_dict(saved[rid])
	_open_sheet(peer_id, pj, region_id, position)


## Trocou de região: a folha da nova região (criada na primeira visita) é enviada
## inteira e o cliente vira a página. A lista de folhas define para onde dá para se
## teletransportar.
func player_changed_region(peer_id: int, region_id: String, position: Vector2) -> void:
	var pj: PlayerJournal = _players.get(peer_id)
	if pj == null:
		return
	pj.region_id = region_id
	pj.has_sample = false
	_open_sheet(peer_id, pj, region_id, position)


func has_sheet(peer_id: int, region_id: String) -> bool:
	var pj: PlayerJournal = _players.get(peer_id)
	return pj != null and pj.journals.has(region_id)


func _open_sheet(peer_id: int, pj: PlayerJournal, region_id: String, position: Vector2) -> void:
	var journal := _journal_for(pj, region_id)
	Net.send_journal_full(peer_id, region_id, journal.export_strokes(), journal.export_marks())
	Net.send_to(peer_id, &"rpc_journal_sheets", [PackedStringArray(pj.journals.keys())])
	if not journal.is_discovered("_entrada"):
		journal.set_discovered("_entrada")
		_add_mark(peer_id, pj, "arrow", position, str(GameConfig.region(region_id).get("entrance_label", "")))
	_sample(peer_id, pj, position, true)


## Marca avulsa na folha atual do jogador (ex.: chefe derrotado).
func mark_here(peer_id: int, symbol: String, position: Vector2, label: String) -> void:
	var pj: PlayerJournal = _players.get(peer_id)
	if pj != null:
		_add_mark(peer_id, pj, symbol, position, label)


## Local da morte vira uma cruz no diário.
func player_died(peer_id: int, position: Vector2) -> void:
	var pj: PlayerJournal = _players.get(peer_id)
	if pj != null:
		_add_mark(peer_id, pj, "cross", position, str(GameConfig.region(pj.region_id).get("death_label", "")))


## Ao renascer, o lápis "levanta" e começa um traço novo no ponto de renascimento.
func player_respawned(peer_id: int, position: Vector2) -> void:
	var pj: PlayerJournal = _players.get(peer_id)
	if pj != null:
		_sample(peer_id, pj, position, true)


func player_left(peer_id: int) -> void:
	_players.erase(peer_id)


func player_moved(peer_id: int, position: Vector2, tick: int) -> void:
	var pj: PlayerJournal = _players.get(peer_id)
	if pj == null:
		return
	if pj.last_sample.distance_to(position) >= _sample_distance:
		_sample(peer_id, pj, position, false)
	if tick % _check_interval == 0:
		_check_landmarks(peer_id, pj, position)


func _sample(peer_id: int, pj: PlayerJournal, position: Vector2, force_new_stroke: bool) -> void:
	var new_stroke := force_new_stroke or not pj.has_sample or pj.last_sample.distance_to(position) > _break_distance
	pj.last_sample = position
	pj.has_sample = true
	_journal_for(pj, pj.region_id).add_point(position, new_stroke)
	Net.send_journal_point(peer_id, pj.region_id, position, new_stroke)


func _check_landmarks(peer_id: int, pj: PlayerJournal, position: Vector2) -> void:
	var journal := _journal_for(pj, pj.region_id)
	for lm: Dictionary in GameConfig.region(pj.region_id).get("landmarks", []):
		var id: String = lm["id"]
		if journal.is_discovered(id):
			continue
		var lm_pos := Vector2(float(lm["pos"][0]), float(lm["pos"][1]))
		if position.distance_to(lm_pos) <= float(lm["radius_m"]):
			journal.set_discovered(id)
			_add_mark(peer_id, pj, str(lm["symbol"]), lm_pos, str(lm["name"]))
			print("[server] jogador %d descobriu '%s'" % [peer_id, lm["name"]])


func _add_mark(peer_id: int, pj: PlayerJournal, symbol: String, position: Vector2, label: String) -> void:
	_journal_for(pj, pj.region_id).add_mark(symbol, position, label)
	Net.send_journal_mark(peer_id, pj.region_id, symbol, position, label)


func _journal_for(pj: PlayerJournal, region_id: String) -> RegionJournal:
	if not pj.journals.has(region_id):
		pj.journals[region_id] = RegionJournal.new(_epsilon, _chunk)
	return pj.journals[region_id]
