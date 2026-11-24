class_name WorldAuthority
extends RefCounted
## WORLD AUTHORITY – the single owner of the shared, persistent world state
## (docs/ARCHITECTURE_AUDIT.md §2, docs/SIMULATION_ARCHITECTURE.md).
##
## Scene-free and server-capable: today it runs in-process behind
## LocalWorldClient (development adapter); in Phase 12/13 the same logic runs
## in a simulation service and clients talk to it via RemoteWorldClient.
## Clients never change world state directly – they send COMMANDS which the
## authority validates (permissions, rules), applies idempotently (command_id)
## and appends to an event log.
##
## Simulation tiers per settlement (the tier decides computing effort, never
## whether something happens – SettlementCore.day_step is identical in all):
##   S0/S1 hot  – a SettlementSim is attached (someone is looking at it):
##                micro routine of every NPC + day steps
##   S2 warm    – near the observer: day steps on a periodic tick
##   S3 cold    – everything else: day steps lazily on access (or at the
##                latest on the next periodic sweep)
## Randomness only via seeds (settlement, NPC, day) → reproducible on any
## machine; graphics profiles never reach this layer.

const LOG_MAX := 500
const APPLIED_MAX := 2000
const KINDS := ["set_policy", "set_priorities", "close_path", "open_path", "join_settlement", "leave_settlement", "delete_account"]

var config: Dictionary = {}
var rules: Dictionary = {"player_migration_enabled": false}   # Phase 8
var clock: Callable                      # () -> int, authority time (UTC seconds)
var records: Callable                    # () -> Array of settlement records (shared references)
var observer_region := ""                # region of the local observer (S2 tier)
var _hot: Dictionary = {}                # settlement_id -> SettlementSim
var _data: Dictionary = {}               # settlement_id -> SettlementData
var stats := {"day_steps": 0, "commands": 0, "rejected": 0, "macro_ms": 0.0}


static func create(p_records: Callable, p_clock: Callable, p_config: Dictionary = {}) -> WorldAuthority:
	var a := WorldAuthority.new()
	a.records = p_records
	a.clock = p_clock
	a.config = p_config if not p_config.is_empty() else SettlementSim.load_config()
	return a


func now() -> int:
	return int(clock.call())


func find(settlement_id: String) -> Dictionary:
	for r in records.call():
		if r.get("settlement_id", "") == settlement_id:
			return r
	return {}


## Local offset of a settlement: fixed at founding, the same for every viewer
## (no device-dependent daylight-saving switch – the settlement keeps the
## standard offset it was founded with; see docs/LIVING_WORLD.md §2).
static func settlement_offset(record: Dictionary) -> int:
	var tz: Dictionary = record.get("time_zone", {})
	if tz.has("offset_min"):
		return int(tz["offset_min"])
	return int(record.get("utc_offset_minutes_at_founding", 0))


func data_for(record: Dictionary) -> SettlementData:
	var id: String = record.get("settlement_id", "")
	if not _data.has(id):
		var d := SettlementData.load_from_file(record.get("template_path", "res://data/settlement_templates/founding_basic.json"))
		d.apply_record(record)
		_data[id] = d
	return _data[id]


## The founding population (Master §4.2) is created by the authority at
## founding – it exists whether or not anybody ever opens the settlement.
func ensure_population(record: Dictionary) -> void:
	if record.get("npcs", []).is_empty():
		var comp: Array = config.get("founding_population", {}).get("composition", [])
		record["npcs"] = NpcRoster.generate(record.get("settlement_id", ""), data_for(record).buildings, comp)
	if not record.has("time_zone"):
		record["time_zone"] = {"name": str(record.get("timezone", "")), "offset_min": int(record.get("utc_offset_minutes_at_founding", 0))}
	var founded := int(record.get("founded_at_unix", now()))
	SettlementCore.ensure(record, config, SettlementCore.day_index(founded, settlement_offset(record)))


# --- tiers ---------------------------------------------------------------------------

func attach_hot(sim: SettlementSim) -> void:
	_hot[sim.record.get("settlement_id", "")] = sim


func detach_hot(settlement_id: String) -> void:
	_hot.erase(settlement_id)


func is_hot(settlement_id: String) -> bool:
	return _hot.has(settlement_id)


func tier_of(record: Dictionary) -> String:
	if _hot.has(record.get("settlement_id", "")):
		return "S1"
	if observer_region != "" and record.get("region_id", "") == observer_region:
		return "S2"
	return "S3"


## Brings one settlement to time t (hot: micro + macro; else macro only).
func bring_up_to_date(record: Dictionary, t: int) -> Array:
	var id: String = record.get("settlement_id", "")
	if _hot.has(id):
		return (_hot[id] as SettlementSim).advance_to(t)
	ensure_population(record)
	var off := settlement_offset(record)
	var us := Time.get_ticks_usec()
	var events := []
	while SettlementCore.day_start_utc(int(record["core"]["day"]) + 1, off) <= t:
		events.append_array(SettlementCore.day_step(record, data_for(record), config, int(record["core"]["day"]) + 1, off))
		stats["day_steps"] = int(stats["day_steps"]) + 1
	stats["macro_ms"] = float(stats["macro_ms"]) + (Time.get_ticks_usec() - us) / 1000.0
	return events


## Periodic sweep: S2 settlements every tick, S3 settlements are only brought
## up to date when accessed or when `include_cold` (e.g. on a slow schedule).
func tick(include_cold: bool = false) -> void:
	var t := now()
	for r in records.call():
		var tier := tier_of(r)
		if tier == "S2" or (tier == "S3" and include_cold):
			bring_up_to_date(r, t)


## Current authoritative state of a settlement (lazy S3 update on access).
func snapshot(settlement_id: String) -> Dictionary:
	var r := find(settlement_id)
	if r.is_empty():
		return {}
	bring_up_to_date(r, now())
	if _hot.has(settlement_id):
		(_hot[settlement_id] as SettlementSim).store()
	return r


## Canonical hash of the shared state of a settlement (everything every
## client must see identically; excludes local-only presentation data).
static func state_hash(record: Dictionary) -> String:
	var shared := {}
	for k in ["settlement_id", "npcs", "core", "lifecycle", "visual_states", "resident_player_ids", "founder_status", "admin_player_ids", "nav_changes", "authority"]:
		if record.has(k):
			shared[k] = record[k]
	return JSON.stringify(JSON.parse_string(JSON.stringify(shared)), "", true).sha256_text()


# --- commands --------------------------------------------------------------------------

## Validates and applies a command. Returns {ok, seq} or {ok: false, reason}.
## Idempotent: a repeated command_id returns the first result without effect.
func submit(cmd: Dictionary) -> Dictionary:
	var cid := str(cmd.get("command_id", ""))
	var issuer := str(cmd.get("issuer", ""))
	var kind := str(cmd.get("kind", ""))
	if cid == "" or not Ids.has_prefix(issuer, "plr") or not kind in KINDS:
		return _reject("malformed command")
	var record := find(str(cmd.get("settlement_id", "")))
	if record.is_empty():
		return _reject("unknown settlement")
	var auth: Dictionary = record.get("authority", {"seq": 0, "log": [], "applied": {}})
	if auth["applied"].has(cid):
		return {"ok": true, "duplicate": true, "seq": int(auth["applied"][cid])}
	var t := now()
	bring_up_to_date(record, t)   # commands act on the CURRENT world
	var why := _check_permission(record, issuer, kind)
	if why != "":
		return _reject(why)
	var payload: Dictionary = cmd.get("payload", {})
	var res := _apply(record, issuer, kind, payload, t)
	if not res.get("ok", false):
		return _reject(str(res.get("reason", "rejected")))
	auth["seq"] = int(auth["seq"]) + 1
	var entry := {"seq": auth["seq"], "t": t, "command_id": cid, "issuer": pseudonym(issuer) if kind == "delete_account" else issuer, "kind": kind, "payload": payload}
	var log_list: Array = auth["log"]
	log_list.append(entry)
	if log_list.size() > LOG_MAX:
		auth["log"] = log_list.slice(log_list.size() - LOG_MAX)
	auth["applied"][cid] = auth["seq"]
	if auth["applied"].size() > APPLIED_MAX:
		var keys: Array = auth["applied"].keys()
		keys.sort_custom(func(x, y): return int(auth["applied"][x]) < int(auth["applied"][y]))
		for k in keys.slice(0, keys.size() - APPLIED_MAX):
			auth["applied"].erase(k)
	record["authority"] = auth
	stats["commands"] = int(stats["commands"]) + 1
	return {"ok": true, "seq": auth["seq"]}


func _reject(reason: String) -> Dictionary:
	stats["rejected"] = int(stats["rejected"]) + 1
	return {"ok": false, "reason": reason}


## Who may do what. Administration (policy, priorities, construction-site
## closures) belongs to the settlement's administrators: the founder and –
## when the founder's account no longer exists – every human resident.
func _check_permission(record: Dictionary, issuer: String, kind: String) -> String:
	var residents: Array = record.get("resident_player_ids", [])
	match kind:
		"join_settlement":
			if not bool(rules.get("player_migration_enabled", false)):
				return "player migration between settlements arrives in Phase 8"
			if issuer in residents:
				return "already a resident"
			for r in records.call():
				if issuer in r.get("resident_player_ids", []):
					return "the player already lives in another settlement"
			return ""
		"leave_settlement", "delete_account":
			return "" if issuer in residents or issuer == record.get("founder_player_id", "") else "not a resident"
		_:
			return "" if issuer in admins_of(record) else "only the settlement administration may do this"


static func admins_of(record: Dictionary) -> Array:
	var admins: Array = record.get("admin_player_ids", [])
	if admins.is_empty():
		if record.get("founder_status", "active") != "deleted" and record.get("founder_player_id", "") in record.get("resident_player_ids", []):
			admins = [record["founder_player_id"]]
		else:
			admins = record.get("resident_player_ids", []).duplicate()
	return admins


func _apply(record: Dictionary, issuer: String, kind: String, payload: Dictionary, t: int) -> Dictionary:
	var core: Dictionary = record["core"]
	match kind:
		"set_policy":
			if not payload.has("open_for_newcomers"):
				return {"ok": false, "reason": "missing open_for_newcomers"}
			core["policy"]["open_for_newcomers"] = bool(payload["open_for_newcomers"])
		"set_priorities":
			var pr: Array = payload.get("priorities", [])
			var known := SettlementCore.FUNCTIONS
			if pr.size() != known.size() or pr.any(func(f): return not f in known):
				return {"ok": false, "reason": "priorities must list every function once"}
			var seen := {}
			for f in pr:
				seen[f] = true
			if seen.size() != known.size():
				return {"ok": false, "reason": "duplicate function"}
			core["policy"]["priorities"] = pr.duplicate()
		"close_path", "open_path":
			var cell: Array = payload.get("cell", [])
			if cell.size() != 2:
				return {"ok": false, "reason": "cell [x, y] required"}
			var c := Vector2i(int(cell[0]), int(cell[1]))
			var d := data_for(record)
			if not d.in_bounds(c.x, c.y):
				return {"ok": false, "reason": "outside the settlement"}
			var changes: Dictionary = record.get("nav_changes", {"version": 0, "closed": []})
			var closed: Array = changes["closed"]
			var key := [c.x, c.y]
			var idx := -1
			for i in closed.size():
				if int(closed[i][0]) == c.x and int(closed[i][1]) == c.y:
					idx = i
			if kind == "close_path" and idx < 0:
				closed.append(key)
			elif kind == "open_path" and idx >= 0:
				closed.remove_at(idx)
			else:
				return {"ok": false, "reason": "no change"}
			changes["version"] = int(changes["version"]) + 1
			record["nav_changes"] = changes
			if _hot.has(record.get("settlement_id", "")):
				(_hot[record["settlement_id"]] as SettlementSim).apply_nav_changes(t)
		"join_settlement":
			record["resident_player_ids"].append(issuer)
			core["events"].append({"t": t, "kind": "player_joined", "player": issuer})
		"leave_settlement", "delete_account":
			record["resident_player_ids"].erase(issuer)
			var admins: Array = record.get("admin_player_ids", [])
			admins.erase(issuer)
			if kind == "delete_account":
				_forget_player(record, issuer)
			if kind == "delete_account" and issuer == record.get("founder_player_id", ""):
				# the settlement outlives its founder's account (directive §8);
				# the founder reference is pseudonymised
				record["founder_status"] = "deleted"
				record["founder_player_id"] = pseudonym(issuer)
			core["events"].append({"t": t, "kind": "player_left" if kind == "leave_settlement" else "account_deleted", "player": issuer if kind == "leave_settlement" else pseudonym(issuer)})
	return {"ok": true}


static func pseudonym(player_id: String) -> String:
	return "plr_deleted_" + player_id.sha256_text().substr(0, 12)


## Account deletion: the player's ID is replaced by a pseudonym in the
## settlement's logs (the world keeps what happened, not who it was).
func _forget_player(record: Dictionary, player_id: String) -> void:
	var p := pseudonym(player_id)
	for e in record.get("authority", {}).get("log", []):
		if e.get("issuer", "") == player_id:
			e["issuer"] = p
	for e in record.get("core", {}).get("events", []):
		if e.get("player", "") == player_id:
			e["player"] = p
