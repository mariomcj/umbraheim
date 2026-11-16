class_name GuildSymbol
extends RefCounted
## Símbolo de guilda: texto hexadecimal com um índice da paleta (data/guilds.json) por pixel.
## Gera a textura (pixels nítidos, sem filtro) com cache por símbolo.

static var _cache: Dictionary = {} # símbolo -> ImageTexture


static func palette() -> Array[Color]:
	var out: Array[Color] = []
	for c: Array in GameConfig.table("guilds")["symbol"]["palette"]:
		out.append(GameConfig.color_of(c))
	return out


static func size() -> int:
	return int(GameConfig.table("guilds")["symbol"]["size"])


static func empty_symbol() -> String:
	return "0".repeat(size() * size())


## Índice da paleta em (x, y); 0 = transparente.
static func pixel(symbol: String, x: int, y: int) -> int:
	var i := y * size() + x
	return maxi(0, "0123456789abcdef".find(symbol[i])) if i < symbol.length() else 0


static func with_pixel(symbol: String, x: int, y: int, color_index: int) -> String:
	var i := y * size() + x
	return symbol.left(i) + "0123456789abcdef"[color_index] + symbol.substr(i + 1)


static func texture(symbol: String) -> ImageTexture:
	if _cache.has(symbol):
		return _cache[symbol]
	var n := size()
	var colors := palette()
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := pixel(symbol, x, y)
			img.set_pixel(x, y, Color(0, 0, 0, 0) if v == 0 else colors[mini(v, colors.size() - 1)])
	var tex := ImageTexture.create_from_image(img)
	_cache[symbol] = tex
	return tex


## TextureRect com o símbolo, ampliado sem borrar.
static func rect(symbol: String, px: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture(symbol)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
