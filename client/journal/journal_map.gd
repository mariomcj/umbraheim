class_name JournalMap
extends Node
## Mapa-diário a lápis — sistema central do jogo (seção 5 da especificação).
##
## O servidor manda as amostras do caminho e as marcações; aqui elas viram desenho:
## - traço de grafite com a ponta do lápis avançando aos poucos (GraphiteBrush numa
##   SubViewport acumulativa: o que já foi desenhado fica assado na textura);
## - símbolos traçados traço a traço (data/journal/symbols.json);
## - nomes escritos letra por letra;
## - seta de posição estilo GPS (norte sempre para cima); M oculta o minimapa.
## Não existe nenhuma outra fonte de informação espacial: o que não foi percorrido não está no papel.

var paper_size: int
var region_name: String = ""

## Rótulos escritos à mão: { pos: Vector2 (px), text: String, start_ms: float, size: int }
var labels: Array[Dictionary] = []
## Posição suavizada da seta de posição (px) e direção no papel.
var marker_px: Vector2 = Vector2.ZERO
var marker_dir: Vector2 = Vector2.UP
var marker_visible: bool = false
## Seta de posição (estilo GPS) — data/config/journal.json.
var marker_size_px: float = 9.0
var marker_color: Color = Color.RED
var marker_outline: Color = Color.WHITE
var label_chars_per_s: float

var _region_id: String = ""
var _px_per_m: float = 10.0
var _viewport: SubViewport
var _brush: GraphiteBrush
var _mini: JournalView
var _full: JournalView
var _dim: ColorRect

# ponta do lápis (caminho)
var _queue := PackedVector2Array()
var _tip := Vector2.ZERO
var _tip_valid := false
var _ink_dist := 0.0
var _pencil_speed: float
var _catchup_px: float
var _marker_sharpness: float
var _player_px := Vector2.ZERO
var _player_known := false

# marcações em andamento: { strokes: Array[PackedVector2Array], index: int, t: float, label: String, label_pos: Vector2 }
var _mark_jobs: Array[Dictionary] = []
var _mark_size: float
var _mark_stroke_s: float
var _label_font: int
var _title_font: int


func _ready() -> void:
	paper_size = GameConfig.get_i("journal", "paper_size_px")
	_pencil_speed = GameConfig.get_f("journal", "pencil_speed_px_s")
	_catchup_px = GameConfig.get_f("journal", "pencil_catchup_px")
	_marker_sharpness = GameConfig.get_f("journal", "marker_follow_sharpness")
	marker_size_px = GameConfig.get_f("journal", "marker_size_px")
	marker_color = GameConfig.color_of(GameConfig.get_value("journal", "marker_color"), Color.RED)
	marker_outline = GameConfig.color_of(GameConfig.get_value("journal", "marker_outline"), Color.WHITE)
	_mark_size = GameConfig.get_f("journal", "mark_size_px")
	_mark_stroke_s = GameConfig.get_f("journal", "mark_stroke_duration_s")
	label_chars_per_s = GameConfig.get_f("journal", "label_chars_per_s")
	_label_font = GameConfig.get_i("journal", "label_font_px")
	_title_font = GameConfig.get_i("journal", "title_font_px")

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(paper_size, paper_size)
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_brush = GraphiteBrush.new()
	_viewport.add_child(_brush)
	_brush.setup(_viewport)
	_brush.clear_ink()

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var mini_size := GameConfig.get_f("journal", "minimap_size_px")
	_mini = JournalView.new()
	_mini.setup(self, _viewport.get_texture(), GameConfig.get_f("journal", "minimap_zoom"), true, false)
	_mini.anchor_left = 1.0
	_mini.anchor_right = 1.0
	_mini.offset_left = -mini_size - 16.0
	_mini.offset_right = -16.0
	_mini.offset_top = 16.0
	_mini.offset_bottom = 16.0 + mini_size
	_mini.rotation = 0.025 # folha levemente torta sobre a "mesa"
	layer.add_child(_mini)
	# ocultar/mostrar o minimapa: × no canto da folha, botão "Mapa" quando oculto, tecla M
	var hide_button := Button.new()
	hide_button.text = "×"
	hide_button.tooltip_text = "Ocultar o minimapa (M)"
	hide_button.flat = true
	hide_button.add_theme_color_override("font_color", Color(0.25, 0.2, 0.17))
	hide_button.add_theme_color_override("font_hover_color", Color(0.6, 0.12, 0.1))
	hide_button.add_theme_font_size_override("font_size", 18)
	hide_button.anchor_left = 1.0
	hide_button.anchor_right = 1.0
	hide_button.offset_left = -26.0
	hide_button.offset_right = -2.0
	hide_button.offset_top = 0.0
	hide_button.offset_bottom = 24.0
	hide_button.pressed.connect(toggle_minimap)
	_mini.add_child(hide_button)
	_show_button = Button.new()
	_show_button.text = "Mapa (M)"
	_show_button.tooltip_text = "Mostrar o minimapa"
	_show_button.anchor_left = 1.0
	_show_button.anchor_right = 1.0
	_show_button.offset_left = -100.0
	_show_button.offset_right = -16.0
	_show_button.offset_top = 16.0
	_show_button.offset_bottom = 46.0
	_show_button.pressed.connect(toggle_minimap)
	layer.add_child(_show_button)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		_mini_hidden_by_user = bool(cfg.get_value("ui", "minimap_hidden", false))
	if "--minimap-hidden" in OS.get_cmdline_user_args(): # debug: oculto sem salvar a preferência
		_mini_hidden_by_user = true
	elif "--minimap-shown" in OS.get_cmdline_user_args():
		_mini_hidden_by_user = false
	_apply_visibility()

	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	layer.add_child(_dim)
	_full = JournalView.new()
	_full.setup(self, _viewport.get_texture(), 1.0, false, true)
	_full.visible = false
	layer.add_child(_full)
	get_viewport().size_changed.connect(_layout_full)
	_layout_full()
	_apply_visibility()


## Afasta o minimapa da borda direita (ex.: para não ficar atrás do inventário).
func set_minimap_right_margin(px: float) -> void:
	var w := _mini.offset_right - _mini.offset_left
	_mini.offset_right = -16.0 - px
	_mini.offset_left = _mini.offset_right - w
	_mini_hidden_by_ui = px + w + 32.0 > get_viewport().get_visible_rect().size.x * 0.62 # sem espaço: some até a janela fechar
	_apply_visibility()


var _mini_hidden_by_ui: bool = false
var _mini_hidden_by_user: bool = false
var _show_button: Button
const SETTINGS_PATH := "user://client.cfg"
var _full_open: bool = false
var _world_on: bool = true # fora do mundo (tela de login) o diário some


func is_full_open() -> bool:
	return _full_open and _world_on


signal page_turned # som de página ao abrir e fechar o diário


func toggle_full() -> void:
	page_turned.emit()
	_full_open = not _full_open
	_apply_visibility()


## Esconde tudo enquanto não há personagem no mundo (login, reconexão).
func set_world_visible(on: bool) -> void:
	_world_on = on
	_apply_visibility()


## Oculta ou mostra o minimapa (o diário em tela cheia continua no J). A escolha fica salva.
func toggle_minimap() -> void:
	_mini_hidden_by_user = not _mini_hidden_by_user
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # mantém o que já houver (ex.: última conta usada)
	cfg.set_value("ui", "minimap_hidden", _mini_hidden_by_user)
	cfg.save(SETTINGS_PATH)
	_apply_visibility()


func is_minimap_hidden() -> bool:
	return _mini_hidden_by_user


## Painel que aparece ao lado do diário aberto (ex.: Viajar).
func add_full_side(panel: Control) -> void:
	_full_side = panel
	_full.get_parent().add_child(panel)
	_layout_full()
	_apply_visibility()


var _full_side: Control = null


func _apply_visibility() -> void:
	if _full == null or _show_button == null:
		return # ainda montando a tela (_ready); o estado é aplicado no fim
	_full.visible = _world_on and _full_open
	if _full_side != null:
		_full_side.visible = _full.visible
	_dim.visible = _full.visible
	var free := _world_on and not _full_open and not _mini_hidden_by_ui
	_mini.visible = free and not _mini_hidden_by_user
	_show_button.visible = free and _mini_hidden_by_user


func _unhandled_input(event: InputEvent) -> void:
	if not _world_on:
		return
	if event.is_action_pressed("toggle_journal") or (_full_open and event.is_action_pressed("ui_cancel")):
		toggle_full()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_minimap") and not _full_open:
		toggle_minimap()
		get_viewport().set_input_as_handled()


func _layout_full() -> void:
	var vp := get_viewport().get_visible_rect().size
	var side := vp.y * GameConfig.get_f("journal", "full_view_height_ratio")
	_full.position = (vp - Vector2(side, side)) / 2.0
	_full.size = Vector2(side, side)
	if _full_side != null:
		_full_side.position = Vector2(minf(_full.position.x + side + 16.0, vp.x - 260.0), _full.position.y + 20.0)


# ---------------------------------------------------------------- conversões

func world_to_px(world: Vector2) -> Vector2:
	# norte (-Z) para cima, leste (+X) para a direita; centro da folha = origem do mundo
	return world * _px_per_m + Vector2(paper_size, paper_size) * 0.5


# ---------------------------------------------------------------- entrada de dados (servidor)

## Abre a folha de uma região. Se já for a atual, não faz nada.
func set_region(region_id: String) -> void:
	if region_id == _region_id:
		return
	_region_id = region_id
	var data := GameConfig.region(region_id)
	_px_per_m = float(data.get("paper_px_per_m", 10.0))
	_brush.tremor = float(data.get("ink_tremor", 1.0))
	region_name = str(data.get("name", region_id))
	_brush.clear_ink()
	_queue.clear()
	_mark_jobs.clear()
	_tip_valid = false
	_ink_dist = 0.0
	labels.clear()
	# título da folha, escrito à mão no topo
	labels.append({"pos": Vector2(paper_size * 0.08, paper_size * 0.12), "text": region_name, "start_ms": Time.get_ticks_msec(), "size": _title_font})


## Estado completo da folha: desenha tudo de uma vez (sem animação).
func load_full(region_id: String, strokes: Array, marks: Array) -> void:
	# trocou de região: guarda a folha atual para a animação de virar a página
	var old_ink: Texture2D = null
	var old_labels: Array = []
	var mini_rect := _mini.view_rect_px()
	var full_rect := _full.view_rect_px()
	if _region_id != "" and _region_id != region_id:
		_brush.flush()
		old_ink = ImageTexture.create_from_image(_viewport.get_texture().get_image())
		old_labels = labels.duplicate(true)
	_region_id = ""
	set_region(region_id)
	if old_ink != null:
		var duration := GameConfig.get_f("journal", "page_turn_s")
		_mini.flip_from(old_ink, old_labels, mini_rect, duration)
		_full.flip_from(old_ink, old_labels, full_rect, duration)
	labels[0]["start_ms"] = -1.0e9
	for stroke: PackedVector2Array in strokes:
		var prev := Vector2.ZERO
		for i in stroke.size():
			var p := world_to_px(stroke[i])
			if i > 0:
				_ink_dist = _brush.segment(prev, p, _ink_dist)
			prev = p
		if not stroke.is_empty():
			_tip = prev
			_tip_valid = true
	for mark: Array in marks:
		var job := _make_mark_job(str(mark[0]), Vector2(float(mark[1]), float(mark[2])), str(mark[3]))
		for s: PackedVector2Array in job["strokes"]:
			_draw_polyline_range(s, 0.0, INF)
		_add_label(job, -1.0e9)
	_brush.flush()


func add_point(region_id: String, world: Vector2, new_stroke: bool) -> void:
	if region_id != _region_id:
		return
	var p := world_to_px(world)
	if new_stroke or not _tip_valid:
		_finish_queue_instantly()
		_tip = p
		_tip_valid = true
		return
	_queue.append(p)


func add_mark(region_id: String, symbol: String, world: Vector2, label: String) -> void:
	if region_id == _region_id:
		_mark_jobs.append(_make_mark_job(symbol, world, label))


func set_player(world: Vector2, yaw: float) -> void:
	_player_px = world_to_px(world)
	marker_dir = Vector2(sin(yaw), cos(yaw)) # yaw 0 = +Z = sul = para baixo no papel
	if not _player_known:
		marker_px = _player_px
		_player_known = true
	marker_visible = true


# ---------------------------------------------------------------- animação

func _process(delta: float) -> void:
	_advance_pencil(delta)
	_advance_marks(delta)
	_brush.flush()
	# a seta acompanha a ponta enquanto desenha e o jogador quando parado
	var target := _tip if not _queue.is_empty() else _player_px
	marker_px = marker_px.lerp(target, 1.0 - exp(-_marker_sharpness * delta))


func _advance_pencil(delta: float) -> void:
	if _queue.is_empty():
		return
	var remaining := _tip.distance_to(_queue[0])
	for i in range(1, _queue.size()):
		remaining += _queue[i - 1].distance_to(_queue[i])
	var budget := _pencil_speed * delta
	if remaining > _catchup_px:
		budget *= remaining / _catchup_px # não deixa o lápis ficar para trás
	while budget > 0.0 and not _queue.is_empty():
		var target := _queue[0]
		var d := _tip.distance_to(target)
		if d <= budget:
			_ink_dist = _brush.segment(_tip, target, _ink_dist)
			_tip = target
			_queue.remove_at(0)
			budget -= d
		else:
			var np := _tip.move_toward(target, budget)
			_ink_dist = _brush.segment(_tip, np, _ink_dist)
			_tip = np
			budget = 0.0


func _finish_queue_instantly() -> void:
	for p in _queue:
		_ink_dist = _brush.segment(_tip, p, _ink_dist)
		_tip = p
	_queue.clear()


func _advance_marks(delta: float) -> void:
	if _mark_jobs.is_empty():
		return
	var job := _mark_jobs[0]
	var strokes: Array = job["strokes"]
	var stroke: PackedVector2Array = strokes[job["index"]]
	var total := _polyline_length(stroke)
	var t0: float = job["t"]
	var t1 := minf(1.0, t0 + delta / _mark_stroke_s)
	_draw_polyline_range(stroke, t0 * total, t1 * total)
	job["t"] = t1
	if t1 >= 1.0:
		job["t"] = 0.0
		job["index"] = int(job["index"]) + 1
		if job["index"] >= strokes.size():
			_add_label(job, Time.get_ticks_msec())
			_mark_jobs.remove_at(0)


func _make_mark_job(symbol: String, world: Vector2, label: String) -> Dictionary:
	var center := world_to_px(world)
	var symbol_strokes: Array = GameConfig.journal_symbols().get(symbol, [])
	# leve rotação e escala "de mão", determinísticas pela posição
	var hand := GraphiteBrush._hash(center.x * 0.37 + center.y * 1.91)
	var xf := Transform2D((hand - 0.5) * 0.5, Vector2.ONE * _mark_size * (0.9 + hand * 0.25), 0.0, center)
	var strokes: Array[PackedVector2Array] = []
	for raw: Array in symbol_strokes:
		var poly := PackedVector2Array()
		for pt: Array in raw:
			poly.append(xf * Vector2(float(pt[0]), float(pt[1])))
		strokes.append(poly)
	if strokes.is_empty():
		push_error("JournalMap: símbolo desconhecido '%s'" % symbol)
	return {"strokes": strokes, "index": 0, "t": 0.0, "label": label,
		"label_pos": center + Vector2(_mark_size * 1.4, _mark_size * 0.4)}


## Adiciona o rótulo de uma marcação; se encostar em outro, desce uma linha
## (como alguém que escreve embaixo para não rabiscar por cima).
func _add_label(job: Dictionary, start_ms: float) -> void:
	var text := str(job["label"])
	if text.is_empty():
		return
	var line_px := float(_label_font) * 1.1 * (float(paper_size) / 600.0)
	var pos: Vector2 = job["label_pos"]
	var box := _label_box(pos, text, line_px)
	for attempt in 6:
		var hit := false
		for other: Dictionary in labels:
			if box.intersects(_label_box(other["pos"], str(other["text"]), line_px)):
				hit = true
				break
		if not hit:
			break
		pos.y += line_px
		box = _label_box(pos, text, line_px)
	labels.append({"pos": pos, "text": text, "start_ms": start_ms, "size": _label_font})


## Caixa aproximada do rótulo em px do papel (a fonte tem tamanho fixo na tela;
## usa a escala do diário aberto, a mais apertada).
func _label_box(pos: Vector2, text: String, line_px: float) -> Rect2:
	return Rect2(pos - Vector2(0.0, line_px * 0.8), Vector2(text.length() * line_px * 0.5, line_px))


## Desenha o trecho da polilinha entre as distâncias `from_len` e `to_len`.
func _draw_polyline_range(poly: PackedVector2Array, from_len: float, to_len: float) -> void:
	var acc := 0.0
	for i in range(1, poly.size()):
		var a := poly[i - 1]
		var b := poly[i]
		var seg := a.distance_to(b)
		var s0 := maxf(from_len, acc)
		var s1 := minf(to_len, acc + seg)
		if s1 > s0 and seg > 0.0:
			_brush.segment(a.lerp(b, (s0 - acc) / seg), a.lerp(b, (s1 - acc) / seg), s0 + float(i) * 31.0, 1.25)
		acc += seg
		if acc >= to_len:
			break


static func _polyline_length(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, poly.size()):
		total += poly[i - 1].distance_to(poly[i])
	return total
