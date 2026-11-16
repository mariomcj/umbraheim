class_name ServerEntity
extends RefCounted
## Base das entidades simuladas pelo servidor (jogadores e monstros).

var id: int
var kind: int
var type_index: int = 0
var position: Vector2
var yaw: float = 0.0
var hp: float = 1.0
var hp_max: float = 1.0
var alive: bool = true
var path := PackedVector2Array()
var path_index: int = 0


func hp_frac() -> float:
	return clampf(hp / hp_max, 0.0, 1.0) if hp_max > 0.0 and alive else 0.0


func meta() -> int:
	return Protocol.make_meta(kind, type_index)


## O primeiro ponto do caminho é a posição atual (vem do NavGrid.find_path).
func set_path(p: PackedVector2Array) -> void:
	path = p
	path_index = 1 if p.size() > 1 else p.size()


func has_path() -> bool:
	return path_index < path.size()


func stop() -> void:
	path = PackedVector2Array()
	path_index = 0


func face(point: Vector2) -> void:
	var to := point - position
	if to.length_squared() > 0.0001:
		yaw = atan2(to.x, to.y)


func follow_path(dt: float, speed: float) -> void:
	var step := speed * dt
	while step > 0.0 and has_path():
		var target := path[path_index]
		var to := target - position
		var d := to.length()
		if d > 0.0001:
			yaw = atan2(to.x, to.y)
		if d <= step:
			position = target
			path_index += 1
			step -= d
		else:
			position += to / d * step
			step = 0.0
