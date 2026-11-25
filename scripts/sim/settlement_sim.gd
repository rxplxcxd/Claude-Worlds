class_name SettlementSim
extends RefCounted
## Simulation of ONE settlement (pure data, no scene) – two layers:
##
## * MACRO (SettlementCore.day_step): once per settlement-local day – health,
##   absences, duty roster, supply, building condition, employment, ageing,
##   deaths, newcomers, lifecycle. Runs in EVERY tier with identical results
##   (hot here, warm/cold in WorldAuthority) – detail never decides whether
##   something happens.
## * MICRO (NpcBrain, tiers S0/S1): the individual daily routine, event-driven,
##   reading the macro state (duty roster, health, employment).
##
## Time: UTC seconds; daily life follows the SETTLEMENT's local time
## (record.time_zone, fixed at founding – the same for every viewer).
## Persistence: record.sim = {version, simulated_at, npcs: {id: state}},
## record.core (macro), identities in record.npcs.
## Long absences: every day is processed by the macro layer (nothing is
## skipped or re-seeded); only the micro state – where somebody stands right
## now – is derived freshly from the last day when the gap exceeds one day
## (it is not observable while nobody watches the settlement).
## render_info is a pure function of (state, t): visible NPC (S0) and
## data-only NPC (S1) are the same NPC.

const CONFIG_PATH := "res://data/sim/living_world.json"
const SIM_VERSION := 2
const MICRO_WINDOW_S := 86400
const DOOR_S := 1.6                # seconds of a door passage (presentation)

var config: Dictionary = {}
var nav: NavGrid
var data: SettlementData
var record: Dictionary = {}
var roster: Array = []            # living NPCs (references into record.npcs)
var states: Dictionary = {}       # npc_id -> state
var simulated_at := 0
var offset_override := -99999     # tests: fixed local offset in minutes
var last_events: Array = []
var macro_events: Array = []      # day-step events since creation
var _ctx: Dictionary = {}          # npc_id -> decision context
var _index: Dictionary = {}        # npc_id -> roster index
var _plan_cache: Dictionary = {}   # day -> previewed duty roster


static func load_config() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return d if d is Dictionary else {}


## Creates the simulation for a settlement record and its SettlementData.
## Fills missing identities and time zone (migration) and brings everything
## to `now`.
static func create(p_record: Dictionary, p_data: SettlementData, now: int, p_config: Dictionary = {}, p_offset_override: int = -99999) -> SettlementSim:
	var s := SettlementSim.new()
	s.config = p_config if not p_config.is_empty() else load_config()
	s.offset_override = p_offset_override
	s.record = p_record
	s.data = p_data
	s.nav = NavGrid.build(p_data, s.config)
	var nc: Dictionary = p_record.get("nav_changes", {})
	if not nc.is_empty():
		s.nav.set_closed(nc.get("closed", []), int(nc.get("version", 0)))
	s._ensure_time_zone()
	var founded := int(p_record.get("founded_at_unix", now))
	for r in p_record.get("npcs", []):
		NpcBrain.ensure_profile(r, s.config, founded)
	var start := int(p_record.get("sim", {}).get("simulated_at", now - MICRO_WINDOW_S))
	SettlementCore.ensure(p_record, s.config, SettlementCore.day_index(mini(start, now), s.offset_min()))
	s._rebuild_roster()
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
	return WorldAuthority.settlement_offset(record)   # identical for every viewer


func _rebuild_roster() -> void:
	roster = SettlementCore.alive_npcs(record)
	_index.clear()
	for i in roster.size():
		var r: Dictionary = roster[i]
		_index[r["npc_id"]] = i
		_ctx[r["npc_id"]] = context_for(r)
	for id in _ctx.keys():
		if not _index.has(id):
			_ctx.erase(id)


func context_for(r: Dictionary) -> Dictionary:
	var home := "bld:" + str(r.get("home_id", ""))
	if not nav.places.has(home):
		home = "plaza" if nav.places.has("plaza") else ""
	var work := "bld:" + str(r.get("employment", {}).get("workplace_id", r.get("workplace_id", "")))
	if not nav.places.has(work):
		work = ""
	var pc: Dictionary = config.get("places", {})
	return {"config": config, "nav": nav, "offset_min": 0, "home": home, "work": work, "record": record,
		"plan_for_day": _plan_for_day,
		"eatery": _nearest(home, nav.places_of_type(pc.get("eatery_types", []))),
		"shop": _nearest(home, nav.places_of_type(pc.get("shop_types", []))),
		"clinic": _nearest(home, nav.places_of_type(pc.get("clinic_types", ["clinic"])))}


func _nearest(from: String, candidates: Array[String]) -> String:
	var best := ""
	var best_t := INF
	for c in candidates:
		var t := nav.travel_seconds(from, c) if from != "" else 0
		if t < best_t:
			best_t = t
			best = c
	return best


## Duty roster of a day: the settled plan of the day step, or – for days not
## yet processed – the preview from the current macro state.
func _plan_for_day(day: int) -> Dictionary:
	var plan: Dictionary = record.get("core", {}).get("plan", {})
	if plan.has(str(day)):
		return plan[str(day)]
	if not _plan_cache.has(day):
		_plan_cache[day] = SettlementCore.roster_for_day(record, data, config, day, offset_min())
	return _plan_cache[day]


func _load_states(now: int) -> void:
	var saved: Dictionary = record.get("sim", {})
	if int(saved.get("version", 0)) == SIM_VERSION and saved.has("npcs"):
		simulated_at = int(saved.get("simulated_at", now))
		states = saved["npcs"].duplicate(true)
	if now - simulated_at > MICRO_WINDOW_S or states.is_empty():
		# The macro layer processes EVERY day of the gap (nothing is lost);
		# the micro routine then starts one day before now.
		var micro_start := now - MICRO_WINDOW_S
		macro_until(micro_start)
		states = {}
		simulated_at = micro_start
	for r in roster:
		var id: String = r["npc_id"]
		if not states.has(id):
			states[id] = NpcBrain.initial_state(r, simulated_at, _ctx[id]["home"])
		_normalise(states[id])


## Macro-only progression (all day steps whose day began at or before t).
func macro_until(t: int) -> Array:
	var off := offset_min()
	var events := []
	while SettlementCore.day_start_utc(int(record["core"]["day"]) + 1, off) <= t:
		events.append_array(_day_step(int(record["core"]["day"]) + 1, off))
	return events


func _day_step(day: int, off: int) -> Array:
	var ev := SettlementCore.day_step(record, data, config, day, off)
	_plan_cache.clear()
	_rebuild_roster()
	var t := SettlementCore.day_start_utc(day, off)
	for r in roster:
		NpcBrain.ensure_profile(r, config, int(record.get("founded_at_unix", t)))
		if not states.is_empty() and not states.has(r["npc_id"]):
			states[r["npc_id"]] = NpcBrain.initial_state(r, t, _ctx[r["npc_id"]]["home"])   # newcomer
	for id in states.keys():
		if not _index.has(id):
			states.erase(id)   # died (record keeps the identity)
	macro_events.append_array(ev)
	return ev


## JSON turns integers into floats – restore ints for exact comparisons.
static func _normalise(st: Dictionary) -> void:
	for k in ["t0", "t1", "needs_at", "n", "work_min", "pause_for"]:
		st[k] = int(st.get(k, 0))
	var nd: Dictionary = st.get("needs", {})
	for k in nd:
		nd[k] = int(nd[k])
	var rc: Dictionary = st.get("recent", {})
	for k in rc:
		rc[k] = int(rc[k])
	var tr: Dictionary = st.get("travel", {})
	for k in ["depart", "arrive", "next_dur", "nav_v"]:
		if tr.has(k):
			tr[k] = int(tr[k])


## Advances the settlement to t: micro routine up to each local midnight,
## then the day step, then on. Returns all events (also in last_events).
func advance_to(t: int) -> Array:
	var off := offset_min()
	var events := []
	while true:
		var boundary := SettlementCore.day_start_utc(int(record["core"]["day"]) + 1, off)
		if boundary > t:
			break
		events.append_array(_advance_micro(boundary, off))
		events.append_array(_day_step(int(record["core"]["day"]) + 1, off))
	events.append_array(_advance_micro(t, off))
	simulated_at = maxi(simulated_at, t)
	last_events = events
	return events


func _advance_micro(t: int, off: int) -> Array:
	var events := []
	for r in roster:
		var id: String = r["npc_id"]
		var ctx: Dictionary = _ctx[id]
		ctx["offset_min"] = off
		events.append_array(NpcBrain.advance(r, states[id], t, ctx))
	return events


## The map changed (authority command: closure/opening): update the grid and
## re-plan every journey in progress whose remaining route is affected –
## people turn at the obstacle and take the next best way.
func apply_nav_changes(t: int) -> int:
	advance_to(t)
	# freeze the routes of everyone walking right now (their path must not
	# silently change under their feet when caches are recomputed)
	for id in states:
		var trf: Dictionary = states[id].get("travel", {})
		if not trf.is_empty() and not trf.has("path"):
			var cells0 := []
			for c in nav.path_between(trf["from"], trf["to"]):
				cells0.append([c.x, c.y])
			if cells0.size() >= 2:
				trf["path"] = cells0
	var nc: Dictionary = record.get("nav_changes", {})
	var changed := nav.set_closed(nc.get("closed", []), int(nc.get("version", 0)))
	if changed.is_empty():
		return 0
	var rerouted := 0
	for id in states:
		var st: Dictionary = states[id]
		var tr: Dictionary = st.get("travel", {})
		if tr.is_empty() or t < int(tr["depart"]) or t >= int(tr["arrive"]):
			continue
		var info := render_info(id, float(t))
		var here := Vector2i(int(floor(info["grid"].x)), int(floor(info["grid"].y)))
		var old: Array = tr["path"] if tr.has("path") else nav.path_between(tr["from"], tr["to"])
		var blocked := false
		for c in old:
			var v := Vector2i(int(c[0]), int(c[1])) if c is Array else Vector2i(c)
			if nav.closed.has(v) or nav.astar.is_point_solid(v):
				blocked = true
				break
		var opened := not blocked and changed.any(func(v): return not nav.closed.has(v))
		if not blocked and not opened:
			continue
		var np := nav.path_from_cell(here, tr["to"])
		if np.size() < 2:
			continue   # destination unreachable for now: keep going, the next decision re-plans
		var cells := []
		for c in np:
			cells.append([c.x, c.y])
		var secs := nav.seconds_of(cells)
		if opened and t + secs >= int(tr["arrive"]):
			continue   # an opening only matters if it is a shortcut
		tr["path"] = cells
		tr["depart"] = t
		tr["arrive"] = t + secs
		tr["nav_v"] = nav.version
		st["t0"] = t
		st["t1"] = t + secs
		rerouted += 1
	return rerouted


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
static func preview(p_record: Dictionary, p_data: SettlementData, t: int, p_config: Dictionary = {}, p_offset_override: int = -99999) -> SettlementSim:
	var copy := p_record.duplicate(true)
	copy.erase("sim")
	return SettlementSim.create(copy, p_data, t, p_config, p_offset_override)


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
		var p: Vector2
		var q: Vector2
		if tr.has("path"):
			p = nav.position_on_cells(tr["path"], f)
			q = nav.position_on_cells(tr["path"], minf(1.0, f + 2.0 / span))
		else:
			p = nav.position_on_path(tr["from"], tr["to"], f)
			q = nav.position_on_path(tr["from"], tr["to"], minf(1.0, f + 2.0 / span))
		var out := {"visible": true, "grid": p, "dir": q - p, "act": "walk", "walking": true, "place": tr["from"], "target": tr["to"], "hurry": tr.get("hurry", false)}
		# doors: stepping out of / into a building (presentation phases)
		var left := float(tr["arrive"]) - t
		var into := t - float(tr["depart"])
		if str(tr["to"]).begins_with("bld:") and left < DOOR_S:
			out["door"] = "enter"
			out["door_f"] = 1.0 - left / DOOR_S
		elif str(tr["from"]).begins_with("bld:") and into < DOOR_S:
			out["door"] = "exit"
			out["door_f"] = into / DOOR_S
		return out
	var act: String = st["act"] if tr.is_empty() else str(tr.get("next", st["act"]))
	var place: String = st["place"] if tr.is_empty() else str(tr["to"])
	var a: Dictionary = config.get("activities", {}).get(act, {})
	var visible := not bool(a.get("indoors", false))
	if act == "work":
		var share := float(config.get("professions", {}).get(_role(npc_id), {}).get("outdoor_share", 0.5))
		visible = SettlementCore._chance(npc_id + "#vis#" + str(int(t / 1200))) < share
	var pl: Dictionary = nav.places.get(place, {})
	var spots: Array = pl.get("spots", [])
	var grid := Vector2(pl.get("cell", Vector2i.ZERO)) + Vector2(0.5, 0.5)
	if visible and not spots.is_empty():
		# unique standing spot: occupants of a place are ordered, each gets
		# its own spot; more people than spots stand in a second ring
		var k := _slot_of(npc_id, place, t)
		var slot := (k + absi(hash(place))) % spots.size()
		grid = Vector2(spots[slot]) + Vector2(0.5, 0.5)
		if k >= spots.size():
			var ang := TAU * float(k) / float(spots.size()) + 0.7
			grid += Vector2(cos(ang), sin(ang)) * 0.32
	return {"visible": visible, "grid": grid, "dir": Vector2.ZERO, "act": act, "walking": false, "place": place, "target": place}


var _slot_cache: Dictionary = {}
var _slot_cache_t := -1


func _slot_of(npc_id: String, place: String, t: float) -> int:
	var ti := int(t)
	if ti != _slot_cache_t:
		_slot_cache.clear()
		_slot_cache_t = ti
		var by_place := {}
		var ids: Array = states.keys()
		ids.sort()
		for id in ids:
			var st: Dictionary = states[id]
			var tr: Dictionary = st.get("travel", {})
			var p: String = st["place"] if tr.is_empty() else (str(tr["to"]) if t >= float(tr["arrive"]) or t < float(tr["depart"]) else "")
			if p == "":
				continue
			var n := int(by_place.get(p, 0))
			_slot_cache[id + "@" + p] = n
			by_place[p] = n + 1
	return int(_slot_cache.get(npc_id + "@" + place, int(_index.get(npc_id, 0))))


func _role(npc_id: String) -> String:
	return str(roster[int(_index.get(npc_id, 0))].get("role", "resident")) if _index.has(npc_id) else "resident"


func needs_now(npc_id: String, t: int) -> Dictionary:
	var i := int(_index.get(npc_id, -1))
	if i < 0:
		return {}
	return NpcBrain.needs_at(states[npc_id], roster[i], config, t, record.get("core", {}).get("stats", {}))


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


## Work hours text for the info card: operating model of the workplace and
## the person's duty today ("Feld früh Mo–Sa 05:30–13:30 · heute 05:38–13:38").
func schedule_text(r: Dictionary, t: int = -1) -> String:
	var e: Dictionary = r.get("employment", {})
	match str(e.get("status", "employed")):
		"retired":
			return "im Ruhestand"
		"unemployed":
			return "arbeitssuchend"
		"deceased":
			return "verstorben"
	var bid := str(e.get("workplace_id", r.get("workplace_id", "")))
	var ty := ""
	for b in data.buildings:
		if b.get("id", "") == bid:
			ty = str(b.get("type", ""))
	var m: Dictionary = config.get("operating_models", {}).get(ty, {})
	var names := ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
	var parts := PackedStringArray()
	for sh in m.get("shifts", []):
		var days: Array = sh.get("days", [])
		var dtext := "täglich" if days.size() == 7 else "%s–%s" % [names[int(days[0])], names[int(days[days.size() - 1])]]
		parts.append("%s %s %s–%s" % [sh.get("name", ""), dtext, _hm(float(sh["start"]) * 60.0), _hm(float(sh["end"]) * 60.0)])
	if parts.is_empty():
		return "keine festen Arbeitszeiten"
	if t >= 0:
		var mine: Array = NpcBrain.next_shift(r, t, _ctx.get(r.get("npc_id", ""), {"offset_min": offset_min(), "plan_for_day": _plan_for_day}))
		if not mine.is_empty() and int(mine[0]) - t < 86400:
			var off := offset_min()
			parts.append("nächster Dienst %s %s–%s" % [str(mine[3]), _hm(float(posmod(int(mine[0]) + off * 60, 86400)) / 60.0), _hm(float(posmod(int(mine[1]) + off * 60, 86400)) / 60.0)])
	return " · ".join(parts)


static func _hm(minutes: float) -> String:
	var m := int(round(minutes)) % 1440
	return "%02d:%02d" % [m / 60, m % 60]
