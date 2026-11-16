extends RefCounted
## Testes da lógica do diário (lado servidor/compartilhado).


func test_rdp_keeps_endpoints_and_drops_collinear() -> String:
	var pts := PackedVector2Array()
	for i in 11:
		pts.append(Vector2(i, 0.0))
	var out := PolylineSimplifier.simplify(pts, 0.01)
	if out.size() != 2 or out[0] != pts[0] or out[1] != pts[10]:
		return "linha reta deveria virar 2 pontos, virou %d" % out.size()
	return ""


func test_rdp_keeps_corner() -> String:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(5, 0.01), Vector2(10, 0), Vector2(10, 5), Vector2(10, 10)])
	var out := PolylineSimplifier.simplify(pts, 0.1)
	if out.size() != 3 or not out[1].is_equal_approx(Vector2(10, 0)):
		return "esperava [início, canto, fim], veio %s" % out
	return ""


func test_strokes_are_continuous_across_chunks() -> String:
	var j := RegionJournal.new(0.05, 4)
	j.add_point(Vector2(0, 0), true)
	for i in range(1, 20):
		j.add_point(Vector2(i, sin(i * 0.9) * 3.0), false)
	var strokes := j.export_strokes()
	if strokes.size() != 1:
		return "esperava 1 traço, veio %d" % strokes.size()
	var s := strokes[0]
	if s[0] != Vector2(0, 0) or not s[s.size() - 1].is_equal_approx(Vector2(19, sin(19 * 0.9) * 3.0)):
		return "traço não vai do primeiro ao último ponto"
	for i in range(1, s.size()):
		if s[i].x <= s[i - 1].x:
			return "pontos fora de ordem ou duplicados na emenda: %s" % s
	return ""


func test_new_stroke_breaks_line() -> String:
	var j := RegionJournal.new(0.1, 8)
	j.add_point(Vector2(0, 0), true)
	j.add_point(Vector2(1, 0), false)
	j.add_point(Vector2(50, 50), true)
	j.add_point(Vector2(51, 50), false)
	var strokes := j.export_strokes()
	if strokes.size() != 2 or strokes[0].size() != 2 or strokes[1].size() != 2:
		return "esperava 2 traços de 2 pontos, veio %s" % [strokes]
	return ""


func test_single_point_stroke_exported() -> String:
	var j := RegionJournal.new(0.1, 8)
	j.add_point(Vector2(3, 4), true)
	var strokes := j.export_strokes()
	return "" if strokes.size() == 1 and strokes[0].size() == 1 else "traço de 1 ponto perdido: %s" % [strokes]


func test_marks_and_discovery() -> String:
	var j := RegionJournal.new(0.1, 8)
	j.add_mark("x", Vector2(1, 2), "Tocha")
	j.set_discovered("tocha")
	var marks := j.export_marks()
	if marks.size() != 1 or marks[0][0] != "x" or marks[0][3] != "Tocha" or not j.is_discovered("tocha"):
		return "marcação/descoberta incorreta: %s" % [marks]
	return ""


## Critério de aceite: desempenho estável após horas de caminhada.
## 60.000 amostras de 1,5 m ≈ 90 km ≈ 5 h andando a 5 m/s.
func test_long_walk_is_compact_and_fast() -> String:
	var j := RegionJournal.new(0.2, 48)
	var pos := Vector2.ZERO
	var heading := 0.0
	var start := Time.get_ticks_usec()
	j.add_point(pos, true)
	for i in 60000:
		heading += sin(i * 0.013) * 0.08 + sin(i * 0.0021) * 0.03
		pos += Vector2.from_angle(heading) * 1.5
		j.add_point(pos, false)
	var elapsed_ms := (Time.get_ticks_usec() - start) / 1000.0
	var stored := j.stored_point_count()
	var exported := j.export_strokes()
	if stored > 30000:
		return "pouca simplificação: %d pontos guardados de 60000" % stored
	if elapsed_ms > 3000.0:
		return "lento demais: %.0f ms" % elapsed_ms
	if exported.size() != 1:
		return "caminho contínuo virou %d traços" % exported.size()
	print("        (5 h de caminhada: %d -> %d pontos, %.0f ms)" % [60001, stored, elapsed_ms])
	return ""
