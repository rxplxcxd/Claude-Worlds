class_name SettlementSim
extends RefCounted
## Phase 3 – simulation of all NPCs of ONE settlement (pure data, no scene).
##
## * Time: UTC seconds; daily life follows the SETTLEMENT's local time
##   (record.time_zone, fixed at founding – the same for every viewer later
##   in multiplayer; for the founder it follows their device incl. DST).
## * advance_to(t): event-driven, cost ~ number of decisions (NpcBrain).
## * Persistence: record.sim = {version, simulated_at, npcs: {id: state}};
##   identities (personality, profession, birth day) live in record.npcs.
## * Catch-up after absence: advance from simulated_at to now before anything
##   is shown – nobody sees a re-simulation. Beyond max_catchup_days the
##   daily routine is re-seeded one day before now (bounded cost; needs and
##   positions are then those of a normal day – nothing a player could have
##   observed is lost).
## * Rendering queries (render_info) are pure functions of (state, t): the
##   visible NPC (LOD S0) and the data-only NPC (S1) are the same NPC – a
##   switch between them never changes the simulation.

const CONFIG_PATH := "res://data/sim/living_world.json"
const SIM_VERSION := 1

var config: Dictionary = {}
var nav: NavGrid
var record: Dictionary = {}
var roster: Array = []
var states: Dictionary = {}       # npc_id -> state
var simulated_at := 0
var offset_override := -99999     # tests: fixed local offset in minutes
var last_events: Array = []
var _ctx: Dictionary = {}          # npc_id -> decision context
var _index: Dictionary = {}        # npc_id -> roster index


static func load_config() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return d if d is Dictionary else {}


## Creates the simulation for a settlement record (WorldState) and its
## SettlementData. Fills missing identities and time zone (migration) and
## brings everything to `now`.
static func create(p_record: Dictionary, data: SettlementData, now: int, p_config: Dictionary = {}) -> SettlementSim:
	var s := SettlementSim.new()
	s.config = p_config if not p_config.is_empty() else load_config()
	s.record = p_record
	s.nav = NavGrid.build(data, s.config)
	s.roster = p_record.get("npcs", [])
	s._ensure_time_zone()
	var founded := int(p_record.get("founded_at_unix", now))
	for i in s.roster.size():
		var r: Dictionary = s.roster[i]
		NpcBrain.ensure_profile(r, s.config, founded)
		s._index[r["npc_id"]] = i
		s._ctx[r["npc_id"]] = s.context_for(r)
	s._load_states(now)
	s.advance_to(now)
	return s


func _ensure_time_zone() -> void:
	if record.has("time_zone"):
		return
	# fixed at founding: the founder's time zone (stored since Phase 1)
	if record.has("timezone"):
		record["time_zone"] = {"name": str(record["timezone"]), "offset_min": int(record.get("utc_offset_minutes_at_founding", 0))}
	else:
		record["time_zone"] = {"name": GameClock.timezone_name, "offset_min": GameClock.utc_offset_minutes}


## Local offset of the settlement in minutes.
func offset_min() -> int:
	if offset_override != -99999:
		return offset_override
	var tz: Dictionary = record.get("time_zone", {})
	if str(tz.get("name", "")) != "" and GameClock.timezone_name == tz.get("name", ""):
		return GameClock.utc_offset_minutes   # founder's device: follows daylight saving time
	return int(tz.get("offset_min", 0))


func context_for(r: Dictionary) -> Dictionary:
	var home := "bld:" + str(r.get("home_id", ""))
	if not nav.places.has(home):
		home = "plaza" if nav.places.has("plaza") else ""
	var work := "bld:" + str(r.get("workplace_id", ""))
	if not nav.places.has(work):
		work = ""
	var pc: Dictionary = config.get("places", {})
	return {"config": config, "nav": nav, "offset_min": 0, "home": home, "work": work,
		"eatery": _nearest(home, nav.places_of_type(pc.get("eatery_types", []))),
		"shop": _nearest(home, nav.places_of_type(pc.get("shop_types", [])))}


func _nearest(from: String, candidates: Array[String]) -> String:
	var best := ""
	var best_t := INF
	for c in candidates:
		var t := nav.travel_seconds(from, c) if from != "" else 0
		if t < best_t:
			best_t = t
			best = c
	return best


func _load_states(now: int) -> void:
	var saved: Dictionary = record.get("sim", {})
	var max_gap := int(float(config.get("max_catchup_days", 14)) * 86400.0)
	if int(saved.get("version", 0)) == SIM_VERSION and saved.has("npcs"):
		simulated_at = int(saved.get("simulated_at", now))
		states = saved["npcs"].duplicate(true)
	if now - simulated_at > max_gap or states.is_empty():
		# fresh start (new settlement) or very long absence: begin the routine
		# one day before now, so at `now` everybody already lives a normal day
		states = {}
		simulated_at = now - 86400
	for r in roster:
		var id: String = r["npc_id"]
		if not states.has(id):
			states[id] = NpcBrain.initial_state(r, simulated_at, _ctx[id]["home"])
		_normalise(states[id])


## JSON turns integers into floats – restore ints for exact comparisons.
static func _normalise(st: Dictionary) -> void:
	for k in ["t0", "t1", "needs_at", "n", "work_min"]:
		st[k] = int(st.get(k, 0))
	var nd: Dictionary = st.get("needs", {})
	for k in nd:
		nd[k] = int(nd[k])
	var rc: Dictionary = st.get("recent", {})
	for k in rc:
		rc[k] = int(rc[k])
	var tr: Dictionary = st.get("travel", {})
	for k in ["depart", "arrive", "next_dur"]:
		if tr.has(k):
			tr[k] = int(tr[k])


## Advances every NPC to t. Returns all events (also kept in last_events).
func advance_to(t: int) -> Array:
	var off := offset_min()
	var events := []
	for r in roster:
		var id: String = r["npc_id"]
		var ctx: Dictionary = _ctx[id]
		ctx["offset_min"] = off
		events.append_array(NpcBrain.advance(r, states[id], t, ctx))
	simulated_at = maxi(simulated_at, t)
	last_events = events
	return events


func to_record() -> Dictionary:
	return {"version": SIM_VERSION, "simulated_at": simulated_at, "npcs": states.duplicate(true)}


## Writes the simulation into the settlement record (WorldState saves it).
func store() -> void:
	record["sim"] = to_record()
	for r in roster:
		var prof: Dictionary = r.get("profession", {})
		if prof.get("skill_name", "") != "":
			# skill grows slowly with working time (+0.01 per 40 h worked), capped;
			# derived from the total so it never drifts with save frequency
			var worked_h := float(states[r["npc_id"]].get("work_min", 0)) / 60.0
			prof["skill_worked_h"] = int(worked_h)
			prof["skill_now"] = snappedf(minf(1.0, float(prof.get("skill", 0.0)) + worked_h / 4000.0), 0.0001)


# --- queries for presentation (pure functions of state and time) ------------------------

func activity_label(act: String) -> String:
	if act == "walk":
		return "ist unterwegs"
	return str(config.get("activities", {}).get(act, {}).get("label", act))


## A throw-away simulation for the time-of-day preview (QA/menu): the same
## people and rules, warmed up one day before the preview time. Never stored.
static func preview(p_record: Dictionary, data: SettlementData, t: int, p_config: Dictionary = {}) -> SettlementSim:
	var copy := p_record.duplicate(true)
	copy.erase("sim")
	return SettlementSim.create(copy, data, t, p_config)


## {visible, grid (Vector2), dir (Vector2), act, walking, place, target}
## t may be fractional (smooth walking between whole seconds).
func render_info(npc_id: String, t: float) -> Dictionary:
	var st: Dictionary = states.get(npc_id, {})
	if st.is_empty():
		return {"visible": false}
	var tr: Dictionary = st.get("travel", {})
	if not tr.is_empty() and t >= float(tr["depart"]) and t < float(tr["arrive"]):
		var span := maxf(1.0, float(int(tr["arrive"]) - int(tr["depart"])))
		var f := clampf((t - float(tr["depart"])) / span, 0.0, 1.0)
		var p := nav.position_on_path(tr["from"], tr["to"], f)
		var q := nav.position_on_path(tr["from"], tr["to"], minf(1.0, f + 2.0 / span))
		return {"visible": true, "grid": p, "dir": q - p, "act": "walk", "walking": true, "place": tr["from"], "target": tr["to"]}
	var act: String = st["act"] if tr.is_empty() else str(tr.get("next", st["act"]))
	var place: String = st["place"] if tr.is_empty() else str(tr["to"])
	var a: Dictionary = config.get("activities", {}).get(act, {})
	var visible := not bool(a.get("indoors", false))
	if act == "work":
		var share := float(config.get("professions", {}).get(_role(npc_id), {}).get("outdoor_share", 0.5))
		visible = float(hash(npc_id + "#" + str(int(t / 1200))) % 100) < share * 100.0
	var pl: Dictionary = nav.places.get(place, {})
	var spots: Array = pl.get("spots", [])
	var grid := Vector2(pl.get("cell", Vector2i.ZERO)) + Vector2(0.5, 0.5)
	if visible and not spots.is_empty():
		var slot := (int(_index.get(npc_id, 0)) * 5 + absi(hash(place))) % spots.size()
		grid = Vector2(spots[slot]) + Vector2(0.5, 0.5)
	return {"visible": visible, "grid": grid, "dir": Vector2.ZERO, "act": act, "walking": false, "place": place, "target": place}


func _role(npc_id: String) -> String:
	return str(roster[int(_index.get(npc_id, 0))].get("role", "resident")) if _index.has(npc_id) else "resident"


func needs_now(npc_id: String, t: int) -> Dictionary:
	var i := int(_index.get(npc_id, -1))
	if i < 0:
		return {}
	return NpcBrain.needs_at(states[npc_id], roster[i], config, t)


## The player talks to an NPC (interaction event, persisted with the state).
func player_talk(npc_id: String, t: int) -> void:
	var i := int(_index.get(npc_id, -1))
	if i < 0:
		return
	advance_to(t)
	NpcBrain.apply_interaction(roster[i], states[npc_id], t, _ctx[npc_id], {"social": 0.08, "leisure": 0.03})


## NPCs at the same public place at time t, grouped (for chat visuals).
func groups_at(t: float) -> Dictionary:
	var out := {}
	for r in roster:
		var info := render_info(r["npc_id"], t)
		if info.get("visible", false) and not info.get("walking", false) and info["act"] in ["socialize", "eat_out", "leisure", "errand"]:
			out[info["place"]] = out.get(info["place"], []) + [r["npc_id"]]
	return out


## Work hours text for the info card ("Mo–Fr 08:00–16:30").
func schedule_text(r: Dictionary) -> String:
	var prof: Dictionary = config.get("professions", {}).get(r.get("role", "resident"), {})
	var names := ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
	var off := int(r.get("profession", {}).get("shift_offset_min", 0))
	var parts := PackedStringArray()
	for s in prof.get("shifts", []):
		var days := PackedStringArray()
		for d in s.get("days", []):
			days.append(names[int(d)])
		var a := float(s["start"]) * 60.0 + off
		var b := float(s["end"]) * 60.0 + off
		parts.append("%s %02d:%02d–%02d:%02d" % [",".join(days), int(a / 60), int(a) % 60, int(b / 60), int(b) % 60])
	return "; ".join(parts) if not parts.is_empty() else "keine festen Arbeitszeiten"
