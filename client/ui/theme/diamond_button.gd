class_name DiamondButton
extends Button
## Botão em losango (docs/design/PROPOSTA_UI.md 2.4): filete dourado, interior escuro e um glifo no centro
## (inicial ou símbolo). Hover acende o filete e um brilho âmbar; "selected" pinta o filete com accent.
## Com badge, escreve um texto pequeno embaixo (ex.: quantidade de poções). Também serve como ícone
## sem clique (mouse_filter = IGNORE).

var glyph: String = "":
	set(v):
		glyph = v
		queue_redraw()
var accent: Color = Color.TRANSPARENT: ## cor do glifo e do filete quando selecionado (vazio = dourado)
	set(v):
		accent = v
		queue_redraw()
var badge: String = "":
	set(v):
		badge = v
		queue_redraw()
var selected: bool = false:
	set(v):
		selected = v
		queue_redraw()
var glyph_font: String = "title": ## papel da fonte do glifo (números leem melhor em "body_bold")
	set(v):
		glyph_font = v
		queue_redraw()
var icon_id: String = "": ## ícone desenhado (UiIcons); vence o glifo quando existe
	set(v):
		icon_id = v
		queue_redraw()
var dimmed: bool = false: ## desligado sem ser "disabled" (ex.: sem poções)
	set(v):
		dimmed = v
		queue_redraw()


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	text = ""
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 1.0
	var hover := is_hovered() and not disabled
	var gold := UiPalette.c("gold")
	var edge := (accent if accent.a > 0.0 else gold) if (selected or hover) else UiPalette.c("gold_dim")
	if disabled or dimmed:
		edge = Color(edge, 0.45)
	var pts := _diamond(c, r)
	var inner := UiPalette.c("ink", 0.92)
	if is_pressed() or button_pressed:
		inner = UiPalette.c("well", 0.95)
	draw_colored_polygon(pts, inner)
	if hover or selected:
		draw_colored_polygon(_diamond(c, r * 0.78), UiPalette.c("ember", 0.18) if hover else Color(edge, 0.14))
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, edge, 1.5 if not selected else 2.0, true)
	draw_polyline(_closed(_diamond(c, r - 3.0)), Color(edge, 0.3), 1.0, true)
	if icon_id != "" and UiIcons.has(icon_id):
		var ic := (accent if accent.a > 0.0 else UiPalette.c("bone")) if not (disabled or dimmed) else UiPalette.c("bone_dim", 0.6)
		if hover:
			ic = ic.lightened(0.2)
		UiIcons.draw(self, icon_id, c, r * 0.48, ic)
	elif glyph != "":
		var font := UiPalette.font(glyph_font)
		var fs := int(r * 0.85)
		var tw := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		while tw.x > r * 1.15 and fs > 8: # números longos (nível 400) encolhem para caber no losango
			fs -= 1
			tw = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var col := (accent if accent.a > 0.0 else UiPalette.c("bone")) if not (disabled or dimmed) else UiPalette.c("bone_dim", 0.6)
		var at := c + Vector2(-tw.x * 0.5, font.get_ascent(fs) * 0.5 - 1.0)
		draw_string_outline(font, at, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
		draw_string(font, at, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if badge != "":
		var bf := UiPalette.font("body_bold")
		var bs := UiPalette.size("hint")
		var bw := bf.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bs)
		var bp := Vector2(c.x - bw.x * 0.5, size.y + bs - 2.0)
		draw_string_outline(bf, bp, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, 4, Color(0, 0, 0, 0.9))
		draw_string(bf, bp, badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, UiPalette.c("bone") if not dimmed else UiPalette.c("bone_dim"))


func _has_point(point: Vector2) -> bool:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	return absf(point.x - c.x) + absf(point.y - c.y) <= r # só o losango pega o clique


static func _diamond(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out
