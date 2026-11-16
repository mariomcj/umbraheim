class_name UiDraw
## Desenhos comuns das janelas de itens (docs/design/PROPOSTA_UI.md 3.3): grade em poço com rejunte fino,
## contorno tracejado, moeda, círculo rúnico (forja) e silhuetas-guia dos slots de equipamento.
## Tudo com as cores de UiPalette; funções estáticas chamadas dentro de _draw().


## Poço com rejunte fino: fundo rebaixado, sombra no topo e linhas da grade.
static func well_grid(c: CanvasItem, origin: Vector2, cols: int, rows: int, cell: float) -> void:
	var size := Vector2(cols, rows) * cell
	c.draw_rect(Rect2(origin, size), UiPalette.c("well", 0.95))
	c.draw_rect(Rect2(origin, Vector2(size.x, 3)), Color(0, 0, 0, 0.45))
	var grout := UiPalette.c("iron_edge", 0.55)
	for x in range(1, cols):
		c.draw_line(origin + Vector2(x * cell, 0), origin + Vector2(x * cell, size.y), grout, 1.0)
	for y in range(1, rows):
		c.draw_line(origin + Vector2(0, y * cell), origin + Vector2(size.x, y * cell), grout, 1.0)
	c.draw_rect(Rect2(origin, size), UiPalette.c("iron_edge"), false, 1.0)
	c.draw_line(origin + Vector2(1, size.y - 1), origin + Vector2(size.x - 1, size.y - 1), UiPalette.c("gold_dim", 0.25), 1.0)


## Retângulo tracejado (área onde o item segurado cairia).
static func dashed_rect(c: CanvasItem, r: Rect2, color: Color, width: float = 1.5, dash: float = 5.0) -> void:
	var p := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		c.draw_dashed_line(p[i], p[(i + 1) % 4], color, width, dash)


## Moeda (óbolo): disco na cor arcana com borda e brilho.
static func coin(c: CanvasItem, center: Vector2, r: float) -> void:
	var col := UiPalette.c("arcane")
	c.draw_circle(center, r, col.darkened(0.35))
	c.draw_circle(center, r * 0.78, col)
	c.draw_arc(center, r * 0.55, 0.0, TAU, 16, col.darkened(0.3), 1.0, true)
	c.draw_circle(center + Vector2(-r * 0.3, -r * 0.3), r * 0.18, Color(1, 1, 1, 0.6))


## Círculo rúnico 2D girando (atrás das vagas da forja).
static func rune_circle(c: CanvasItem, center: Vector2, r: float, color: Color, t: float) -> void:
	c.draw_arc(center, r, 0.0, TAU, 64, Color(color, 0.55), 2.0, true)
	c.draw_arc(center, r * 0.82, 0.0, TAU, 64, Color(color, 0.3), 1.0, true)
	c.draw_arc(center, r * 0.45, 0.0, TAU, 48, Color(color, 0.25), 1.0, true)
	var n := 18
	for i in n:
		var a := t * 0.25 + TAU * i / n
		var d := Vector2(cos(a), sin(a))
		c.draw_line(center + d * r * 0.86, center + d * r * 0.96, Color(color, 0.6), 2.0, true)
	for i in 3: # triângulo interno girando ao contrário
		var a0 := -t * 0.18 + TAU * i / 3.0
		var a1 := -t * 0.18 + TAU * (i + 1) / 3.0
		c.draw_line(center + Vector2(cos(a0), sin(a0)) * r * 0.8, center + Vector2(cos(a1), sin(a1)) * r * 0.8, Color(color, 0.22), 1.0, true)


## Silhueta-guia de um slot vazio de equipamento (traços simples, gold_dim fraco).
static func slot_silhouette(c: CanvasItem, slot: String, r: Rect2) -> void:
	var col := UiPalette.c("gold_dim", 0.35)
	var ct := r.get_center()
	var s := minf(r.size.x, r.size.y)
	var w := 1.5
	match slot:
		"helm":
			c.draw_arc(ct + Vector2(0, s * 0.08), s * 0.3, PI, TAU, 16, col, w, true)
			c.draw_line(ct + Vector2(-s * 0.3, s * 0.08), ct + Vector2(-s * 0.3, s * 0.3), col, w)
			c.draw_line(ct + Vector2(s * 0.3, s * 0.08), ct + Vector2(s * 0.3, s * 0.3), col, w)
			c.draw_line(ct + Vector2(-s * 0.16, s * 0.12), ct + Vector2(s * 0.16, s * 0.12), col, w)
		"weapon":
			c.draw_line(Vector2(ct.x, r.position.y + 12), Vector2(ct.x, r.end.y - 22), col, w * 2.0)
			c.draw_line(Vector2(ct.x - 10, r.end.y - 22), Vector2(ct.x + 10, r.end.y - 22), col, w * 1.5)
			c.draw_line(Vector2(ct.x, r.end.y - 22), Vector2(ct.x, r.end.y - 10), col, w * 1.5)
		"shield":
			var pts := PackedVector2Array([ct + Vector2(-s * 0.32, -s * 0.35), ct + Vector2(s * 0.32, -s * 0.35), ct + Vector2(s * 0.3, s * 0.05),
				ct + Vector2(0, s * 0.4), ct + Vector2(-s * 0.3, s * 0.05), ct + Vector2(-s * 0.32, -s * 0.35)])
			c.draw_polyline(pts, col, w, true)
		"armor":
			var pts := PackedVector2Array([ct + Vector2(-s * 0.4, -s * 0.32), ct + Vector2(-s * 0.15, -s * 0.38), ct + Vector2(0, -s * 0.28),
				ct + Vector2(s * 0.15, -s * 0.38), ct + Vector2(s * 0.4, -s * 0.32), ct + Vector2(s * 0.3, -s * 0.05), ct + Vector2(s * 0.25, s * 0.38),
				ct + Vector2(-s * 0.25, s * 0.38), ct + Vector2(-s * 0.3, -s * 0.05), ct + Vector2(-s * 0.4, -s * 0.32)])
			c.draw_polyline(pts, col, w, true)
		"pants":
			var pts := PackedVector2Array([ct + Vector2(-s * 0.3, -s * 0.3), ct + Vector2(s * 0.3, -s * 0.3), ct + Vector2(s * 0.35, s * 0.35),
				ct + Vector2(s * 0.08, s * 0.35), ct + Vector2(0, -s * 0.05), ct + Vector2(-s * 0.08, s * 0.35), ct + Vector2(-s * 0.35, s * 0.35),
				ct + Vector2(-s * 0.3, -s * 0.3)])
			c.draw_polyline(pts, col, w, true)
		"gloves":
			c.draw_rect(Rect2(ct + Vector2(-s * 0.2, -s * 0.05), Vector2(s * 0.4, s * 0.35)), col, false, w)
			for i in 4:
				var x := -s * 0.18 + i * s * 0.12
				c.draw_line(ct + Vector2(x, -s * 0.05), ct + Vector2(x, -s * 0.3), col, w)
		"boots":
			var pts := PackedVector2Array([ct + Vector2(-s * 0.15, -s * 0.35), ct + Vector2(s * 0.08, -s * 0.35), ct + Vector2(s * 0.08, s * 0.1),
				ct + Vector2(s * 0.35, s * 0.2), ct + Vector2(s * 0.35, s * 0.32), ct + Vector2(-s * 0.15, s * 0.32), ct + Vector2(-s * 0.15, -s * 0.35)])
			c.draw_polyline(pts, col, w, true)
		"ring1", "ring2":
			c.draw_arc(ct + Vector2(0, s * 0.05), s * 0.25, 0.0, TAU, 16, col, w, true)
			c.draw_colored_polygon(PackedVector2Array([ct + Vector2(0, -s * 0.38), ct + Vector2(s * 0.1, -s * 0.24), ct + Vector2(0, -s * 0.14), ct + Vector2(-s * 0.1, -s * 0.24)]), col)
		"amulet":
			c.draw_arc(ct + Vector2(0, -s * 0.15), s * 0.28, 0.2, PI - 0.2, 12, col, w, true)
			c.draw_colored_polygon(PackedVector2Array([ct + Vector2(0, s * 0.1), ct + Vector2(s * 0.12, s * 0.24), ct + Vector2(0, s * 0.38), ct + Vector2(-s * 0.12, s * 0.24)]), col)
		"wings":
			for side in [-1.0, 1.0]:
				for i in 3:
					var a := lerpf(-0.5, 0.45, i / 2.0)
					c.draw_line(ct, ct + Vector2(cos(a) * side, -sin(a)) * r.size.x * lerpf(0.4, 0.28, i / 2.0), col, w)
		"pet":
			c.draw_circle(ct + Vector2(0, s * 0.12), s * 0.15, col)
			for i in 4:
				var a := lerpf(-2.5, -0.65, i / 3.0)
				c.draw_circle(ct + Vector2(cos(a), sin(a)) * s * 0.3 + Vector2(0, s * 0.08), s * 0.07, col)
