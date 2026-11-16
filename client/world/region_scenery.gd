class_name RegionScenery
extends Node3D
## Cenário procedural determinístico de uma região (árvores mortas, pedras, gelo...).
## A mesma semente gera exatamente o mesmo cenário no servidor (WorldBuilder chama
## populate() antes de montar a grade de navegação) e no cliente (_ready), então
## colisão e visual nunca divergem. Só o "tronco" de cada peça entra no grupo
## "obstacle"; galhos e enfeites não bloqueiam o caminho.

## Tipos: dead_tree, rock, ice_spike, ice_block, pine.
@export var seed_value: int = 1
@export var props: Dictionary = {"dead_tree": 40, "rock": 20}
@export var area_half_m: float = 34.0
@export var min_spacing_m: float = 2.6
## Áreas livres: Vector3(x, z, raio) — portais, chegada, trilhas.
@export var clear_zones: Array[Vector3] = []
## Trilhas livres: Vector4(x1, z1, x2, z2), com meia largura em path_half_width_m.
@export var clear_paths: Array[Vector4] = []
@export var path_half_width_m: float = 2.2
@export var tint: Color = Color(1, 1, 1, 1)

var _populated: bool = false
var _materials: Dictionary = {}
const ICE_SHADER := preload("res://assets/shaders/ice.gdshader")

## Modelos de verdade (Quaternius, Stylized Nature) por tipo de peça. As peças simples
## continuam existindo como colisão (servidor e predição usam a mesma grade), mas ficam
## invisíveis no cliente. Gelo não tem modelo: fica a peça simples.
const NATURE := "res://assets/models/environment/quaternius_stylized_nature/"
const MODELS := {
	"dead_tree": ["DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4", "DeadTree_5"],
	"pine": ["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"],
	"rock": ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"],
}
static var _model_cache: Dictionary = {} # nome -> [PackedScene, AABB]
var _visuals: bool = true


func _ready() -> void:
	populate()


func populate() -> void:
	if _populated:
		return
	_populated = true
	_visuals = DisplayServer.get_name() != "headless" # servidor e bots: só a colisão
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var placed: Array[Vector2] = []
	var kinds := props.keys()
	kinds.sort()
	for kind: String in kinds:
		var count := int(props[kind])
		var tries := 0
		var made := 0
		while made < count and tries < count * 30:
			tries += 1
			var pos := Vector2(rng.randf_range(-area_half_m, area_half_m), rng.randf_range(-area_half_m, area_half_m))
			if not _is_free(pos, placed):
				continue
			placed.append(pos)
			_make(kind, pos, rng)
			made += 1


func _is_free(pos: Vector2, placed: Array[Vector2]) -> bool:
	for z in clear_zones:
		if pos.distance_to(Vector2(z.x, z.y)) < z.z:
			return false
	for p in clear_paths:
		var a := Vector2(p.x, p.y)
		var b := Vector2(p.z, p.w)
		if pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, a, b)) < path_half_width_m:
			return false
	for q in placed:
		if pos.distance_to(q) < min_spacing_m:
			return false
	return true


func _make(kind: String, pos: Vector2, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.y)
	root.rotation.y = rng.randf() * TAU
	add_child(root)
	match kind:
		"dead_tree":
			var h := rng.randf_range(3.0, 5.0)
			_part(root, _cylinder(0.18, 0.32, h, 6), Vector3(0, h * 0.5, 0), Vector3.ZERO, "bark", true)
			for i in rng.randi_range(2, 3):
				var y := rng.randf_range(h * 0.45, h * 0.85)
				var branch_len := rng.randf_range(0.9, 1.6)
				_part(root, _box(Vector3(0.1, branch_len, 0.1)), Vector3(0, y, 0),
					Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(0.7, 1.2)), "bark", false)
			_model(root, kind, pos, h, "height")
		"pine":
			var h2 := rng.randf_range(3.5, 5.5)
			_part(root, _cylinder(0.12, 0.2, 1.2, 6), Vector3(0, 0.6, 0), Vector3.ZERO, "bark", true)
			_part(root, _cylinder(0.0, 1.1, h2, 7), Vector3(0, 1.0 + h2 * 0.5, 0), Vector3.ZERO, "needles", false)
			_model(root, kind, pos, h2 + 1.0, "height")
		"rock":
			var s := rng.randf_range(0.7, 1.6)
			_part(root, _box(Vector3(s * 1.3, s * 0.8, s)), Vector3(0, s * 0.35, 0),
				Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)), "stone", true)
			_model(root, kind, pos, s * 1.4, "width")
		"ice_spike":
			var h3 := rng.randf_range(1.6, 3.6)
			_part(root, _cylinder(0.0, rng.randf_range(0.3, 0.55), h3, 5), Vector3(0, h3 * 0.5, 0),
				Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15)), "ice", true)
		"ice_block":
			var s2 := rng.randf_range(0.8, 1.8)
			_part(root, _box(Vector3(s2, s2 * 0.7, s2 * 1.2)), Vector3(0, s2 * 0.3, 0),
				Vector3(0, 0, rng.randf_range(-0.15, 0.15)), "ice", true)


## Troca o visual da peça por um modelo (no cliente). A variante sai da posição, sem
## sortear de novo: o gerador continua igual, e o cenário e a colisão não mudam.
func _model(root: Node3D, kind: String, pos: Vector2, size_m: float, axis: String) -> void:
	if not _visuals or not MODELS.has(kind):
		return
	var names: Array = MODELS[kind]
	var model_name := str(names[absi(int(pos.x * 7.0) * 31 + int(pos.y * 7.0) * 17) % names.size()])
	var entry: Array = _load_model(model_name)
	if entry.is_empty():
		return
	var aabb: AABB = entry[1]
	var ref := aabb.size.y if axis == "height" else maxf(aabb.size.x, aabb.size.z)
	var model: Node3D = (entry[0] as PackedScene).instantiate()
	model.set_meta(&"scenery_kind", kind) # AmbienceDirector retinge por tipo (ambience.json -> scenery_tint)
	model.scale = Vector3.ONE * (size_m / maxf(0.01, ref))
	model.position.y = -aabb.position.y * model.scale.y # a base no chão
	root.add_child(model)
	for child in root.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false # fica só como colisão


static func _load_model(model_name: String) -> Array:
	if _model_cache.has(model_name):
		return _model_cache[model_name]
	var path := NATURE + model_name + ".gltf"
	var out: Array = []
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		var probe: Node = scene.instantiate()
		var aabb := AABB()
		var first := true
		for m in probe.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			var a := mi.transform * mi.get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
		probe.free()
		out = [scene, aabb]
	_model_cache[model_name] = out
	return out


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, rot: Vector3, mat: String, blocks: bool) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.rotation = rot
	m.material_override = _material(mat)
	if blocks:
		m.add_to_group("obstacle", true)
	parent.add_child(m)


func _material(kind: String) -> Material:
	if _materials.has(kind):
		return _materials[kind]
	if kind == "ice" and _visuals: # gelo com shader próprio (ambience.json -> materials.ice)
		var ice := ShaderMaterial.new()
		ice.shader = ICE_SHADER
		var cfg: Dictionary = (GameConfig.get_value("ambience", "materials") as Dictionary).get("ice", {})
		for key: String in cfg:
			var v: Variant = cfg[key]
			ice.set_shader_parameter(key, Color.html(v) if v is String else v)
		_materials[kind] = ice
		return ice
	var m := StandardMaterial3D.new()
	match kind:
		"bark":
			m.albedo_color = Color(0.17, 0.13, 0.1) * tint
			m.roughness = 1.0
		"needles":
			m.albedo_color = Color(0.12, 0.17, 0.14) * tint
			m.roughness = 1.0
		"stone":
			m.albedo_color = Color(0.22, 0.22, 0.23) * tint
			m.roughness = 0.95
		"ice":
			m.albedo_color = Color(0.62, 0.78, 0.92)
			m.roughness = 0.15
			m.metallic = 0.1
			m.emission_enabled = true
			m.emission = Color(0.25, 0.45, 0.7)
			m.emission_energy_multiplier = 0.35
	_materials[kind] = m
	return m


static func _cylinder(top: float, bottom: float, h: float, segments: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segments
	c.rings = 1
	return c


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b
