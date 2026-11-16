class_name ItemCodec
extends RefCounted
## Item <-> PackedInt32Array compacto para a rede:
## [uid, base_index, level, rarity, flags (bit0 = sorte), extra, máscara de opções excelentes,
##  container, x, y, quantidade]

const SIZE := 11
const FLAG_LUCK := 1


static func encode(item: Dictionary, catalog: ItemCatalog) -> PackedInt32Array:
	var mask := 0
	for opt: String in item.get("exc", []):
		var bit := catalog.exc_ids.find(opt)
		if bit >= 0:
			mask |= 1 << bit
	var a := PackedInt32Array()
	a.resize(SIZE)
	a[0] = int(item.get("uid", 0))
	a[1] = catalog.base_ids.find(str(item.get("base", "")))
	a[2] = int(item.get("level", 0))
	a[3] = int(item.get("rarity", 0))
	a[4] = FLAG_LUCK if bool(item.get("luck", false)) else 0
	a[5] = int(item.get("extra", 0))
	a[6] = mask
	a[7] = int(item.get("container", 0))
	a[8] = int(item.get("x", 0))
	a[9] = int(item.get("y", 0))
	a[10] = int(item.get("count", 1))
	return a


static func decode(a: PackedInt32Array, catalog: ItemCatalog) -> Dictionary:
	if a.size() != SIZE or a[1] < 0 or a[1] >= catalog.base_ids.size():
		return {}
	var exc: Array[String] = []
	for bit in catalog.exc_ids.size():
		if a[6] & (1 << bit):
			exc.append(catalog.exc_ids[bit])
	return {"uid": a[0], "base": catalog.base_ids[a[1]], "level": a[2], "rarity": a[3],
		"luck": (a[4] & FLAG_LUCK) != 0, "extra": a[5], "exc": exc, "container": a[7], "x": a[8], "y": a[9],
		"count": maxi(1, a[10])}
