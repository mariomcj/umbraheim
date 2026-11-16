class_name JournalView
extends Control
## Uma "janela" sobre a folha do diário: o minimapa (segue o jogador, com zoom)
## ou o diário aberto em tela cheia (folha inteira). O papel e o grafite vêm do
## shader journal_paper; rótulos e a seta de posição (estilo GPS) são desenhados por cima (Overlay),
## fora da textura acumulativa, porque mudam a cada frame.

const PAPER_SHADER := preload("res://assets/shaders/journal_paper.gdshader")
const INK_COLOR := Color(0.17, 0.15, 0.14, 0.88)


class Overlay extends Control:
	var view: JournalView

	func _draw() -> void:
		var journal := view.journal
		var rect := view.view_rect_px()
		var scale := size.x / rect.size.x
		var font := ThemeDB.fallback_font
		var now := float(Time.get_ticks_msec())
		for label: Dictionary in journal.labels:
			var chars := int((now - float(label["start_ms"])) / 1000.0 * journal.label_chars_per_s)
			if chars <= 0:
				continue
			var text: String = str(label["text"]).left(chars)
			var font_px := int(label["size"])
			var at: Vector2 = (Vector2(label["pos"]) - rect.position) * scale
			# letra levemente inclinada, como escrita à mão
			draw_set_transform(at, -0.04, Vector2(1.0, 1.0))
			draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, INK_COLOR)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		if journal.marker_visible:
			_draw_gps_arrow((journal.marker_px - rect.position) * scale, journal.marker_dir, now)

	## Seta de navegação (estilo GPS) centrada na posição do jogador, apontando para
	## onde ele olha, com um halo pulsando por baixo. Cores em data/config/journal.json.
	func _draw_gps_arrow(center: Vector2, dir: Vector2, now_ms: float) -> void:
		var d := dir.normalized() if dir.length() > 0.01 else Vector2.UP
		var n := Vector2(-d.y, d.x)
		var s := view.journal.marker_size_px
		var fill: Color = view.journal.marker_color
		var pulse := 0.5 + 0.5 * sin(now_ms * 0.004)
		draw_circle(center, s * (1.6 + 0.35 * pulse), Color(fill, 0.12 + 0.1 * (1.0 - pulse)))
		draw_circle(center, s * 1.15, Color(fill, 0.22))
		var tip := center + d * s * 1.2
		var left := center - d * s * 0.85 + n * s * 0.95
		var notch := center - d * s * 0.3
		var right := center - d * s * 0.85 - n * s * 0.95
		var arrow := PackedVector2Array([tip, left, notch, right])
		draw_colored_polygon(arrow, fill)
		# metade mais clara dá volume, como nas setas de navegação
		draw_colored_polygon(PackedVector2Array([tip, notch, right]), fill.lightened(0.25))
		arrow.append(tip)
		draw_polyline(arrow, view.journal.marker_outline, 2.0, true)


var journal: JournalMap
var zoom: float = 1.0
var follow_player: bool = false

var _material: ShaderMaterial
var _overlay: Overlay


func setup(map: JournalMap, ink: Texture2D, view_zoom: float, follow: bool, block_mouse: bool) -> void:
	journal = map
	zoom = view_zoom
	follow_player = follow
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP if block_mouse else Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = PAPER_SHADER
	_material.set_shader_parameter("ink_tex", ink)
	_material.set_shader_parameter("paper_px", float(map.paper_size))
	var paper := ColorRect.new()
	paper.material = _material
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(paper)
	_overlay = Overlay.new()
	_overlay.view = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)


## Área da folha (em px do papel) mostrada nesta janela. Norte sempre para cima.
func view_rect_px() -> Rect2:
	var paper := float(journal.paper_size)
	var side := paper / zoom
	var center := journal.marker_px if follow_player else Vector2(paper, paper) * 0.5
	var origin := (center - Vector2(side, side) * 0.5).clamp(Vector2.ZERO, Vector2(paper - side, paper - side))
	return Rect2(origin, Vector2(side, side))


## Rótulos da folha antiga, congelados, desenhados sobre a página que vira.
class PageLabels extends Control:
	var labels: Array = []
	var rect: Rect2

	func _draw() -> void:
		var scale := size.x / rect.size.x
		for label: Dictionary in labels:
			draw_set_transform((Vector2(label["pos"]) - rect.position) * scale, -0.04, Vector2.ONE)
			draw_string(ThemeDB.fallback_font, Vector2.ZERO, str(label["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(label["size"]), INK_COLOR)


## Virada de página: a folha antiga (cópia da tinta e dos rótulos) fica por cima e
## "vira" para a esquerda, como num caderno, revelando a folha nova por baixo.
func flip_from(old_ink: Texture2D, old_labels: Array, old_rect: Rect2, duration: float) -> void:
	var page := ColorRect.new()
	var mat := _material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("ink_tex", old_ink)
	mat.set_shader_parameter("view_origin", old_rect.position / float(journal.paper_size))
	mat.set_shader_parameter("view_size", old_rect.size / float(journal.paper_size))
	page.material = mat
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page) # por cima do papel e dos rótulos novos
	page.position = Vector2.ZERO
	page.size = size
	var texts := PageLabels.new()
	texts.labels = old_labels
	texts.rect = old_rect
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.position = Vector2.ZERO
	texts.size = size
	page.add_child(texts)
	page.pivot_offset = Vector2(0.0, size.y * 0.5)
	var shade := ColorRect.new() # sombra que escurece a página enquanto ela dobra
	shade.color = Color(0, 0, 0, 0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(shade)
	var t := page.create_tween()
	t.set_parallel(true)
	t.tween_property(page, "scale:x", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(page, "scale:y", 1.04, duration * 0.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(shade, "color:a", 0.45, duration).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(page.queue_free)


func _process(_delta: float) -> void:
	if not visible:
		return
	var rect := view_rect_px()
	var paper := float(journal.paper_size)
	_material.set_shader_parameter("view_origin", rect.position / paper)
	_material.set_shader_parameter("view_size", rect.size / paper)
	_overlay.queue_redraw()
