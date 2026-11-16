class_name Protocol
extends RefCounted
## Constantes do protocolo cliente <-> servidor.
## Incrementar VERSION a cada mudança incompatível; o servidor recusa versões diferentes.

const VERSION := 18 # v2: diário | v3: combate | v4: inventário | v5: joias e forja | v6: cidade, lojas, armazém | v7: contas | v8: chat, grupo e troca | v9: snapshot binário, interesse, predição | v10: várias regiões, portais, teletransporte | v11: chefes, monstros dourados, avisos | v12: PvP, Fora da Lei e Herói | v13: guildas, guerra de guildas e amigos | v14: três classes, invocações, bônus temporários, missões e evolução | v15: eventos com horário (Fortaleza Sitiada) | v16: Arena das Ondas e Círculo que Encolhe (painel com extra e anel) | v17: reset e maestria | v18: cerco ao castelo e impostos

## Ações de item (rpc_item_action).
const ITEM_MOVE := 0 # dest = 0 (inventário em x, y), 1 + slot de equipamento, forja (200) ou armazém (300, em x, y)
const ITEM_AUTO := 1 # botão direito: equipa ou desequipa
const ITEM_DROP := 2 # joga no chão
const ITEM_USE_ON := 3 # usa (joia) sobre o item dest (uid)
const ITEM_USE := 4 # usa um consumível (poção, pergaminho, grimório)

## Efeito visual de refino/forja (rpc_refine_fx).
const FX_SUCCESS := 0
const FX_FAIL := 1
const FX_DESTROYED := 2

## Canais de chat (rpc_chat / rpc_chat_message).
enum Chat { GENERAL, WHISPER, PARTY, SYSTEM, GUILD }

## Ações de grupo (rpc_party_action, com o nome do alvo quando precisa).
enum Party { INVITE, ACCEPT, DECLINE, LEAVE, KICK }

## Ações de troca (rpc_trade_action).
enum Trade { REQUEST, ACCEPT, DECLINE, ADD_ITEM, REMOVE_ITEM, SET_CURRENCY, LOCK, CONFIRM, CANCEL }

## Convites que pedem resposta (rpc_prompt).
enum Prompt { PARTY_INVITE, TRADE_REQUEST, GUILD_INVITE, GUILD_WAR, FRIEND_REQUEST }

## Ações de guilda (rpc_guild_action: alvo = nome do personagem ou da guilda; extra = símbolo).
## CREATE: alvo = nome da guilda, extra = símbolo. SET_SYMBOL: extra = símbolo.
enum Guild { CREATE, INVITE, ACCEPT, DECLINE, LEAVE, KICK, PROMOTE, DEMOTE, TRANSFER, DISBAND,
	WAR_DECLARE, WAR_ACCEPT, WAR_DECLINE, SET_SYMBOL }

## Ações da lista de amigos (rpc_friend_action, com o nome).
enum Friend { REQUEST, ACCEPT, DECLINE, REMOVE }

## Ações do castelo (rpc_castle_action, no Arauto do Cerco). SET_TAX: valor em milésimos (50 = 5%).
enum Castle { REGISTER, ENTER, SET_TAX, WITHDRAW }

## Ações de missão (rpc_quest_action, com o id da missão; precisa da janela do NPC aberta).
enum Quest { ACCEPT, TURN_IN, ABANDON }

## Peer id do servidor na multiplayer API da Godot.
const SERVER_PEER_ID := 1

## Tipo de entidade (meta = KIND * 65536 + índice do tipo).
const KIND_PLAYER := 0
const KIND_MONSTER := 1
const KIND_SUMMON := 2 # invocação aliada (tipo = índice em SummonSystem.summon_type_ids)
const META_KIND_SHIFT := 65536

## Tipos de dano (cor do número flutuante).
const DMG_NORMAL := 0
const DMG_CRITICAL := 1
const DMG_EXCELLENT := 2
const DMG_HEAL := 3 # número verde/azul de poção

## Raridade dos drops.
const RARITY_NORMAL := 0
const RARITY_EXCELLENT := 1
const RARITY_JEWEL := 2
const RARITY_CURRENCY := 3
const RARITY_ANCESTRAL := 4

## Atributos distribuíveis (índice usado no RPC de distribuição de pontos).
const STAT_KEYS: PackedStringArray = ["str", "agi", "vit", "ene"]

## Estado do próprio jogador (PackedInt64Array) — índices.
## SPELLS = máscara de bits das magias aprendidas (índice na lista da classe).
enum PS { HP, HP_MAX, MANA, MANA_MAX, LEVEL, XP, XP_NEXT, POINTS, STR, AGI, VIT, ENE,
	CURRENCY, MAGIC_MIN, MAGIC_MAX, DEFENSE, ALIVE, RESPAWN_MS, ITEMS, SPELLS, MOVE_SPEED_CMS,
	RESETS, MASTER_LEVEL, MASTER_XP, MASTER_XP_NEXT, MASTER_POINTS, COUNT }


static func make_meta(kind: int, type_index: int) -> int:
	return kind * META_KIND_SHIFT + type_index


static func meta_kind(meta: int) -> int:
	return meta / META_KIND_SHIFT


static func meta_type(meta: int) -> int:
	return meta % META_KIND_SHIFT
