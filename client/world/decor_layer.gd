class_name DecorLayer
extends Node3D
## Decoração visual da região (docs/design/PROPOSTA_AMBIENTACAO.md, parte 4): mato, pedrinhas, cogumelos,
## entulho e a moldura de silhuetas nas bordas. Só no cliente, sem colisão, com semente própria:
## não mexe na semente do RegionScenery nem na grade de navegação (regra da Fase 4).
## Uma MultiMeshInstance3D por malha de modelo (uma chamada de desenho para todas as cópias).
## Dados em ambience.json -> regions.<id>.decor (formato em _decor_doc).

const OBSTACLE_MARGIN_M := 0.35

var _obstacles: Array[Rect2] = []
var _clear_zones: Array[Vector3] = []
var _clear_paths: Array[Vector4] = []
var _path_half: float = 2.2
var _safe: Array[Rect2] = []
static var _mesh_cache: Dictionary = {} # caminho -> [[Mesh, Transform3D], ...] e AABB


## Monta a camada sobre a cena da região. mult = multiplicador de quantidade do perfil de qualidade.
static func build(world: Node3D, region_id: String, cfg: Dictionary, mult: float) -> DecorLayer:
	var layer := DecorLayer.new()
	layer.name = "Decor"
	world.add_child(layer)
	layer._collect_blockers(world, region_id)
	var dirs: Dictionary = GameConfig.get_value("ambience", "decor_dirs")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 1))
	var half := GameConfig.get_f("movement", "world_half_extent_m")
	for entry: Dictionary in cfg.get("layers", []):
		var count := int(round(float(entry.get("count", 0)) * mult))
		if count > 0:
			layer._scatter(entry, count, rng, half, dirs)
	return layer


func _collect_blockers(world: Node3D, region_id: String) -> void:
	for n in get_tree().get_nodes_in_group("obstacle"):
		if not world.is_ancestor_of(n):
			continue
		var meshes: Array = [n] if n is MeshInstance3D else []
		meshes.append_array(n.find_children("*", "MeshInstance3D", true, false))
		for m: MeshInstance3D in meshes:
			var a := m.global_transform * m.get_aabb()
			_obstacles.append(Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(OBSTACLE_MARGIN_M))
	for s in world.find_children("*", "RegionScenery", true, false):
		var rs := s as RegionScenery
		_clear_zones.append_array(rs.clear_zones)
		_clear_paths.append_array(rs.clear_paths)
		_path_half = rs.path_half_width_m
	for z: Dictionary in GameConfig.region(region_id).get("safe_zones", []):
		var r: Array = z["rect"]
		_safe.append(Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1])))


## Ponto livre para a peça: fora de obstáculos e, com "clear", fora de trilhas, áreas livres e zonas seguras.
func _free(p: Vector2, clear: bool) -> bool:
	for r in _obstacles:
		if r.has_point(p):
			return false
	if not clear:
		return true
	for r in _safe:
		if r.has_point(p):
			return false
	for z in _clear_zones:
		if p.distance_to(Vector2(z.x, z.y)) < z.z:
			return false
	for seg in _clear_paths:
		if Geometry2D.get_closest_point_to_segment(p, Vector2(seg.x, seg.y), Vector2(seg.z, seg.w)).distance_to(p) < _path_half:
			return false
	return true


## Sorteia a posição conforme a zona: "inside" (área andável), "ring" (faixa da borda) ou "rect" [x1, z1, x2, z2].
func _point(entry: Dictionary, rng: RandomNumberGenerator, half: float) -> Vector2:
	match str(entry.get("zone", "inside")):
		"ring":
			var band: Array = entry.get("ring_m", [half + 1.0, half + 7.0])
			var d := rng.randf_range(float(band[0]), float(band[1]))
			var t := rng.randf_range(-float(band[1]), float(band[1]))
			match rng.randi() % 4:
				0: return Vector2(t, -d)
				1: return Vector2(t, d)
				2: return Vector2(-d, t)
				_: return Vector2(d, t)
		"rect":
			var r: Array = entry["rect"]
			return Vector2(rng.randf_range(float(r[0]), float(r[2])), rng.randf_range(float(r[1]), float(r[3])))
	var m := half - float(entry.get("margin_m", 1.0))
	return Vector2(rng.randf_range(-m, m), rng.randf_range(-m, m))


func _scatter(entry: Dictionary, count: int, rng: RandomNumberGenerator, half: float, dirs: Dictionary) -> void:
	var models: Array = entry.get("models", [])
	if models.is_empty():
		return
	var per_model: Dictionary = {} # modelo -> [Transform3D]
	var sc: Array = entry.get("scale", [1.0, 1.0])
	var clear := bool(entry.get("clear", true))
	var made := 0
	var tries := 0
	while made < count and tries < count * 20:
		tries += 1
		var p := _point(entry, rng, half)
		var model := str(models[rng.randi() % models.size()])
		var s := rng.randf_range(float(sc[0]), float(sc[1]))
		var yaw := rng.randf() * TAU
		var tilt := rng.randf_range(-1.0, 1.0) * deg_to_rad(float(entry.get("tilt_deg", 0.0)))
		if not _free(p, clear):
			continue
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt) * Basis.from_scale(Vector3.ONE * s)
		(per_model.get_or_add(model, []) as Array).append(Transform3D(basis, Vector3(p.x, -float(entry.get("sink_m", 0.0)) * s, p.y)))
		made += 1
	var tint := Color.html(str(entry.get("tint", "#FFFFFF")))
	var shadow := bool(entry.get("shadow", false))
	for model: String in per_model:
		_add_instances(_resolve(model, dirs), per_model[model], tint, shadow, float(entry.get("visibility_m", 0.0)))


static func _resolve(model: String, dirs: Dictionary) -> String:
	var cut := model.find("/")
	return str(dirs.get(model.left(cut), "")) + model.substr(cut + 1) + ".gltf"


func _add_instances(path: String, xforms: Array, tint: Color, shadow: bool, visibility_m: float) -> void:
	for part: Array in _meshes(path):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _tinted(part[0] as Mesh, tint)
		mm.instance_count = xforms.size()
		var local: Transform3D = part[1]
		for i in xforms.size():
			mm.set_instance_transform(i, (xforms[i] as Transform3D) * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if visibility_m > 0.0:
			mmi.visibility_range_end = visibility_m
		add_child(mmi)


## Cópia da malha com os materiais multiplicados pela tinta da região (secos, frios, queimados).
static func _tinted(mesh: Mesh, tint: Color) -> Mesh:
	if tint == Color.WHITE:
		return mesh
	var copy := mesh.duplicate() as Mesh
	for i in copy.get_surface_count():
		var src := copy.surface_get_material(i)
		if src is BaseMaterial3D:
			var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
			m.albedo_color = m.albedo_color * tint
			copy.surface_set_material(i, m)
	return copy


static func _meshes(path: String) -> Array:
	if _mesh_cache.has(path):
		return _mesh_cache[path]
	var out: Array = []
	if ResourceLoader.exists(path):
		var probe: Node = (load(path) as PackedScene).instantiate()
		for n in probe.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var xf := Transform3D.IDENTITY
			var cur: Node = mi
			while cur != probe and cur is Node3D:
				xf = (cur as Node3D).transform * xf
				cur = cur.get_parent()
			out.append([mi.mesh, xf])
		probe.free()
	else:
		push_warning("decor: modelo não encontrado: %s" % path)
	_mesh_cache[path] = out
	return out
