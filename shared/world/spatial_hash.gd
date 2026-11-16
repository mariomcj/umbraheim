class_name SpatialHash
extends RefCounted
## Grade de células no plano XZ para achar rápido "quem está perto" (interesse por área).
## Remontada a cada tick a partir das posições; a consulta só olha as células que
## o círculo toca, em vez de comparar todo mundo com todo mundo.

var cell_size: float
var _cells: Dictionary = {} # Vector2i -> Array de [valor, posição]


func _init(cell_m: float) -> void:
	cell_size = maxf(1.0, cell_m)


func clear() -> void:
	_cells.clear()


func insert(value: Variant, pos: Vector2) -> void:
	var c := _cell(pos)
	if not _cells.has(c):
		_cells[c] = []
	(_cells[c] as Array).append([value, pos])


## Valores a até `radius` de `center`.
func query(center: Vector2, radius: float) -> Array:
	var out: Array = []
	var lo := _cell(center - Vector2(radius, radius))
	var hi := _cell(center + Vector2(radius, radius))
	var r2 := radius * radius
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			for entry: Array in _cells.get(Vector2i(cx, cy), []):
				if (entry[1] as Vector2).distance_squared_to(center) <= r2:
					out.append(entry[0])
	return out


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.y / cell_size))
