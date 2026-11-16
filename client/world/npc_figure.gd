extends Node3D
## Figura provisória de NPC (corpo, manto, capuz e nome). Só aparência e destaque
## de mouse; a interação é decidida pelo servidor. As cores vêm dos exports, assim
## a mesma cena serve ao ferreiro, à alquimista e ao guardião do cofre.

@export var display_name: String = "NPC"
@export var robe_color: Color = Color(0.3, 0.25, 0.2)
@export var accent_color: Color = Color(0.8, 0.6, 0.3)
@export var title: String = ""

var hovered: bool = false

var _t: float = 0.0
var _base_y: float

@onready var _label: Label3D = $NameLabel
@onready var _title: Label3D = $TitleLabel
@onready var _light: OmniLight3D = $Light
@onready var _upper: Node3D = $Upper


func _ready() -> void:
	_label.text = display_name
	_title.text = title
	_title.visible = not title.is_empty()
	var robe := StandardMaterial3D.new()
	robe.albedo_color = robe_color
	robe.roughness = 0.9
	for path in ["Robe", "Upper/Body", "Upper/Hood"]:
		(get_node(path) as MeshInstance3D).material_override = robe
	var accent := StandardMaterial3D.new()
	accent.albedo_color = accent_color.darkened(0.3)
	accent.emission_enabled = true
	accent.emission = accent_color
	accent.emission_energy_multiplier = 0.6
	($Upper/Sash as MeshInstance3D).material_override = accent
	_light.light_color = accent_color
	_base_y = _upper.position.y
	_t = randf() * TAU


## Nome vindo dos dados da região (fonte única).
func set_display_name(n: String) -> void:
	display_name = n
	if is_node_ready():
		_label.text = n


func _process(delta: float) -> void:
	_t += delta
	_upper.position.y = _base_y + sin(_t * 1.3) * 0.02 # respiração
	_upper.rotation.y = sin(_t * 0.4) * 0.12
	_label.scale = Vector3.ONE * (1.2 if hovered else 1.0)
	_label.modulate = Color(1.0, 0.92, 0.6) if hovered else Color(0.95, 0.85, 0.6)
	_light.light_energy = 0.9 if hovered else 0.35
