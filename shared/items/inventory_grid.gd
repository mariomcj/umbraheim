class_name InventoryGrid
extends RefCounted
## Inventário em grade: cada item ocupa um retângulo de células (ex.: cajado 1x4, manto 2x3).
## Lógica pura (sem rede), usada pelo servidor para validar e pelo cliente para pré-visualizar.

var cols: int
var rows: int
var _cells := PackedInt32Array() # uid ocupando a célula (0 = livre)
var _rects: Dictionary = {} # uid -> Rect2i


func _init(columns: int, row_count: int) -> void:
	cols = columns
	rows = row_count
	_cells.resize(cols * rows)
	_cells.fill(0)


func rect_of(uid: int) -> Rect2i:
	return _rects.get(uid, Rect2i(-1, -1, 0, 0))


func has(uid: int) -> bool:
	return _rects.has(uid)


func uid_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows:
		return 0
	return _cells[cell.y * cols + cell.x]


## Cabe em (x, y)? `ignore_uid` permite testar a movimentação do próprio item.
func can_place(x: int, y: int, size: Vector2i, ignore_uid: int = 0) -> bool:
	if x < 0 or y < 0 or x + size.x > cols or y + size.y > rows:
		return false
	for cy in range(y, y + size.y):
		for cx in range(x, x + size.x):
			var u := _cells[cy * cols + cx]
			if u != 0 and u != ignore_uid:
				return false
	return true


func place(uid: int, x: int, y: int, size: Vector2i) -> bool:
	if uid == 0 or _rects.has(uid) or not can_place(x, y, size):
		return false
	_fill(Rect2i(x, y, size.x, size.y), uid)
	_rects[uid] = Rect2i(x, y, size.x, size.y)
	return true


func remove(uid: int) -> bool:
	if not _rects.has(uid):
		return false
	_fill(_rects[uid], 0)
	_rects.erase(uid)
	return true


func move(uid: int, x: int, y: int) -> bool:
	if not _rects.has(uid):
		return false
	var r: Rect2i = _rects[uid]
	if not can_place(x, y, r.size, uid):
		return false
	remove(uid)
	return place(uid, x, y, r.size)


## Primeira posição livre (varre por colunas, como os inventários clássicos). (-1, -1) se não houver.
func find_free(size: Vector2i) -> Vector2i:
	for x in range(0, cols - size.x + 1):
		for y in range(0, rows - size.y + 1):
			if can_place(x, y, size):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Cópia independente (para simular se algo cabe antes de mexer de verdade).
func clone() -> InventoryGrid:
	var g := InventoryGrid.new(cols, rows)
	g._cells = _cells.duplicate()
	g._rects = _rects.duplicate()
	return g


func count() -> int:
	return _rects.size()


func _fill(r: Rect2i, value: int) -> void:
	for cy in range(r.position.y, r.end.y):
		for cx in range(r.position.x, r.end.x):
			_cells[cy * cols + cx] = value
