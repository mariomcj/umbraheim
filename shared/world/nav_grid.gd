class_name NavGrid
extends RefCounted
## Grade de navegação 2D (plano XZ) usada pelo servidor para pathfinding de jogadores
## e monstros. A* (AStarGrid2D) + "puxar o barbante" (remove vértices desnecessários
## com teste de linha de visão). Bloqueios vêm dos obstáculos da cena da região.

var cell: float = 0.5
var half: float = 40.0
var size: int = 0
var _astar := AStarGrid2D.new()


func build(half_extent: float, cell_size: float, blockers: Array[Rect2], inflate: float) -> void:
	half = half_extent
	cell = cell_size
	size = ceili(half * 2.0 / cell)
	_astar.region = Rect2i(0, 0, size, size)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for r in blockers:
		var g := r.grow(inflate)
		var c0 := to_cell(g.position)
		var c1 := to_cell(g.end)
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				# marca a célula se o centro dela cai no retângulo inflado
				if g.has_point(to_world(Vector2i(x, y))):
					_astar.set_point_solid(Vector2i(x, y), true)


## Marca (ou libera) as células de um retângulo, com a mesma regra do build (bloqueios que abrem).
func set_rect_solid(r: Rect2, solid: bool, inflate: float) -> void:
	var g := r.grow(inflate)
	var c0 := to_cell(g.position)
	var c1 := to_cell(g.end)
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			if g.has_point(to_world(Vector2i(x, y))):
				_astar.set_point_solid(Vector2i(x, y), solid)


func to_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x + half) / cell), 0, size - 1), clampi(floori((p.y + half) / cell), 0, size - 1))


func to_world(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * cell - half, (c.y + 0.5) * cell - half)


func in_bounds(p: Vector2) -> bool:
	return absf(p.x) < half and absf(p.y) < half


func is_walkable(p: Vector2) -> bool:
	return in_bounds(p) and not _astar.is_point_solid(to_cell(p))


func solid_count() -> int:
	var n := 0
	for x in size:
		for y in size:
			if _astar.is_point_solid(Vector2i(x, y)):
				n += 1
	return n


## Célula andável mais próxima (busca em anéis).
func nearest_walkable(c: Vector2i, max_ring: int = 12) -> Vector2i:
	if not _astar.is_point_solid(c):
		return c
	for ring in range(1, max_ring + 1):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				var n := c + Vector2i(dx, dy)
				if _astar.is_in_boundsv(n) and not _astar.is_point_solid(n):
					return n
	return c


func nearest_walkable_point(p: Vector2) -> Vector2:
	if is_walkable(p):
		return p
	return to_world(nearest_walkable(to_cell(p)))


## Caminho de `from` até `to` (inclui `from` como primeiro ponto). Vazio se impossível.
## Se o destino estiver bloqueado, vai até a célula livre mais próxima.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var goal := to if is_walkable(to) else nearest_walkable_point(to)
	if has_line_of_sight(from, goal):
		return PackedVector2Array([from, goal])
	var a := nearest_walkable(to_cell(from))
	var b := nearest_walkable(to_cell(goal))
	var ids := _astar.get_id_path(a, b, true)
	if ids.is_empty():
		return PackedVector2Array()
	var pts := PackedVector2Array([from])
	for i in range(1, ids.size()):
		pts.append(to_world(ids[i]))
	if ids[ids.size() - 1] == b:
		pts[pts.size() - 1] = goal
	return smooth(pts)


## Remove vértices intermediários quando há linha de visão direta.
func smooth(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	var i := 0
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not has_line_of_sight(pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	return out


func has_line_of_sight(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	var steps := maxi(1, ceili(d / (cell * 0.5)))
	for k in range(1, steps + 1):
		if not is_walkable(a.lerp(b, float(k) / steps)):
			return false
	return true


## Movimento livre (WASD) com deslize nas paredes.
func slide(from: Vector2, delta: Vector2) -> Vector2:
	if is_walkable(from + delta):
		return from + delta
	if is_walkable(from + Vector2(delta.x, 0.0)):
		return from + Vector2(delta.x, 0.0)
	if is_walkable(from + Vector2(0.0, delta.y)):
		return from + Vector2(0.0, delta.y)
	return from
