class_name SoundDirector
extends Node
## Som do cliente: música do menu, ambiente por região, combate, magias, vozes dos monstros,
## passos do próprio personagem e clique dos botões. Tudo vem de data/config/audio.json.
## Sons no mundo não são posicionais: o volume cai com a distância até o próprio personagem
## (a câmera isométrica fica longe demais para a atenuação 3D da Godot).
## No headless (servidor, bots, testes) não carrega nem toca nada.

const AUDIO_DIR := "res://assets/audio/"
const BUSES: PackedStringArray = ["Music", "Ambient", "SFX", "UI"]

## O próprio personagem: referência para a distância e para os passos.
var local_avatar: Avatar = null

var _enabled := true
var _sounds: Dictionary = {}
var _streams: Dictionary = {} # caminho -> AudioStream
var _last_play: Dictionary = {} # nome do som -> segundos
var _voice_cooldown: Dictionary = {} # entity_id -> segundos
var _pool: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _music_name := ""
var _ambient_name := ""
var _full_m := 6.0
var _max_m := 28.0
var _fade_s := 1.5
var _stride_m := 1.7
var _walked := 0.0
var _last_step_pos := Vector3.INF
var _region := ""


func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	var cfg := GameConfig.section("audio")
	_sounds = cfg.get("sounds", {})
	var buses: Dictionary = cfg.get("buses", {})
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_volume_db(idx, float(buses.get(bus, 0.0)))
	var falloff: Dictionary = cfg.get("falloff", {})
	_full_m = float(falloff.get("full_m", _full_m))
	_max_m = float(falloff.get("max_m", _max_m))
	_fade_s = float(cfg.get("music_fade_s", _fade_s))
	_stride_m = float((cfg.get("footsteps", {}) as Dictionary).get("stride_m", _stride_m))
	for i in int(cfg.get("voices_max", 16)):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = "Ambient"
	add_child(_ambient)
	# clique em qualquer botão da interface, inclusive os criados depois
	get_tree().node_added.connect(_on_node_added)
	_hook_buttons(get_tree().root)


# ---------------------------------------------------------------- telas

## Tela de entrada: música do menu, sem ambiente.
func enter_menu() -> void:
	if not _enabled:
		return
	_crossfade(_ambient, "", "_ambient_name")
	_crossfade(_music, str((GameConfig.get_value("audio", "music") as Dictionary).get("menu", "")), "_music_name")


## Personagem no mundo: a música do menu sai e entra o ambiente da região.
func enter_world(region_id: String) -> void:
	if not _enabled:
		return
	_crossfade(_music, "", "_music_name")
	set_region(region_id)


func set_region(region_id: String) -> void:
	if not _enabled:
		return
	_region = region_id
	_last_step_pos = Vector3.INF
	if _music_name != "":
		return # ainda na tela de entrada
	var amb: Dictionary = GameConfig.get_value("audio", "ambient")
	_crossfade(_ambient, str(amb.get(region_id, amb.get("default", ""))), "_ambient_name")


# ---------------------------------------------------------------- eventos do jogo

## Lançamento de magia (som na hora) e impacto (no tempo do efeito visual).
func cast(spell: Dictionary, caster: Avatar, target: Avatar, target_pos: Vector3) -> void:
	if not _enabled:
		return
	var kind := str(spell.get("kind", ""))
	var by_kind: Dictionary = (GameConfig.get_value("audio", "spells") as Dictionary).get(kind, {})
	var over: Dictionary = (GameConfig.get_value("audio", "spell_overrides") as Dictionary).get(str(spell.get("id", "")), {})
	var cast_sound := str(over.get("cast", by_kind.get("cast", "")))
	var impact_sound := str(over.get("impact", by_kind.get("impact", "")))
	var from := caster.global_position if caster != null else target_pos
	var at := target.global_position if target != null else target_pos
	if kind == "nova":
		at = from
	play_at(cast_sound, from)
	if impact_sound == "":
		return
	var delay := float(spell.get("cast_delay_s", 0.1))
	if kind == "projectile":
		delay = from.distance_to(at) / maxf(1.0, float(spell.get("projectile_speed_mps", 20.0)))
	get_tree().create_timer(maxf(0.0, delay)).timeout.connect(func() -> void: play_at(impact_sound, at))


## Ataque corpo a corpo de monstro ou jogador sem magia: golpe no alvo e, às vezes, a voz do monstro.
func attack(attacker: Avatar, target: Avatar) -> void:
	if not _enabled:
		return
	if target != null:
		if target == local_avatar:
			play("player_hurt")
		else:
			play_at("melee_hit", target.global_position)
	if attacker != null and attacker.is_monster:
		var cfg: Dictionary = GameConfig.get_value("audio", "monsters")
		var now := Time.get_ticks_msec() / 1000.0
		if now - float(_voice_cooldown.get(attacker.entity_id, -999.0)) < float(cfg.get("cooldown_s", 4.0)):
			return
		if randf() > float(cfg.get("attack_chance", 0.5)):
			return
		_voice_cooldown[attacker.entity_id] = now
		play_at(str(_voice(attacker).get("attack", "")), attacker.global_position)


func monster_died(view: Avatar) -> void:
	if not _enabled or view == null:
		return
	_voice_cooldown.erase(view.entity_id)
	play_at(str(_voice(view).get("death", "")), view.global_position)


func player_died() -> void:
	play("player_death")


func level_up(view: Avatar) -> void:
	if view != null and view == local_avatar:
		play("level_up")


# ---------------------------------------------------------------- tocar

## Som sem distância (interface, o próprio personagem).
func play(sound_name: String, volume_offset_db: float = 0.0, bus: String = "SFX") -> void:
	if not _enabled or sound_name == "" or not _sounds.has(sound_name):
		return
	var s: Dictionary = _sounds[sound_name]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(sound_name, -999.0)) < float(s.get("cooldown_s", 0.0)):
		return
	var stream := _pick(s)
	if stream == null:
		return
	_last_play[sound_name] = now
	var p := _pool[_next_voice]
	_next_voice = (_next_voice + 1) % _pool.size()
	p.stop()
	p.bus = bus
	p.stream = stream
	p.volume_db = float(s.get("volume_db", 0.0)) + volume_offset_db
	p.pitch_scale = randf_range(float(s.get("pitch_min", 1.0)), float(s.get("pitch_max", 1.0)))
	p.play()


## Som no mundo: cai de volume com a distância até o próprio personagem.
func play_at(sound_name: String, at: Vector3) -> void:
	if not _enabled or sound_name == "":
		return
	var offset := 0.0
	if local_avatar != null and is_instance_valid(local_avatar):
		var d := Vector2(at.x - local_avatar.global_position.x, at.z - local_avatar.global_position.z).length()
		if d >= _max_m:
			return
		if d > _full_m:
			var k := (d - _full_m) / maxf(0.01, _max_m - _full_m)
			offset = linear_to_db(1.0 - k)
	play(sound_name, offset)


func _process(_delta: float) -> void:
	if not _enabled or local_avatar == null or not is_instance_valid(local_avatar) or local_avatar.dying:
		return
	var pos := local_avatar.global_position
	if _last_step_pos == Vector3.INF:
		_last_step_pos = pos
		return
	var step := Vector2(pos.x - _last_step_pos.x, pos.z - _last_step_pos.z).length()
	_last_step_pos = pos
	if step > 3.0: # teletransporte ou correção do servidor: não é passo
		_walked = 0.0
		return
	_walked += step
	if _walked >= _stride_m:
		_walked = 0.0
		var steps: Dictionary = GameConfig.get_value("audio", "footsteps")
		play(str((steps.get("by_region", {}) as Dictionary).get(_region, steps.get("default", ""))))


# ---------------------------------------------------------------- interno

func _voice(view: Avatar) -> Dictionary:
	var cfg: Dictionary = GameConfig.get_value("audio", "monsters")
	var id := view.monster_type.trim_suffix(MonsterCatalog.GOLDEN_SUFFIX_ID)
	var by_id: Dictionary = cfg.get("by_id", {})
	if by_id.has(id):
		return by_id[id]
	var by_model: Dictionary = cfg.get("by_model", {})
	if by_model.has(view.monster_model):
		return by_model[view.monster_model]
	return cfg.get("default", {})


func _pick(s: Dictionary) -> AudioStream:
	var files: Array = s.get("files", [])
	if files.is_empty():
		return null
	return _stream(str(files[randi() % files.size()]), bool(s.get("loop", false)))


func _stream(file: String, loop: bool) -> AudioStream:
	if _streams.has(file):
		return _streams[file]
	var stream := load(AUDIO_DIR + file) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	_streams[file] = stream
	return stream


## Troca a faixa de um tocador contínuo (música ou ambiente) com fade.
func _crossfade(player: AudioStreamPlayer, sound_name: String, field: String) -> void:
	if str(get(field)) == sound_name:
		return
	set(field, sound_name)
	var t := create_tween()
	if player.playing:
		t.tween_property(player, "volume_db", -60.0, _fade_s * 0.5)
	t.tween_callback(func() -> void:
		player.stop()
		if sound_name == "" or not _sounds.has(sound_name):
			return
		var s: Dictionary = _sounds[sound_name]
		player.stream = _pick(s)
		player.volume_db = -60.0
		player.play()
		create_tween().tween_property(player, "volume_db", float(s.get("volume_db", 0.0)), _fade_s))


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node as BaseButton)


func _hook_buttons(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node as BaseButton)
	for c in node.get_children():
		_hook_buttons(c)


func _connect_button(b: BaseButton) -> void:
	if not b.pressed.is_connected(_on_button_pressed):
		b.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	ui("click")


## Som de um evento de interface (audio.json -> ui), no canal UI.
func ui(event: String) -> void:
	play(str((GameConfig.get_value("audio", "ui") as Dictionary).get(event, "")), 0.0, "UI")
