class_name LocalPredictor
extends RefCounted
## Predição do próprio movimento (andar com WASD ou clique no chão).
## O cliente roda o MESMO código de movimento do servidor (ServerEntity.follow_path,
## NavGrid.slide e find_path, com a grade montada da mesma cena), então o personagem
## responde na hora em vez de esperar a ida e volta ao servidor.
##
## Reconciliação: o snapshot traz a posição do servidor, que corresponde ao que o
## cliente previu há ~1 RTT. Compara com o histórico daquele momento; se o erro passa
## de prediction_correction_m, desloca a previsão pelo erro (e suaviza na tela);
## se passa de prediction_snap_m (teleporte, renascimento), vai direto para o servidor.
## Ações que o servidor dirige (atacar, pegar item, falar com NPC) não são previstas:
## nelas o personagem volta a seguir a interpolação normal.

var grid: NavGrid
var half_extent: float
var ghost := ServerEntity.new()
var active: bool = false
var speed: float = 5.0
var rtt_ms: float = 100.0
var move_dir := Vector2.ZERO
var correction_m: float
var snap_m: float
var smoothing: float
var corrections: int = 0 # quantas vezes precisou corrigir (debug)
var last_error_m: float = 0.0

var _history: Array[Vector3] = [] # (tempo_ms, x, z)
var _offset := Vector2.ZERO # diferença visual que some aos poucos depois de uma correção


func _init(nav_grid: NavGrid, world_half_extent: float) -> void:
	grid = nav_grid
	half_extent = world_half_extent
	correction_m = GameConfig.get_f("network", "prediction_correction_m")
	snap_m = GameConfig.get_f("network", "prediction_snap_m")
	smoothing = GameConfig.get_f("network", "prediction_smoothing")


func reset(pos: Vector2) -> void:
	ghost.position = pos
	ghost.stop()
	move_dir = Vector2.ZERO
	active = false
	_history.clear()
	_offset = Vector2.ZERO


## Liga a predição partindo da última posição do servidor, mas desenhando a partir de
## onde o personagem está na tela (a diferença some aos poucos, sem salto).
func blend_from(rendered: Vector2) -> void:
	active = true
	_history.clear()
	_offset = rendered - ghost.position


## Intenção WASD (direção já relativa à câmera, no plano XZ).
func on_move_dir(dir: Vector2) -> void:
	move_dir = dir.limit_length(1.0)
	if move_dir != Vector2.ZERO:
		active = true
		ghost.stop()


## Intenção de clique no chão: mesmo caminho que o servidor vai calcular.
func on_move_to(target: Vector2) -> void:
	active = true
	move_dir = Vector2.ZERO
	var t := target.clamp(Vector2(-half_extent, -half_extent), Vector2(half_extent, half_extent))
	ghost.set_path(grid.find_path(ghost.position, t))


## Ação dirigida pelo servidor: para de prever até o próximo movimento.
func suspend() -> void:
	active = false
	move_dir = Vector2.ZERO
	ghost.stop()


func step(dt: float) -> void:
	_offset = _offset.lerp(Vector2.ZERO, 1.0 - exp(-smoothing * dt))
	if not active:
		return
	if move_dir != Vector2.ZERO:
		ghost.position = grid.slide(ghost.position, move_dir * speed * dt)
		ghost.yaw = atan2(move_dir.x, move_dir.y)
	elif ghost.has_path():
		ghost.follow_path(dt, speed)
	_history.append(Vector3(Time.get_ticks_msec(), ghost.position.x, ghost.position.y))
	while _history.size() > 2 and _history[0].x < _history[-1].x - 2000.0:
		_history.remove_at(0)


## Posição autoritativa do servidor (do snapshot) chegando agora.
func reconcile(server_pos: Vector2, now_ms: float, tick_ms: float) -> void:
	if not active:
		ghost.position = server_pos
		_history.clear()
		return
	var past := _predicted_at(now_ms - rtt_ms - tick_ms * 0.5)
	if past == Vector2.INF:
		return
	var err := server_pos - past
	last_error_m = err.length()
	if last_error_m > snap_m:
		_offset = Vector2.ZERO
		ghost.position = server_pos
		ghost.stop()
		_history.clear()
		corrections += 1
	elif last_error_m > correction_m:
		ghost.position += err
		for i in _history.size():
			_history[i] = Vector3(_history[i].x, _history[i].y + err.x, _history[i].z + err.y)
		_offset -= err # na tela, o personagem desliza até o lugar certo em vez de pular
		corrections += 1


func render_position() -> Vector2:
	return ghost.position + _offset


func _predicted_at(t: float) -> Vector2:
	if _history.is_empty():
		return Vector2.INF
	if t <= _history[0].x:
		return Vector2(_history[0].y, _history[0].z)
	for i in range(_history.size() - 1, -1, -1):
		if _history[i].x <= t:
			if i == _history.size() - 1:
				return Vector2(_history[i].y, _history[i].z)
			var a := _history[i]
			var b := _history[i + 1]
			var k := clampf((t - a.x) / maxf(1.0, b.x - a.x), 0.0, 1.0)
			return Vector2(lerpf(a.y, b.y, k), lerpf(a.z, b.z, k))
	return Vector2(_history[0].y, _history[0].z)
