class_name GuildSymbolEditor
extends VBoxContainer
## Editor de pixels do símbolo da guilda: grade size x size, paleta embaixo.
## Botão esquerdo pinta com a cor escolhida (arrastando pinta vários), direito apaga.

signal changed(symbol: String)

const CELL := 18.0

class Canvas extends Control:
	var editor: GuildSymbolEditor

	func _draw() -> void:
		editor._draw_canvas(self)

	func _gui_input(event: InputEvent) -> void:
		editor._canvas_input(self, event)


var symbol: String
var selected: int = 2
var _canvas: Canvas
var _swatches: Array[Button] = []
var _painting: int = -1 # cor sendo arrastada (-1 = nenhuma)
var _preview: TextureRect


func _ready() -> void:
	symbol = GuildSymbol.empty_symbol()
	add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	_canvas = Canvas.new()
	_canvas.editor = self
	_canvas.custom_minimum_size = Vector2.ONE * CELL * GuildSymbol.size()
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(_canvas)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	row.add_child(side)
	var hint := Label.new()
	hint.text = "Esquerdo: pinta\nDireito: apaga\n\nComo fica:"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52))
	side.add_child(hint)
	_preview = GuildSymbol.rect(symbol, 32.0)
	side.add_child(_preview)
	var clear := Button.new()
	clear.text = "Limpar"
	clear.add_theme_font_size_override("font_size", 11)
	clear.pressed.connect(func() -> void: set_symbol(GuildSymbol.empty_symbol()))
	side.add_child(clear)
	var pal := GridContainer.new()
	pal.columns = 8
	pal.add_theme_constant_override("h_separation", 3)
	pal.add_theme_constant_override("v_separation", 3)
	add_child(pal)
	var colors := GuildSymbol.palette()
	for i in range(1, colors.size()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(20, 20)
		b.toggle_mode = true
		b.button_pressed = i == selected
		var sb := StyleBoxFlat.new()
		sb.bg_color = colors[i]
		sb.set_border_width_all(1)
		sb.border_color = Color(0.3, 0.27, 0.2)
		var sel := sb.duplicate() as StyleBoxFlat
		sel.set_border_width_all(3)
		sel.border_color = Color(1.0, 0.85, 0.4)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sel)
		b.add_theme_stylebox_override("hover_pressed", sel)
		b.pressed.connect(_pick.bind(i))
		pal.add_child(b)
		_swatches.append(b)


func set_symbol(s: String) -> void:
	symbol = s if s.length() == GuildSymbol.size() * GuildSymbol.size() else GuildSymbol.empty_symbol()
	_refresh()


func filled() -> int:
	return symbol.length() - symbol.count("0")


func _pick(i: int) -> void:
	selected = i
	for k in _swatches.size():
		_swatches[k].set_pressed_no_signal(k + 1 == i)


func _refresh() -> void:
	_canvas.queue_redraw()
	_preview.texture = GuildSymbol.texture(symbol)
	changed.emit(symbol)


func _draw_canvas(c: Control) -> void:
	var n := GuildSymbol.size()
	var colors := GuildSymbol.palette()
	for y in n:
		for x in n:
			var r := Rect2(Vector2(x, y) * CELL, Vector2.ONE * CELL)
			var v := GuildSymbol.pixel(symbol, x, y)
			if v == 0: # xadrez = transparente
				c.draw_rect(r, Color(0.16, 0.15, 0.15) if (x + y) % 2 == 0 else Color(0.12, 0.11, 0.11))
			else:
				c.draw_rect(r, colors[v])
	for i in n + 1:
		c.draw_line(Vector2(i * CELL, 0), Vector2(i * CELL, n * CELL), Color(0, 0, 0, 0.35))
		c.draw_line(Vector2(0, i * CELL), Vector2(n * CELL, i * CELL), Color(0, 0, 0, 0.35))
	c.draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * n * CELL), Color(0.5, 0.42, 0.25), false, 1.0)


func _canvas_input(_c: Control, event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			_painting = selected if mb.button_index == MOUSE_BUTTON_LEFT else 0
			_paint_at(mb.position)
		elif not mb.pressed:
			_painting = -1
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _painting >= 0:
		_paint_at(mm.position)


func _paint_at(pos: Vector2) -> void:
	var n := GuildSymbol.size()
	var x := int(pos.x / CELL)
	var y := int(pos.y / CELL)
	if x < 0 or y < 0 or x >= n or y >= n or GuildSymbol.pixel(symbol, x, y) == _painting:
		return
	symbol = GuildSymbol.with_pixel(symbol, x, y, _painting)
	_refresh()
