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
## continent) and founding claims its region as the settlement's TERRITORY.
## Saves from Phase 1 (no position) are migrated to the best free site.
##
## The registry is stored locally (user://). In multiplayer phases the
## authoritative server owns this registry and performs found_settlement();
## the client only sends the founding request.

signal settlement_founded(record: Dictionary)

const GENESIS_PATH := "res://data/world/genesis.json"
const DEFAULT_SAVE_PATH := "user://worlds_world.json"

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


func _ready() -> void:
	load_world()


## Loads the genesis state and applies locally saved changes (foundings).
func load_world() -> void:
	_settlements.clear()
	_territories.clear()
	migrated_settlement_ids.clear()
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
	_migrate_positions()


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
	_settlements.append(record)
	_claim_territory(record)
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


## Founding claims the settlement's region (one region per settlement in
## Phase 2; growth of territories follows with Phase 4/9).
func _claim_territory(record: Dictionary) -> void:
	var region_id: String = record.get("region_id", "")
	if region_id == "" or territory_of_region(region_id) != {}:
		return
	var t := {
		"territory_id": Ids.generate("ter"),
		"owner_settlement_id": record["settlement_id"],
		"owner_player_id": record.get("founder_player_id", ""),
		"region_ids": [region_id],
		"kind": "settlement",
		"claimed_at_unix": int(GameClock.get_utc_unix()),
	}
	_territories.append(t)
	record["territory_id"] = t["territory_id"]


func get_territories() -> Array[Dictionary]:
	return _territories


func territory_of_region(region_id: String) -> Dictionary:
	for t in _territories:
		if (t.get("region_ids", []) as Array).has(region_id):
			return t
	return {}


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
	f.store_string(JSON.stringify({"world_id": world_id, "settlements": _settlements, "territories": _territories}, "  "))


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
	var residents: Array = s.get("resident_player_ids", [])
	if residents.is_empty():
		return "%s has no human resident (NPC-only settlements are not allowed)" % id
	return ""


## Territory invariants: every territory belongs to an existing settlement,
## a region belongs to at most one territory.
func validate_territories() -> PackedStringArray:
	var out: PackedStringArray = []
	var seen := {}
	for t in _territories:
		if get_settlement(t.get("owner_settlement_id", "")).is_empty():
			out.append("%s has no owner settlement" % t.get("territory_id", "?"))
		for r in t.get("region_ids", []):
			if seen.has(r):
				out.append("region %s claimed twice" % r)
			seen[r] = true
	return out


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
