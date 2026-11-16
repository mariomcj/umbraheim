class_name ClassPreview
extends SubViewportContainer
## Modelo 3D da classe na escolha de personagem (docs/design/PROPOSTA_UI.md 3.1): o mesmo ModelRig do jogo
## num SubViewport transparente, girando devagar sobre o círculo rúnico, com luz na cor da classe.
## O modelo só carrega quando a tela de escolha aparece (set_class), não na abertura do jogo.

const RUNE_SHADER := preload("res://assets/shaders/rune_circle.gdshader")

var _viewport: SubViewport
var _pivot: Node3D
var _rig: ModelRig
var _rune: ShaderMaterial
var _rim: OmniLight3D
var _class_id := ""
var _cfg: Dictionary


func _ready() -> void:
	_cfg = GameConfig.get_value("ui", "theme").get("class_preview", {})
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.42, 0.5)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var cam := Camera3D.new()
	cam.fov = float(_cfg.get("fov", 30.0))
	var eye: Array = _cfg.get("camera", [0.0, 1.35, 4.2])
	var look: Array = _cfg.get("look_at", [0.0, 0.85, 0.0])
	cam.position = Vector3(float(eye[0]), float(eye[1]), float(eye[2]))
	_viewport.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(float(look[0]), float(look[1]), float(look[2])))
	var key := DirectionalLight3D.new()
	key.light_energy = 1.2
	key.light_color = Color(0.85, 0.82, 0.9)
	key.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-30), 0)
	_viewport.add_child(key)
	_rim = OmniLight3D.new() # contraluz na cor da classe
	_rim.position = Vector3(0.0, 1.6, -1.4)
	_rim.omni_range = 4.0
	_rim.light_energy = 2.0
	_viewport.add_child(_rim)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * float(_cfg.get("rune_size_m", 2.2))
	_rune = ShaderMaterial.new()
	_rune.shader = RUNE_SHADER
	_rune.set_shader_parameter("intensity", 1.4)
	var rune := MeshInstance3D.new()
	rune.mesh = plane
	rune.material_override = _rune
	rune.position.y = 0.01
	_viewport.add_child(rune)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)


func set_class(class_id: String) -> void:
	var color := UiPalette.class_color(class_id)
	_rune.set_shader_parameter("color", color)
	_rim.light_color = color
	if class_id == _class_id:
		return
	_class_id = class_id
	if _rig != null:
		_rig.queue_free()
		_rig = null
	_rig = ModelRig.create(ModelRig.model_for_class(class_id))
	if _rig != null:
		_pivot.add_child(_rig)
		_rig.play_state("idle")


func _process(delta: float) -> void:
	if is_visible_in_tree() and _pivot != null:
		_pivot.rotation.y += delta * float(_cfg.get("spin_rad_s", 0.35))
