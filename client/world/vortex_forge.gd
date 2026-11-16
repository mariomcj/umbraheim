extends Node3D
## Forja do Vórtice (visual): anel arcano girando sobre um pedestal, núcleo pulsando.
## A lógica (abrir, combinar) é do servidor; aqui é só a aparência e o destaque.

@export var spin_speed: float = 0.7
@export var pulse_speed: float = 1.6

var hovered: bool = false

@onready var _ring: Node3D = $Ring
@onready var _core: MeshInstance3D = $Core
@onready var _light: OmniLight3D = $Light
@onready var _label: Label3D = $NameLabel


func _process(delta: float) -> void:
	_ring.rotate_y(spin_speed * delta)
	_ring.rotation.x = sin(Time.get_ticks_msec() * 0.0007) * 0.35
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.001 * pulse_speed * TAU)
	_light.light_energy = 1.2 * pulse * (1.5 if hovered else 1.0)
	_core.scale = Vector3.ONE * (0.9 + 0.1 * pulse)
	_label.scale = Vector3.ONE * (1.2 if hovered else 1.0)
