class_name NpcBrain
extends RefCounted
## Phase 3 – the decision logic and state progression of ONE NPC.
## Pure static functions on plain dictionaries (persistable, server-capable).
##
## State (stored per NPC in the settlement record, see SettlementSim):
##   act, place, t0, t1        current activity, where, from/until (UTC seconds)
##   travel                    {} or {from, to, depart, arrive, next, next_dur}
##   needs, needs_at           needs (0..1) valid at needs_at (an activity boundary)
##   n, last_act, skill        decision counter (deterministic noise), last activity, work skill
##
## Progression is EVENT-DRIVEN ("analytisches Fortschreiben",
## SIMULATION_ARCHITECTURE.md §3): between two decisions needs change
## linearly, so advance() jumps from boundary to boundary. Cost is
## proportional to the number of decisions (~15 per NPC and day), not to the
## elapsed time. advance(t2) gives exactly the same state as advance(t1) +
## advance(t2) (tested) – the basis for consistent LOD switching and for
## catching up after absence without any visible re-simulation.

const NEED_KEYS := ["food", "energy", "social", "leisure", "hygiene"]
const TRAITS := ["openness", "diligence", "sociability", "ambition", "risk"]
const MAX_STEPS := 20000


# --- identity -------------------------------------------------------------------

## Adds persistent identity fields (personality, birth day, profession) to a
## roster record that does not have them yet (older saves). Deterministic.
static func ensure_profile(rec: Dictionary, config: Dictionary, founded_unix: int) -> bool:
	if rec.has("personality") and rec.has("profession") and rec.has("birth_day"):
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(rec.get("npc_id", "")) + "#profile")
	var p := {}
	for t in TRAITS:
		p[t] = snappedf(clampf(rng.randfn(0.5, 0.18), 0.05, 0.95), 0.01)
	rec["personality"] = p
	var age := rng.randi_range(19, 67)
	rec["birth_day"] = int(founded_unix / 86400) - age * 365 - rng.randi_range(0, 364)
	var role: String = rec.get("role", "resident")
	var prof: Dictionary = config.get("professions", {}).get(role, {})
	rec["profession"] = {
		"title": prof.get("title", role),
		"skill_name": prof.get("skill", ""),
		"skill": snappedf(rng.randf_range(0.3, 0.7), 0.01) if prof.get("skill", "") != "" else 0.0,
		"shift_offset_min": [0, 0, 15, 30, -15][rng.randi_range(0, 4)] if not prof.get("shifts", []).is_empty() else 0,
	}
	return true


static func age_years(rec: Dictionary, now_unix: int) -> int:
	return int((int(now_unix / 86400) - int(rec.get("birth_day", 0))) / 365.25)


# --- state ---------------------------------------------------------------------

static func initial_state(rec: Dictionary, t: int, home_place: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(rec.get("npc_id", "")) + "#init")
	var needs := {}
	for k in NEED_KEYS:
		needs[k] = rng.randi_range(550000, 900000)
	return {"act": "relax_home", "place": home_place, "t0": t, "t1": t, "travel": {}, "needs": needs, "needs_at": t, "n": 0, "last_act": "", "work_min": 0}


## Needs are stored as INTEGERS in millionths (fixed point): exact across
## JSON save/load (Godot's JSON keeps only ~6 significant float digits), so
## a reloaded world continues bit-identically.
const SCALE := 1000000


## Needs (floats 0..1) at any time t – not stored; stored values stay at needs_at.
static func needs_at(state: Dictionary, rec: Dictionary, config: Dictionary, t: int) -> Dictionary:
	var act: String = "walk" if not state.get("travel", {}).is_empty() else state["act"]
	return to_float(_integrate(state["needs"], act, t - int(state["needs_at"]), rec, config))


static func to_float(fixed: Dictionary) -> Dictionary:
	var out := {}
	for k in NEED_KEYS:
		out[k] = float(fixed.get(k, SCALE / 2)) / SCALE
	return out


static func to_fixed(f: Dictionary) -> Dictionary:
	var out := {}
	for k in NEED_KEYS:
		out[k] = clampi(int(round(float(f.get(k, 0.5)) * SCALE)), 0, SCALE)
	return out


## Linear change of every need over `seconds` of activity `act` (fixed point).
static func _integrate(needs: Dictionary, act: String, seconds: int, rec: Dictionary, config: Dictionary) -> Dictionary:
	var out := {}
	var defs: Dictionary = config.get("needs", {})
	var gains: Dictionary = config.get("activities", {}).get(act, {}).get("gain", {})
	var pers: Dictionary = rec.get("personality", {})
	for k in NEED_KEYS:
		var d: Dictionary = defs.get(k, {})
		var decay := float(d.get("decay", 0.04))
		if act == "sleep":
			decay *= float(d.get("sleep_factor", 1.0))
		var trait_name := str(d.get("trait", ""))
		if trait_name != "":
			decay *= 0.6 + 0.8 * float(pers.get(trait_name, 0.5))
		var rate := float(gains.get(k, 0.0)) - decay   # per hour
		var delta := int(round(rate * float(seconds) / 3600.0 * SCALE))
		out[k] = clampi(int(needs.get(k, SCALE / 2)) + delta, 0, SCALE)
	return out


# --- time & schedule -------------------------------------------------------------

static func local_hour(t: int, offset_min: int) -> float:
	return float(posmod(t + offset_min * 60, 86400)) / 3600.0


static func weekday(t: int, offset_min: int) -> int:
	# 1970-01-01 was a Thursday (4); 0 = Sunday
	return posmod(int(floor(float(t + offset_min * 60) / 86400.0)) + 4, 7)


static func day_start(t: int, offset_min: int) -> int:
	var local := t + offset_min * 60
	return local - posmod(local, 86400) - offset_min * 60


## Shift windows of the NPC as [start, end] UTC seconds for the local day of t.
static func shifts_on_day(rec: Dictionary, config: Dictionary, t: int, offset_min: int) -> Array:
	var prof: Dictionary = config.get("professions", {}).get(rec.get("role", "resident"), {})
	var out := []
	var wd := weekday(t, offset_min)
	var d0 := day_start(t, offset_min)
	var off := int(rec.get("profession", {}).get("shift_offset_min", 0))
	for s in prof.get("shifts", []):
		var days: Array = []
		for d in s.get("days", []):
			days.append(int(d))   # JSON numbers are floats; 2 in [2.0] is false in GDScript
		if wd in days:
			out.append([d0 + int(float(s["start"]) * 3600.0) + off * 60, d0 + int(float(s["end"]) * 3600.0) + off * 60])
	return out


## The current or next shift [start, end] within 36 h of t, or [] if none.
static func next_shift(rec: Dictionary, config: Dictionary, t: int, offset_min: int) -> Array:
	for day in 3:
		for s in shifts_on_day(rec, config, t + day * 86400, offset_min):
			if int(s[1]) > t:
				return s if int(s[0]) - t < 36 * 3600 else []
	return []


# --- decisions (utility AI) ----------------------------------------------------------

static func _pressure(n: float) -> float:
	return pow(1.0 - n, 2.0) * 4.0 + (2.0 if n < 0.15 else 0.0)


static func _in_windows(h: float, windows: Array) -> bool:
	for w in windows:
		var a := float(w[0])
		var b := float(w[1])
		if (h >= a and h < b) or (b > 24.0 and h + 24.0 >= a and h + 24.0 < b):
			return true
	return false


static func _noise(npc_id: String, n: int) -> float:
	return float(hash(npc_id + "#" + str(n)) % 1000) / 1000.0


## Chooses the next activity at time t. ctx = {config, nav, offset_min,
## home, work, eatery, shop} (place ids, see SettlementSim.context_for).
## Returns {act, place, minutes, score}.
static func decide(rec: Dictionary, state: Dictionary, t: int, ctx: Dictionary) -> Dictionary:
	var config: Dictionary = ctx["config"]
	var nav: NavGrid = ctx["nav"]
	var off: int = ctx["offset_min"]
	var needs: Dictionary = to_float(state["needs"])
	var pers: Dictionary = rec.get("personality", {})
	var acts: Dictionary = config.get("activities", {})
	var h := local_hour(t, off)
	var here: String = state["place"]
	var shift := next_shift(rec, config, t, off)
	var work_place: String = ctx.get("work", "")
	var in_shift := not shift.is_empty() and work_place != "" and t >= int(shift[0]) - 15 * 60 and t < int(shift[1])
	# time budget until the next obligation (go to work)
	var budget_end := t + 24 * 3600
	if not shift.is_empty() and work_place != "" and not in_shift:
		budget_end = int(shift[0]) - 15 * 60
	var best := {"act": "relax_home", "place": ctx["home"], "minutes": 30, "score": -INF}
	for act in acts:
		var a: Dictionary = acts[act]
		var place := _place_for(a.get("place", "home"), ctx)
		if place == "" or not nav.places.has(place):
			continue
		if act != "work" and act != "sleep" and not _in_windows(h, a.get("windows", [[0, 24]])):
			continue
		var travel := nav.travel_seconds(here, place)
		var minutes := int(a.get("minutes", [60, 60])[0])
		var bonus := 0.0
		if act == "work":
			if not in_shift:
				continue
			minutes = int((int(shift[1]) - t - travel) / 60)
			if minutes < 15:
				continue
			bonus = 2.5 * (0.8 + 0.4 * float(pers.get("diligence", 0.5)))
			if float(needs["food"]) < 0.12 or float(needs["energy"]) < 0.08:
				bonus -= 2.0
		else:
			if act == "sleep":
				var need_h := (1.0 - float(needs["energy"])) / 0.14
				minutes = int(clampf(need_h, 5.0, 10.0) * 60.0)
				if h >= 20.0 or h < 5.0:
					# night sleep lasts until the personal wake time (early birds
					# get up earlier); the next obligation may cut it shorter
					var wake_h := 6.75 - (float(pers.get("diligence", 0.5)) - 0.5) * 2.0
					var until := (wake_h - h) if h < 5.0 else (24.0 - h + wake_h)
					minutes = int(clampf(until, 5.0, 10.0) * 60.0)
				var night := h >= 21.5 or h < 6.0
				bonus = (1.5 + 2.0 * (1.0 - float(needs["energy"]))) if night else (-3.0 if float(needs["energy"]) > 0.25 else 0.0)
				# late risers / early birds
				bonus += (float(pers.get("diligence", 0.5)) - 0.5) * (0.6 if h < 6.0 else -0.6)
			elif act == "eat_home" or act == "eat_out":
				if (h >= 6.5 and h < 9.0) or (h >= 11.5 and h < 13.5) or (h >= 17.5 and h < 20.0):
					bonus = 0.8 * (1.0 - float(needs["food"]))   # mealtime, if hungry at all
			elif act == "relax_home":
				bonus = 0.15 if (h < 9.0 or h >= 19.0) else -0.15   # daytime: rather go out
			if act == "eat_out":
				bonus -= 0.35   # costs money/time – a treat, not the default
			# respect the next obligation
			var left := (budget_end - t - travel) / 60
			if left < minutes:
				if act == "sleep" and left >= 60:
					minutes = left
				elif left >= 15 and act != "sleep":
					minutes = left
				else:
					continue
		if minutes <= 0:
			continue
		var dur_h := minutes / 60.0
		var benefit := 0.0
		var gains: Dictionary = a.get("gain", {})
		for k in NEED_KEYS:
			var g := float(gains.get(k, 0.0))
			if g > 0.0:
				benefit += _pressure(float(needs[k])) * minf(g * dur_h, 1.0 - float(needs[k]))
		var score := benefit / sqrt(maxf(dur_h, 1.0)) + bonus   # short activities are not inflated
		var trait_name := str(a.get("trait", ""))
		if trait_name != "":
			score *= 0.6 + 0.8 * float(pers.get(trait_name, 0.5))
		score -= travel / 60.0 * 0.02
		if act == str(state.get("last_act", "")) and act != "work" and act != "sleep":
			score -= 0.5
		var cd := float(a.get("cooldown_h", 0.0))
		if cd > 0.0 and t - int(state.get("recent", {}).get(act, -1000000)) < int(cd * 3600.0):
			score -= 0.8   # did that recently
		score += _noise(str(rec.get("npc_id", "")) + act, int(state.get("n", 0))) * 0.12
		if score > float(best["score"]):
			best = {"act": act, "place": place, "minutes": minutes, "score": score}
	return best


static func _place_for(kind: String, ctx: Dictionary) -> String:
	match kind:
		"home":
			return ctx.get("home", "")
		"work":
			return ctx.get("work", "")
		"eatery":
			return ctx.get("eatery", "")
		"shop":
			return ctx.get("shop", "")
		_:
			return kind   # "plaza", "park"


# --- progression ---------------------------------------------------------------------

## Advances the state to `to` (UTC seconds). Returns the events that happened
## ({t, npc, kind, act, place}). Deterministic; idempotent for to <= now.
static func advance(rec: Dictionary, state: Dictionary, to: int, ctx: Dictionary) -> Array:
	var events := []
	var config: Dictionary = ctx["config"]
	var nav: NavGrid = ctx["nav"]
	var steps := 0
	while steps < MAX_STEPS:
		steps += 1
		var travel: Dictionary = state.get("travel", {})
		var boundary := int(travel["arrive"]) if not travel.is_empty() else int(state["t1"])
		if boundary > to:
			break
		var act_now: String = "walk" if not travel.is_empty() else str(state["act"])
		var secs := boundary - int(state["needs_at"])
		state["needs"] = _integrate(state["needs"], act_now, secs, rec, config)
		state["needs_at"] = boundary
		if act_now == "work":
			state["work_min"] = int(state.get("work_min", 0)) + int(secs / 60)
		if not travel.is_empty():
			state["place"] = travel["to"]
			state["act"] = travel["next"]
			state["t0"] = boundary
			state["t1"] = boundary + int(travel["next_dur"]) * 60
			state["travel"] = {}
			_mark_recent(state, state["act"], boundary)
			events.append({"t": boundary, "npc": rec.get("npc_id", ""), "kind": "activity_start", "act": state["act"], "place": state["place"]})
			continue
		state["last_act"] = state["act"]
		var d := decide(rec, state, boundary, ctx)
		state["n"] = int(state.get("n", 0)) + 1
		if d["place"] != state["place"]:
			var walk_s := maxi(1, nav.travel_seconds(state["place"], d["place"]))
			state["travel"] = {"from": state["place"], "to": d["place"], "depart": boundary, "arrive": boundary + walk_s, "next": d["act"], "next_dur": d["minutes"]}
			state["act"] = "walk"
			state["t0"] = boundary
			state["t1"] = boundary + walk_s
			events.append({"t": boundary, "npc": rec.get("npc_id", ""), "kind": "walk_start", "act": d["act"], "place": d["place"]})
		else:
			state["act"] = d["act"]
			_mark_recent(state, d["act"], boundary)
			state["t0"] = boundary
			state["t1"] = boundary + maxi(1, int(d["minutes"])) * 60
			events.append({"t": boundary, "npc": rec.get("npc_id", ""), "kind": "activity_start", "act": state["act"], "place": state["place"]})
	return events


static func _mark_recent(state: Dictionary, act: String, t: int) -> void:
	var r: Dictionary = state.get("recent", {})
	r[act] = t
	state["recent"] = r


## External interaction (e.g. the player talks to the NPC) at time t:
## needs are brought to t first, then changed. The current activity continues.
static func apply_interaction(rec: Dictionary, state: Dictionary, t: int, ctx: Dictionary, delta: Dictionary) -> void:
	var act: String = "walk" if not state.get("travel", {}).is_empty() else state["act"]
	var cur := _integrate(state["needs"], act, t - int(state["needs_at"]), rec, ctx["config"])
	for k in delta:
		if cur.has(k):
			cur[k] = clampi(int(cur[k]) + int(round(float(delta[k]) * SCALE)), 0, SCALE)
	state["needs"] = cur
	state["needs_at"] = t


## Mood 0..1 from needs (for texts and later social systems).
static func mood(needs: Dictionary) -> float:
	var s := 0.0
	for k in NEED_KEYS:
		s += float(needs.get(k, 0.5))
	return s / NEED_KEYS.size()
