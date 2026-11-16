class_name UiPalette
## Paleta e fontes da interface, lidas de data/config/ui.json -> theme.
## Substitui as constantes GOLD/PARCHMENT que cada janela repetia.

static var _colors: Dictionary = {}
static var _fonts: Dictionary = {}


static func theme_cfg() -> Dictionary:
	return GameConfig.get_value("ui", "theme")


## Cor da paleta pelo nome (ink, gold, bone, ember...). Nome desconhecido: magenta, para aparecer no teste visual.
static func c(color_name: String, alpha: float = 1.0) -> Color:
	if _colors.is_empty():
		for key: String in (theme_cfg()["colors"] as Dictionary):
			_colors[key] = Color.html(str(theme_cfg()["colors"][key]))
	var col: Color = _colors.get(color_name, Color.MAGENTA)
	col.a *= alpha
	return col


## Cor de assinatura da classe (feiticeiro = void, cavaleiro = blood, vidente = spectral).
static func class_color(class_id: String) -> Color:
	var map: Dictionary = theme_cfg().get("class_colors", {})
	return c(str(map.get(class_id, "void")))


static func size(size_name: String) -> int:
	return int((theme_cfg()["sizes"] as Dictionary).get(size_name, 14))


## Fonte pelo papel (title, body, body_bold, lore...). O título vem em Cinzel com peso e espaçamento do tema.
static func font(role: String) -> Font:
	if _fonts.has(role):
		return _fonts[role]
	var path := str((theme_cfg()["fonts"] as Dictionary).get(role, ""))
	var f: Font = null
	if path != "" and ResourceLoader.exists(path):
		var base := load(path) as Font
		if role == "title":
			var v := FontVariation.new()
			v.base_font = base
			var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
			v.variation_opentype = {wght: int(theme_cfg().get("title_weight", 600))}
			v.spacing_glyph = int(theme_cfg().get("title_spacing_px", 1))
			f = v
		else:
			f = base
	_fonts[role] = f
	return f
