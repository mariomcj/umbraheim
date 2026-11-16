class_name ServerPlayer
extends ServerEntity
## Personagem de um jogador no servidor. Tudo aqui é autoritativo.

var peer_id: int
var character_id: int = 0 # id no banco
var account_id: int = 0
var char_name: String = ""
var region_id: String = ""
var class_id: String
var level: int = 1
var xp: int = 0
var points: int = 0
var stats: Dictionary = {} # str/agi/vit/ene -> int
var derived: Dictionary = {} # calculado por StatCalculator
var mana: float = 0.0
var currency: int = 0
var inventory: InventoryGrid
var storage: InventoryGrid # armazém (cofre)
var items: Dictionary = {} # uid -> item (inventário, equipados, forja e armazém)
var equipment: Dictionary = {} # nome do slot -> uid
var bonuses: Dictionary = {} # bônus somados do equipamento
var npc_open: String = "" # NPC com janela aberta (ex.: "forja", "ferreiro")
var learned_spells: int = 0 # máscara de bits (índice na lista de magias da classe)
var cast_error: String = "" # motivo da última recusa de PvP
var infamy: int = 0 # mortes sem motivo (nível de Fora da Lei)
var hero: int = 0 # Fora da Lei derrubados
var infamy_decay: float = 0.0 # progresso até perder 1 de infâmia (s)
var self_defense: Dictionary = {} # id do agressor -> até quando posso revidar sem penalidade
var evolution: int = 0 # 0 = classe base, 1 = evoluída (missão)
var quests: Dictionary = {} # quest_id -> {step, count} ou {done: true}
var resets: int = 0 # renascimentos
var master_level: int = 0 # maestria (depois do nível máximo)
var master_xp: int = 0
var master_points: int = 0
var mastery: Dictionary = {} # nó -> pontos
var mastery_bonuses: Dictionary = {} # calculado pelo MasterySystem
var ignore_equipment: bool = false # Círculo que Encolhe: o equipamento de fora não vale
var buffs: Dictionary = {} # id -> {name, until, stats} (magias de bônus temporário)
var portal_message_at: float = 0.0 # evita repetir o aviso de nível do portal
var use_ready_at: Dictionary = {} # tipo de uso (heal_hp, return...) -> tempo em que fica pronto

var move_dir: Vector2 = Vector2.ZERO
## Ação atual: {} | {type:"move"} | {type:"cast", spell, target_id, target_pos, repeat}
## | {type:"pickup", drop_id}
var action: Dictionary = {}
var cooldowns: Dictionary = {} # índice da magia -> tempo em que fica pronta
var next_repath: float = 0.0
var respawn_at: float = 0.0
var last_state := PackedInt64Array()


const ADDITIVE_BONUSES: PackedStringArray = ["magic_min", "magic_max", "defense", "hp_max", "mana_max", "attack_speed"]
const COMBAT_BONUSES: PackedStringArray = ["crit_chance", "excellent_chance", "damage_pct", "damage_reduction_pct",
	"reflect_pct", "hp_on_kill_frac", "mana_on_kill_frac", "currency_pct"]


func equipped_items() -> Array:
	var out: Array = []
	for slot: String in equipment:
		out.append(items[equipment[slot]])
	return out


## Atributos derivados = fórmulas da classe (com os atributos somados aos do equipamento)
## + bônus aditivos e percentuais dos itens equipados.
func recompute(calc: StatCalculator, catalog: ItemCatalog) -> void:
	bonuses = catalog.equipment_bonuses(equipped_items()) if not ignore_equipment else {}
	for k: String in mastery_bonuses: # maestria: soma como bônus de equipamento (vale até no Círculo)
		bonuses[k] = float(bonuses.get(k, 0.0)) + float(mastery_bonuses[k])
	for b: Dictionary in buffs.values(): # bônus temporários somam como se fossem de equipamento
		for k: String in b["stats"]:
			bonuses[k] = float(bonuses.get(k, 0.0)) + float(b["stats"][k])
	var effective := stats.duplicate()
	for s: String in Protocol.STAT_KEYS:
		effective[s] = int(effective.get(s, 0)) + roundi(float(bonuses.get("stat_" + s, 0.0)))
	derived = calc.compute(level, effective)
	for k in ADDITIVE_BONUSES:
		derived[k] = float(derived.get(k, 0.0)) + float(bonuses.get(k, 0.0))
	derived["hp_max"] = float(derived["hp_max"]) * (1.0 + float(bonuses.get("hp_max_pct", 0.0)))
	derived["mana_max"] = float(derived["mana_max"]) * (1.0 + float(bonuses.get("mana_max_pct", 0.0)))
	for k in COMBAT_BONUSES:
		derived[k] = float(bonuses.get(k, 0.0))
	var old_max := hp_max
	hp_max = float(derived.get("hp_max", 1.0))
	if old_max > 0.0 and hp > 0.0:
		hp = minf(hp, hp_max)
	mana = minf(mana, mana_max())


func mana_max() -> float:
	return float(derived.get("mana_max", 0.0))


func full_restore() -> void:
	hp = hp_max
	mana = mana_max()


func state_array(xp_next: int, respawn_ms: int, master_next: int = 0) -> PackedInt64Array:
	var s := PackedInt64Array()
	s.resize(Protocol.PS.COUNT)
	s[Protocol.PS.HP] = ceili(hp)
	s[Protocol.PS.HP_MAX] = roundi(hp_max)
	s[Protocol.PS.MANA] = floori(mana)
	s[Protocol.PS.MANA_MAX] = roundi(mana_max())
	s[Protocol.PS.LEVEL] = level
	s[Protocol.PS.XP] = xp
	s[Protocol.PS.XP_NEXT] = xp_next
	s[Protocol.PS.POINTS] = points
	s[Protocol.PS.STR] = int(stats.get("str", 0))
	s[Protocol.PS.AGI] = int(stats.get("agi", 0))
	s[Protocol.PS.VIT] = int(stats.get("vit", 0))
	s[Protocol.PS.ENE] = int(stats.get("ene", 0))
	s[Protocol.PS.CURRENCY] = currency
	s[Protocol.PS.MAGIC_MIN] = roundi(float(derived.get("magic_min", 0.0)))
	s[Protocol.PS.MAGIC_MAX] = roundi(float(derived.get("magic_max", 0.0)))
	s[Protocol.PS.DEFENSE] = roundi(float(derived.get("defense", 0.0)))
	s[Protocol.PS.ALIVE] = 1 if alive else 0
	s[Protocol.PS.RESPAWN_MS] = respawn_ms
	s[Protocol.PS.ITEMS] = items.size()
	s[Protocol.PS.SPELLS] = learned_spells
	s[Protocol.PS.MOVE_SPEED_CMS] = roundi(float(derived.get("move_speed_mps", 5.0)) * 100.0)
	s[Protocol.PS.RESETS] = resets
	s[Protocol.PS.MASTER_LEVEL] = master_level
	s[Protocol.PS.MASTER_XP] = master_xp
	s[Protocol.PS.MASTER_XP_NEXT] = master_next
	s[Protocol.PS.MASTER_POINTS] = master_points
	return s


func knows_spell(index: int) -> bool:
	return (learned_spells & (1 << index)) != 0
