class_name SafeZones
extends RefCounted
## Zonas seguras de uma região (cidades): retângulos [x0, z0, x1, z1] no plano XZ.
## O servidor usa para bloquear combate; o cliente, para mostrar o aviso na tela.

var _zones: Array[Dictionary] = [] # {id, name, rect: Rect2}


func _init(region: Dictionary) -> void:
	for z: Dictionary in region.get("safe_zones", []):
		var r: Array = z["rect"]
		var rect := Rect2(Vector2(float(r[0]), float(r[1])), Vector2(float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))).abs()
		_zones.append({"id": str(z.get("id", "")), "name": str(z.get("name", "")), "rect": rect})


func contains(pos: Vector2) -> bool:
	return not zone_at(pos).is_empty()


## Zona que contém o ponto, ou {}.
func zone_at(pos: Vector2) -> Dictionary:
	for z in _zones:
		if (z["rect"] as Rect2).has_point(pos):
			return z
	return {}
