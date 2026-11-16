class_name GameRepository
extends RefCounted
## Camada de repositório: TUDO que o jogo guarda passa por aqui, em Dictionaries
## neutros (sem tipos do banco). A implementação atual é SqliteRepository; trocar
## por PostgreSQL é escrever outra classe com estes mesmos métodos.
##
## Conta:      {id, name, salt (hex), hash (hex), iterations}
## Personagem: {id, account_id, name, class_id, level, xp, points, stats: {str, agi, vit, ene},
##              currency, hp, mana, region_id, pos: [x, z], learned_spells,
##              items: [item (ver ItemCatalog)], journals: {region_id: {strokes, marks, discovered}}}
##              infamy, hero, evolution (0/1), quests: {quest_id: {step, count} | {done: true}}
## Resumo (seleção de personagem): {id, name, class_id, level, evolution}
## Guilda:     {id, name, symbol (hex, um índice da paleta por pixel), wins,
##              members: [{character_id, name, class_id, level, role (0 = mestre)}]}
## Amigo:      {id, name, class_id, level} (a amizade é mútua: duas linhas)


func open() -> bool:
	return false


func close() -> void:
	pass


func find_account(_name: String) -> Dictionary:
	return {}


## Retorna o id da conta criada, ou 0 (nome já existe).
func create_account(_name: String, _salt_hex: String, _hash_hex: String, _iterations: int) -> int:
	return 0


func touch_login(_account_id: int) -> void:
	pass


func list_characters(_account_id: int) -> Array:
	return []


func character_name_taken(_name: String) -> bool:
	return true


## Cria o personagem com o estado inicial dado e retorna o id (0 = falhou).
func create_character(_account_id: int, _record: Dictionary) -> int:
	return 0


func load_character(_character_id: int) -> Dictionary:
	return {}


func save_character(_record: Dictionary) -> bool:
	return false


## Vários personagens de uma vez, tudo ou nada (troca entre jogadores).
func save_characters(_records: Array) -> bool:
	return false


## Maior uid de item já salvo (a fábrica de itens continua a partir dele).
func max_item_uid() -> int:
	return 0


# ---------------------------------------------------------------- guildas

## Todas as guildas com os membros (o servidor mantém em memória).
func load_guilds() -> Array:
	return []


func guild_name_taken(_name: String) -> bool:
	return true


## Cria a guilda com o mestre como primeiro membro; retorna o id (0 = nome já existe ou falhou).
func create_guild(_name: String, _symbol: String, _master_character_id: int) -> int:
	return 0


## Apaga a guilda e todos os vínculos de membro.
func delete_guild(_guild_id: int) -> bool:
	return false


## Entra na guilda ou muda de cargo (mantém a data de entrada).
func set_guild_member(_guild_id: int, _character_id: int, _role: int) -> bool:
	return false


func remove_guild_member(_character_id: int) -> bool:
	return false


func set_guild_symbol(_guild_id: int, _symbol: String) -> bool:
	return false


## +1 vitória em guerra de guildas.
func add_guild_win(_guild_id: int) -> bool:
	return false


# ---------------------------------------------------------------- amigos

func list_friends(_character_id: int) -> Array:
	return []


## Amizade mútua (os dois lados de uma vez).
func add_friendship(_a: int, _b: int) -> bool:
	return false


func remove_friendship(_a: int, _b: int) -> bool:
	return false


# ---------------------------------------------------------------- castelo

## {id, guild_id (0 = sem dona), tax_pct, treasury, registered: [guild_id], since} ou {}.
func load_castle(_castle_id: String) -> Dictionary:
	return {}


func save_castle(_record: Dictionary) -> bool:
	return false
