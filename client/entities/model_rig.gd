class_name ModelRig
extends Node3D
## Modelo 3D animado de um Avatar (só no cliente). Os dados vêm de data/config/models.json.
## Estados: idle, walk, run (laço, escolhidos pela velocidade) e attack, cast, hit, death (uma vez).
## Animações compartilhadas (anims != "self"): os clipes de um arquivo-fonte são copiados uma vez
## por modelo, com as trilhas apontadas para o esqueleto dele (os ossos têm os mesmos nomes).

const LOOPED := ["idle", "walk", "run"]

static var _scenes: Dictionary = {} # caminho -> PackedScene
static var _libraries: Dictionary = {} # id do modelo -> AnimationLibrary
static var _boxes: Dictionary = {} # id do modelo -> AABB das malhas mantidas (pose de descanso)

var model_id: String = ""
var model: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var float_m: float = 0.0

var _def: Dictionary
var _clips: Dictionary = {} # estado -> nome do clipe no AnimationPlayer
var _oneshot: String = ""
var _loco: String = ""
var _run_scale: float = 1.0
var _moving_mps: float = 0.35
var _run_mps: float = 3.4
var _hands: Dictionary = {} # "right"/"left" -> BoneAttachment3D
var _weapons: Array[Node3D] = []


## Cria o modelo pelo id; null se o id não existe ou o arquivo não carrega.
static func create(id: String) -> ModelRig:
	var models: Dictionary = GameConfig.get_value("models", "models")
	if not models.has(id):
		return null
	var def: Dictionary = models[id]
	var scene := _scene(str(def["path"]))
	if scene == null:
		return null
	var rig := ModelRig.new()
	rig.name = "Model"
	rig._build(id, def, scene)
	return rig


static func model_for_class(class_id: String) -> String:
	var classes: Dictionary = GameConfig.get_value("models", "classes")
	return str(classes.get(class_id, ""))


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]


func _build(id: String, def: Dictionary, scene: PackedScene) -> void:
	model_id = id
	_def = def
	var loco: Dictionary = GameConfig.get_value("models", "locomotion")
	_moving_mps = float(loco.get("moving_mps", 0.35))
	_run_mps = float(loco.get("run_mps", 3.4))
	model = scene.instantiate()
	add_child(model)
	var keep: Array = def.get("keep", [])
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var kept := keep.is_empty()
		for prefix: String in keep:
			if mi.name.begins_with(prefix):
				kept = true
		mi.visible = kept
		if kept:
			meshes.append(mi)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	skeleton = skeletons[0] if not skeletons.is_empty() else null
	# escala pela altura das malhas mantidas, com os pés no chão
	if def.has("scale"): # escala fixa (FBX com esqueleto em outra unidade: a caixa de descanso engana)
		model.scale = Vector3.ONE * float(def["scale"])
		model.position.y = float(def.get("lift_m", 0.0))
	else:
		var box := _rest_box()
		var s := float(def.get("height_m", 1.8)) / maxf(0.001, box.size.y)
		model.scale = Vector3.ONE * s
		model.position.y = -box.position.y * s
	model.rotation_degrees.y = float(def.get("yaw_deg", 0.0))
	float_m = float(def.get("float_m", 0.0))
	if def.has("tint"):
		_tint(GameConfig.color_of(def["tint"]))
	_run_scale = float(def.get("run_speed_scale", 1.0))
	_setup_animations()
	if skeleton != null:
		var hands: Dictionary = def.get("hands", {})
		for side: String in hands:
			var att := BoneAttachment3D.new()
			att.bone_name = str(hands[side])
			skeleton.add_child(att)
			_hands[side] = att
		for prop: Dictionary in def.get("props", []):
			_attach(str(prop["path"]), str(prop.get("hand", "right")))
	play_state("idle")


## Caixa das malhas mantidas na pose de descanso, no espaço do modelo (sem escala).
func _rest_box() -> AABB:
	if _boxes.has(model_id):
		return _boxes[model_id]
	var box := AABB()
	var first := true
	for mi in meshes:
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		# malha com pele: a Godot a desenha no espaço do esqueleto, não no do nó da malha
		if mi.skin != null and not mi.skeleton.is_empty() and mi.get_node_or_null(mi.skeleton) is Skeleton3D:
			n = mi.get_node(mi.skeleton)
		while n != null and n != model:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b := xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	_boxes[model_id] = box
	return box


func _tint(color: Color) -> void:
	for mi in meshes:
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat == null:
				continue
			var copy := mat.duplicate() as StandardMaterial3D
			copy.albedo_color = mat.albedo_color * color
			mi.set_surface_override_material(i, copy)


# ---------------------------------------------------------------- animações

func _setup_animations() -> void:
	var source := str(_def.get("anims", "self"))
	var clips: Dictionary = {}
	if source == "kaykit":
		clips = (GameConfig.get_value("models", "kaykit_clips") as Dictionary).duplicate()
	clips.merge(_def.get("clips", {}), true)
	if source == "self":
		var players := model.find_children("*", "AnimationPlayer", true, false)
		if players.is_empty():
			return
		anim = players[0]
		for state: String in clips:
			if anim.has_animation(str(clips[state])):
				_clips[state] = str(clips[state])
	else:
		for old: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
			old.queue_free() # as próprias (se vieram) não são usadas
		if skeleton == null:
			return
		anim = AnimationPlayer.new()
		anim.name = "RigAnimations"
		model.add_child(anim)
		anim.root_node = anim.get_path_to(model)
		anim.add_animation_library("m", _shared_library(source, clips))
		for state: String in clips:
			if anim.has_animation("m/" + str(clips[state])):
				_clips[state] = "m/" + str(clips[state])
	for state: String in LOOPED:
		if _clips.has(state):
			anim.get_animation(_clips[state]).loop_mode = Animation.LOOP_LINEAR
	for state: String in ["attack", "cast", "hit", "death"]:
		if _clips.has(state):
			anim.get_animation(_clips[state]).loop_mode = Animation.LOOP_NONE
	anim.animation_finished.connect(_on_finished)


## Biblioteca com só os clipes usados, apontada para o esqueleto deste modelo (cache por modelo).
func _shared_library(source: String, clips: Dictionary) -> AnimationLibrary:
	if _libraries.has(model_id):
		return _libraries[model_id]
	var lib := AnimationLibrary.new()
	var wanted: Array = clips.values()
	var target_skel := str(model.get_path_to(skeleton))
	var sources: Dictionary = GameConfig.get_value("models", "anim_sources")
	for path: String in sources.get(source, []):
		var scene := _scene(path)
		if scene == null:
			continue
		var src: Node = scene.instantiate()
		var players := src.find_children("*", "AnimationPlayer", true, false)
		var skels := src.find_children("*", "Skeleton3D", true, false)
		if not players.is_empty() and not skels.is_empty():
			var player: AnimationPlayer = players[0]
			var src_skel := str(player.get_node(player.root_node).get_path_to(skels[0]))
			for clip_name: String in player.get_animation_list():
				if clip_name in wanted and not lib.has_animation(clip_name):
					lib.add_animation(clip_name, _retarget(player.get_animation(clip_name), src_skel, target_skel))
		src.free()
	_libraries[model_id] = lib
	return lib


func _retarget(source: Animation, src_skel: String, target_skel: String) -> Animation:
	var a := source.duplicate(true) as Animation
	for t in range(a.get_track_count() - 1, -1, -1):
		var path := str(a.track_get_path(t))
		var colon := path.find(":")
		if colon < 0 or path.substr(0, colon) != src_skel:
			a.remove_track(t) # trilha de outro nó (não é osso): ignorada
			continue
		var bone := path.substr(colon + 1)
		if skeleton.find_bone(bone) < 0:
			a.remove_track(t)
			continue
		a.track_set_path(t, NodePath(target_skel + ":" + bone))
	return a


func has_state(state: String) -> bool:
	return _clips.has(state)


func play_state(state: String) -> void:
	if anim == null or not _clips.has(state):
		return
	var speed := 1.0
	if state == "run" and not _clips.has("run"):
		state = "walk"
		speed = _run_scale
	if not _clips.has(state):
		return
	anim.play(_clips[state], 0.15, speed)


## Toca um estado uma vez (attack, cast, hit, death) e volta à locomoção no fim; death fica parado.
func play_once(state: String) -> bool:
	if anim == null or not _clips.has(state):
		return false
	if _oneshot == "death":
		return true
	if state == "hit" and _oneshot != "":
		return true # não corta um ataque com a reação ao golpe
	_oneshot = state
	anim.play(_clips[state], 0.08)
	return true


func clip_length(state: String) -> float:
	if anim == null or not _clips.has(state):
		return 0.0
	return anim.get_animation(_clips[state]).length


## Velocidade horizontal (m/s) do avatar neste quadro: escolhe parado, andar ou correr.
func update_locomotion(speed_mps: float) -> void:
	if _oneshot != "" or anim == null:
		return
	var state := "idle"
	if speed_mps >= _run_mps:
		state = "run"
	elif speed_mps >= _moving_mps:
		state = "walk"
	if state != _loco or not anim.is_playing():
		_loco = state
		play_state(state)


func _on_finished(_clip: StringName) -> void:
	if _oneshot == "death":
		return
	_oneshot = ""
	_loco = ""


# ---------------------------------------------------------------- armas nas mãos

func can_hold() -> bool:
	return not _hands.is_empty()


## Arma do item (pelo "mesh" do visual do item) na mão certa; null se não houver modelo para ela.
func attach_weapon(kind: String) -> Node3D:
	var weapons: Dictionary = GameConfig.get_value("models", "weapons")
	if not weapons.has(kind) or _hands.is_empty():
		return null
	var w: Dictionary = weapons[kind]
	return _attach(str(w["path"]), str(w.get("hand", "right")), true)


func clear_weapons() -> void:
	for w in _weapons:
		if is_instance_valid(w):
			w.queue_free()
	_weapons.clear()


func _attach(path: String, hand: String, removable: bool = false) -> Node3D:
	if not _hands.has(hand):
		return null
	var scene := _scene(path)
	if scene == null:
		return null
	var node: Node3D = scene.instantiate()
	(_hands[hand] as Node3D).add_child(node)
	if removable:
		_weapons.append(node) # fora de `meshes`: some quando o equipamento muda
	else:
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			meshes.append(mi)
	return node
