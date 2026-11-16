class_name SqliteRepository
extends GameRepository
## Repositório em SQLite (extensão godot-sqlite, só no servidor).
## O objeto do banco é criado por ClassDB e usado sem tipo: assim este script
## compila também na build Web, onde a extensão não existe (lá ele nunca roda).

const SCHEMA_VERSION := 6
## Migrações: versão -> comandos que levam da versão anterior para ela.
const MIGRATIONS := {
	2: [
		"ALTER TABLE characters ADD COLUMN infamy INTEGER NOT NULL DEFAULT 0;",
		"ALTER TABLE characters ADD COLUMN hero INTEGER NOT NULL DEFAULT 0;",
	],
	3: [ # guildas e amigos
		"""CREATE TABLE IF NOT EXISTS guilds (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL,
			name_key TEXT NOT NULL UNIQUE,
			symbol TEXT NOT NULL,
			wins INTEGER NOT NULL DEFAULT 0,
			created_at INTEGER NOT NULL);""",
		"""CREATE TABLE IF NOT EXISTS guild_members (
			character_id INTEGER PRIMARY KEY REFERENCES characters(id),
			guild_id INTEGER NOT NULL REFERENCES guilds(id),
			role INTEGER NOT NULL,
			joined_at INTEGER NOT NULL);""",
		"CREATE INDEX IF NOT EXISTS guild_members_by_guild ON guild_members(guild_id);",
		"""CREATE TABLE IF NOT EXISTS friends (
			character_id INTEGER NOT NULL REFERENCES characters(id),
			friend_id INTEGER NOT NULL REFERENCES characters(id),
			since INTEGER NOT NULL,
			PRIMARY KEY (character_id, friend_id));""",
	],
	4: [ # classes: evolução e missões
		"ALTER TABLE characters ADD COLUMN evolution INTEGER NOT NULL DEFAULT 0;",
		"ALTER TABLE characters ADD COLUMN quests TEXT NOT NULL DEFAULT '{}';",
	],
	5: [ # endgame: reset e maestria
		"ALTER TABLE characters ADD COLUMN resets INTEGER NOT NULL DEFAULT 0;",
		"ALTER TABLE characters ADD COLUMN master_level INTEGER NOT NULL DEFAULT 0;",
		"ALTER TABLE characters ADD COLUMN master_xp INTEGER NOT NULL DEFAULT 0;",
		"ALTER TABLE characters ADD COLUMN master_points INTEGER NOT NULL DEFAULT 0;",
		"ALTER TABLE characters ADD COLUMN mastery TEXT NOT NULL DEFAULT '{}';",
	],
	6: [ # cerco ao castelo
		"""CREATE TABLE IF NOT EXISTS castles (
			id TEXT PRIMARY KEY,
			guild_id INTEGER NOT NULL DEFAULT 0,
			tax_pct REAL NOT NULL DEFAULT 0,
			treasury INTEGER NOT NULL DEFAULT 0,
			registered TEXT NOT NULL DEFAULT '[]',
			since INTEGER NOT NULL DEFAULT 0);""",
	],
}
const SCHEMA: PackedStringArray = [
	"CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);",
	"""CREATE TABLE IF NOT EXISTS accounts (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT NOT NULL UNIQUE,
		salt TEXT NOT NULL,
		hash TEXT NOT NULL,
		iterations INTEGER NOT NULL,
		created_at INTEGER NOT NULL,
		last_login INTEGER);""",
	"""CREATE TABLE IF NOT EXISTS characters (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		account_id INTEGER NOT NULL REFERENCES accounts(id),
		name TEXT NOT NULL,
		name_key TEXT NOT NULL UNIQUE,
		class_id TEXT NOT NULL,
		level INTEGER NOT NULL, xp INTEGER NOT NULL, points INTEGER NOT NULL,
		str INTEGER NOT NULL, agi INTEGER NOT NULL, vit INTEGER NOT NULL, ene INTEGER NOT NULL,
		currency INTEGER NOT NULL, hp REAL NOT NULL, mana REAL NOT NULL,
		region_id TEXT NOT NULL, pos_x REAL NOT NULL, pos_z REAL NOT NULL,
		learned_spells INTEGER NOT NULL,
		created_at INTEGER NOT NULL, saved_at INTEGER NOT NULL);""",
	"CREATE INDEX IF NOT EXISTS characters_by_account ON characters(account_id);",
	"""CREATE TABLE IF NOT EXISTS items (
		uid INTEGER PRIMARY KEY,
		character_id INTEGER NOT NULL REFERENCES characters(id),
		base TEXT NOT NULL, level INTEGER NOT NULL, rarity INTEGER NOT NULL, luck INTEGER NOT NULL,
		extra INTEGER NOT NULL, exc TEXT NOT NULL,
		container INTEGER NOT NULL, x INTEGER NOT NULL, y INTEGER NOT NULL, count INTEGER NOT NULL);""",
	"CREATE INDEX IF NOT EXISTS items_by_character ON items(character_id);",
	"""CREATE TABLE IF NOT EXISTS journals (
		character_id INTEGER NOT NULL REFERENCES characters(id),
		region_id TEXT NOT NULL,
		data TEXT NOT NULL,
		PRIMARY KEY (character_id, region_id));""",
]

var path: String
var _db: Object


func _init(db_path: String) -> void:
	path = db_path


static func available() -> bool:
	return ClassDB.class_exists("SQLite")


func open() -> bool:
	if not available():
		push_error("[db] extensão godot-sqlite não carregada")
		return false
	_db = ClassDB.instantiate("SQLite")
	_db.set("path", path if path == ":memory:" else ProjectSettings.globalize_path(path))
	_db.set("verbosity_level", 0)
	_db.set("foreign_keys", true)
	if not _db.call("open_db"):
		push_error("[db] não abriu %s: %s" % [path, _db.get("error_message")])
		return false
	_exec("PRAGMA journal_mode=WAL;")
	_exec("PRAGMA synchronous=NORMAL;")
	for sql in SCHEMA:
		if not _exec(sql):
			return false
	var v := _rows("SELECT version FROM schema_version;", [])
	if v.is_empty():
		_exec("INSERT INTO schema_version (version) VALUES (1);") # as tabelas acima são a versão 1
		v = [{"version": 1}]
	var version := int(v[0]["version"])
	while version < SCHEMA_VERSION:
		version += 1
		for sql: String in MIGRATIONS.get(version, []):
			if not _exec(sql):
				return false
		_exec("UPDATE schema_version SET version = ?;", [version])
		print("[db] banco migrado para a versão %d" % version)
	return true


func close() -> void:
	if _db != null:
		_db.call("close_db")
		_db = null


# ---------------------------------------------------------------- contas

func find_account(account_name: String) -> Dictionary:
	var r := _rows("SELECT id, name, salt, hash, iterations FROM accounts WHERE name = ?;", [account_name])
	return r[0] if not r.is_empty() else {}


func create_account(account_name: String, salt_hex: String, hash_hex: String, iterations: int) -> int:
	if not find_account(account_name).is_empty():
		return 0
	if not _exec("INSERT INTO accounts (name, salt, hash, iterations, created_at) VALUES (?, ?, ?, ?, ?);",
			[account_name, salt_hex, hash_hex, iterations, _now()]):
		return 0
	return int(_db.get("last_insert_rowid"))


func touch_login(account_id: int) -> void:
	_exec("UPDATE accounts SET last_login = ? WHERE id = ?;", [_now(), account_id])


# ---------------------------------------------------------------- personagens

func list_characters(account_id: int) -> Array:
	return _rows("SELECT id, name, class_id, level, evolution, resets FROM characters WHERE account_id = ? ORDER BY id;", [account_id])


func character_name_taken(character_name: String) -> bool:
	return not _rows("SELECT id FROM characters WHERE name_key = ?;", [character_name.to_lower()]).is_empty()


func create_character(account_id: int, record: Dictionary) -> int:
	var s: Dictionary = record["stats"]
	var pos: Array = record["pos"]
	if not _exec("""INSERT INTO characters (account_id, name, name_key, class_id, level, xp, points, str, agi, vit, ene,
			currency, hp, mana, region_id, pos_x, pos_z, learned_spells, created_at, saved_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);""",
			[account_id, record["name"], str(record["name"]).to_lower(), record["class_id"], record["level"], record["xp"],
			record["points"], s["str"], s["agi"], s["vit"], s["ene"], record["currency"], record["hp"], record["mana"],
			record["region_id"], pos[0], pos[1], record["learned_spells"], _now(), _now()]):
		return 0
	var id := int(_db.get("last_insert_rowid"))
	record["id"] = id
	return id if save_character(record) else 0


func load_character(character_id: int) -> Dictionary:
	var r := _rows("SELECT * FROM characters WHERE id = ?;", [character_id])
	if r.is_empty():
		return {}
	var c: Dictionary = r[0]
	var rec := {
		"id": int(c["id"]), "account_id": int(c["account_id"]), "name": str(c["name"]), "class_id": str(c["class_id"]),
		"level": int(c["level"]), "xp": int(c["xp"]), "points": int(c["points"]),
		"stats": {"str": int(c["str"]), "agi": int(c["agi"]), "vit": int(c["vit"]), "ene": int(c["ene"])},
		"currency": int(c["currency"]), "hp": float(c["hp"]), "mana": float(c["mana"]),
		"region_id": str(c["region_id"]), "pos": [float(c["pos_x"]), float(c["pos_z"])],
		"learned_spells": int(c["learned_spells"]), "items": [], "journals": {},
		"infamy": int(c.get("infamy", 0)), "hero": int(c.get("hero", 0)),
		"evolution": int(c.get("evolution", 0)), "quests": {},
		"resets": int(c.get("resets", 0)), "master_level": int(c.get("master_level", 0)),
		"master_xp": int(c.get("master_xp", 0)), "master_points": int(c.get("master_points", 0)), "mastery": {},
	}
	var m: Variant = JSON.parse_string(str(c.get("mastery", "{}")))
	if m is Dictionary:
		for k: Variant in m:
			rec["mastery"][str(k)] = int(m[k])
	var q: Variant = JSON.parse_string(str(c.get("quests", "{}")))
	if q is Dictionary:
		rec["quests"] = q
	for it: Dictionary in _rows("SELECT * FROM items WHERE character_id = ?;", [character_id]):
		var exc := str(it["exc"])
		rec["items"].append({"uid": int(it["uid"]), "base": str(it["base"]), "level": int(it["level"]),
			"rarity": int(it["rarity"]), "luck": int(it["luck"]) != 0, "extra": int(it["extra"]),
			"exc": Array(exc.split(",", false)), "container": int(it["container"]),
			"x": int(it["x"]), "y": int(it["y"]), "count": int(it["count"])})
	for j: Dictionary in _rows("SELECT region_id, data FROM journals WHERE character_id = ?;", [character_id]):
		var parsed: Variant = JSON.parse_string(str(j["data"]))
		if parsed is Dictionary:
			rec["journals"][str(j["region_id"])] = parsed
	return rec


## Salva tudo numa transação: atributos, itens (reescritos) e diário.
func save_character(record: Dictionary) -> bool:
	return save_characters([record])


## Vários personagens numa transação só (ex.: os dois lados de uma troca):
## ou todos ficam salvos, ou nenhum.
func save_characters(records: Array) -> bool:
	_exec("BEGIN;")
	var ok := true
	for record: Dictionary in records:
		ok = ok and _save_one(record)
	_exec("COMMIT;" if ok else "ROLLBACK;")
	if not ok:
		push_error("[db] falha ao salvar %d personagem(ns): %s" % [records.size(), _db.get("error_message")])
	return ok


func _save_one(record: Dictionary) -> bool:
	var id := int(record["id"])
	var s: Dictionary = record["stats"]
	var pos: Array = record["pos"]
	var ok := _exec("""UPDATE characters SET level = ?, xp = ?, points = ?, str = ?, agi = ?, vit = ?, ene = ?,
			currency = ?, hp = ?, mana = ?, region_id = ?, pos_x = ?, pos_z = ?, learned_spells = ?, saved_at = ?,
			infamy = ?, hero = ?, evolution = ?, quests = ?,
			resets = ?, master_level = ?, master_xp = ?, master_points = ?, mastery = ?
			WHERE id = ?;""",
			[record["level"], record["xp"], record["points"], s["str"], s["agi"], s["vit"], s["ene"],
			record["currency"], record["hp"], record["mana"], record["region_id"], pos[0], pos[1],
			record["learned_spells"], _now(), int(record.get("infamy", 0)), int(record.get("hero", 0)),
			int(record.get("evolution", 0)), JSON.stringify(record.get("quests", {})),
			int(record.get("resets", 0)), int(record.get("master_level", 0)), int(record.get("master_xp", 0)),
			int(record.get("master_points", 0)), JSON.stringify(record.get("mastery", {})), id])
	ok = ok and _exec("DELETE FROM items WHERE character_id = ?;", [id])
	for it: Dictionary in record.get("items", []):
		if not ok:
			break
		# OR REPLACE: um item que trocou de dono (troca entre jogadores) muda de linha sem duplicar
		ok = _exec("""INSERT OR REPLACE INTO items (uid, character_id, base, level, rarity, luck, extra, exc, container, x, y, count)
				VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);""",
				[it["uid"], id, it["base"], it["level"], it["rarity"], 1 if bool(it["luck"]) else 0, it["extra"],
				",".join(PackedStringArray(it.get("exc", []))), it["container"], it["x"], it["y"], it.get("count", 1)])
	var journals: Dictionary = record.get("journals", {})
	for region_id: String in journals:
		if not ok:
			break
		ok = _exec("INSERT OR REPLACE INTO journals (character_id, region_id, data) VALUES (?, ?, ?);",
				[id, region_id, JSON.stringify(journals[region_id])])
	return ok


func max_item_uid() -> int:
	var r := _rows("SELECT MAX(uid) AS m FROM items;", [])
	return int(r[0]["m"]) if not r.is_empty() and r[0]["m"] != null else 0


# ---------------------------------------------------------------- guildas

func load_guilds() -> Array:
	var by_id := {}
	var out: Array = []
	for r: Dictionary in _rows("""SELECT g.id, g.name, g.symbol, g.wins, m.character_id, m.role,
			c.name AS cname, c.class_id, c.level
			FROM guilds g LEFT JOIN guild_members m ON m.guild_id = g.id
			LEFT JOIN characters c ON c.id = m.character_id ORDER BY g.id, m.role;""", []):
		var gid := int(r["id"])
		if not by_id.has(gid):
			by_id[gid] = {"id": gid, "name": str(r["name"]), "symbol": str(r["symbol"]), "wins": int(r["wins"]), "members": []}
			out.append(by_id[gid])
		if r["character_id"] != null:
			by_id[gid]["members"].append({"character_id": int(r["character_id"]), "name": str(r["cname"]),
				"class_id": str(r["class_id"]), "level": int(r["level"]), "role": int(r["role"])})
	return out


func guild_name_taken(guild_name: String) -> bool:
	return not _rows("SELECT id FROM guilds WHERE name_key = ?;", [guild_name.to_lower()]).is_empty()


func create_guild(guild_name: String, symbol: String, master_character_id: int) -> int:
	if guild_name_taken(guild_name):
		return 0
	_exec("BEGIN;")
	var ok := _exec("INSERT INTO guilds (name, name_key, symbol, created_at) VALUES (?, ?, ?, ?);",
			[guild_name, guild_name.to_lower(), symbol, _now()])
	var id := int(_db.get("last_insert_rowid")) if ok else 0
	ok = ok and _exec("INSERT OR REPLACE INTO guild_members (character_id, guild_id, role, joined_at) VALUES (?, ?, 0, ?);",
			[master_character_id, id, _now()])
	_exec("COMMIT;" if ok else "ROLLBACK;")
	return id if ok else 0


func delete_guild(guild_id: int) -> bool:
	_exec("BEGIN;")
	var ok := _exec("DELETE FROM guild_members WHERE guild_id = ?;", [guild_id]) 		and _exec("DELETE FROM guilds WHERE id = ?;", [guild_id])
	_exec("COMMIT;" if ok else "ROLLBACK;")
	return ok


func set_guild_member(guild_id: int, character_id: int, role: int) -> bool:
	var r := _rows("SELECT joined_at FROM guild_members WHERE character_id = ? AND guild_id = ?;", [character_id, guild_id])
	var joined := int(r[0]["joined_at"]) if not r.is_empty() else _now()
	return _exec("INSERT OR REPLACE INTO guild_members (character_id, guild_id, role, joined_at) VALUES (?, ?, ?, ?);",
			[character_id, guild_id, role, joined])


func remove_guild_member(character_id: int) -> bool:
	return _exec("DELETE FROM guild_members WHERE character_id = ?;", [character_id])


func set_guild_symbol(guild_id: int, symbol: String) -> bool:
	return _exec("UPDATE guilds SET symbol = ? WHERE id = ?;", [symbol, guild_id])


func add_guild_win(guild_id: int) -> bool:
	return _exec("UPDATE guilds SET wins = wins + 1 WHERE id = ?;", [guild_id])


# ---------------------------------------------------------------- castelo

func load_castle(castle_id: String) -> Dictionary:
	var r := _rows("SELECT * FROM castles WHERE id = ?;", [castle_id])
	if r.is_empty():
		return {}
	var c: Dictionary = r[0]
	var reg: Array = []
	var parsed: Variant = JSON.parse_string(str(c["registered"]))
	if parsed is Array:
		for v: Variant in parsed:
			reg.append(int(v))
	return {"id": str(c["id"]), "guild_id": int(c["guild_id"]), "tax_pct": float(c["tax_pct"]), "treasury": int(c["treasury"]),
		"registered": reg, "since": int(c["since"])}


func save_castle(record: Dictionary) -> bool:
	return _exec("INSERT OR REPLACE INTO castles (id, guild_id, tax_pct, treasury, registered, since) VALUES (?, ?, ?, ?, ?, ?);",
		[record["id"], int(record["guild_id"]), float(record["tax_pct"]), int(record["treasury"]),
		JSON.stringify(record.get("registered", [])), int(record.get("since", 0))])


# ---------------------------------------------------------------- amigos

func list_friends(character_id: int) -> Array:
	return _rows("""SELECT c.id, c.name, c.class_id, c.level FROM friends f JOIN characters c ON c.id = f.friend_id
			WHERE f.character_id = ? ORDER BY c.name_key;""", [character_id])


func add_friendship(a: int, b: int) -> bool:
	_exec("BEGIN;")
	var ok := _exec("INSERT OR IGNORE INTO friends (character_id, friend_id, since) VALUES (?, ?, ?);", [a, b, _now()]) 		and _exec("INSERT OR IGNORE INTO friends (character_id, friend_id, since) VALUES (?, ?, ?);", [b, a, _now()])
	_exec("COMMIT;" if ok else "ROLLBACK;")
	return ok


func remove_friendship(a: int, b: int) -> bool:
	return _exec("DELETE FROM friends WHERE (character_id = ? AND friend_id = ?) OR (character_id = ? AND friend_id = ?);", [a, b, b, a])


# ---------------------------------------------------------------- utilidades

func _exec(sql: String, bindings: Array = []) -> bool:
	var ok: bool = _db.call("query_with_bindings", sql, bindings) if not bindings.is_empty() else _db.call("query", sql)
	if not ok:
		push_error("[db] %s | %s" % [_db.get("error_message"), sql.substr(0, 80)])
	return ok


## Linhas do último SELECT com chaves String (a extensão devolve StringName).
func _rows(sql: String, bindings: Array) -> Array:
	if not _exec(sql, bindings):
		return []
	var out: Array = []
	for row: Dictionary in _db.get("query_result"):
		var d := {}
		for k: Variant in row:
			d[str(k)] = row[k]
		out.append(d)
	return out


static func _now() -> int:
	return int(Time.get_unix_time_from_system())
