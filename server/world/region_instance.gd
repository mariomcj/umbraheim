class_name RegionInstance
extends RefCounted
## Uma região do mundo rodando no servidor: grade de navegação (da cena da região),
## monstros, drops, NPCs, zonas seguras, portais e os jogadores que estão nela.
## O GameServer simula todas as regiões ao mesmo tempo, no mesmo tick.

var id: String # id da instância (igual ao da região, ou "<região>@<faixa>" nos eventos)
var data_id: String # id dos dados (data/regions/<data_id>.json)
var data: Dictionary
var grid: NavGrid
var monsters: MonsterSystem
var drops: DropSystem
var npcs: NpcSystem
var safe: SafeZones
var spatial: SpatialHash
var players: Dictionary = {} # peer_id -> ServerPlayer


func _init(server: GameServer, region_id: String, half_extent: float, cell_m: float, instance_id: String = "") -> void:
	id = instance_id if instance_id != "" else region_id
	data_id = region_id
	data = GameConfig.region(region_id)
	grid = WorldBuilder.build_nav_grid(data, half_extent)
	safe = SafeZones.new(data)
	spatial = SpatialHash.new(cell_m)
	npcs = NpcSystem.new(server, self)
	drops = DropSystem.new(server, self, GameConfig.table("drops"))
	monsters = MonsterSystem.new(server, self, MonsterCatalog.from_config())
	monsters.spawn_region(data)


func is_event() -> bool:
	return data.has("event")


## Abre ou fecha um bloqueio dinâmico (dynamic_blockers) na grade.
func set_blocker(blocker_id: String, solid: bool) -> void:
	WorldBuilder.apply_blockers(grid, data, solid, [blocker_id])


func display_name() -> String:
	return str(data.get("name", id))


func level_req() -> int:
	return int(data.get("level_req", 1))


## Ponto nomeado dos dados (player_spawn, return_point, teleport_point...) num lugar andável.
func point(key: String, fallback_key: String = "player_spawn") -> Vector2:
	var p: Array = data.get(key, data.get(fallback_key, [0.0, 0.0]))
	return grid.nearest_walkable_point(Vector2(float(p[0]), float(p[1])))


func portals() -> Array:
	return data.get("portals", [])


func portal(portal_id: String) -> Dictionary:
	for pt: Dictionary in portals():
		if str(pt["id"]) == portal_id:
			return pt
	return {}


func peers() -> Array:
	return players.keys()
