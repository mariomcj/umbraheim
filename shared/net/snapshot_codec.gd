class_name SnapshotCodec
extends RefCounted
## Snapshot binário, quantizado e com delta por jogador (protocolo v9).
##
## Formato (little-endian):
##   tick u32 | quantidade u16 | por entidade:
##     id s32 | flags u8 | [meta s32 se FLAG_META] | [x s16, z s16 (cm), yaw u8, vida u8 se FLAG_STATE]
## - meta (tipo da entidade) só vai na primeira vez que o jogador vê a entidade;
## - estado só vai se mudou desde o último envio para ESSE jogador;
## - entidade que some da lista saiu da área de interesse (o cliente remove).
## Tamanho: 15 bytes na primeira vez, 11 se mudou, 5 se ficou igual
## (antes: 28 bytes por entidade, sempre).

const FLAG_META := 1
const FLAG_STATE := 2
const POS_SCALE := 100.0 # 1 cm
const POS_LIMIT := 32767


static func quantize(pos: Vector2, yaw: float, hp_frac: float) -> PackedInt32Array:
	return PackedInt32Array([
		clampi(roundi(pos.x * POS_SCALE), -POS_LIMIT, POS_LIMIT),
		clampi(roundi(pos.y * POS_SCALE), -POS_LIMIT, POS_LIMIT),
		roundi(wrapf(yaw, 0.0, TAU) / TAU * 256.0) % 256,
		clampi(roundi(hp_frac * 255.0), 0, 255),
	])


static func dequantize(q: PackedInt32Array) -> Vector4:
	var yaw := wrapf(q[2] / 256.0 * TAU, -PI, PI)
	return Vector4(q[0] / POS_SCALE, q[1] / POS_SCALE, yaw, q[3] / 255.0)


## Lado do servidor: um por jogador conectado (lembra o que ele já recebeu).
class Encoder:
	var known: Dictionary = {} # id -> estado quantizado já enviado

	## entities: Array de [id, meta, posição (Vector2), yaw, fração de vida].
	func encode(tick: int, entities: Array) -> PackedByteArray:
		var buf := PackedByteArray()
		buf.resize(6 + entities.size() * 15)
		buf.encode_u32(0, tick)
		buf.encode_u16(4, entities.size())
		var o := 6
		var seen := {}
		for e: Array in entities:
			var id: int = e[0]
			seen[id] = true
			var q := SnapshotCodec.quantize(e[2], e[3], e[4])
			var flags := 0
			if not known.has(id):
				flags |= FLAG_META | FLAG_STATE
			elif known[id] != q:
				flags |= FLAG_STATE
			buf.encode_s32(o, id)
			buf.encode_u8(o + 4, flags)
			o += 5
			if flags & FLAG_META:
				buf.encode_s32(o, int(e[1]))
				o += 4
			if flags & FLAG_STATE:
				buf.encode_s16(o, q[0])
				buf.encode_s16(o + 2, q[1])
				buf.encode_u8(o + 4, q[2])
				buf.encode_u8(o + 5, q[3])
				o += 6
				known[id] = q
		for id: int in known.keys():
			if not seen.has(id):
				known.erase(id) # saiu da área: se voltar, vai de novo com meta
		buf.resize(o)
		return buf


## Lado do cliente: guarda o último estado e o tipo de cada entidade visível.
class Decoder:
	var states: Dictionary = {} # id -> Vector4(x, z, yaw, vida)
	var metas: Dictionary = {} # id -> meta

	func reset() -> void:
		states.clear()
		metas.clear()

	## Retorna {tick, ids: PackedInt32Array, metas: PackedInt32Array, states: {id: Vector4}}; {} se malformado.
	func decode(buf: PackedByteArray) -> Dictionary:
		if buf.size() < 6:
			push_error("SnapshotCodec: snapshot curto demais (%d bytes)" % buf.size())
			return {}
		var count := buf.decode_u16(4)
		var o := 6
		var ids := PackedInt32Array()
		var out_metas := PackedInt32Array()
		var out_states := {}
		for i in count:
			if o + 5 > buf.size():
				push_error("SnapshotCodec: snapshot truncado")
				return {}
			var id := buf.decode_s32(o)
			var flags := buf.decode_u8(o + 4)
			o += 5
			if flags & FLAG_META:
				if o + 4 > buf.size():
					push_error("SnapshotCodec: snapshot truncado")
					return {}
				metas[id] = buf.decode_s32(o)
				o += 4
			if flags & FLAG_STATE:
				if o + 6 > buf.size():
					push_error("SnapshotCodec: snapshot truncado")
					return {}
				states[id] = SnapshotCodec.dequantize(PackedInt32Array([buf.decode_s16(o), buf.decode_s16(o + 2),
					buf.decode_u8(o + 4), buf.decode_u8(o + 5)]))
				o += 6
			if not states.has(id) or not metas.has(id):
				continue # sem base (não deveria acontecer): ignora até o próximo envio completo
			ids.append(id)
			out_metas.append(metas[id])
			out_states[id] = states[id]
		for id: int in states.keys():
			if not out_states.has(id):
				states.erase(id)
				metas.erase(id)
		return {"tick": buf.decode_u32(0), "ids": ids, "metas": out_metas, "states": out_states}
