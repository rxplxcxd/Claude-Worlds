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
## Phase 1 stores the registry locally (user://). In multiplayer phases the
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


func _ready() -> void:
	load_world()


## Loads the genesis state and applies locally saved changes (foundings).
func load_world() -> void:
	_settlements.clear()
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


## Founds a new settlement. Returns the record, or {} if the request violates
## the rules (e.g. no human founder).
func found_settlement(template_path: String, founder_player_id: String, settlement_name: String = "") -> Dictionary:
	if not Ids.has_prefix(founder_player_id, "plr"):
		push_error("WorldState: a settlement can only be founded by a human player (got '%s')" % founder_player_id)
		return {}
	var template := _read_json(template_path)
	if template.is_empty():
		push_error("WorldState: unknown founding template " + template_path)
		return {}
	var label := settlement_name.strip_edges()
	if label == "":
		label = template.get("default_name", "Neue Siedlung")
	var location: Dictionary = template.get("location", {})
	var record := {
		"settlement_id": Ids.generate("stl"),
		"name": label,
		"template_path": template_path,
		"template_id": template.get("template_id", ""),
		"founder_player_id": founder_player_id,
		"resident_player_ids": [founder_player_id],
		"founded_at_game_minutes": GameClock.get_total_minutes(),
		"founded_at_unix": int(Time.get_unix_time_from_system()),
		"world_id": world_id,
		"planet_id": planet_id,
		"continent_id": location.get("continent_id", ""),
		"region_id": location.get("region_id", ""),
		"order_on_planet": _settlements.size() + 1,
	}
	_settlements.append(record)
	save_world()
	settlement_founded.emit(record)
	return record


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
	f.store_string(JSON.stringify({"world_id": world_id, "settlements": _settlements}, "  "))


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


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
