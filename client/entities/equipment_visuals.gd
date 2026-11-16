class_name EquipmentVisuals
extends RefCounted
## Monta o equipamento visível no personagem (placeholders com primitivas) a partir
## da aparência replicada pelo servidor: [base, nível, raridade] por slot visível.
## Brilho progressivo do refino (data/config/vfx.json -> refine_glow): leve a partir de +7,
## intenso a partir de +9, aura com partículas a partir de +11. Excelente e ancestral
## ganham contorno com a cor da raridade.

const RIM_SHADER := preload("res://assets/shaders/rim_highlight.gdshader")
const PARTICLE_SHADER := preload("res://assets/shaders/particle_soft.gdshader")


## Com `rig` (modelo animado): armas e escudos vão para as mãos do modelo, com o brilho do refino;
## as peças de armadura não ganham forma (o modelo já veste a classe), só a aura de +11; asas continuam.
static func build(appearance: PackedInt32Array, catalog: ItemCatalog, rig: ModelRig = null) -> Node3D:
	var gear := Node3D.new()
	gear.name = "Gear"
	var tiers: Array = GameConfig.get_value("vfx", "refine_glow")
	var rims: Dictionary = GameConfig.get_value("vfx", "rarity_rim")
	for i in ItemCatalog.VISIBLE_SLOTS.size():
		var base_index := appearance[i * 3] if appearance.size() >= (i + 1) * 3 else -1
		if base_index < 0 or base_index >= catalog.base_ids.size():
			continue
		var level := appearance[i * 3 + 1]
		var rarity := appearance[i * 3 + 2]
		var base: Dictionary = catalog.bases[catalog.base_ids[base_index]]
		var vis: Dictionary = base.get("visual", {})
		var color := GameConfig.color_of(vis.get("color"), Color.GRAY)
		var glow := GameConfig.color_of(vis.get("glow"), Color.WHITE)
		var energy := 0.0
		var particles := 0
		for t: Dictionary in tiers:
			if level >= int(t["min_level"]):
				energy = float(t["energy"])
				particles = int(t.get("particles", 0))
		var rim := Color(0, 0, 0, 0)
		if rarity == ItemCatalog.RARITY_EXCELLENT:
			rim = GameConfig.color_of(rims.get("excellent"))
		elif rarity == ItemCatalog.RARITY_ANCESTRAL:
			rim = GameConfig.color_of(rims.get("ancestral"))
		var kind := str(vis.get("mesh", ""))
		if rig != null and rig.can_hold() and kind != "wings":
			var held := rig.attach_weapon(kind)
			if held != null:
				_glow_model(held, glow, energy, rim)
				if particles > 0:
					held.add_child(_aura(glow, particles))
			elif particles > 0:
				gear.add_child(_aura(glow, particles))
			continue
		var piece := _piece(kind, color, glow, energy, rim)
		if piece == null:
			continue
		gear.add_child(piece)
		if particles > 0:
			piece.add_child(_aura(glow, particles))
	return gear


static func _piece(kind: String, color: Color, glow: Color, energy: float, rim: Color) -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	if energy > 0.0:
		mat.emission_enabled = true
		mat.emission = glow
		mat.emission_energy_multiplier = energy * 0.16 # brilho na peça inteira: sutil, senão vira plástico
	var overlay: ShaderMaterial = null
	if rim.a > 0.0 or energy > 0.0:
		# contorno: cor da raridade; sem raridade, a cor do brilho do refino
		overlay = ShaderMaterial.new()
		overlay.shader = RIM_SHADER
		overlay.set_shader_parameter("rim_color", rim if rim.a > 0.0 else glow)
		overlay.set_shader_parameter("intensity", 0.9 + energy * 0.35)
	match kind:
		"staff":
			root.position = Vector3(0.42, 0.0, 0.12)
			root.rotation = Vector3(0.12, 0.0, -0.08)
			var shaft := CylinderMesh.new()
			shaft.top_radius = 0.03
			shaft.bottom_radius = 0.04
			shaft.height = 1.7
			_add(root, shaft, mat, overlay, Vector3(0, 0.85, 0))
			var orb_mat := StandardMaterial3D.new()
			orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			orb_mat.albedo_color = glow * (1.0 + energy)
			var orb := SphereMesh.new()
			orb.radius = 0.09
			orb.height = 0.18
			_add(root, orb, orb_mat, null, Vector3(0, 1.75, 0))
			if energy > 0.0:
				var light := OmniLight3D.new()
				light.light_color = glow
				light.light_energy = 0.4 + energy * 0.4
				light.omni_range = 2.5
				light.position = Vector3(0, 1.75, 0)
				root.add_child(light)
		"sword":
			root.position = Vector3(0.42, 0.0, 0.14)
			root.rotation = Vector3(0.35, 0.0, -0.1)
			var grip := CylinderMesh.new()
			grip.top_radius = 0.025
			grip.bottom_radius = 0.03
			grip.height = 0.26
			_add(root, grip, mat, null, Vector3(0, 0.95, 0))
			var guard := BoxMesh.new()
			guard.size = Vector3(0.28, 0.04, 0.06)
			_add(root, guard, mat, overlay, Vector3(0, 1.09, 0))
			var blade_mat := StandardMaterial3D.new()
			blade_mat.albedo_color = Color(0.7, 0.7, 0.74).lerp(glow, 0.15)
			blade_mat.metallic = 0.8
			blade_mat.roughness = 0.3
			blade_mat.emission_enabled = true
			blade_mat.emission = glow
			blade_mat.emission_energy_multiplier = 0.25 + energy * 0.35 # a magia canalizada na lâmina
			var blade := BoxMesh.new()
			blade.size = Vector3(0.07, 0.95, 0.02)
			_add(root, blade, blade_mat, overlay, Vector3(0, 1.58, 0))
			if energy > 0.0:
				var light := OmniLight3D.new()
				light.light_color = glow
				light.light_energy = 0.3 + energy * 0.35
				light.omni_range = 2.0
				light.position = Vector3(0, 1.5, 0)
				root.add_child(light)
		"shield":
			var box := BoxMesh.new()
			box.size = Vector3(0.06, 0.6, 0.5)
			root.rotation = Vector3(0, 0.3, 0)
			_add(root, box, mat, overlay, Vector3(-0.43, 1.0, 0.08))
		"hood":
			var hood := SphereMesh.new()
			hood.radius = 0.33
			hood.height = 0.5
			_add(root, hood, mat, overlay, Vector3(0, 1.62, -0.02))
		"robe":
			var robe := CylinderMesh.new()
			robe.top_radius = 0.37
			robe.bottom_radius = 0.52
			robe.height = 1.1
			_add(root, robe, mat, overlay, Vector3(0, 0.75, 0))
		"skirt":
			var skirt := CylinderMesh.new()
			skirt.top_radius = 0.4
			skirt.bottom_radius = 0.47
			skirt.height = 0.42
			_add(root, skirt, mat, overlay, Vector3(0, 0.33, 0))
		"gloves":
			for side in [-1.0, 1.0]:
				var g := SphereMesh.new()
				g.radius = 0.1
				g.height = 0.2
				_add(root, g, mat, overlay, Vector3(0.4 * side, 0.95, 0.1))
		"wings":
			var wings := WingsVisual.new()
			wings.setup(mat, overlay, glow, energy)
			root.add_child(wings)
		"boots":
			for side in [-1.0, 1.0]:
				var b := BoxMesh.new()
				b.size = Vector3(0.17, 0.18, 0.3)
				_add(root, b, mat, overlay, Vector3(0.15 * side, 0.09, 0.05))
		_:
			return null
	return root


## Brilho do refino e contorno da raridade num modelo (arma na mão), sem perder a textura.
static func _glow_model(node: Node3D, glow: Color, energy: float, rim: Color) -> void:
	var overlay: ShaderMaterial = null
	if rim.a > 0.0 or energy > 0.0:
		overlay = ShaderMaterial.new()
		overlay.shader = RIM_SHADER
		overlay.set_shader_parameter("rim_color", rim if rim.a > 0.0 else glow)
		overlay.set_shader_parameter("intensity", 0.9 + energy * 0.35)
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if overlay != null:
			mi.material_overlay = overlay
		if energy <= 0.0 or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat == null:
				continue
			var copy := mat.duplicate() as StandardMaterial3D
			copy.emission_enabled = true
			copy.emission = glow
			copy.emission_energy_multiplier = energy * 0.16
			mi.set_surface_override_material(i, copy)
	if energy > 0.0:
		var light := OmniLight3D.new()
		light.light_color = glow
		light.light_energy = 0.3 + energy * 0.35
		light.omni_range = 2.0
		node.add_child(light)


static func _add(root: Node3D, mesh: Mesh, mat: Material, overlay: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if overlay != null:
		mi.material_overlay = overlay
	mi.position = pos
	root.add_child(mi)


## Aura de partículas para itens +11 ou mais.
static func _aura(color: Color, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.4
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.25
	p.position = Vector3(0, 0.9, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = PARTICLE_SHADER
	quad.material = mat
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	return p
