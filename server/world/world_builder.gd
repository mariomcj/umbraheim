class_name WorldBuilder
extends RefCounted
## Monta a grade de navegação do servidor a partir da MESMA cena que o cliente
## renderiza: todo MeshInstance3D no grupo "obstacle" vira um bloqueio (pegada XZ
## da sua AABB). Assim cenário e colisão nunca divergem.


static func build_nav_grid(region: Dictionary, half_extent: float) -> NavGrid:
	var blockers: Array[Rect2] = []
	var scene: PackedScene = load(str(region["scene"]))
	var root := scene.instantiate()
	# cenário procedural (RegionScenery): gera as peças antes de procurar os obstáculos
	for node in root.find_children("*", "", true, false):
		if node.has_method("populate"):
			node.call("populate")
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if not _in_obstacle_group(mesh_node, root) or mesh_node.mesh == null:
			continue
		var box: AABB = _global_transform(mesh_node, root) * mesh_node.mesh.get_aabb()
		blockers.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
	root.free()
	var grid := NavGrid.new()
	grid.build(half_extent, float(region.get("nav_cell_m", 0.5)), blockers, float(region.get("nav_agent_radius_m", 0.4)))
	apply_blockers(grid, region, true)
	print("[server] grade de navegação: %d obstáculos, %d células bloqueadas de %d" % [blockers.size(), grid.solid_count(), grid.size * grid.size])
	return grid


## Bloqueios dinâmicos da região (dynamic_blockers: grade, portão de evento): fecha ou abre
## todos, ou só os de `ids`.
static func apply_blockers(grid: NavGrid, region: Dictionary, solid: bool, ids: Array = []) -> void:
	for b: Dictionary in region.get("dynamic_blockers", []):
		if not ids.is_empty() and not str(b["id"]) in ids:
			continue
		var r: Array = b["rect"]
		grid.set_rect_solid(Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1])), solid,
			float(region.get("nav_agent_radius_m", 0.4)))


## Vale o grupo no próprio nó ou em algum ancestral (ex.: a tocha inteira é obstáculo).
static func _in_obstacle_group(node: Node, root: Node) -> bool:
	var n := node
	while n != null:
		if n.is_in_group("obstacle"):
			return true
		if n == root:
			break
		n = n.get_parent()
	return false


## Transform global calculado sem a cena estar na árvore.
static func _global_transform(node: Node3D, root: Node) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf
