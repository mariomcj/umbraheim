extends Node3D
## Vitrine dos modelos animados (data/config/models.json): classes e monstros lado a lado,
## cada um num estado. Só para desenvolvimento (scenes/dev fica fora da exportação).
## Rodar: godot --path . res://scenes/dev/model_lineup.tscn [-- --screenshot=C:/x.png --state=walk --frames=120]
## Outros: --only=<id>, --golden, --hover, --die, --portal (um portal de frente para a câmera).

const AVATAR := preload("res://client/entities/avatar.tscn")

var _shot_path: String = ""
var _frames: int = 150
var _state: String = "idle"
var _avatars: Array[Avatar] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_shot_path = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--frames="):
			_frames = arg.trim_prefix("--frames=").to_int()
		elif arg.begins_with("--state="):
			_state = arg.trim_prefix("--state=")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.15, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.7)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 12)
	ground.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.22, 0.2, 0.24)
	ground.material_override = floor_mat
	add_child(ground)
	var models: Dictionary = GameConfig.get_value("models", "models")
	var x := -float(models.size() - 1) * 1.6
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
	if only != "":
		x = 0.0
	for id: String in models:
		if only != "" and id != only:
			continue
		var a: Avatar = AVATAR.instantiate()
		add_child(a)
		a.position = Vector3(x, 0, 0)
		a.rotation_degrees.y = 20.0
		a.attach_model(id)
		a.set_player_name(id)
		a.set_process(false) # sem locomoção automática: o estado vem de --state
		if a.rig != null:
			print("%s: escala %.3f, caixa %s" % [id, a.rig.model.scale.x, a.rig._rest_box()])
		_avatars.append(a)
		x += 3.2
	if "--portal" in OS.get_cmdline_user_args():
		var portal := PortalView.new()
		add_child(portal)
		portal.setup({"pos": [0.0, -2.0], "label": "Portal"}, Color(0.55, 0.3, 0.95))
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.2, 9.5)
	cam.rotation_degrees = Vector3(-12, 0, 0)
	cam.fov = 70
	add_child(cam)
	await get_tree().create_timer(0.3).timeout
	if "--fx" in OS.get_cmdline_user_args():
		_fx_demo()
	for a in _avatars:
		if a.rig == null:
			continue
		if "--golden" in OS.get_cmdline_user_args():
			a._make_golden()
		if "--hover" in OS.get_cmdline_user_args():
			a.set_hovered(true)
			a.set_hovered(false)
		if "--die" in OS.get_cmdline_user_args():
			a.set_process(true)
			a.play_death()
			continue
		if _state in ["attack", "cast", "hit", "death"]:
			a.rig.play_once(_state)
		else:
			a.rig.play_state(_state)


## Efeitos de partícula lado a lado: impacto, erupção (área), aura, subida de nível e rastro.
func _fx_demo() -> void:
	var vfx := VfxPlayer.new()
	add_child(vfx)
	var violet := Color(0.6, 0.3, 1.0)
	vfx.impact(Vector3(-6, 1, 0), violet, 1.4)
	vfx._eruption(Vector3(-2, 0, 0), 1.6, Color(0.9, 0.35, 0.15))
	if not _avatars.is_empty():
		vfx._aura_burst(_avatars[0], Color(0.4, 0.9, 0.6))
		vfx.level_up(_avatars[_avatars.size() - 1], 10)
	var trail := vfx._particles(violet, 40, 0.8, false, "trail")
	trail.initial_velocity_min = 1.0
	trail.initial_velocity_max = 2.0
	add_child(trail)
	trail.position = Vector3(6, 1.2, 0)
	trail.emitting = true


func _process(_delta: float) -> void:
	if _shot_path == "":
		return
	_frames -= 1
	if _frames == 0:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		get_tree().quit()
