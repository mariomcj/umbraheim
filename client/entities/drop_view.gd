class_name DropView
extends Node3D
## Item no chão: pequeno objeto brilhante + nome colorido pela raridade
## (normal branco, excelente verde, joia dourada, moeda âmbar).

var drop_id: int
var rarity: int
var _mesh: MeshInstance3D
var _label: Label3D
var _hovered: bool = false


func setup(id: int, text: String, drop_rarity: int, color: Color) -> void:
	drop_id = id
	rarity = drop_rarity
	_mesh = MeshInstance3D.new()
	match rarity:
		Protocol.RARITY_CURRENCY:
			var coin := CylinderMesh.new()
			coin.top_radius = 0.16
			coin.bottom_radius = 0.16
			coin.height = 0.1
			coin.radial_segments = 12
			_mesh.mesh = coin
		Protocol.RARITY_JEWEL:
			var gem := SphereMesh.new()
			gem.radius = 0.15
			gem.height = 0.36
			gem.radial_segments = 6
			gem.rings = 2
			_mesh.mesh = gem
		_:
			var box := BoxMesh.new()
			box.size = Vector3(0.45, 0.08, 0.22)
			_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.3)
	mat.emission_enabled = true
	mat.emission = color
	match rarity:
		Protocol.RARITY_NORMAL:
			mat.emission_energy_multiplier = 0.35
		Protocol.RARITY_CURRENCY:
			mat.emission_energy_multiplier = 0.6
		_:
			mat.emission_energy_multiplier = 1.6
	_mesh.material_override = mat
	_mesh.position = Vector3(0, 0.15, 0)
	add_child(_mesh)
	_label = Label3D.new()
	_label.text = text
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.0045
	_label.font_size = 40
	_label.outline_size = 10
	_label.modulate = color
	_label.outline_modulate = Color(0, 0, 0, 0.9)
	_label.position = Vector3(0, 0.6, 0)
	add_child(_label)


func set_hovered(on: bool) -> void:
	if on != _hovered:
		_hovered = on
		_label.scale = Vector3.ONE * (1.25 if on else 1.0)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.002 + float(drop_id)
	_mesh.position.y = 0.15 + sin(t) * 0.05
	_mesh.rotation.y = t * 0.8
