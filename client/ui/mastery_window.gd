class_name MasteryWindow
extends PanelContainer
## Árvore de maestria (K): três colunas (Ataque, Defesa, Utilidade). Cada nó mostra os pontos,
## o máximo e o bônus; clique põe 1 ponto (o servidor confere pontos livres e pré-requisitos).

var GOLD: Color = UiPalette.c("gold")
var TEXT: Color = UiPalette.c("bone")
var DIM: Color = UiPalette.c("bone_dim")

var mastery: Dictionary = {}
var free_points: int = 0
var master_level: int = 0
var master_xp: int = 0
var master_next: int = 0

var _cfg: Dictionary
var _nodes: Dictionary
var _header: Label
var _columns: HBoxContainer


func _ready() -> void:
	_cfg = GameConfig.table("mastery")
	_nodes = MasterySystem.index_nodes(_cfg)
	theme_type_variation = &"WindowPanel"
	position = Vector2(306, 110) # ao lado da janela de atributos (C)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title := _label("MAESTRIA", 16, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(hide)
	top.add_child(close)
	_header = _label("", 12, TEXT)
	_header.theme_type_variation = &"LoreLabel"
	_header.custom_minimum_size = Vector2(650, 0)
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_header)
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 14)
	box.add_child(_columns)
	visible = false
	Net.mastery_state_received.connect(func(m: Dictionary) -> void:
		mastery = m
		_rebuild())
	_rebuild()


func toggle() -> void:
	visible = not visible
	if visible:
		_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()


## Do estado do jogador (PS): nível, XP e pontos livres de maestria.
func set_progress(level: int, xp: int, next: int, points: int) -> void:
	var changed := level != master_level or points != free_points
	master_level = level
	master_xp = xp
	master_next = next
	free_points = points
	if visible:
		if changed:
			_rebuild()
		else:
			_update_header()


func _update_header() -> void:
	var max_level := int(GameConfig.table("progression")["max_level"])
	if master_level == 0 and master_next == 0:
		_header.text = "A maestria começa no nível %d: a XP passa a encher níveis de maestria, e cada um dá %d ponto." % [max_level, int(_cfg["points_per_level"])]
	else:
		_header.text = "Maestria %d · XP %d / %d · pontos livres: %d" % [master_level, master_xp, master_next, free_points]


func _rebuild() -> void:
	if _columns == null:
		return
	_update_header()
	for c in _columns.get_children():
		c.queue_free()
	for tree: Dictionary in _cfg["trees"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.custom_minimum_size = Vector2(220, 0)
		_columns.add_child(col)
		var color := GameConfig.color_of(tree["color"])
		var spent := 0
		for n: Dictionary in tree["nodes"]:
			spent += int(mastery.get(str(n["id"]), 0))
		var head := _label("%s · %d" % [str(tree["name"]).to_upper(), spent], 14, color)
		head.theme_type_variation = &"HeaderLabel"
		head.add_theme_color_override("font_color", color)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.custom_minimum_size = Vector2(0, 30)
		col.add_child(head)
		var nodes: Array = tree["nodes"]
		for i in nodes.size():
			var n: Dictionary = nodes[i]
			var id := str(n["id"])
			var pts := int(mastery.get(id, 0))
			var why := MasterySystem.can_spend(mastery, id, _nodes, maxi(free_points, 1))
			var b := MasteryNode.new()
			b.color = color
			b.points = pts
			b.max_points = int(n["max"])
			b.title = str(n["name"])
			var value := float(n["per_point"]) * maxi(pts, 1) * float(n["scale"])
			var shown := str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
			b.detail = str(n["text"]) % shown
			b.first = i == 0
			b.last = i == nodes.size() - 1
			b.tooltip_text = "Por ponto: %s" % (str(n["text"]) % ("%.1f" % (float(n["per_point"]) * float(n["scale"]))).trim_suffix(".0"))
			var reqs: Array = n.get("requires", [])
			if not reqs.is_empty():
				b.tooltip_text += "
Exige %d pontos em %s." % [int(reqs[0][1]), _nodes.get(str(reqs[0][0]), {}).get("name", "?")]
			b.disabled = why != "" or free_points <= 0
			b.pressed.connect(Net.send_mastery_spend.bind(id))
			col.add_child(b)
	_shrink.call_deferred()


## As linhas com quebra só sabem a altura depois de um quadro: encolhe ao conteúdo.
func _shrink() -> void:
	await get_tree().process_frame
	size = Vector2.ZERO


## Nó da trilha: losango com os pontos, nome, bônus e barra fina de progresso (pontos/máximo).
## Ligado ao nó de cima e de baixo por um fio na cor da trilha; brilha quando aceita um ponto.
class MasteryNode extends Button:
	var color: Color
	var points: int
	var max_points: int
	var title: String
	var detail: String
	var first: bool
	var last: bool

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(220, 58)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _process(_d: float) -> void:
		if not disabled and visible:
			queue_redraw() # pulso do nó disponível

	func _draw() -> void:
		var r := 15.0
		var ct := Vector2(22, size.y * 0.5)
		var wire := Color(color, 0.35 if points > 0 else 0.15)
		if not first:
			draw_line(Vector2(ct.x, 0), ct - Vector2(0, r + 2), wire, 2.0)
		if not last:
			draw_line(ct + Vector2(0, r + 2), Vector2(ct.x, size.y), wire, 2.0)
		var hover := is_hovered() and not disabled
		if not disabled:
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
			_diamond(ct, r + 4 + pulse * 2.0, Color(UiPalette.c("ember"), 0.18 + 0.2 * pulse), true)
		_diamond(ct, r, UiPalette.c("well", 0.95), true)
		if points > 0:
			_diamond(ct, r - 3, Color(color, 0.3 + 0.5 * float(points) / maxf(max_points, 1)), true)
		var edge := UiPalette.c("ember") if hover else (color if points > 0 else UiPalette.c("gold_dim"))
		_diamond(ct, r, edge, false)
		var nf := UiPalette.font("body_bold")
		var num := str(points)
		var nw := nf.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(nf, ct + Vector2(-nw * 0.5, 5), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiPalette.c("bone") if points > 0 else UiPalette.c("bone_dim"))
		var x := 46.0
		var tf := UiPalette.font("body_bold")
		var maxed := points >= max_points
		var name_col := color if points > 0 else (UiPalette.c("bone") if not disabled else UiPalette.c("bone_dim"))
		draw_string(tf, Vector2(x, 19), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 34, 13, name_col)
		var cnt := "%d/%d" % [points, max_points]
		var cw := tf.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(tf, Vector2(size.x - cw - 2, 19), cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiPalette.c("gold") if maxed else UiPalette.c("bone_dim"))
		draw_string(UiPalette.font("body"), Vector2(x, 35), detail, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 2, 11, UiPalette.c("bone_dim"))
		var bar := Rect2(x, 42, size.x - x - 2, 3)
		draw_rect(bar, UiPalette.c("well"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(points) / maxf(max_points, 1), bar.size.y)), color)

	func _diamond(ct: Vector2, r: float, col: Color, filled: bool) -> void:
		var pts := PackedVector2Array([ct + Vector2(0, -r), ct + Vector2(r, 0), ct + Vector2(0, r), ct + Vector2(-r, 0)])
		if filled:
			draw_colored_polygon(pts, col)
		else:
			pts.append(pts[0])
			draw_polyline(pts, col, 1.5, true)


static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if font_size >= 16: # títulos e cabeçalhos em Cinzel (tema)
		l.theme_type_variation = &"TitleLabel"
	return l
