extends Node
## Registry of everything that exists on the planet (Phase 1: settlements).
##
## BINDING DESIGN RULE (docs/WORLD_DESIGN.md §1, "Leerer Planet"):
##   * The planet starts completely EMPTY (data/world/genesis.json has no
##     settlements). Nature and resources exist, people do not.
##   * A settlement only comes into existence when a HUMAN player founds it.
##   * There are no NPC-only settlements: every settlement has a human
##     founder and at least one human resident.
##
## Phase 2: every settlement has a POSITION on the planet (lat/lon, region,
## continent). Paket 2.1 (DESIGN_DIRECTIVES.md, TERRITORY_SYSTEM.md):
##   * Founding claims its own TERRITORY: a 1 × 1 km square (spherical
##     polygon) – no longer a whole natural region; regions only describe
##     nature, any number of settlements fit into one region.
##   * New independent settlements need 20 km to every territory border
##     (geodesic, border to border). Territories must never overlap.
##   * One active founding per player (abuse protection).
##   * The core area never lapses (no penalty for breaks). Expansions are
##     stored separately (record "expansions", later phases).
## Saves from Phase 1 (no position) and Phase 2 (region claims) are migrated.
##
## The registry is stored locally (user://). In multiplayer phases the
## authoritative server owns this registry and performs found_settlement();
## the client only sends the founding request.

signal settlement_founded(record: Dictionary)

const GENESIS_PATH := "res://data/world/genesis.json"
const DEFAULT_SAVE_PATH := "user://worlds_world.json"
## 1 = Phase 1, 2 = Phase 2 (position + region claim), 3 = Paket 2.1 (polygon territories),
## 4 = Phase 3 (living world: npcs[] gain personality/profession/birth_day,
##     settlement gains time_zone, sim {version, simulated_at, npcs{state}},
##     visual_states{}) – filled lazily by SettlementSim.create (migration)
const SCHEMA_VERSION := 4

var world_id: String = ""
var planet_id: String = ""
var planet_name: String = ""
var rules: Dictionary = {}
var save_path: String = DEFAULT_SAVE_PATH

var _settlements: Array[Dictionary] = []
## Territories: {territory_id, owner_settlement_id, owner_player_id,
## region_ids[], kind, claimed_at_unix}. Created by founding only.
var _territories: Array[Dictionary] = []
## Set when load_world() moved an old settlement onto the planet.
var migrated_settlement_ids: Array[String] = []
## Set when load_world() converted a Phase-2 region claim into a 1 km² territory.
var migrated_territory_ids: Array[String] = []


## The world authority (in-process development adapter, server-capable) and
## the client interface all game code uses to read/change the shared world.
var authority: WorldAuthority
var client: WorldClient
var _tick_left := 300.0
const TICK_SECONDS := 300.0   # S2 sweep interval while the game runs


func _ready() -> void:
	load_world()
	_start_authority()


func _start_authority() -> void:
	authority = WorldAuthority.create(func(): return _settlements, func(): return int(GameClock.get_utc_unix()))
	client = LocalWorldClient.connect_to(authority, LocalProfile.player_id)
	var mine := get_settlement_of(LocalProfile.player_id)
	authority.observer_region = str(mine.get("region_id", ""))


func _process(delta: float) -> void:
	_tick_left -= delta
	if _tick_left <= 0.0 and authority:
		_tick_left = TICK_SECONDS
		authority.tick(false)


## Loads the genesis state and applies locally saved changes (foundings).
func load_world() -> void:
	_settlements.clear()
	_territories.clear()
	migrated_settlement_ids.clear()
	migrated_territory_ids.clear()
	var genesis := _read_json(GENESIS_PATH)
	world_id = genesis.get("world_id", "wld_prime")
	planet_id = genesis.get("planet_id", "")
	planet_name = genesis.get("planet_name", "")
	rules = genesis.get("rules", {})
	if not genesis.get("settlements", []).is_empty():
		push_error("WorldState: genesis must not contain settlements (empty planet rule)")
	var saved := _read_json(save_path) if FileAccess.file_exists(save_path) else {}
	if saved.get("world_id", world_id) != world_id:
		return
	for s in saved.get("settlements", []):
		if _check_record(s) == "":
			_settlements.append(s)
		else:
			push_warning("WorldState: dropped invalid settlement record: " + _check_record(s))
	for t in saved.get("territories", []):
		_territories.append(t)
	_migrate_territories()
	_migrate_positions()


## Phase-2 saves claimed whole regions: convert every such territory into the
## settlement's 1 × 1 km start territory (keeps its ID and history).
func _migrate_territories() -> void:
	var changed := false
	var p := Geography.planet()
	if p == null:
		return
	for i in _territories.size():
		var t: Dictionary = _territories[i]
		if t.has("geometry"):
			continue
		var s := get_settlement(t.get("owner_settlement_id", ""))
		if s.is_empty() or not s.has("position"):
			continue
		var nt := TerritoryGeometry.make_territory(t["territory_id"], s["settlement_id"], t.get("owner_player_id", s.get("founder_player_id", "")),
				float(s["position"]["lat"]), float(s["position"]["lon"]), p.radius_km, int(t.get("claimed_at_unix", GameClock.get_utc_unix())))
		nt["history"].append({"version": 2, "at_unix": int(GameClock.get_utc_unix()), "change": "migrated: region claim %s → 1 × 1 km start territory" % str(t.get("region_ids", []))})
		nt["version"] = 2
		_territories[i] = nt
		_ensure_area(s)
		migrated_territory_ids.append(nt["territory_id"])
		changed = true
	if changed:
		save_world()


## Phase-1 saves have no position on the planet: place them on the best free
## site (deterministic) and claim the region, once.
func _migrate_positions() -> void:
	var changed := false
	for s in _settlements:
		if s.has("position"):
			continue
		var site := Geography.best_site(_settlements, _territories)
		if site.is_empty():
			continue
		_apply_site(s, site)
		_claim_territory(s)
		migrated_settlement_ids.append(s["settlement_id"])
		changed = true
	if changed:
		save_world()


## Founds a new settlement. Returns the record, or {} if the request violates
## the rules (e.g. no human founder).
func found_settlement(template_path: String, founder_player_id: String, settlement_name: String = "", site: Dictionary = {}) -> Dictionary:
	if not Ids.has_prefix(founder_player_id, "plr"):
		push_error("WorldState: a settlement can only be founded by a human player (got '%s')" % founder_player_id)
		return {}
	if not get_settlement_of(founder_player_id).is_empty():
		push_error("WorldState: %s already lives in a settlement (one active founding per player)" % founder_player_id)
		return {}
	var template := _read_json(template_path)
	if template.is_empty():
		push_error("WorldState: unknown founding template " + template_path)
		return {}
	# Location: the chosen site (globe) or, without a choice, the best free site.
	if site.is_empty():
		site = Geography.best_site(_settlements, _territories)
	elif site.has("lat"):
		site = Geography.rate_site(site["lat"], site["lon"], _settlements, _territories)
	if site.is_empty() or not site.get("valid", false):
		push_error("WorldState: invalid founding site %s" % str(site.get("reasons", [])))
		return {}
	var label := settlement_name.strip_edges()
	if label == "":
		label = template.get("default_name", "Neue Siedlung")
	var record := {
		"settlement_id": Ids.generate("stl"),
		"name": label.substr(0, 32),
		"template_path": template_path,
		"template_id": template.get("template_id", ""),
		"founder_player_id": founder_player_id,
		"resident_player_ids": [founder_player_id],
		"founded_at_game_minutes": GameClock.get_total_minutes(),
		"founded_at_unix": int(GameClock.get_utc_unix()),
		"timezone": GameClock.timezone_name,
		"utc_offset_minutes_at_founding": GameClock.utc_offset_minutes,
		"world_id": world_id,
		"planet_id": planet_id,
		"order_on_planet": _settlements.size() + 1,
	}
	_apply_site(record, site)
	record["time_zone"] = {"name": GameClock.timezone_name, "offset_min": GameClock.utc_offset_minutes}
	_settlements.append(record)
	_claim_territory(record)
	if authority and CharacterCatalog.is_available():
		authority.ensure_population(record)   # founding population (Master §4.2)
		authority.observer_region = str(record.get("region_id", ""))
	save_world()
	settlement_founded.emit(record)
	return record


func _apply_site(record: Dictionary, site: Dictionary) -> void:
	var sample: Dictionary = site["sample"]
	var region: Dictionary = site["region"]
	record["position"] = {"lat": snappedf(sample["lat"], 0.0001), "lon": snappedf(sample["lon"], 0.0001)}
	record["region_id"] = region.get("region_id", "")
	record["region_name"] = region.get("name", "")
	record["continent_id"] = region.get("continent_id", "")
	var p := Geography.planet()
	record["continent_name"] = p.continent(record["continent_id"]).get("name", "") if p else ""
	record["site_score"] = site.get("score", 0)
	record["terrain"] = sample.get("biome", "")
	var diff: Dictionary = site.get("difficulty", {})
	record["difficulty"] = diff.get("class", "")
	record["difficulty_requirements"] = diff.get("requirements", [])
	_ensure_area(record)


## Settlement area (the locally playable grid) – distinct from the territory.
## Start: 1 × 1 km, 10 m tiles, aligned east/north at the position.
func _ensure_area(record: Dictionary) -> void:
	if record.has("settlement_area") or not record.has("position"):
		return
	record["settlement_area"] = {
		"origin": [record["position"]["lat"], record["position"]["lon"]],
		"frame": "east_north", "size_m": 1000, "tile_m": 10,
		"note": "Phase 4 fills the full area; today the founding template (~260 m) is its core.",
	}


## Founding claims exactly the 1 × 1 km start square (TerritoryGeometry).
func _claim_territory(record: Dictionary) -> void:
	if record.get("territory_id", "") != "" and not territory_of_settlement(record["settlement_id"]).is_empty():
		return
	var p := Geography.planet()
	if p == null or not record.has("position"):
		return
	var t := TerritoryGeometry.make_territory(Ids.generate("ter"), record["settlement_id"], record.get("founder_player_id", ""),
			float(record["position"]["lat"]), float(record["position"]["lon"]), p.radius_km, int(GameClock.get_utc_unix()))
	_territories.append(t)
	record["territory_id"] = t["territory_id"]


func get_territories() -> Array[Dictionary]:
	return _territories


func territory_of_settlement(settlement_id: String) -> Dictionary:
	for t in _territories:
		if t.get("owner_settlement_id", "") == settlement_id:
			return t
	return {}


## Settlements whose position lies in the natural region (any number).
func settlements_in_region(region_id: String) -> Array:
	return _settlements.filter(func(s): return s.get("region_id", "") == region_id)


func get_settlement(settlement_id: String) -> Dictionary:
	for s in _settlements:
		if s.get("settlement_id", "") == settlement_id:
			return s
	return {}


func get_settlements() -> Array[Dictionary]:
	return _settlements


func is_planet_empty() -> bool:
	return _settlements.is_empty()


## The settlement the player lives in, or {} (Phase 1: one per player).
func get_settlement_of(player_id: String) -> Dictionary:
	for s in _settlements:
		if (s.get("resident_player_ids", []) as Array).has(player_id):
			return s
	return {}


## Checks the empty-planet invariants for every settlement.
func validate() -> PackedStringArray:
	var out: PackedStringArray = []
	for s in _settlements:
		var p := _check_record(s)
		if p != "":
			out.append(p)
	return out


func save_world() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("WorldState: could not save (%s)" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify({"schema_version": SCHEMA_VERSION, "world_id": world_id, "settlements": _settlements, "territories": _territories}, "  ", true, true))


## Switches storage (used by tests so the real local world is untouched).
func use_storage(path: String, wipe: bool) -> void:
	save_path = path
	if wipe and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	load_world()


func _check_record(s: Dictionary) -> String:
	var id: String = s.get("settlement_id", "?")
	if not Ids.has_prefix(s.get("founder_player_id", ""), "plr"):
		return "%s has no human founder" % id
	# Founded by a human – later the settlement may lose all human residents
	# (accounts deleted, players moved away): it persists and lives on with
	# its NPCs; it is abandoned only when nobody lives there any more
	# (docs/ARCHITECTURE_AUDIT.md A10, SETTLEMENT_SYSTEM.md).
	return ""


## Territory invariants: every territory belongs to an existing settlement,
## has a geometry and an index cover, and territories never overlap.
func validate_territories() -> PackedStringArray:
	var out: PackedStringArray = []
	for t in _territories:
		var id: String = t.get("territory_id", "?")
		if get_settlement(t.get("owner_settlement_id", "")).is_empty():
			out.append("%s has no owner settlement" % id)
		if TerritoryGeometry.rings_of(t).is_empty():
			out.append("%s has no geometry" % id)
		if (t.get("cover_l8", []) as Array).is_empty():
			out.append("%s has no index cover" % id)
	for pair in TerritoryGeometry.overlapping_pairs(_territories):
		out.append("territories %s and %s overlap" % pair)
	return out


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
