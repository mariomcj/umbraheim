extends OmniLight3D
## Tremulação barata de tocha (sem custo de sombra). Parâmetros ajustáveis na cena.

@export var base_energy: float = 1.6
@export var flicker_amount: float = 0.35
@export var flicker_speed: float = 9.0

var _phase: float


func _ready() -> void:
	_phase = randf() * 100.0


func _process(delta: float) -> void:
	_phase += delta * flicker_speed
	var n := sin(_phase) * 0.5 + sin(_phase * 2.37 + 1.3) * 0.3 + sin(_phase * 5.11) * 0.2
	light_energy = base_energy + n * flicker_amount
