class_name RegionJournal
extends RefCounted
## Diário de UMA região para UM personagem: traços (caminho percorrido) e marcações.
## Os pontos chegam crus (um a cada sample_distance) e são simplificados em blocos
## com Ramer–Douglas–Peucker, para economizar memória, banco e rede.
## Formato exportado (usado na rede e, na Fase 3, no banco):
##   strokes: Array[PackedVector2Array] (coordenadas do mundo x, z)
##   marks:   Array[Array] com [simbolo: String, x: float, z: float, rotulo: String]

var epsilon: float
var chunk_points: int

var _strokes: Array[PackedVector2Array] = [] # partes já simplificadas
var _pending: PackedVector2Array = PackedVector2Array() # cauda crua do último traço
var _marks: Array[Array] = []
var _discovered: Dictionary = {} # id -> true


func _init(simplify_epsilon: float, simplify_chunk_points: int) -> void:
	epsilon = simplify_epsilon
	chunk_points = maxi(3, simplify_chunk_points)


func add_point(point: Vector2, new_stroke: bool) -> void:
	if new_stroke or _strokes.is_empty():
		_flush_pending()
		_strokes.append(PackedVector2Array())
		_pending = PackedVector2Array([point])
		return
	_pending.append(point)
	if _pending.size() >= chunk_points:
		_flush_pending()


func add_mark(symbol: String, point: Vector2, label: String) -> void:
	_marks.append([symbol, point.x, point.y, label])


func is_discovered(id: String) -> bool:
	return _discovered.has(id)


func set_discovered(id: String) -> void:
	_discovered[id] = true


func export_strokes() -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for s in _strokes:
		out.append(s.duplicate())
	if not out.is_empty() and _pending.size() > 0:
		out[out.size() - 1] = _with_simplified(out[out.size() - 1], _pending)
	return out


func export_marks() -> Array[Array]:
	return _marks.duplicate(true)


## Formato para o banco (JSON): {strokes: [[x0, z0, x1, z1, ...], ...], marks: [...], discovered: [ids]}.
## Coordenadas arredondadas a 1 cm.
func to_dict() -> Dictionary:
	var strokes: Array = []
	for s in export_strokes():
		var flat: Array = []
		for p in s:
			flat.append(snappedf(p.x, 0.01))
			flat.append(snappedf(p.y, 0.01))
		strokes.append(flat)
	return {"strokes": strokes, "marks": export_marks(), "discovered": _discovered.keys()}


func load_dict(d: Dictionary) -> void:
	_strokes.clear()
	_pending = PackedVector2Array()
	for flat: Array in d.get("strokes", []):
		var s := PackedVector2Array()
		for i in range(0, flat.size() - 1, 2):
			s.append(Vector2(float(flat[i]), float(flat[i + 1])))
		_strokes.append(s)
	_marks.clear()
	for m: Array in d.get("marks", []):
		_marks.append([str(m[0]), float(m[1]), float(m[2]), str(m[3])])
	_discovered.clear()
	for id: Variant in d.get("discovered", []):
		_discovered[str(id)] = true


func stored_point_count() -> int:
	var total := _pending.size()
	for s in _strokes:
		total += s.size()
	return total


## Simplifica a cauda crua e a anexa ao último traço; o último ponto continua
## na cauda para o próximo bloco emendar sem buraco.
func _flush_pending() -> void:
	if _strokes.is_empty() or _pending.is_empty():
		return
	var last_index := _strokes.size() - 1
	_strokes[last_index] = _with_simplified(_strokes[last_index], _pending)
	_pending = PackedVector2Array([_pending[_pending.size() - 1]])


## Retorna uma cópia de `stroke` com `raw` simplificado anexado (sem duplicar o ponto de emenda).
func _with_simplified(stroke: PackedVector2Array, raw: PackedVector2Array) -> PackedVector2Array:
	var result := stroke.duplicate()
	var simplified := PolylineSimplifier.simplify(raw, epsilon)
	var start := 1 if not result.is_empty() and result[result.size() - 1].is_equal_approx(simplified[0]) else 0
	for i in range(start, simplified.size()):
		result.append(simplified[i])
	return result
