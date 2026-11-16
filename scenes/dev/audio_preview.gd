extends Control
## Prévia dos candidatos de áudio (assets/audio/candidates.json, gerado por tools/process_audio.py).
## Cada som tem ▶ para tocar e uma caixa "manter"; "Salvar escolha" grava assets/audio/selection.json.
## Depois: python -I tools/process_audio.py --apply-selection (apaga os não marcados).
## Rodar: godot --path . res://scenes/dev/audio_preview.tscn [-- --screenshot=C:/x.png]
## Só para desenvolvimento (scenes/dev fica fora da exportação).

const CANDIDATES := "res://assets/audio/candidates.json"
const SELECTION := "res://assets/audio/selection.json"
const CAT_NAMES := {
	"music": "Música do menu", "magic": "Magia", "combat": "Combate", "monsters": "Monstros",
	"footsteps": "Passos", "ambient": "Ambiente", "ui": "Interface", "unsorted": "Sem categoria (downloads/)",
}

var _player := AudioStreamPlayer.new()
var _checks: Dictionary = {} # arquivo (res://...) -> CheckBox
var _status := Label.new()
var _shot_path := ""
var _frames := 30


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_shot_path = arg.trim_prefix("--screenshot=")
	add_child(_player)
	_player.finished.connect(func() -> void: _status.text = "Parado.")
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.09, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 12
	root.offset_right = -16
	root.offset_bottom = -12
	add_child(root)

	var bar := HBoxContainer.new()
	root.add_child(bar)
	var title := Label.new()
	title.text = "Umbraheim — prévia de áudio"
	title.add_theme_font_size_override("font_size", 20)
	bar.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_add_button(bar, "■ Parar", _stop)
	_add_button(bar, "Marcar todos", func() -> void: _set_all(true))
	_add_button(bar, "Desmarcar todos", func() -> void: _set_all(false))
	_add_button(bar, "Salvar escolha", _save)
	_status.text = "Clique em ▶ para ouvir. Marque \"manter\" nos que ficam e salve."
	root.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var items := _load_candidates()
	if items.is_empty():
		_status.text = "Nenhum candidato em %s (rode tools/process_audio.py)." % CANDIDATES
		return
	var kept := _load_selection()
	var by_cat: Dictionary = {}
	for it: Dictionary in items:
		var cat := str(it.get("categoria", "unsorted"))
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(it)
	for cat: String in CAT_NAMES:
		if by_cat.has(cat):
			_add_category(list, cat, by_cat[cat], kept)
	for cat: String in by_cat:
		if not CAT_NAMES.has(cat):
			_add_category(list, cat, by_cat[cat], kept)


func _add_category(list: VBoxContainer, cat: String, items: Array, kept: Dictionary) -> void:
	var head := Label.new()
	head.text = "%s (%d)" % [CAT_NAMES.get(cat, cat), items.size()]
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color(0.75, 0.6, 1.0))
	list.add_child(head)
	for it: Dictionary in items:
		var path := "res://" + str(it["arquivo"])
		var row := HBoxContainer.new()
		list.add_child(row)
		_add_button(row, "▶", func() -> void: _play(path, str(it.get("nome", ""))))
		var check := CheckBox.new()
		check.text = "manter"
		check.button_pressed = kept.is_empty() or kept.has(str(it["arquivo"]))
		row.add_child(check)
		_checks[str(it["arquivo"])] = check
		var info := Label.new()
		var label := str(it.get("nome", ""))
		if str(it.get("rotulo", "")) != "":
			label += " — " + str(it["rotulo"])
		info.text = "%s   [%.1f s]   %s · %s   (%s)" % [label, float(it.get("duracao_s", 0.0)),
			str(it.get("autor", "")), str(it.get("licença", "")), str(it["arquivo"]).get_file()]
		info.tooltip_text = _tooltip(it)
		info.mouse_filter = Control.MOUSE_FILTER_PASS
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.clip_text = true
		row.add_child(info)
	list.add_child(HSeparator.new())


func _tooltip(it: Dictionary) -> String:
	var lines: Array[String] = []
	var tags: Array = it.get("tags", [])
	if not tags.is_empty():
		lines.append("Tags: " + ", ".join(tags.map(func(t: Variant) -> String: return str(t))))
	if str(it.get("descricao", "")) != "":
		lines.append(str(it["descricao"]))
	if str(it.get("busca", "")) != "":
		lines.append("Busca: " + str(it["busca"]))
	lines.append(str(it.get("url", "")))
	return "\n".join(lines)


func _add_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _play(path: String, nome: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		_status.text = "Não consegui abrir %s (rode a importação da Godot)." % path
		return
	_player.stream = stream
	_player.play()
	_status.text = "Tocando: %s" % nome


func _stop() -> void:
	_player.stop()
	_status.text = "Parado."


func _set_all(on: bool) -> void:
	for c: CheckBox in _checks.values():
		c.button_pressed = on


func _save() -> void:
	var keep: Array[String] = []
	for f: String in _checks:
		if (_checks[f] as CheckBox).button_pressed:
			keep.append(f)
	var file := FileAccess.open(SELECTION, FileAccess.WRITE)
	if file == null:
		_status.text = "Erro ao gravar %s." % SELECTION
		return
	file.store_string(JSON.stringify({"keep": keep}, " "))
	file.close()
	_status.text = "Escolha salva: %d de %d mantidos em %s. Avise o agente para apagar os descartados." % [
		keep.size(), _checks.size(), ProjectSettings.globalize_path(SELECTION)]


func _load_candidates() -> Array:
	if not FileAccess.file_exists(CANDIDATES):
		return []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATES))
	return data if data is Array else []


func _load_selection() -> Dictionary:
	var out: Dictionary = {}
	if FileAccess.file_exists(SELECTION):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SELECTION))
		if data is Dictionary:
			for f: Variant in (data as Dictionary).get("keep", []):
				out[str(f)] = true
	return out


func _process(_delta: float) -> void:
	if _shot_path == "":
		return
	_frames -= 1
	if _frames == 0:
		get_viewport().get_texture().get_image().save_png(_shot_path)
		get_tree().quit()
