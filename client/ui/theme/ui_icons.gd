class_name UiIcons
extends RefCounted
## Ícones originais desenhados no código (docs/design/PROPOSTA_UI.md 2.4 e parte I): silhuetas simples
## num espaço unitário (-1..1, y para baixo), preenchidas na cor pedida e com contorno escuro para ler
## sobre qualquer fundo. Qual ícone cada coisa usa vem de ui.json -> theme.icons (por tipo de magia,
## por magia e por botão de sistema); ícone desconhecido = nada desenhado (quem chama mostra a letra).

const NAMES: PackedStringArray = ["bolt", "burst", "lightning", "blade", "nova", "shield", "heal", "spirit",
	"flame", "meteor", "rift", "sun", "bag", "bust", "book", "star", "banner", "pair"]


static func has(id: String) -> bool:
	return NAMES.has(id)


## Ícone de uma magia: "icon" da própria magia, depois icons.spells[id], depois icons.spell_kinds[kind].
static func for_spell(spell: Dictionary) -> String:
	var cfg := _cfg()
	if spell.has("icon"):
		return str(spell["icon"])
	var by_id: Dictionary = cfg.get("spells", {})
	if by_id.has(str(spell.get("id", ""))):
		return str(by_id[str(spell["id"])])
	return str((cfg.get("spell_kinds", {}) as Dictionary).get(str(spell.get("kind", "")), ""))


static func for_action(action: String) -> String:
	return str((_cfg().get("system", {}) as Dictionary).get(action, ""))


static func _cfg() -> Dictionary:
	return UiPalette.theme_cfg().get("icons", {}) as Dictionary


## Desenha o ícone centrado em c, cabendo num círculo de raio r.
static func draw(ci: CanvasItem, id: String, c: Vector2, r: float, color: Color) -> void:
	var outline := Color(0, 0, 0, 0.75 * color.a)
	var w := maxf(1.0, r * 0.09)
	for shape: Array in _shapes(id):
		var kind: String = shape[0]
		var pts := PackedVector2Array()
		for p: Vector2 in shape[1]:
			pts.append(c + p * r)
		var col: Color = color if shape.size() < 3 else Color(color.darkened(float(shape[2])), color.a)
		match kind:
			"fill":
				ci.draw_colored_polygon(pts, col)
				var closed := pts.duplicate()
				closed.append(pts[0])
				ci.draw_polyline(closed, outline, w, true)
			"line":
				ci.draw_polyline(pts, outline, w * 2.6, true)
				ci.draw_polyline(pts, col, w * 1.4, true)
			"dot":
				ci.draw_circle(pts[0], (shape[1][1] as Vector2).x * r + w * 0.6, outline)
				ci.draw_circle(pts[0], (shape[1][1] as Vector2).x * r, col)


static func _circle(c: Vector2, rad: float, n: int = 16, a0: float = 0.0, a1: float = TAU) -> Array:
	var out: Array = []
	for i in n + 1:
		var a := a0 + (a1 - a0) * float(i) / n
		out.append(c + Vector2(cos(a), sin(a)) * rad)
	return out


static func _star(points: int, outer: float, inner: float, rot: float = -PI / 2.0) -> Array:
	var out: Array = []
	for i in points * 2:
		var a := rot + PI * float(i) / points
		out.append(Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return out


## Lista de [tipo, pontos, escurecer?]: "fill" polígono, "line" traço, "dot" [centro, Vector2(raio, 0)].
static func _shapes(id: String) -> Array:
	match id:
		"bolt": # dardo: cabeça em losango e rastro afinando
			return [["fill", [Vector2(-0.85, 0.85), Vector2(-0.05, -0.2), Vector2(0.2, 0.05)]],
				["fill", [Vector2(0.75, -0.75), Vector2(0.45, 0.05), Vector2(0.15, -0.15), Vector2(-0.05, -0.45)]]]
		"burst": # explosão em área: estrela de 8 pontas
			return [["fill", _star(8, 0.95, 0.42)], ["dot", [Vector2.ZERO, Vector2(0.22, 0)], 0.45]]
		"lightning":
			return [["fill", [Vector2(0.25, -0.95), Vector2(-0.55, 0.12), Vector2(-0.05, 0.12), Vector2(-0.3, 0.95),
				Vector2(0.55, -0.15), Vector2(0.05, -0.15), Vector2(0.3, -0.95)]]]
		"blade": # espada inclinada: lâmina, guarda e cabo
			return [["fill", [Vector2(0.85, -0.85), Vector2(0.62, -0.32), Vector2(-0.2, 0.5), Vector2(-0.5, 0.2), Vector2(0.32, -0.62)]],
				["line", [Vector2(-0.62, 0.05), Vector2(-0.05, 0.62)]],
				["line", [Vector2(-0.38, 0.38), Vector2(-0.8, 0.8)], 0.35]]
		"nova": # anel com raios
			var out: Array = [["line", _circle(Vector2.ZERO, 0.42, 20)], ["dot", [Vector2.ZERO, Vector2(0.18, 0)]]]
			for i in 8:
				var d := Vector2.from_angle(TAU * i / 8.0)
				out.append(["line", [d * 0.62, d * 0.95]])
			return out
		"shield":
			return [["fill", [Vector2(0, -0.92), Vector2(0.75, -0.62), Vector2(0.68, 0.1), Vector2(0, 0.95), Vector2(-0.68, 0.1), Vector2(-0.75, -0.62)]],
				["fill", [Vector2(0, -0.6), Vector2(0.4, -0.4), Vector2(0.36, 0.05), Vector2(0, 0.58)], 0.4]]
		"heal": # cruz de pontas largas com losango no meio
			return [["fill", [Vector2(-0.22, -0.9), Vector2(0.22, -0.9), Vector2(0.22, -0.22), Vector2(0.9, -0.22), Vector2(0.9, 0.22),
				Vector2(0.22, 0.22), Vector2(0.22, 0.9), Vector2(-0.22, 0.9), Vector2(-0.22, 0.22), Vector2(-0.9, 0.22),
				Vector2(-0.9, -0.22), Vector2(-0.22, -0.22)]],
				["fill", [Vector2(0, -0.2), Vector2(0.2, 0), Vector2(0, 0.2), Vector2(-0.2, 0)], 0.45]]
		"spirit": # fantasma: cabeça redonda e barra ondulada
			var body: Array = _circle(Vector2(0, -0.2), 0.62, 14, PI, TAU)
			body.append_array([Vector2(0.62, 0.85), Vector2(0.31, 0.6), Vector2(0, 0.85), Vector2(-0.31, 0.6), Vector2(-0.62, 0.85)])
			return [["fill", body], ["dot", [Vector2(-0.24, -0.22), Vector2(0.12, 0)], 0.8], ["dot", [Vector2(0.24, -0.22), Vector2(0.12, 0)], 0.8]]
		"flame":
			return [["fill", [Vector2(0, -0.95), Vector2(0.3, -0.45), Vector2(0.62, -0.1), Vector2(0.62, 0.35), Vector2(0.3, 0.85),
				Vector2(-0.3, 0.85), Vector2(-0.62, 0.35), Vector2(-0.5, -0.15), Vector2(-0.2, 0.05), Vector2(-0.15, -0.45)]],
				["fill", [Vector2(0.05, -0.15), Vector2(0.3, 0.3), Vector2(0.15, 0.7), Vector2(-0.18, 0.7), Vector2(-0.3, 0.35)], 0.4]]
		"meteor": # pedra com três rastros
			return [["line", [Vector2(-0.9, -0.15), Vector2(-0.1, 0.0)]], ["line", [Vector2(-0.75, -0.65), Vector2(0.0, -0.25)]],
				["line", [Vector2(-0.2, -0.9), Vector2(0.15, -0.35)]], ["dot", [Vector2(0.38, 0.38), Vector2(0.45, 0)]]]
		"rift": # fenda: rasgo em ziguezague dentro de um olho
			return [["fill", [Vector2(-0.95, 0), Vector2(-0.4, -0.5), Vector2(0.4, -0.5), Vector2(0.95, 0), Vector2(0.4, 0.5), Vector2(-0.4, 0.5)], 0.55],
				["line", [Vector2(-0.1, -0.75), Vector2(0.15, -0.25), Vector2(-0.15, 0.2), Vector2(0.1, 0.75)]]]
		"sun":
			var s: Array = [["fill", _star(12, 0.95, 0.6)], ["dot", [Vector2.ZERO, Vector2(0.42, 0)], 0.35]]
			return s
		"bag": # mochila: bolsa com cordão
			return [["fill", [Vector2(-0.3, -0.55), Vector2(0.3, -0.55), Vector2(0.75, 0.05), Vector2(0.7, 0.75), Vector2(0.4, 0.9),
				Vector2(-0.4, 0.9), Vector2(-0.7, 0.75), Vector2(-0.75, 0.05)]],
				["fill", [Vector2(-0.4, -0.95), Vector2(0.4, -0.95), Vector2(0.25, -0.55), Vector2(-0.25, -0.55)], 0.3],
				["line", [Vector2(-0.45, -0.5), Vector2(0.45, -0.5)], 0.5]]
		"bust": # atributos: busto (cabeça e ombros)
			var shoulders: Array = _circle(Vector2(0, 0.95), 0.8, 14, PI, TAU)
			return [["dot", [Vector2(0, -0.42), Vector2(0.36, 0)]], ["fill", shoulders]]
		"book": # diário: livro aberto
			return [["fill", [Vector2(0, -0.55), Vector2(0.9, -0.75), Vector2(0.9, 0.55), Vector2(0, 0.8)]],
				["fill", [Vector2(0, -0.55), Vector2(0, 0.8), Vector2(-0.9, 0.55), Vector2(-0.9, -0.75)], 0.25],
				["line", [Vector2(0.2, -0.35), Vector2(0.7, -0.45)], 0.55], ["line", [Vector2(0.2, -0.05), Vector2(0.7, -0.15)], 0.55]]
		"star": # maestria
			return [["fill", _star(5, 0.98, 0.42)]]
		"banner": # guilda: estandarte em rabo de andorinha num mastro
			return [["line", [Vector2(-0.6, -0.95), Vector2(-0.6, 0.95)], 0.35],
				["fill", [Vector2(-0.6, -0.8), Vector2(0.75, -0.8), Vector2(0.75, 0.6), Vector2(0.08, 0.25), Vector2(-0.6, 0.6)]],
				["fill", [Vector2(0.08, -0.55), Vector2(0.3, -0.3), Vector2(0.08, -0.05), Vector2(-0.14, -0.3)], 0.5]]
		"pair": # amigos: dois bustos
			return [["dot", [Vector2(0.4, -0.38), Vector2(0.27, 0)], 0.3], ["fill", _circle(Vector2(0.4, 0.75), 0.52, 12, PI, TAU), 0.3],
				["dot", [Vector2(-0.4, -0.38), Vector2(0.27, 0)]], ["fill", _circle(Vector2(-0.4, 0.75), 0.52, 12, PI, TAU)]]
	return []
