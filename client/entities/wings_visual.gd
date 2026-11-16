class_name WingsVisual
extends Node3D
## Asas nas costas do personagem (placeholder com primitivas): duas asas em leque,
## cada uma com penas longas presas num pivô no ombro, batendo devagar, e brasas
## que se soltam das pontas. Material e brilho de refino vêm do EquipmentVisuals.

const FEATHERS := 6
const PARTICLE_SHADER := preload("res://assets/shaders/particle_soft.gdshader")

var _left: Node3D
var _right: Node3D
var _t: float = 0.0
var _speed: float = 2.2


func setup(mat: Material, overlay: Material, glow: Color, energy: float) -> void:
	position = Vector3(0.0, 1.28, -0.24)
	_left = _wing(-1.0, mat, overlay)
	_right = _wing(1.0, mat, overlay)
	add_child(_left)
	add_child(_right)
	_left.add_child(_embers(glow, 10 + int(energy * 6.0), -1.0))
	_right.add_child(_embers(glow, 10 + int(energy * 6.0), 1.0))
	_t = randf() * TAU


func _wing(side: float, mat: Material, overlay: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.1 * side, 0.0, 0.0)
	for i in FEATHERS:
		var k := float(i) / float(FEATHERS - 1) # 0 = pena de cima (mais longa)
		var length := lerpf(1.25, 0.55, k)
		var feather := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(length, 0.16 - k * 0.04, 0.025)
		feather.mesh = box
		feather.material_override = mat
		if overlay != null:
			feather.material_overlay = overlay
		var angle := lerpf(0.55, -0.55, k) # leque: de cima para baixo
		var dir := Vector3(cos(angle) * side, sin(angle), 0.0)
		feather.position = dir * length * 0.5 + Vector3(0, 0.0, -0.02 * i)
		feather.rotation = Vector3(0.0, 0.0, angle * side)
		pivot.add_child(feather)
	return pivot


func _embers(color: Color, amount: int, side: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.5, 0.35, 0.05)
	p.position = Vector3(0.6 * side, 0.05, 0.0) # meio da asa
	p.direction = Vector3.DOWN
	p.spread = 40.0
	p.gravity = Vector3(0, -0.35, 0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.14
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


func _process(delta: float) -> void:
	_t += delta * _speed
	# batida: as asas varrem para trás e voltam, com um leve sobe-e-desce
	var sweep := 0.35 + sin(_t) * 0.32
	var lift := sin(_t + 0.6) * 0.12
	_left.rotation = Vector3(0.0, -sweep, -lift)
	_right.rotation = Vector3(0.0, sweep, lift)
