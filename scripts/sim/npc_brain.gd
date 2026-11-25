class_name NpcBrain
extends RefCounted
## The daily life of ONE NPC (tier S0/S1). Pure static functions on plain
## dictionaries (persistable, server-capable).
##
## State (per NPC, stored in record.sim.npcs):
##   act, place, t0, t1      current activity, where, from/until (UTC seconds)
##   travel                  {} or {from, to, depart, arrive, next, next_dur}
##   needs, needs_at         needs (fixed point, millionths) valid at needs_at
##   n, last_act, recent     decision counter (seeded randomness), last activity, cooldowns
##   pause_for, work_min     shift whose break was taken, minutes worked (skill)
##
## Decisions combine needs, PERSONALITY, obligations from the settlement's
## duty roster (SettlementCore), health, preferences and seeded randomness:
## a weighted random choice among the best options (temperature grows with
## impulsivity). Same inputs + same seeds → same life (testable); different
## days and people → different lives.
## Progression is EVENT-DRIVEN: cost ∝ decisions, advance(t2) equals
## advance(t1)+advance(t2) exactly (tested).

const NEED_KEYS := ["food", "energy", "social", "leisure", "hygiene"]
const TRAITS := ["extraversion", "confidence", "sociability", "conscientiousness", "reliability", "risk", "curiosity", "ambition", "impulsivity"]
const MAX_STEPS := 20000
const SCALE := 1000000


# --- identity -------------------------------------------------------------------

## Adds/extends persistent identity fields (personality incl. chronotype and
## preferences, profession). Older records are migrated deterministically.
static func ensure_profile(rec: Dictionary, config: Dictionary, founded_unix: int) -> bool:
	var changed := false
	var rng := RandomNumberGenerator.new()
	rng.seed = SettlementCore.mix(str(rec.get("npc_id", "")) + "#profile2")
	var p: Dictionary = rec.get("personality", {})
	var mig: Dictionary = config.get("personality", {}).get("migrate_from", {})
	for old in mig:
		if p.has(old) and not p.has(mig[old]):
			p[mig[old]] = p[old]
	for t in TRAITS:
		if not p.has(t):
			p[t] = snappedf(clampf(rng.randfn(0.5, 0.2), 0.03, 0.97), 0.01)
			changed = true
	# coherent profile: shy people are rarely very extraverted
	if not p.has("chronotype"):
		p["chronotype"] = snappedf(clampf(rng.randfn(0.0, 0.45), -1.0, 1.0), 0.01)
		p["leisure_place"] = "park" if rng.randf() < 0.5 + (float(p["curiosity"]) - 0.5) * 0.6 else "plaza"
		p["eat_out_affinity"] = snappedf(clampf(rng.randfn(0.5, 0.2), 0.0, 1.0), 0.01)
		changed = true
	rec["personality"] = p
	if not rec.has("profession"):
		var role: String = rec.get("role", "resident")
		var prof: Dictionary = config.get("professions", {}).get(role, {})
		rec["profession"] = {"title": prof.get("title", role), "skill_name": prof.get("skill", ""),
			"skill": snappedf(rng.randf_range(0.3, 0.7), 0.01) if prof.get("skill", "") != "" else 0.0}
		changed = true
	return changed


static func trait_of(rec: Dictionary, name: String) -> float:
	return float(rec.get("personality", {}).get(name, 0.5))


# --- needs (fixed point) ---------------------------------------------------------

static func initial_state(rec: Dictionary, t: int, home_place: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(rec.get("npc_id", "")) + "#init")
	var needs := {}
	for k in NEED_KEYS:
		needs[k] = rng.randi_range(550000, 900000)
	return {"act": "relax_home", "place": home_place, "t0": t, "t1": t, "travel": {}, "needs": needs, "needs_at": t, "n": 0, "last_act": "", "work_min": 0, "pause_for": 0}


static func needs_at(state: Dictionary, rec: Dictionary, config: Dictionary, t: int, supply: Dictionary = {}) -> Dictionary:
	var act: String = "walk" if not state.get("travel", {}).is_empty() else state["act"]
	return to_float(_integrate(state["needs"], act, t - int(state["needs_at"]), rec, config, supply))


static func to_float(fixed: Dictionary) -> Dictionary:
	var out := {}
	for k in NEED_KEYS:
		out[k] = float(fixed.get(k, SCALE / 2)) / SCALE
	return out


static func _integrate(needs: Dictionary, act: String, seconds: int, rec: Dictionary, config: Dictionary, supply: Dictionary = {}) -> Dictionary:
	var out := {}
	var defs: Dictionary = config.get("needs", {})
	var gains: Dictionary = config.get("activities", {}).get(act, {}).get("gain", {})
	# basic supply (Grundversorgung): shortages make meals, washing and
	# evenings at home less effective – people feel what the settlement lacks
	if not supply.is_empty() and (supply.get("food_short", false) or supply.get("water_short", false) or supply.get("energy_short", false)):
		gains = gains.duplicate()
		if gains.has("food"):
			gains["food"] = float(gains["food"]) * (0.5 if supply.get("food_short", false) else 1.0) * (0.8 if supply.get("water_short", false) else 1.0)
		if gains.has("hygiene") and supply.get("water_short", false):
			gains["hygiene"] = float(gains["hygiene"]) * 0.3
		if act == "relax_home" and supply.get("energy_short", false):
			gains["leisure"] = float(gains.get("leisure", 0.0)) * 0.6
	for k in NEED_KEYS:
		var d: Dictionary = defs.get(k, {})
		var decay := float(d.get("decay", 0.04))
		if act == "sleep" or act == "rest_sick":
			decay *= float(d.get("sleep_factor", 1.0))
		# personality shapes needs: introverts need less company, curious people more variety
		if k == "social":
			decay *= 0.4 + 1.2 * trait_of(rec, "extraversion")
		elif k == "leisure":
			decay *= 0.6 + 0.8 * trait_of(rec, "curiosity")
		var rate := float(gains.get(k, 0.0)) - decay
		out[k] = clampi(int(needs.get(k, SCALE / 2)) + int(round(rate * float(seconds) / 3600.0 * SCALE)), 0, SCALE)
	return out


# --- time & obligations --------------------------------------------------------------

static func local_hour(t: int, offset_min: int) -> float:
	return float(posmod(t + offset_min * 60, 86400)) / 3600.0


static func weekday(t: int, offset_min: int) -> int:
	return posmod(int(floor(float(t + offset_min * 60) / 86400.0)) + 4, 7)


static func day_start(t: int, offset_min: int) -> int:
	var local := t + offset_min * 60
	return local - posmod(local, 86400) - offset_min * 60


## The NPC's current or next shift [start, end, building] from the duty
## roster (yesterday's night shift, today, tomorrow), or [].
static func next_shift(rec: Dictionary, t: int, ctx: Dictionary) -> Array:
	var plans: Callable = ctx.get("plan_for_day", Callable())
	if not plans.is_valid():
		return []
	var day := SettlementCore.day_index(t, int(ctx["offset_min"]))
	for d in [day - 1, day, day + 1]:
		var plan: Dictionary = plans.call(d)
		var sh: Array = plan.get("shifts", {}).get(rec.get("npc_id", ""), [])
		if not sh.is_empty() and int(sh[1]) > t:
			return sh
	return []


static func _absent_today(rec: Dictionary, t: int, ctx: Dictionary) -> bool:
	var day := SettlementCore.day_index(t, int(ctx["offset_min"]))
	var rcd: Dictionary = ctx.get("record", {})
	return rcd.get("core", {}).get("absent", {}).get(str(day), {}).has(rec.get("npc_id", ""))


static func _sick(rec: Dictionary) -> bool:
	return str(rec.get("health", {}).get("status", "healthy")) != "healthy"


# --- decisions -------------------------------------------------------------------------

static func _pressure(n: float) -> float:
	return pow(1.0 - n, 2.0) * 4.0 + (2.0 if n < 0.15 else 0.0)


static func _in_windows(h: float, windows: Array) -> bool:
	for w in windows:
		var a := float(w[0])
		var b := float(w[1])
		if (h >= a and h < b) or (b > 24.0 and h + 24.0 >= a and h + 24.0 < b):
			return true
	return false


static func _seeded(npc_id: String, n: int, salt: String) -> float:
	return SettlementCore._chance(npc_id + "#" + str(n) + "#" + salt)


## Personal wake time (local hours): chronotype, conscientiousness, weekend.
static func wake_hour(rec: Dictionary, t: int, ctx: Dictionary) -> float:
	var wd := weekday(t + 6 * 3600, int(ctx["offset_min"]))   # the coming morning
	var h := 6.6 + 1.5 * trait_of(rec, "chronotype") - 0.6 * (trait_of(rec, "conscientiousness") - 0.5)
	if wd == 0 or wd == 6:
		h += 0.5 + 0.6 * maxf(0.0, trait_of(rec, "chronotype"))
	# day-to-day variation (seeded): sometimes earlier, sometimes later
	h += (_seeded(str(rec.get("npc_id", "")), SettlementCore.day_index(t + 6 * 3600, int(ctx["offset_min"])), "wake") - 0.5) * (0.6 + 0.8 * trait_of(rec, "impulsivity"))
	return clampf(h, 4.5, 10.5)


## Chooses the next activity at time t. Returns {act, place, minutes, score}.
static func decide(rec: Dictionary, state: Dictionary, t: int, ctx: Dictionary) -> Dictionary:
	var config: Dictionary = ctx["config"]
	var nav: NavGrid = ctx["nav"]
	var off: int = ctx["offset_min"]
	var needs: Dictionary = to_float(state["needs"])
	var acts: Dictionary = config.get("activities", {})
	var h := local_hour(t, off)
	var here: String = state["place"]
	var id: String = str(rec.get("npc_id", ""))
	var sick := _sick(rec)
	var shift: Array = [] if sick else next_shift(rec, t, ctx)
	if not shift.is_empty() and _absent_today(rec, int(shift[0]), ctx):
		shift = []   # skipping today's shift (unexcused – decided by the settlement day step)
	var work_place := ("bld:" + str(shift[2])) if not shift.is_empty() else ""
	var late := int(_seeded(id, SettlementCore.day_index(t, off), "late") * 25.0 * (1.0 - trait_of(rec, "reliability")))
	var early := int(5.0 + 15.0 * trait_of(rec, "conscientiousness"))
	var in_shift := work_place != "" and t >= int(shift[0]) - early * 60 + late * 60 and t < int(shift[1])
	var budget_end := t + 24 * 3600
	if work_place != "" and not in_shift and int(shift[0]) > t:
		budget_end = int(shift[0]) - (early - late) * 60
	var bed := 21.5 + 1.4 * trait_of(rec, "chronotype") + (0.8 if trait_of(rec, "impulsivity") > 0.65 else 0.0)
	var cands := []
	for act in acts:
		var a: Dictionary = acts[act]
		if bool(a.get("sick_only", false)) and not sick:
			continue
		if sick and not bool(a.get("sick_ok", false)):
			continue
		var place := work_place if (act == "work" or act == "pause") else _place_for(a.get("place", "home"), ctx)
		if (act == "work" or act == "pause") and not in_shift:
			continue
		if place == "" or not nav.places.has(place):
			continue
		var wins: Array = a.get("windows", [[0, 24]])
		if act == "socialize" and trait_of(rec, "impulsivity") > 0.6:
			wins = [[9, 23.5]]   # impulsive people stay out later
		if act != "work" and act != "sleep" and act != "pause" and not _in_windows(h, wins):
			continue
		var travel := nav.travel_seconds(here, place)
		var minutes := int(a.get("minutes", [60, 60])[0])
		var bonus := 0.0
		if act == "work" or act == "pause":
			var mid := (int(shift[0]) + int(shift[1])) / 2
			var long_shift := int(shift[1]) - int(shift[0]) >= 6 * 3600
			var pause_due := long_shift and int(state.get("pause_for", 0)) != int(shift[0]) and t >= mid - 1800 - 900
			if act == "pause":
				if not pause_due:
					continue
				minutes = 30
				bonus = 6.0
			else:
				var stop := int(shift[1]) + int(trait_of(rec, "ambition") * 15.0) * 60
				if long_shift and int(state.get("pause_for", 0)) != int(shift[0]) and t < mid - 1800 - 900:
					stop = mid - 1800
				minutes = int((stop - t - travel) / 60)
				if minutes < 10:
					continue
				bonus = 2.5 + 1.5 * trait_of(rec, "conscientiousness")
				if float(needs["food"]) < 0.1 or float(needs["energy"]) < 0.06:
					bonus -= 2.5
		else:
			if act == "sleep" or act == "rest_sick":
				var night := h >= bed or h < 5.0
				minutes = int(clampf((1.0 - float(needs["energy"])) / 0.14, 1.0, 10.0) * 60.0)
				if night:
					var wake := wake_hour(rec, t, ctx)
					minutes = int(clampf((wake - h) if h < 5.0 else (24.0 - h + wake), 4.0, 11.0) * 60.0)
					bonus = 1.5 + 2.0 * (1.0 - float(needs["energy"]))
				elif sick:
					bonus = 0.8
				elif float(needs["energy"]) > 0.25:
					bonus = -3.0
				if act == "rest_sick":
					minutes = mini(minutes, 180) if not night else minutes
			elif act == "eat_home" or act == "eat_out":
				if (h >= 6.5 and h < 9.0) or (h >= 11.5 and h < 13.5) or (h >= 17.5 and h < 20.0):
					bonus = 0.8 * (1.0 - float(needs["food"]))
				if act == "eat_out":
					bonus -= 0.35
			elif act == "relax_home":
				bonus = 0.15 if (h < 9.0 or h >= 19.0) else -0.15
			elif act == "see_doctor":
				bonus = 1.5 if int(state.get("recent", {}).get("see_doctor", -10000000)) < day_start(t, off) else -5.0
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
		var score := benefit / sqrt(maxf(dur_h, 1.0)) + bonus
		# personality (measurable effects, see docs/LIVING_WORLD.md §5)
		match act:
			"socialize":
				score *= (0.3 + 1.4 * trait_of(rec, "extraversion")) * (0.7 + 0.6 * trait_of(rec, "sociability"))
			"leisure":
				score *= 0.6 + 0.8 * trait_of(rec, "curiosity")
			"eat_out":
				score *= 0.4 + 0.5 * trait_of(rec, "extraversion") + 0.3 * trait_of(rec, "confidence") + 0.4 * trait_of(rec, "eat_out_affinity")
			"errand":
				score *= 0.6 + 0.8 * trait_of(rec, "confidence")
			"relax_home":
				score *= 1.4 - 0.8 * trait_of(rec, "extraversion")
			"wash":
				score *= 0.7 + 0.6 * trait_of(rec, "conscientiousness")
		# additive personality bias (introverts prefer home, extraverts company)
		var ex := trait_of(rec, "extraversion") - 0.5
		if act == "socialize" or act == "eat_out":
			score += 0.9 * ex
		elif act == "relax_home":
			score -= 0.7 * ex
		elif act == "leisure":
			score += 0.5 * (trait_of(rec, "curiosity") - 0.5)
		# duty: during a shift only work and the break count (barring emergencies)
		if in_shift and act != "work" and act != "pause":
			score -= 4.0
		if act == "leisure" and rec.get("personality", {}).get("leisure_place", "park") == "park":
			score += 0.15
		if act == "socialize" and rec.get("personality", {}).get("leisure_place", "park") == "plaza":
			score += 0.15
		score -= travel / 60.0 * 0.02
		if act == str(state.get("last_act", "")) and act != "work" and act != "sleep" and act != "rest_sick":
			score -= 0.5 * (0.5 + trait_of(rec, "curiosity"))
		var cd := float(a.get("cooldown_h", 0.0))
		if cd > 0.0 and t - int(state.get("recent", {}).get(act, -1000000)) < int(cd * 3600.0):
			score -= 0.8
		var cand := {"act": act, "place": place, "minutes": minutes, "score": score}
		if act == "work" and t + travel > int(shift[0]) + 120:
			cand["hurry"] = true   # late for the shift: runs
		if act == "pause":
			cand["shift_start"] = int(shift[0])
		cands.append(cand)
	if cands.is_empty():
		return {"act": "rest_sick" if sick else "relax_home", "place": ctx["home"], "minutes": 30, "score": 0.0}
	cands.sort_custom(func(x, y): return float(x["score"]) > float(y["score"]))
	# obligations and exhaustion are not left to chance
	if cands[0]["act"] in ["work", "pause"] or (cands[0]["act"] in ["sleep", "rest_sick"] and float(cands[0]["score"]) > 2.0):
		return cands[0]
	# weighted random choice among the best options (seeded): impulsive
	# people pick less "optimal" activities more often
	var temp := 0.08 + 0.45 * trait_of(rec, "impulsivity")
	var top := cands.slice(0, mini(4, cands.size()))
	var best_s := float(top[0]["score"])
	var weights := []
	var total := 0.0
	for c in top:
		var w := exp((float(c["score"]) - best_s) / temp)
		weights.append(w)
		total += w
	var r := _seeded(id, int(state.get("n", 0)), "pick") * total
	for i in top.size():
		r -= float(weights[i])
		if r <= 0.0:
			return top[i]
	return top[0]


static func _place_for(kind: String, ctx: Dictionary) -> String:
	match kind:
		"home":
			return ctx.get("home", "")
		"work":
			return ctx.get("work", "home")
		"eatery":
			return ctx.get("eatery", "")
		"shop":
			return ctx.get("shop", "")
		"clinic":
			return ctx.get("clinic", "")
		_:
			return kind   # "plaza", "park"


# --- progression ---------------------------------------------------------------------

## Advances the state to `to`. Returns events ({t, npc, kind, act, place}).
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
		state["needs"] = _integrate(state["needs"], act_now, secs, rec, config, _supply(ctx))
		state["needs_at"] = boundary
		if act_now == "work":
			state["work_min"] = int(state.get("work_min", 0)) + int(secs / 60)
		if not travel.is_empty():
			state["place"] = travel["to"]
			state["act"] = travel["next"]
			state["t0"] = boundary
			state["t1"] = boundary + int(travel["next_dur"]) * 60
			state["travel"] = {}
			_started(state, str(state["act"]), boundary, ctx)
			events.append({"t": boundary, "npc": rec.get("npc_id", ""), "kind": "activity_start", "act": state["act"], "place": state["place"]})
			continue
		state["last_act"] = state["act"]
		var d := decide(rec, state, boundary, ctx)
		state["n"] = int(state.get("n", 0)) + 1
		if d.has("shift_start"):
			state["pause_for"] = int(d["shift_start"])
		if d["place"] != state["place"]:
			var walk_s := maxi(1, nav.travel_seconds(state["place"], d["place"]))
			if d.get("hurry", false):
				walk_s = maxi(1, int(walk_s * 0.55))
			state["travel"] = {"from": state["place"], "to": d["place"], "depart": boundary, "arrive": boundary + walk_s, "next": d["act"], "next_dur": d["minutes"], "nav_v": nav.version}
			if d.get("hurry", false):
				state["travel"]["hurry"] = true
			state["act"] = "walk"
			state["t0"] = boundary
			state["t1"] = boundary + walk_s
			events.append({"t": boundary, "npc": rec.get("npc_id", ""), "kind": "walk_start", "act": d["act"], "place": d["place"]})
		else:
			state["act"] = d["act"]
			_started(state, str(d["act"]), boundary, ctx)
			state["t0"] = boundary
			state["t1"] = boundary + maxi(1, int(d["minutes"])) * 60
			events.append({"t": boundary, "npc": rec.get("npc_id", ""), "kind": "activity_start", "act": state["act"], "place": state["place"]})
	return events


static func _supply(ctx: Dictionary) -> Dictionary:
	return ctx.get("record", {}).get("core", {}).get("stats", {})


static func _started(state: Dictionary, act: String, t: int, ctx: Dictionary) -> void:
	var r: Dictionary = state.get("recent", {})
	r[act] = t
	state["recent"] = r


## External interaction (e.g. the player greets the NPC) at time t.
static func apply_interaction(rec: Dictionary, state: Dictionary, t: int, ctx: Dictionary, delta: Dictionary) -> void:
	var act: String = "walk" if not state.get("travel", {}).is_empty() else state["act"]
	var cur := _integrate(state["needs"], act, t - int(state["needs_at"]), rec, ctx["config"], _supply(ctx))
	for k in delta:
		if cur.has(k):
			cur[k] = clampi(int(cur[k]) + int(round(float(delta[k]) * SCALE)), 0, SCALE)
	state["needs"] = cur
	state["needs_at"] = t


static func mood(needs: Dictionary) -> float:
	var s := 0.0
	for k in NEED_KEYS:
		s += float(needs.get(k, 0.5))
	return s / NEED_KEYS.size()
