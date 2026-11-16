extends RefCounted
## Snapshot binário com delta por jogador, quantização e grade espacial de interesse.


func _entities() -> Array:
	return [
		[1, Protocol.make_meta(Protocol.KIND_PLAYER, 0), Vector2(1.5, -2.0), 0.0, 1.0],
		[2_000_000_123, Protocol.make_meta(Protocol.KIND_PLAYER, 0), Vector2(-30.25, 17.5), PI / 2.0, 0.5],
		[-42, Protocol.make_meta(Protocol.KIND_MONSTER, 1), Vector2(0.004, 37.99), -1.0, 0.0],
	]


func test_roundtrip_and_precision() -> String:
	var enc := SnapshotCodec.Encoder.new()
	var dec := SnapshotCodec.Decoder.new()
	var out := dec.decode(enc.encode(77, _entities()))
	if out.is_empty() or int(out["tick"]) != 77 or (out["ids"] as PackedInt32Array).size() != 3:
		return "decodificação falhou: %s" % out
	for e: Array in _entities():
		var v: Vector4 = out["states"].get(e[0], Vector4.INF)
		if Vector2(v.x, v.y).distance_to(e[2]) > 0.006:
			return "posição de %d: %s vs %s (ids grandes não podem perder precisão)" % [e[0], Vector2(v.x, v.y), e[2]]
		if absf(angle_difference(v.z, e[3])) > TAU / 256.0 or absf(v.w - e[4]) > 1.0 / 255.0:
			return "yaw/vida de %d fora da tolerância: %s" % [e[0], v]
	var metas: PackedInt32Array = out["metas"]
	if Protocol.meta_kind(metas[2]) != Protocol.KIND_MONSTER or Protocol.meta_type(metas[2]) != 1:
		return "meta incorreta"
	return ""


func test_delta_sizes() -> String:
	var enc := SnapshotCodec.Encoder.new()
	var dec := SnapshotCodec.Decoder.new()
	var first := enc.encode(1, _entities())
	if first.size() != 6 + 3 * 15:
		return "primeiro envio deveria ter 15 bytes por entidade (%d)" % first.size()
	var same := enc.encode(2, _entities())
	if same.size() != 6 + 3 * 5:
		return "entidades paradas deveriam custar 5 bytes (%d)" % same.size()
	dec.decode(first)
	var moved := _entities()
	moved[0][2] = Vector2(2.0, -2.0)
	var third := enc.encode(3, moved)
	if third.size() != 6 + 11 + 2 * 5:
		return "só a que se moveu leva estado (%d)" % third.size()
	var out := dec.decode(same)
	out = dec.decode(third)
	var v: Vector4 = out["states"][1]
	if not Vector2(v.x, v.y).is_equal_approx(Vector2(2.0, -2.0)) or (out["states"] as Dictionary).size() != 3:
		return "o decodificador não manteve as paradas e atualizou a que andou"
	return ""


func test_leave_and_reenter_resends_meta() -> String:
	var enc := SnapshotCodec.Encoder.new()
	var dec := SnapshotCodec.Decoder.new()
	dec.decode(enc.encode(1, _entities()))
	var only_two := _entities().slice(0, 2)
	var out := dec.decode(enc.encode(2, only_two))
	if (out["ids"] as PackedInt32Array).has(-42) or dec.metas.has(-42):
		return "a entidade que saiu da área deveria sumir no cliente"
	var back := enc.encode(3, _entities())
	if back.size() != 6 + 2 * 5 + 15:
		return "ao voltar, a entidade deveria vir completa (%d bytes)" % back.size()
	out = dec.decode(back)
	return "" if (out["ids"] as PackedInt32Array).has(-42) else "não reapareceu"


func test_rejects_malformed() -> String:
	# esperado: push_error no log + dicionário vazio
	var dec := SnapshotCodec.Decoder.new()
	var good := SnapshotCodec.Encoder.new().encode(1, _entities())
	if not dec.decode(good.slice(0, good.size() - 3)).is_empty() or not dec.decode(PackedByteArray([1, 2])).is_empty():
		return "snapshot malformado foi aceito"
	return ""


func test_spatial_hash() -> String:
	var h := SpatialHash.new(16.0)
	h.insert("perto", Vector2(3, 4))
	h.insert("borda", Vector2(30, 0))
	h.insert("longe", Vector2(31, 0))
	h.insert("outro_lado", Vector2(-29.9, 0))
	var found := h.query(Vector2.ZERO, 30.0)
	found.sort()
	if found != ["borda", "outro_lado", "perto"]:
		return "consulta errada: %s" % [found]
	return ""


func test_meta_roundtrip() -> String:
	var meta := Protocol.make_meta(Protocol.KIND_MONSTER, 7)
	if Protocol.meta_kind(meta) != Protocol.KIND_MONSTER or Protocol.meta_type(meta) != 7:
		return "meta incorreta"
	return ""
