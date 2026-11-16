class_name ServerMonster
extends ServerEntity
## Monstro no servidor. IA: parado/vagando -> perseguindo -> atacando -> voltando para casa.

enum State { IDLE, CHASE, ATTACK, RETURN }

var def_id: String
var region: RegionInstance
var temporary: bool = false # monstro de evento: não renasce
var event_id: int = 0
var spawned_once: bool = false
var invulnerable: bool = false # evento: o portão só pode ser ferido depois da etapa certa
var def: Dictionary
var home: Vector2
var spawn_radius: float
var state: State = State.IDLE
var target_id: int = 0
var attack_ready_at: float = 0.0
var respawn_at: float = 0.0
var next_repath: float = 0.0
var next_wander: float = 0.0
var damage_by: Dictionary = {} # peer_id -> dano causado (define quem é o dono do drop)


func level() -> int:
	return int(def.get("level", 1))


func defense() -> float:
	return float(def.get("defense", 0.0))


func top_damager() -> int:
	var best := 0
	var best_dmg := -1.0
	for peer: int in damage_by:
		if float(damage_by[peer]) > best_dmg:
			best_dmg = float(damage_by[peer])
			best = peer
	return best
