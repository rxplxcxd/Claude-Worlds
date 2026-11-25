class_name SettlementCore
extends RefCounted
## Settlement DAY STEP – the long-term life of one settlement (Phase 3/4).
## Pure static functions on the settlement record (server-capable).
##
## Runs once per settlement-local day in EVERY simulation tier (hot, warm,
## cold/lazy) with identical results: health, absences and substitutions,
## duty rosters from the business operating models, basic supply (food,
## water, energy), maintenance and building condition, fires and emergency
## response, employment consequences, ageing, mortality and newcomers, and
## the settlement lifecycle (active / abandoned). The detail tier only
## decides how much is computed, never whether something happens.
## The individual daily routine (NpcBrain, tier S0/S1) READS this state.
##
## Randomness only via seeds (settlement, day, NPC) – reproducible.

const CORE_VERSION := 1
const MAX_EVENTS := 300
const FUNCTIONS := ["verwaltung", "wasser", "energie", "lebensmittel", "medizin", "notfall", "bau", "handwerk", "handel", "laden"]


# --- small helpers ---------------------------------------------------------------

static func day_index(t: int, offset_min: int) -> int:
	return int(floor(float(t + offset_min * 60) / 86400.0))


static func day_start_utc(day: int, offset_min: int) -> int:
	return day * 86400 - offset_min * 60


static func _rng(seed_text: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = mix(seed_text)
	return r


## Well-distributed 32-bit hash of a seed text. Godot's String.hash() is
## too weak for "seed#day" style keys (consecutive days give consecutive
## values), so it is finalised with the Murmur3 mixer.
static func mix(seed_text: String) -> int:
	var h := hash(seed_text) & 0xffffffff
	h = ((h ^ (h >> 16)) * 0x85ebca6b) & 0xffffffff
	h = ((h ^ (h >> 13)) * 0xc2b2ae35) & 0xffffffff
	return h ^ (h >> 16)


## Uniform number in [0, 1) from a seed text.
static func _chance(seed_text: String) -> float:
	return float(mix(seed_text)) / 4294967296.0


static func alive_npcs(record: Dictionary) -> Array:
	return record.get("npcs", []).filter(func(r): return r.get("alive", true))


static func age_years(r: Dictionary, day: int, cfg: Dictionary) -> float:
	# birth_day is a REAL day index; ageing runs at days_per_year real days per year
	var dpy := float(cfg.get("demography", {}).get("days_per_year", 28))
	var age0 := float(r.get("age_at_arrival", 30.0))
	var arrived := int(r.get("arrived_day", day))
	return age0 + float(day - arrived) / dpy


static func trait_of(r: Dictionary, name: String) -> float:
	return float(r.get("personality", {}).get(name, 0.5))


## Ensures the core block and per-NPC macro fields (migration from 0.5.0).
static func ensure(record: Dictionary, cfg: Dictionary, day: int) -> void:
	var core: Dictionary = record.get("core", {})
	if int(core.get("version", 0)) != CORE_VERSION:
		var n: int = alive_npcs(record).size() + record.get("resident_player_ids", []).size()
		var st: Dictionary = cfg.get("supply", {}).get("founding_stock_days", {})
		core = {
			"version": CORE_VERSION, "day": day - 1,
			"stocks": {"food": float(st.get("food", 21)) * n, "water": float(st.get("water", 3)) * n, "energy": float(st.get("energy", 3)) * n},
			"condition": {}, "coverage": {}, "stats": {}, "plan": {}, "events": [],
			"policy": {"open_for_newcomers": true, "priorities": ["wasser", "lebensmittel", "energie", "medizin", "notfall", "bau", "verwaltung", "handel", "laden", "handwerk"]},
			"counters": {"deaths": 0, "arrivals": 0, "illnesses": 0, "accidents": 0, "dismissals": 0, "fires": 0},
		}
		record["core"] = core
	if not record.has("lifecycle"):
		record["lifecycle"] = {"status": "active", "since_day": day}
	for r in record.get("npcs", []):
		NpcBrain.ensure_profile(r, cfg, 0)
		if not r.has("alive"):
			r["alive"] = true
		if not r.has("arrived_day"):
			r["arrived_day"] = day
			r["age_at_arrival"] = float(_rng(str(r.get("npc_id", "")) + "#age").randi_range(19, 62))
		if not r.has("health"):
			r["health"] = {"status": "healthy", "until_day": 0}
		if not r.has("employment"):
			var wp: String = r.get("workplace_id", "")
			var st0 := "employed" if wp != "" else ("pool" if r.get("role", "") == "worker" else "none")
			r["employment"] = {"workplace_id": wp, "status": st0, "warnings": [], "since_day": day}


# --- buildings and staff ----------------------------------------------------------

static func building_types(record: Dictionary, data: SettlementData) -> Dictionary:
	var out := {}
	for b in data.buildings:
		out[b.get("id", "")] = b.get("type", "")
	return out


static func staff_of(record: Dictionary, bid: String) -> Array:
	var out := []
	for r in alive_npcs(record):
		var e: Dictionary = r.get("employment", {})
		if e.get("status", "") == "employed" and e.get("workplace_id", "") == bid:
			out.append(r)
	out.sort_custom(func(a, b): return str(a["npc_id"]) < str(b["npc_id"]))
	return out


## Duty roster of day `day`: {npc_id: [start_utc, end_utc, building_id, shift_name]},
## plus "on_call" {building_id: npc_id} and "gaps" {building_id: missing staff-hours}.
## Rotation: weekly, so early/late/night change between people; 7-day
## operations give everybody two days off (rotating); individual offsets.
static func roster_for_day(record: Dictionary, data: SettlementData, cfg: Dictionary, day: int, offset_min: int) -> Dictionary:
	var models: Dictionary = cfg.get("operating_models", {})
	var types := building_types(record, data)
	var wd := posmod(day + 4, 7)
	var week := int(floor(float(day) / 7.0))
	var d0 := day_start_utc(day, offset_min)
	var shifts := {}
	var on_call := {}
	var gaps := {}
	var absent: Dictionary = record.get("core", {}).get("absent", {}).get(str(day), {})
	var busy := {}
	var bids: Array = types.keys()
	bids.sort()
	for bid in bids:
		var m: Dictionary = models.get(types[bid], {})
		if m.is_empty():
			continue
		var staff := staff_of(record, bid)
		var seven: bool = m.get("shifts", []).any(func(s): return s.get("days", []).size() == 7)
		var avail := []
		for i in staff.size():
			var r: Dictionary = staff[i]
			if absent.has(r["npc_id"]) or str(r.get("health", {}).get("status", "healthy")) != "healthy":
				continue
			if seven and staff.size() > 2 and posmod(wd - i * 2, 7) < 2:
				continue   # rotating two days off in 24/7 operations
			avail.append(r)
		# weekly rotation of who takes which shift
		if not avail.is_empty():
			var rot := posmod(week, avail.size())
			avail = avail.slice(rot) + avail.slice(0, rot)
		var si := 0
		for s in m.get("shifts", []):
			si += 1
			var days: Array = []
			for dd in s.get("days", []):
				days.append(int(dd))
			if not wd in days:
				continue
			var need := int(s.get("staff", 1))
			for k in need:
				var pick: Dictionary = {}
				for r in avail:
					if not busy.has(r["npc_id"]):
						pick = r
						break
				var hours := float(s["end"]) - float(s["start"])
				if pick.is_empty():
					gaps[bid] = float(gaps.get(bid, 0.0)) + hours
					continue
				busy[pick["npc_id"]] = true
				var off := (mix(str(pick["npc_id"]) + "#off") % 5) * 5 - 10   # −10…+10 min individual start
				shifts[pick["npc_id"]] = [d0 + int(float(s["start"]) * 3600.0) + off * 60, d0 + int(float(s["end"]) * 3600.0) + off * 60, bid, s.get("name", "")]
		if m.get("on_call_night", false):
			for r in staff:
				if not busy.has(r["npc_id"]) and not absent.has(r["npc_id"]) and str(r.get("health", {}).get("status", "healthy")) == "healthy":
					on_call[bid] = r["npc_id"]
					break
	return {"day": day, "shifts": shifts, "on_call": on_call, "gaps": gaps}


# --- the day step -------------------------------------------------------------------------

## Processes settlement-local day `day` (all effects of that day). Returns events.
static func day_step(record: Dictionary, data: SettlementData, cfg: Dictionary, day: int, offset_min: int) -> Array:
	ensure(record, cfg, day)
	var core: Dictionary = record["core"]
	var sid: String = record.get("settlement_id", "")
	var events := []
	var t := day_start_utc(day, offset_min)
	var hc: Dictionary = cfg.get("health", {})
	var sup: Dictionary = cfg.get("supply", {})
	var emp: Dictionary = cfg.get("employment", {})
	var dem: Dictionary = cfg.get("demography", {})
	var stats: Dictionary = core.get("stats", {})
	var shortage := 1.0 if bool(stats.get("food_short", false)) or bool(stats.get("water_short", false)) else 0.0
	var clinic_cov := float(core.get("coverage", {}).get("medizin", 0.0))

	# 1. health: recovery, illness, (accidents are rolled with the roster below)
	for r in alive_npcs(record):
		var h: Dictionary = r["health"]
		if h["status"] != "healthy" and int(h.get("until_day", 0)) <= day:
			r["health"] = {"status": "healthy", "until_day": 0}
			events.append(_ev(t, "recovered", r["npc_id"]))
		elif h["status"] == "healthy":
			var age := age_years(r, day, cfg)
			var p := float(hc.get("illness_base", 0.0035)) * (1.0 + float(hc.get("illness_age_factor", 0.02)) * maxf(0.0, age - 40.0)) * (1.0 + float(hc.get("illness_shortage_factor", 2.0)) * shortage)
			if _chance("%s#ill#%s#%d" % [sid, r["npc_id"], day]) < p:
				var rng := _rng("%s#illd#%s#%d" % [sid, r["npc_id"], day])
				var dur := rng.randi_range(int(hc["illness_days"][0]), int(hc["illness_days"][1]))
				if clinic_cov > 0.5:
					dur = maxi(1, int(round(dur * float(hc.get("clinic_speedup", 0.6)))))
				r["health"] = {"status": "ill", "until_day": day + dur, "since_day": day}
				core["counters"]["illnesses"] = int(core["counters"].get("illnesses", 0)) + 1
				events.append(_ev(t, "fell_ill", r["npc_id"], {"days": dur}))
		# retirement
		var e: Dictionary = r["employment"]
		if e.get("status", "") == "employed" and age_years(r, day, cfg) >= float(emp.get("retirement_age", 67)):
			r["employment"] = {"workplace_id": "", "status": "retired", "warnings": [], "since_day": day}
			events.append(_ev(t, "retired", r["npc_id"]))

	# 2. unexcused absences (reliability): only people who have a shift today
	core["absent"] = {str(day): {}}
	var planned := roster_for_day(record, data, cfg, day, offset_min)
	var absent_today := {}
	for id in planned["shifts"]:
		var ra := _npc(record, id)
		var p2 := float(emp.get("unexcused_base", 0.006)) * (1.6 - 1.4 * trait_of(ra, "reliability"))
		if _chance("%s#abs#%s#%d" % [sid, id, day]) < p2:
			absent_today[id] = "unexcused"
	core["absent"] = {str(day): absent_today}   # only the current day is kept

	# 3. roster with substitution (Master §13.6): colleagues off duty step in
	#    for critical services, general workers (pool) fill any gap
	var roster := roster_for_day(record, data, cfg, day, offset_min) if not absent_today.is_empty() else planned
	var types := building_types(record, data)
	var models: Dictionary = cfg.get("operating_models", {})
	var gap_bids: Array = roster["gaps"].keys()
	gap_bids.sort_custom(func(a, b): return (1 if models.get(types.get(a, ""), {}).get("critical", false) else 0) > (1 if models.get(types.get(b, ""), {}).get("critical", false) else 0))
	for bid in gap_bids:
		var m: Dictionary = models.get(types.get(bid, ""), {})
		var team := {}
		for x in staff_of(record, bid):
			team[x["npc_id"]] = true
		var tie := SocialCore.ties_to(record, team)
		var pool_sorted: Array = _pool(record)
		pool_sorted.sort_custom(func(x, y): return float(tie.get(x["npc_id"], 0.0)) > float(tie.get(y["npc_id"], 0.0)) or (float(tie.get(x["npc_id"], 0.0)) == float(tie.get(y["npc_id"], 0.0)) and str(x["npc_id"]) < str(y["npc_id"])))
		var helpers: Array = (staff_of(record, bid) if m.get("critical", false) else []) + pool_sorted
		for r in helpers:
			var id: String = r["npc_id"]
			if roster["shifts"].has(id) or absent_today.has(id) or r["health"]["status"] != "healthy":
				continue
			var hours := float(roster["gaps"][bid])
			var start := t + 14 * 3600
			roster["shifts"][id] = [start, start + int(minf(hours, 8.0) * 3600.0), bid, "Vertretung"]
			roster["gaps"][bid] = maxf(0.0, hours - 8.0)
			events.append(_ev(t, "substitution", id, {"building": bid}))
			var soc: Dictionary = SocialCore.person(r)
			soc["helped"] = int(soc.get("helped", 0)) + 1
			if float(roster["gaps"][bid]) <= 0.0:
				break
	var wd0 := posmod(day + 4, 7)
	if wd0 >= 1 and wd0 <= 5:
		var help_bid := _first_of_type(types, str(cfg.get("employment", {}).get("pool_default_type", "farm_shop")))
		for r in _pool(record):
			var pid: String = r["npc_id"]
			if help_bid != "" and not roster["shifts"].has(pid) and not absent_today.has(pid) and r["health"]["status"] == "healthy":
				var off2 := (mix(pid + "#off") % 5) * 5 - 10
				roster["shifts"][pid] = [t + 8 * 3600 + off2 * 60, t + 15 * 3600 + off2 * 60, help_bid, "Aushilfe"]
	for id in absent_today:
		events.append(_ev(t, "absent_unexcused", id))
		var e2: Dictionary = _npc(record, id)["employment"]
		var w: Array = e2.get("warnings", [])
		w = w.filter(func(d): return int(d) > day - int(emp.get("warning_window_days", 45)))
		w.append(day)
		e2["warnings"] = w
		if w.size() >= int(emp.get("warnings_to_dismissal", 3)):
			var old: String = e2.get("workplace_id", "")
			_npc(record, id)["employment"] = {"workplace_id": "", "status": "unemployed", "warnings": [], "since_day": day, "dismissed_from": old}
			core["counters"]["dismissals"] = int(core["counters"].get("dismissals", 0)) + 1
			events.append(_ev(t, "dismissed", id, {"building": old}))
	var keep: Dictionary = {str(day): roster}
	if core.get("plan", {}).has(str(day - 1)):
		keep[str(day - 1)] = core["plan"][str(day - 1)]   # night shifts reaching into today
	core["plan"] = keep

	# 4. accidents at work
	for id in roster["shifts"]:
		var r3 := _npc(record, id)
		var fn := str(models.get(types.get(roster["shifts"][id][2], ""), {}).get("function", ""))
		var pa := float(hc.get("accident_per_workday", {}).get(fn, 0.0)) * (0.5 + trait_of(r3, "risk"))
		if pa > 0.0 and _chance("%s#acc#%s#%d" % [sid, id, day]) < pa:
			var dur2 := _rng("%s#accd#%s#%d" % [sid, id, day]).randi_range(int(hc["accident_days"][0]), int(hc["accident_days"][1]))
			r3["health"] = {"status": "injured", "until_day": day + 1 + dur2, "since_day": day}
			core["counters"]["accidents"] = int(core["counters"].get("accidents", 0)) + 1
			events.append(_ev(t, "accident", id, {"days": dur2, "building": roster["shifts"][id][2]}))

	# 5. coverage per function (staffed hours / required hours) and on-call
	var cov := {}
	var req := {}
	for bid in types:
		var m2: Dictionary = models.get(types[bid], {})
		var fn2 := str(m2.get("function", ""))
		if fn2 == "":
			continue
		var wd := posmod(day + 4, 7)
		for s in m2.get("shifts", []):
			var days2: Array = []
			for dd in s.get("days", []):
				days2.append(int(dd))
			if wd in days2:
				req[fn2] = float(req.get(fn2, 0.0)) + (float(s["end"]) - float(s["start"])) * int(s.get("staff", 1))
	var hours_by_fn := {}
	for id in roster["shifts"]:
		var sh: Array = roster["shifts"][id]
		var fn3 := str(models.get(types.get(sh[2], ""), {}).get("function", ""))
		hours_by_fn[fn3] = float(hours_by_fn.get(fn3, 0.0)) + float(int(sh[1]) - int(sh[0])) / 3600.0
	for fn4 in FUNCTIONS:
		cov[fn4] = minf(1.0, float(hours_by_fn.get(fn4, 0.0)) / float(req[fn4])) if float(req.get(fn4, 0.0)) > 0.0 else 0.0
	core["coverage"] = cov

	# 6. basic supply (Grundversorgung)
	var people: int = alive_npcs(record).size() + record.get("resident_player_ids", []).size()
	var cons: Dictionary = sup.get("consumption_per_person", {})
	var region: Dictionary = record.get("region_factors", {})
	var soil := float(region.get("food", 1.0))
	var prod := {
		"food": _farm_output(float(hours_by_fn.get("lebensmittel", 0.0)), sup) * soil
			+ float(hours_by_fn.get("handel", 0.0)) * float(sup.get("food_per_trade_hour", 0.35))
			+ float(hours_by_fn.get("laden", 0.0)) * float(sup.get("food_per_shop_hour", 0.2)),
		"water": float(sup.get("water_capacity_per_day", 60)) * float(region.get("water", 1.0)) * _uptime(cov.get("wasser", 0.0), roster["on_call"], types, "water_works", sup),
		"energy": float(sup.get("energy_capacity_per_day", 55)) * float(region.get("energy", 1.0)) * _uptime(cov.get("energie", 0.0), roster["on_call"], types, "energy_station", sup),
	}
	var stocks: Dictionary = core["stocks"]
	var cap: Dictionary = sup.get("storage_days", {})
	for k in ["food", "water", "energy"]:
		var before := float(stocks.get(k, 0.0))
		var after := clampf(before + float(prod[k]) - float(cons.get(k, 1.0)) * people, 0.0, float(cap.get(k, 30)) * maxi(1, people))
		stocks[k] = snappedf(after, 0.01)
		stats[k + "_prod"] = snappedf(float(prod[k]), 0.01)
		stats[k + "_cons"] = float(cons.get(k, 1.0)) * people
		var short: bool = after <= 0.0 and float(prod[k]) < float(cons.get(k, 1.0)) * people
		if short and not bool(stats.get(k + "_short", false)):
			events.append(_ev(t, "shortage_start", "", {"resource": k}))
		elif not short and bool(stats.get(k + "_short", false)):
			events.append(_ev(t, "shortage_end", "", {"resource": k}))
		stats[k + "_short"] = short

	# 7. maintenance and building condition (→ Living Assets wear)
	var condition: Dictionary = core["condition"]
	var abandoned: bool = record["lifecycle"].get("status", "active") == "abandoned"
	var decay := float(sup.get("abandoned_decay_per_day" if abandoned else "building_decay_per_day", 0.0025))
	var bids: Array = types.keys()
	bids.sort()
	for bid in bids:
		condition[bid] = snappedf(maxf(0.0, float(condition.get(bid, 1.0)) - decay), 0.0001)
	var repair := float(hours_by_fn.get("bau", 0.0)) * float(sup.get("repair_per_builder_hour", 0.012)) * float(region.get("materials", 1.0))
	while repair > 0.0001 and not bids.is_empty():
		var worst: String = bids[0]
		for bid in bids:
			if float(condition[bid]) < float(condition[worst]):
				worst = bid
		if float(condition[worst]) >= 0.999:
			break
		var add := minf(repair, 1.0 - float(condition[worst]))
		condition[worst] = snappedf(float(condition[worst]) + add, 0.0001)
		repair -= add
	for bid in bids:
		_sync_wear(record, bid, float(condition[bid]), abandoned, t, cfg, events)

	# 8. fires and emergency response (Brand- und Notfallschutz)
	for bid in bids:
		if _chance("%s#fire#%s#%d" % [sid, bid, day]) < float(sup.get("fire_per_building_day", 0.00025)):
			core["counters"]["fires"] = int(core["counters"].get("fires", 0)) + 1
			var responded: bool = float(cov.get("notfall", 0.0)) > 0.0 or roster["on_call"].size() > 0
			var ev := "fire_small" if responded else "fire_large"
			VisualEventRouter.apply_building_event(record, bid, ev, t, cfg)
			condition[bid] = maxf(0.0, float(condition[bid]) - (0.1 if responded else 0.45))
			events.append(_ev(t, "fire", "", {"building": bid, "contained": responded}))

	# 9. employment: administration assigns unemployed people to vacancies
	var admin_ok := float(cov.get("verwaltung", 0.0)) > 0.0 or posmod(day + 4, 7) in [0, 6]
	if admin_ok:
		var seekers: Array = alive_npcs(record)
		var employed := {}
		for x in seekers:
			if x["employment"].get("status", "") == "employed":
				employed[x["npc_id"]] = true
		var ties := SocialCore.ties_to(record, employed)
		if not ties.is_empty():
			seekers = seekers.filter(func(x): return x["employment"].get("status", "") in ["unemployed", "pool"])
			seekers.sort_custom(func(x, y): return float(ties.get(x["npc_id"], 0.0)) > float(ties.get(y["npc_id"], 0.0)) or (float(ties.get(x["npc_id"], 0.0)) == float(ties.get(y["npc_id"], 0.0)) and str(x["npc_id"]) < str(y["npc_id"])))
		for r in seekers:
			var e3: Dictionary = r["employment"]
			if not e3.get("status", "") in ["unemployed", "pool"] or (e3.has("dismissed_from") and day - int(e3.get("since_day", day)) < int(emp.get("rehire_after_days", 10))):
				continue
			var job := _vacancy(record, data, cfg, r)
			if job != "":
				r["employment"] = {"workplace_id": job, "status": "employed", "warnings": [], "since_day": day}
				r["workplace_id"] = job
				events.append(_ev(t, "hired", r["npc_id"], {"building": job}))

	# 10. demography: mortality (Gompertz) and newcomers
	var dpy := float(dem.get("days_per_year", 28))
	for r in alive_npcs(record):
		var age2 := age_years(r, day, cfg)
		if age2 < SocialCore.ADULT_AGE:
			continue      # Master §13.7: children never die (or come to harm) in the simulation
		var yearly := minf(1.0, float(dem.get("gompertz_a", 0.00005)) * exp(float(dem.get("gompertz_b", 0.09)) * age2))
		if _chance("%s#death#%s#%d" % [sid, r["npc_id"], day]) < yearly / dpy:
			r["alive"] = false
			r["died_day"] = day
			r["employment"] = {"workplace_id": "", "status": "deceased", "warnings": [], "since_day": day}
			core["counters"]["deaths"] = int(core["counters"].get("deaths", 0)) + 1
			events.append(_ev(t, "died", r["npc_id"], {"age": int(age2)}))
	var policy: Dictionary = core.get("policy", {})
	var free := housing_free(record, data, cfg)
	var food_days := float(stocks["food"]) / maxf(1.0, float(people))
	# newcomers need somebody who receives them: an empty settlement is only
	# resettled through later phases (player return / migration, Phase 8)
	var receivers: int = alive_npcs(record).size() + record.get("resident_player_ids", []).size()
	if not abandoned and receivers > 0 and bool(policy.get("open_for_newcomers", true)) and free > 0 and food_days > 3.0 and not bool(stats.get("water_short", false)):
		var attract := attractiveness(record, cfg)
		stats["attractiveness"] = snappedf(attract, 0.01)
		if _chance("%s#arrive#%d" % [sid, day]) < float(dem.get("arrival_base_per_day", 0.12)) * attract:
			var nr := new_settler(record, data, cfg, day)
			events.append(_ev(t, "arrived", nr["npc_id"], {"role": nr["role"]}))

	# 10b. social life (Phase 5): relationships, families, groups, goals, memories
	SocialCore.day_step(record, data, cfg, day, t, events)

	# 11. lifecycle: a settlement is abandoned only when nobody lives there
	var inhabitants: int = alive_npcs(record).size() + record.get("resident_player_ids", []).size()
	var lc: Dictionary = record["lifecycle"]
	if inhabitants == 0 and lc.get("status", "active") == "active":
		record["lifecycle"] = {"status": "abandoned", "since_day": day}
		events.append(_ev(t, "abandoned", ""))
	elif inhabitants > 0 and lc.get("status", "active") == "abandoned":
		record["lifecycle"] = {"status": "active", "since_day": day}
		events.append(_ev(t, "resettled", ""))

	stats["population"] = alive_npcs(record).size()
	stats["humans"] = record.get("resident_player_ids", []).size()
	stats["housing_free"] = housing_free(record, data, cfg)
	stats["unemployed"] = alive_npcs(record).filter(func(r): return r["employment"].get("status", "") == "unemployed").size()
	stats["pool"] = _pool(record).size()
	stats["ill"] = alive_npcs(record).filter(func(r): return r["health"]["status"] != "healthy").size()
	core["stats"] = stats
	# population development: weekly history (5 years kept)
	if posmod(day, 7) == 0:
		var hist: Array = core.get("history", [])
		hist.append({"day": day, "population": stats["population"], "humans": stats["humans"], "food_days": snappedf(float(stocks["food"]) / maxf(1.0, float(people)), 0.1), "employed": alive_npcs(record).filter(func(r): return r["employment"].get("status", "") == "employed").size()})
		if hist.size() > 260:
			hist = hist.slice(hist.size() - 260)
		core["history"] = hist
	core["day"] = day
	var evlog: Array = core.get("events", [])
	evlog.append_array(events)
	if evlog.size() > MAX_EVENTS:
		evlog = evlog.slice(evlog.size() - MAX_EVENTS)
	core["events"] = evlog
	return events


## Farm output with limited farmland: beyond the capacity of the fields,
## extra hands add little (diminishing returns).
static func _farm_output(hours: float, sup: Dictionary) -> float:
	var cap := float(sup.get("farm_capacity_hours_per_day", 40.0))
	var rate := float(sup.get("food_per_farm_hour", 1.15))
	return minf(hours, cap) * rate + maxf(0.0, hours - cap) * rate * float(sup.get("farm_overcapacity_factor", 0.25))


static func _uptime(coverage: float, on_call: Dictionary, types: Dictionary, type_name: String, sup: Dictionary) -> float:
	# staffed share of the day runs at full uptime; nights with on-call are nearly as good
	var has_call := false
	for bid in on_call:
		if types.get(bid, "") == type_name:
			has_call = true
	var staffed := clampf(coverage, 0.0, 1.0) * (16.0 / 24.0)
	var night := (8.0 / 24.0) * (float(sup.get("uptime_on_call", 0.97)) if has_call else float(sup.get("uptime_unstaffed", 0.75)))
	var rest := (1.0 - clampf(coverage, 0.0, 1.0)) * (16.0 / 24.0) * float(sup.get("uptime_unstaffed", 0.75))
	return staffed + night + rest


static func _sync_wear(record: Dictionary, bid: String, cond: float, abandoned: bool, t: int, cfg: Dictionary, events: Array) -> void:
	var vs := VisualEventRouter.visual_state_of(record, bid)
	var want := 0 if cond > 0.75 else (1 if cond > 0.5 else (2 if cond > 0.3 else 3))
	var changed := false
	while vs.wear < want:
		vs.apply_event("neglected", t)
		changed = true
	while vs.wear > want:
		vs.apply_event("maintained", t)
		changed = true
	if abandoned and cond < 0.15 and vs.overgrowth < 2:
		vs.apply_event("overgrown", t)
		changed = true
	if abandoned and cond <= 0.0 and vs.structure == "intact":
		vs.apply_event("damaged", t)
		vs.apply_event("damaged", t)
		changed = true
	if changed:
		var all: Dictionary = record.get("visual_states", {})
		all[bid] = vs.to_dict()
		record["visual_states"] = all
		events.append(_ev(t, "building_condition", "", {"building": bid, "wear": vs.wear, "structure": vs.structure}))


static func _npc(record: Dictionary, id: String) -> Dictionary:
	for r in record.get("npcs", []):
		if r.get("npc_id", "") == id:
			return r
	return {}


## General workers (Allgemeine Arbeitskräfte): flexible, assigned daily.
static func _pool(record: Dictionary) -> Array:
	var out := alive_npcs(record).filter(func(r): return r["employment"].get("status", "") == "pool")
	out.sort_custom(func(a, b): return str(a["npc_id"]) < str(b["npc_id"]))
	return out


static func _first_of_type(types: Dictionary, ty: String) -> String:
	var ids: Array = types.keys()
	ids.sort()
	for bid in ids:
		if types[bid] == ty:
			return bid
	return ""


static func _ev(t: int, kind: String, npc: String, data: Dictionary = {}) -> Dictionary:
	var e := {"t": t, "kind": kind}
	if npc != "":
		e["npc"] = npc
	for k in data:
		e[k] = data[k]
	return e


# --- capacities, attractiveness, newcomers ------------------------------------------

static func housing_capacity(record: Dictionary, data: SettlementData, cfg: Dictionary) -> Dictionary:
	var out := {}
	var dem: Dictionary = cfg.get("demography", {})
	for b in data.buildings:
		var ty: String = b.get("type", "")
		if ty == "house":
			out[b["id"]] = int(dem.get("housing_per_house", 4))
		elif ty == "player_home":
			out[b["id"]] = int(dem.get("housing_per_home", 2))
	return out


static func housing_free(record: Dictionary, data: SettlementData, cfg: Dictionary) -> int:
	var cap := housing_capacity(record, data, cfg)
	var used := {}
	for r in alive_npcs(record):
		used[r.get("home_id", "")] = int(used.get(r.get("home_id", ""), 0)) + 1
	var free := 0
	for h in cap:
		free += maxi(0, int(cap[h]) - int(used.get(h, 0)))
	return free


static func attractiveness(record: Dictionary, cfg: Dictionary) -> float:
	var st: Dictionary = record.get("core", {}).get("stats", {})
	var a := 0.6
	for k in ["food", "water", "energy"]:
		if bool(st.get(k + "_short", false)):
			a -= 0.25
		elif float(st.get(k + "_prod", 1.0)) < float(st.get(k + "_cons", 0.0)):
			a -= 0.15   # production below consumption: stocks are shrinking
	var cov: Dictionary = record.get("core", {}).get("coverage", {})
	a += 0.15 * float(cov.get("medizin", 0.0)) + 0.1 * float(cov.get("notfall", 0.0)) + 0.1 * float(cov.get("handel", 0.0))
	return clampf(a, 0.0, 1.0)


## Open position with the highest priority for a person (administration).
static func _vacancy(record: Dictionary, data: SettlementData, cfg: Dictionary, r: Dictionary) -> String:
	var models: Dictionary = cfg.get("operating_models", {})
	var types := building_types(record, data)
	var prio: Array = record.get("core", {}).get("policy", {}).get("priorities", FUNCTIONS)
	for fn in prio:
		var bids: Array = types.keys()
		bids.sort()
		for bid in bids:
			var m: Dictionary = models.get(types[bid], {})
			if str(m.get("function", "")) != fn or bid == str(r.get("employment", {}).get("dismissed_from", "")):
				continue
			if staff_of(record, bid).size() < target_staff(m):
				return bid
	return ""


## Staff a business needs to run its operating model with rotation.
static func target_staff(m: Dictionary) -> int:
	var per_day := 0
	var seven := false
	for s in m.get("shifts", []):
		per_day += int(s.get("staff", 1))
		if s.get("days", []).size() == 7:
			seven = true
	return per_day + (1 if seven else 0)


## A new settler arrives (Phase 4 "Bevölkerungsentwicklung"): adult, own
## identity, a home with free space and – via the administration – a job.
static func new_settler(record: Dictionary, data: SettlementData, cfg: Dictionary, day: int) -> Dictionary:
	var sid: String = record.get("settlement_id", "")
	var n: int = record.get("npcs", []).size()
	var rng := _rng("%s#settler#%d#%d" % [sid, day, n])
	var cap := housing_capacity(record, data, cfg)
	var used := {}
	for r in alive_npcs(record):
		used[r.get("home_id", "")] = int(used.get(r.get("home_id", ""), 0)) + 1
	var home := ""
	var homes: Array = cap.keys()
	homes.sort()
	for h in homes:
		if int(used.get(h, 0)) < int(cap[h]):
			home = h
			break
	var probe := {"employment": {}}
	var job := _vacancy(record, data, cfg, probe)
	var role := "worker"
	var models: Dictionary = cfg.get("operating_models", {})
	var types := building_types(record, data)
	if job != "":
		role = role_for_function(str(models.get(types.get(job, ""), {}).get("function", "")))
	var rec := NpcRoster.make_identity(sid, n, role, job, home, rng)
	var ar: Array = cfg.get("demography", {}).get("arrival_age", [18, 45])
	NpcBrain.ensure_profile(rec, cfg, 0)
	rec["alive"] = true
	rec["arrived_day"] = day
	rec["age_at_arrival"] = float(rng.randi_range(int(ar[0]), int(ar[1])))
	rec["health"] = {"status": "healthy", "until_day": 0}
	rec["employment"] = {"workplace_id": job, "status": "employed" if job != "" else "pool", "warnings": [], "since_day": day}
	record["npcs"].append(rec)
	record["core"]["counters"]["arrivals"] = int(record["core"]["counters"].get("arrivals", 0)) + 1
	return rec


static func role_for_function(fn: String) -> String:
	return {"verwaltung": "admin", "wasser": "utility", "energie": "utility", "lebensmittel": "farmer", "medizin": "medic",
		"notfall": "rescue", "bau": "builder", "handwerk": "craftsman", "handel": "merchant", "laden": "merchant"}.get(fn, "worker")
