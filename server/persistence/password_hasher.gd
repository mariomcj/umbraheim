class_name PasswordHasher
extends RefCounted
## Hash de senha com PBKDF2-HMAC-SHA256 (RFC 8018), usando só o que a Godot já tem
## (Crypto.hmac_digest). Uma saída de 32 bytes = um bloco do PBKDF2.
## Lento de propósito: rode numa thread (WorkerThreadPool), nunca no tick do servidor.


static func new_salt() -> PackedByteArray:
	return Crypto.new().generate_random_bytes(16)


## Retorna o hash em hexadecimal.
static func hash_password(password: String, salt: PackedByteArray, iterations: int) -> String:
	var crypto := Crypto.new()
	var key := password.to_utf8_buffer()
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1])) # INT(1), big-endian
	var u := crypto.hmac_digest(HashingContext.HASH_SHA256, key, block)
	# T = U1 xor U2 xor ... ; o XOR vai em 4 inteiros de 64 bits por iteração (rápido em GDScript)
	var t0 := u.decode_s64(0)
	var t1 := u.decode_s64(8)
	var t2 := u.decode_s64(16)
	var t3 := u.decode_s64(24)
	for i in range(1, maxi(1, iterations)):
		u = crypto.hmac_digest(HashingContext.HASH_SHA256, key, u)
		t0 ^= u.decode_s64(0)
		t1 ^= u.decode_s64(8)
		t2 ^= u.decode_s64(16)
		t3 ^= u.decode_s64(24)
	var out := PackedByteArray()
	out.resize(32)
	out.encode_s64(0, t0)
	out.encode_s64(8, t1)
	out.encode_s64(16, t2)
	out.encode_s64(24, t3)
	return out.hex_encode()


## Comparação em tempo constante (não vaza quantos caracteres batem).
static func equals(a: String, b: String) -> bool:
	if a.length() != b.length():
		return false
	var diff := 0
	for i in a.length():
		diff |= a.unicode_at(i) ^ b.unicode_at(i)
	return diff == 0
