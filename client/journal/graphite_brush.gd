class_name GraphiteBrush
extends Node2D
## Pincel de grafite. Vive dentro de uma SubViewport que NÃO é limpa entre frames:
## cada pedacinho de traço é desenhado uma única vez e fica "assado" na textura.
## Assim o custo é constante mesmo depois de horas de caminhada, e passar de novo
## pelo mesmo lugar soma alfa (o traço escurece, como grafite acumulado).
##
## O traço é feito de "carimbos" curtos ao longo do caminho, cada um com pressão,
## tremor e ondulação próprios. O ruído depende só da distância acumulada, então
## redesenhar o mesmo caminho produz o mesmo traço.

var spacing: float
var width: float
var alpha: float
var jitter: float
var wobble: float
var tremor: float = 1.0

var _viewport: SubViewport
var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _draw_points := PackedVector2Array()
var _draw_colors := PackedColorArray()


func setup(viewport: SubViewport) -> void:
	_viewport = viewport
	spacing = GameConfig.get_f("journal", "stamp_spacing_px")
	width = GameConfig.get_f("journal", "stroke_width_px")
	alpha = GameConfig.get_f("journal", "stroke_alpha")
	jitter = GameConfig.get_f("journal", "jitter_px")
	wobble = GameConfig.get_f("journal", "wobble_px")


## Desenha de `a` até `b`. `dist` é a distância acumulada no início do trecho;
## retorna a distância acumulada no fim (passe-a para o próximo trecho).
func segment(a: Vector2, b: Vector2, dist: float, pressure_scale: float = 1.0) -> float:
	var length := a.distance_to(b)
	if length < 0.001:
		return dist
	var dir := (b - a) / length
	var normal := Vector2(-dir.y, dir.x)
	var steps := maxi(1, ceili(length / spacing))
	var half := dir * spacing * 0.85
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		var d := dist + length * t
		var wob := (sin(d * 0.045) * 0.6 + sin(d * 0.131 + 1.3) * 0.4) * wobble * tremor
		var jit := (_hash(d) - 0.5) * 2.0 * jitter * tremor
		var p := a.lerp(b, t) + normal * (wob + jit)
		var pressure := (0.7 + 0.2 * sin(d * 0.021 + 0.7) + 0.1 * _hash(d * 1.7 + 3.1)) * pressure_scale
		_points.append(p - half)
		_points.append(p + half)
		_colors.append(Color(0.0, 0.0, 0.0, clampf(alpha * pressure, 0.0, 1.0)))
	return dist + length


func clear_ink() -> void:
	_points.clear()
	_colors.clear()
	_draw_points = PackedVector2Array()
	_draw_colors = PackedColorArray()
	queue_redraw() # esvazia os comandos antigos, senão seriam redesenhados na folha limpa
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Chamado uma vez por frame: envia os carimbos acumulados para a textura.
func flush() -> void:
	if _points.is_empty():
		return
	_draw_points = _points
	_draw_colors = _colors
	_points = PackedVector2Array()
	_colors = PackedColorArray()
	queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _draw() -> void:
	if _draw_points.is_empty():
		return
	draw_multiline_colors(_draw_points, _draw_colors, width, true)
	_draw_points = PackedVector2Array()
	_draw_colors = PackedColorArray()


static func _hash(x: float) -> float:
	return fposmod(sin(x * 12.9898) * 43758.5453, 1.0)
