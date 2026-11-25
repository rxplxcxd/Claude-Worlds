class_name SocialCore
extends RefCounted
## SOCIAL LIFE (Phase 5, docs/SOCIAL_SYSTEM.md) – relationships, families,
## friendships, conversations, social groups, memories and personal goals.
##
## Pure static functions on the settlement record, run once per settlement
## day inside SettlementCore.day_step – in EVERY simulation tier with the
## same result (hot, warm, cold catch-up). Randomness only via seeds.
##
## Data (all JSON-safe, persisted with the settlement):
##   record.social = {version, edges: {"a|b": Edge}, groups: {gid: Group}, counters}
##   Edge  = {a, b, kind, affinity -1..1, trust 0..1, familiarity 0..1,
##            colleague, family, since_day, last_day, meetings}
##   kind  = acquaintance | friend | close_friend | partner | rival | family
##   npc.social = {interests[], goals[], memories[], partner_id, parents[],
##                 children[], groups[], talks{day,count}}
## Players take part with the id "player:<uid>" (edges, memories on the NPC side).
##
## Rules that protect players (Master §13.1/§13.7): relationships with a
## player fade only very slowly when they are away; a child never comes to
## harm because a player is offline – children are cared for by the
## household and are excluded from mortality.

const VERSION := 1
const MAX_EDGES_PER_PERSON := 30
const MAX_MEMORIES := 16
const ADULT_AGE := 18.0

const INTERESTS := {
	"garden": {"label": "Gärtnern", "group": "Gartenfreunde", "place": "park"},
	"music": {"label": "Musik", "group": "Chor", "place": "plaza"},
	"sport": {"label": "Sport", "group": "Sportgruppe", "place": "park"},
	"reading": {"label": "Lesen", "group": "Lesekreis", "place": "plaza"},
	"craft": {"label": "Handwerk", "group": "Werkstattrunde", "place": "plaza"},
	"cooking": {"label": "Kochen", "group": "Kochrunde", "place": "plaza"},
	"games": {"label": "Spiele", "group": "Spieleabend", "place": "plaza"},
	"nature": {"label": "Natur", "group": "Wandergruppe", "place": "park"},
	"history": {"label": "Geschichte", "group": "Geschichtsverein", "place": "plaza"},
	"politics": {"label": "Politik", "group": "Bürgerrunde", "place": "plaza"},
}

const GOALS := {
	"friends": "Neue Freundschaften schließen",
	"partner": "Eine Partnerschaft finden",
	"family": "Eine Familie gründen",
	"career": "Im Beruf vorankommen",
	"community": "Sich in einem Verein engagieren",
	"helper": "Anderen helfen",
	"calm": "Ein ruhiges, gesundes Leben führen",
}

const KIND_LABEL := {"acquaintance": "Bekannt", "friend": "Befreundet", "close_friend": "Eng befreundet",
	"partner": "Partner:in", "rival": "Rivalität", "family": "Familie"}

const STAGES := [[1.0, "Säugling"], [3.0, "Kleinkind"], [6.0, "Kindergartenkind"], [12.0, "Schulkind"], [18.0, "Jugendliche:r"]]


# --- access helpers ------------------------------------------------------------------------

static func edge_key(a: String, b: String) -> String:
	return (a + "|" + b) if a < b else (b + "|" + a)


static func state(record: Dictionary) -> Dictionary:
	if not record.has("social") or int(record["social"].get("version", 0)) != VERSION:
		var old: Dictionary = record.get("social", {})
		record["social"] = {"version": VERSION, "edges": old.get("edges", {}), "groups": old.get("groups", {}),
			"counters": old.get("counters", {"friendships": 0, "partnerships": 0, "births": 0, "groups": 0, "conflicts": 0})}
	return record["social"]


static func edge(record: Dictionary, a: String, b: String) -> Dictionary:
	return state(record)["edges"].get(edge_key(a, b), {})


static func person(r: Dictionary) -> Dictionary:
	if not r.has("social"):
		r["social"] = {}
	var s: Dictionary = r["social"]
	for k in ["interests", "goals", "memories", "parents", "children", "groups"]:
		if not s.has(k):
			s[k] = []
	if not s.has("partner_id"):
		s["partner_id"] = ""
	return s


static func is_child(r: Dictionary, day: int, cfg: Dictionary) -> bool:
	return SettlementCore.age_years(r, day, cfg) < ADULT_AGE


static func life_stage(r: Dictionary, day: int, cfg: Dictionary) -> String:
	var age := SettlementCore.age_years(r, day, cfg)
	for st in STAGES:
		if age < float(st[0]):
			return str(st[1])
	return "erwachsen"


## Ensures interests and goals for a person (deterministic by id).
static func ensure_person(r: Dictionary, day: int, cfg: Dictionary) -> void:
	var s := person(r)
	var id := str(r.get("npc_id", ""))
	if (s["interests"] as Array).is_empty():
		var keys: Array = INTERESTS.keys()
		keys.sort()
		var rng := SettlementCore._rng(id + "#interests")
		var n := 1 + (1 if rng.randf() < 0.6 else 0) + (1 if rng.randf() < 0.2 else 0)
		var pool := keys.duplicate()
		for i in n:
			s["interests"].append(pool.pop_at(rng.randi() % pool.size()))
	if (s["goals"] as Array).is_empty() and not is_child(r, day, cfg):
		_pick_goal(r, day, cfg, "")


static func _pick_goal(r: Dictionary, day: int, cfg: Dictionary, avoid: String) -> void:
	var s := person(r)
	var id := str(r.get("npc_id", ""))
	var age := SettlementCore.age_years(r, day, cfg)
	var w := {
		"friends": 0.6 + SettlementCore.trait_of(r, "extraversion"),
		"partner": (1.2 if age < 45.0 and str(s.get("partner_id", "")) == "" else 0.0),
		"family": (1.0 if age >= 22.0 and age < 42.0 and str(s.get("partner_id", "")) != "" and (s["children"] as Array).size() < 3 else 0.0),
		"career": 0.3 + SettlementCore.trait_of(r, "ambition") * 1.2 if r.get("employment", {}).get("status", "") == "employed" else 0.0,
		"community": 0.3 + SettlementCore.trait_of(r, "sociability"),
		"helper": 0.2 + SettlementCore.trait_of(r, "reliability") * 0.6,
		"calm": 0.2 + (0.8 if age > 55.0 else 0.0),
	}
	for g in s["goals"]:
		w[g["kind"]] = 0.0
	if avoid != "":
		w[avoid] = 0.0
	var total := 0.0
	for k in w:
		total += maxf(0.0, float(w[k]))
	if total <= 0.0:
		return
	var x := SettlementCore._chance("%s#goal#%d" % [id, day]) * total
	var keys: Array = w.keys()
	keys.sort()
	for k in keys:
		x -= maxf(0.0, float(w[k]))
		if x <= 0.0:
			s["goals"].append({"kind": k, "since_day": day, "progress": 0.0})
			return


## Adds a memory (important events only); keeps the most significant ones.
static func remember(r: Dictionary, day: int, kind: String, with: String, text: String, weight: float) -> void:
	var s := person(r)
	var mem: Array = s["memories"]
	mem.append({"day": day, "kind": kind, "with": with, "text": text, "weight": snappedf(weight, 0.01)})
	if mem.size() > MAX_MEMORIES:
		# significance fades with age; promises and family events stay longer
		mem.sort_custom(func(a, b): return _salience(a, day) > _salience(b, day))
		mem.resize(MAX_MEMORIES)
		mem.sort_custom(func(a, b): return int(a["day"]) < int(b["day"]))
	s["memories"] = mem


static func _salience(m: Dictionary, day: int) -> float:
	var keep := 3.0 if m["kind"] in ["birth", "partnership", "death", "promise_kept", "child_born"] else 1.0
	return float(m["weight"]) * keep / (1.0 + float(day - int(m["day"])) / 120.0)


# --- compatibility and encounters ----------------------------------------------------------

static func compatibility(ra: Dictionary, rb: Dictionary) -> float:
	var shared := 0
	for i in person(ra)["interests"]:
		if person(rb)["interests"].has(i):
			shared += 1
	var c := 0.2
	c -= absf(SettlementCore.trait_of(ra, "extraversion") - SettlementCore.trait_of(rb, "extraversion")) * 0.35
	c -= absf(SettlementCore.trait_of(ra, "conscientiousness") - SettlementCore.trait_of(rb, "conscientiousness")) * 0.25
	c += 0.18 * shared
	c += (SettlementCore.trait_of(ra, "sociability") + SettlementCore.trait_of(rb, "sociability") - 1.0) * 0.2
	return clampf(c, -0.6, 0.9)


## One encounter between two people: familiarity grows, affinity moves with
## compatibility (and chance); rare quarrels between impulsive people.
static func encounter(record: Dictionary, ra: Dictionary, rb: Dictionary, day: int, context: String, strength: float, events: Array, t: int) -> void:
	var a := str(ra["npc_id"])
	var b := str(rb["npc_id"])
	if a == b:
		return
	var st := state(record)
	var key := edge_key(a, b)
	var e: Dictionary = st["edges"].get(key, {})
	if e.is_empty():
		e = {"a": key.get_slice("|", 0), "b": key.get_slice("|", 1), "kind": "acquaintance", "affinity": 0.0, "trust": 0.2,
			"familiarity": 0.0, "colleague": false, "family": false, "since_day": day, "last_day": day, "meetings": 0}
		st["edges"][key] = e
	if int(e.get("last_day", -1)) == day and int(e.get("meetings", 0)) > 0 and context != "household":
		strength *= 0.4                               # several encounters a day count less
	var seed_text := "%s#enc#%s#%d#%s" % [record.get("settlement_id", ""), key, day, context]
	var noise := SettlementCore._chance(seed_text) - 0.5
	var comp: float = _compat.get(key, INF)
	if comp == INF:
		comp = compatibility(ra, rb)
		_compat[key] = comp
	e["familiarity"] = snappedf(minf(1.0, float(e["familiarity"]) + 0.03 * strength), 0.001)
	var quarrel_p := 0.003 * strength * (SettlementCore.trait_of(ra, "impulsivity") + SettlementCore.trait_of(rb, "impulsivity"))
	if SettlementCore._chance(seed_text + "#q") < quarrel_p and not e["kind"] in ["partner", "family"]:
		e["affinity"] = snappedf(clampf(float(e["affinity"]) - 0.18, -1.0, 1.0), 0.001)
		e["trust"] = snappedf(clampf(float(e["trust"]) - 0.08, 0.0, 1.0), 0.001)
		st["counters"]["conflicts"] = int(st["counters"].get("conflicts", 0)) + 1
		for pair in [[ra, b], [rb, a]]:
			remember(pair[0], day, "conflict", pair[1], "Streit", 0.5)
		events.append(SettlementCore._ev(t, "social_conflict", a, {"with": b}))
	else:
		# affinity tends to an equilibrium given by compatibility (≈ 1.5 × comp):
		# compatible people become friends, most stay acquaintances
		var aff0 := float(e["affinity"])
		var drift := comp * 0.03 + noise * 0.03 - 0.015 * aff0
		if e["kind"] in ["partner", "family"]:
			drift = maxf(drift, 0.004)                # close bonds are kept up
		e["affinity"] = snappedf(clampf(aff0 + drift * strength, -1.0, 1.0), 0.001)
		e["trust"] = snappedf(clampf(float(e["trust"]) + 0.015 * strength * (0.5 + comp), 0.0, 1.0), 0.001)
	if context == "work":
		e["colleague"] = true
	e["last_day"] = day
	e["meetings"] = int(e.get("meetings", 0)) + 1
	_update_kind(record, e, ra, rb, day, events, t)


static func _update_kind(record: Dictionary, e: Dictionary, ra: Dictionary, rb: Dictionary, day: int, events: Array, t: int) -> void:
	var old := str(e["kind"])
	if old in ["partner", "family"]:
		return
	var aff := float(e["affinity"])
	var fam := float(e["familiarity"])
	var k := "acquaintance"
	if aff <= -0.35:
		k = "rival"
	elif aff >= 0.62 and fam >= 0.65:
		k = "close_friend"
	elif aff >= 0.42 and fam >= 0.35:
		k = "friend"
	elif old in ["friend", "close_friend"] and aff >= 0.3:
		k = old                                        # friendships are sticky (hysteresis)
	if k == old:
		return
	e["kind"] = k
	var a := str(ra["npc_id"])
	var b := str(rb["npc_id"])
	var st := state(record)
	if k == "friend" and old == "acquaintance":
		st["counters"]["friendships"] = int(st["counters"].get("friendships", 0)) + 1
		remember(ra, day, "friendship", b, "Freundschaft mit %s" % _first(rb), 0.7)
		remember(rb, day, "friendship", a, "Freundschaft mit %s" % _first(ra), 0.7)
		events.append(SettlementCore._ev(t, "friendship", a, {"with": b}))
	elif k == "close_friend":
		remember(ra, day, "close_friendship", b, "Enge Freundschaft mit %s" % _first(rb), 0.8)
		remember(rb, day, "close_friendship", a, "Enge Freundschaft mit %s" % _first(ra), 0.8)
	elif k == "rival":
		remember(ra, day, "rivalry", b, "Zerstritten mit %s" % _first(rb), 0.6)
		remember(rb, day, "rivalry", a, "Zerstritten mit %s" % _first(ra), 0.6)
		events.append(SettlementCore._ev(t, "rivalry", a, {"with": b}))


static func _first(r: Dictionary) -> String:
	return str(r.get("name", "")).get_slice(" ", 0)


# --- the day step ------------------------------------------------------------------------------

## Social life of one settlement day. Called by SettlementCore.day_step
## after the demography step (deaths are known), before the lifecycle.
static func day_step(record: Dictionary, data: SettlementData, cfg: Dictionary, day: int, t: int, events: Array) -> void:
	var sc: Dictionary = cfg.get("social", {})
	if not bool(sc.get("enabled", true)):
		return
	var st := state(record)
	var sid := str(record.get("settlement_id", ""))
	var people: Array = SettlementCore.alive_npcs(record)
	if people.is_empty():
		return
	var by_id := {}
	for r in people:
		ensure_person(r, day, cfg)
		by_id[str(r["npc_id"])] = r
	_by_id = by_id
	_cfg = cfg
	var wd := posmod(day + 4, 7)
	var workday := wd >= 1 and wd <= 5
	_build_day_cache(record)
	# 1. households (family members, flat mates) meet every day
	var homes := {}
	for r in people:
		var h := str(r.get("home_id", ""))
		if h != "":
			if not homes.has(h):
				homes[h] = []
			homes[h].append(r)
	for h in _sorted_keys(homes):
		var hs: Array = homes[h]
		if hs.size() <= 6:
			for i in hs.size():
				for j in range(i + 1, hs.size()):
					encounter(record, hs[i], hs[j], day, "household", 0.6, events, t)
		else:
			# a large house (dormitory, shared flats): a few house mates a day
			for i in hs.size():
				for k in 2:
					var j := int(SettlementCore._chance("%s#hm#%s#%d#%d" % [sid, hs[i]["npc_id"], day, k]) * hs.size()) % hs.size()
					if j != i:
						encounter(record, hs[i], hs[j], day, "household", 0.6, events, t)
	# 2. colleagues on working days
	if workday:
		var work := {}
		for r in people:
			if r.get("employment", {}).get("status", "") == "employed" and r["health"]["status"] == "healthy":
				var w := str(r["employment"].get("workplace_id", ""))
				if not work.has(w):
					work[w] = []
				work[w].append(r)
		for w in _sorted_keys(work):
			var ws: Array = work[w]
			if ws.size() <= 5:
				for i in ws.size():
					for j in range(i + 1, ws.size()):
						if SettlementCore._chance("%s#col#%s#%s#%d" % [sid, ws[i]["npc_id"], ws[j]["npc_id"], day]) < 0.7:
							encounter(record, ws[i], ws[j], day, "work", 0.8, events, t)
			else:
				# large teams: everybody works closely with a few colleagues a day (linear, not quadratic)
				for i in ws.size():
					for k in 3:
						var j := int(SettlementCore._chance("%s#colp#%s#%d#%d" % [sid, ws[i]["npc_id"], day, k]) * ws.size()) % ws.size()
						if j != i:
							encounter(record, ws[i], ws[j], day, "work", 0.8, events, t)
	# 3. leisure: people meet at plaza and park (more for sociable people and
	#    for those whose goal is new friendships); they prefer their friends
	var adults: Array = people.filter(func(r): return not is_child(r, day, cfg))
	for r in people:
		var id := str(r["npc_id"])
		var soc := SettlementCore.trait_of(r, "extraversion") * 0.6 + SettlementCore.trait_of(r, "sociability") * 0.4
		if _has_goal(r, "friends"):
			soc += 0.25
		var n := int(floor(soc * 2.2 + SettlementCore._chance("%s#out#%s#%d" % [sid, id, day])))
		var pool: Array = adults if not is_child(r, day, cfg) else people.filter(func(x): return is_child(x, day, cfg))
		if pool.size() < 2:
			continue
		for k in n:
			var other: Dictionary = _pick_partner(record, r, pool, day, k)
			if not other.is_empty():
				encounter(record, r, other, day, "leisure", 0.5, events, t)
	# 4. social groups: weekly meetings, founding, joining
	_groups_step(record, people, by_id, day, cfg, sid, events, t)
	# 5. partnerships, moving in together, children
	_partners_step(record, data, people, by_id, day, cfg, sid, sc, events, t)
	# 6. the dead: memories of friends and family, edges become history
	for ev in events:
		if ev.get("kind", "") == "died":
			_mourn(record, str(ev.get("npc", "")), by_id, day)
	# 7. growing up: a young person becomes an adult (joins the labour pool)
	for r in people:
		var s := person(r)
		if r.get("employment", {}).get("status", "") == "child" and not is_child(r, day, cfg):
			r["employment"] = {"workplace_id": "", "status": "pool", "warnings": [], "since_day": day}
			r["role"] = "worker"
			remember(r, day, "grown_up", "", "Erwachsen geworden", 0.6)
			events.append(SettlementCore._ev(t, "grown_up", str(r["npc_id"])))
			_pick_goal(r, day, cfg, "")
	# 8. personal goals: progress and fulfilment
	for r in people:
		_goals_step(record, r, day, cfg, events, t)
	# 9. slow fading of contacts nobody keeps up (never abrupt; players are
	#    away without penalty – their edges fade at a third of the rate)
	if posmod(day, 7) == 0:
		var keys: Array = st["edges"].keys()
		keys.sort()
		for key in keys:
			var e: Dictionary = st["edges"][key]
			var idle := day - int(e.get("last_day", day))
			if idle < 21 or e["kind"] in ["partner", "family"]:
				continue
			var rate := 0.01 if not (str(key).contains("player:")) else 0.003
			e["familiarity"] = snappedf(maxf(0.0, float(e["familiarity"]) - rate), 0.001)
			if float(e["familiarity"]) <= 0.0 and e["kind"] == "acquaintance" and not str(key).contains("player:"):
				st["edges"].erase(key)
	if posmod(day, 7) == 0:
		_prune(record, people)


static func _sorted_keys(d: Dictionary) -> Array:
	var k: Array = d.keys()
	k.sort()
	return k


static func _has_goal(r: Dictionary, kind: String) -> bool:
	for g in person(r)["goals"]:
		if g["kind"] == kind and not g.has("done_day"):
			return true
	return false


## Per-day cache: liked people per person (affinity ≥ 0.2) and friend counts –
## built once per day from the edge list instead of scanning it per person.
static var _liked: Dictionary = {}
static var _by_id: Dictionary = {}            # alive people of the settlement today
static var _cfg: Dictionary = {}
static var _compat: Dictionary = {}           # pair -> compatibility (traits and interests do not change)
static var _friends: Dictionary = {}


static func _build_day_cache(record: Dictionary) -> void:
	_liked = {}
	_friends = {}
	var edges: Dictionary = state(record)["edges"]
	for key in _sorted_keys(edges):              # sorted: identical after save → load (key order may differ)
		var e: Dictionary = edges[key]
		var aff := float(e["affinity"])
		for pair in [[e["a"], e["b"]], [e["b"], e["a"]]]:
			if aff >= 0.2:
				if not _liked.has(pair[0]):
					_liked[pair[0]] = []
				_liked[pair[0]].append([pair[1], aff])
			if e["kind"] in ["friend", "close_friend"]:
				_friends[pair[0]] = int(_friends.get(pair[0], 0)) + 1


## Somebody to meet: friends first (by affinity), else anybody (seeded).
static func _pick_partner(record: Dictionary, r: Dictionary, pool: Array, day: int, k: int) -> Dictionary:
	var id := str(r["npc_id"])
	var sid := str(record.get("settlement_id", ""))
	var x := SettlementCore._chance("%s#pick#%s#%d#%d" % [sid, id, day, k])
	if x < 0.55 and _liked.has(id):
		var opts: Array = _liked[id]
		var j := int(SettlementCore._chance("%s#fv#%s#%d#%d" % [sid, id, day, k]) * opts.size()) % opts.size()
		# prefer the best liked of two random picks
		var j2 := (j + 1 + int(x * 7.0)) % opts.size()
		var pick: Array = opts[j] if float(opts[j][1]) >= float(opts[j2][1]) else opts[j2]
		var o: Dictionary = _by_id.get(str(pick[0]), {})
		if not o.is_empty() and is_child(o, day, _cfg) == is_child(r, day, _cfg):
			return o
	var o2: Dictionary = pool[int(x * 1000003.0) % pool.size()]
	return {} if o2["npc_id"] == id else o2


static func _groups_step(record: Dictionary, people: Array, by_id: Dictionary, day: int, cfg: Dictionary, sid: String, events: Array, t: int) -> void:
	var st := state(record)
	var groups: Dictionary = st["groups"]
	var wd := posmod(day + 4, 7)
	# meetings
	for gid in _sorted_keys(groups):
		var g: Dictionary = groups[gid]
		if int(g["weekday"]) != wd:
			continue
		var present: Array = []
		for m in g["members"]:
			if by_id.has(m) and by_id[m]["health"]["status"] == "healthy":
				present.append(by_id[m])
		for i in present.size():
			for j in range(i + 1, present.size()):
				encounter(record, present[i], present[j], day, "group", 0.7, events, t)
		g["last_meeting"] = day
		g["meetings"] = int(g.get("meetings", 0)) + 1
	# founding and joining (weekly)
	if posmod(day, 7) != 3:
		return
	var adults: Array = people.filter(func(r): return not is_child(r, day, cfg))
	for interest in _sorted_keys(INTERESTS):
		var gid := ""
		for k in groups:
			if groups[k]["interest"] == interest:
				gid = k
		var fans: Array = adults.filter(func(r): return person(r)["interests"].has(interest))
		if gid == "":
			if fans.size() < 4 or groups.size() >= maxi(1, adults.size() / 8):
				continue
			fans.sort_custom(func(a, b): return _founder_score(a) > _founder_score(b))
			var founder: Dictionary = fans[0]
			if _founder_score(founder) < 0.62 and not _has_goal(founder, "community"):
				continue
			gid = "grp_%s_%s" % [sid.trim_prefix("stl_"), interest]
			var info: Dictionary = INTERESTS[interest]
			groups[gid] = {"id": gid, "interest": interest, "name": str(info["group"]), "founder": founder["npc_id"], "founded_day": day,
				"members": [founder["npc_id"]], "weekday": SettlementCore._rng(gid).randi_range(0, 6), "hour": 18 + SettlementCore._rng(gid + "h").randi_range(0, 1),
				"place": str(info["place"]), "meetings": 0}
			st["counters"]["groups"] = int(st["counters"].get("groups", 0)) + 1
			person(founder)["groups"].append(gid)
			remember(founder, day, "group_founded", gid, "%s gegründet" % info["group"], 0.8)
			events.append(SettlementCore._ev(t, "group_founded", str(founder["npc_id"]), {"group": gid}))
		var g2: Dictionary = groups[gid]
		for r in fans:
			var id := str(r["npc_id"])
			if g2["members"].has(id):
				continue
			var ties := 0.0
			for m in g2["members"]:
				var e := edge(record, id, str(m))
				if not e.is_empty():
					ties += maxf(0.0, float(e["affinity"]))
			var p := 0.04 + SettlementCore.trait_of(r, "sociability") * 0.1 + ties * 0.15 + (0.25 if _has_goal(r, "community") else 0.0)
			if SettlementCore._chance("%s#join#%s#%s#%d" % [sid, gid, id, day]) < p:
				g2["members"].append(id)
				person(r)["groups"].append(gid)
				remember(r, day, "group_joined", gid, "Mitglied: %s" % g2["name"], 0.5)
				events.append(SettlementCore._ev(t, "group_joined", id, {"group": gid}))
	# members who died or left are removed
	for gid in groups.keys():
		var g3: Dictionary = groups[gid]
		g3["members"] = g3["members"].filter(func(m): return by_id.has(m) or str(m).begins_with("player:"))
		if (g3["members"] as Array).is_empty():
			groups.erase(gid)
	_refresh_meetings(record, people)


## Copies each member's meeting times onto the person (read by the daily routine).
static func _refresh_meetings(record: Dictionary, people: Array) -> void:
	var groups: Dictionary = state(record)["groups"]
	for r in people:
		var s := person(r)
		var ms: Array = []
		for gid in s["groups"]:
			if groups.has(gid):
				var g: Dictionary = groups[gid]
				ms.append([int(g["weekday"]), float(g["hour"]), str(g["place"])])
		s["groups"] = (s["groups"] as Array).filter(func(gid): return groups.has(gid))
		s["meetings"] = ms


static func _founder_score(r: Dictionary) -> float:
	return SettlementCore.trait_of(r, "sociability") * 0.5 + SettlementCore.trait_of(r, "confidence") * 0.3 + SettlementCore.trait_of(r, "extraversion") * 0.2


static func _partners_step(record: Dictionary, data: SettlementData, people: Array, by_id: Dictionary, day: int, cfg: Dictionary, sid: String, sc: Dictionary, events: Array, t: int) -> void:
	var st := state(record)
	var edges: Dictionary = st["edges"]
	# new partnerships: close bond, both adult and single
	for key in _sorted_keys(edges):
		var e: Dictionary = edges[key]
		if not e["kind"] in ["friend", "close_friend"] or str(key).contains("player:"):
			continue
		var ra: Dictionary = by_id.get(e["a"], {})
		var rb: Dictionary = by_id.get(e["b"], {})
		if ra.is_empty() or rb.is_empty() or is_child(ra, day, cfg) or is_child(rb, day, cfg) or e.get("family", false):
			continue
		if str(person(ra)["partner_id"]) != "" or str(person(rb)["partner_id"]) != "":
			continue
		if float(e["affinity"]) < 0.45 or float(e["familiarity"]) < 0.5:
			continue
		# attraction is personal: not every good friendship becomes a partnership
		if SettlementCore._chance("%s#spark#%s" % [sid, key]) < 0.55:
			continue
		if absf(SettlementCore.age_years(ra, day, cfg) - SettlementCore.age_years(rb, day, cfg)) > 15.0:
			continue
		var p := float(sc.get("partnership_per_day", 0.02)) * (1.6 if _has_goal(ra, "partner") or _has_goal(rb, "partner") else 1.0)
		if SettlementCore._chance("%s#love#%s#%d" % [sid, key, day]) >= p:
			continue
		e["kind"] = "partner"
		person(ra)["partner_id"] = rb["npc_id"]
		person(rb)["partner_id"] = ra["npc_id"]
		st["counters"]["partnerships"] = int(st["counters"].get("partnerships", 0)) + 1
		remember(ra, day, "partnership", rb["npc_id"], "Partnerschaft mit %s" % _first(rb), 1.0)
		remember(rb, day, "partnership", ra["npc_id"], "Partnerschaft mit %s" % _first(ra), 1.0)
		events.append(SettlementCore._ev(t, "partnership", str(ra["npc_id"]), {"with": rb["npc_id"]}))
		_move_in_together(record, data, cfg, ra, rb, day, events, t)
	# children: couples who live together and want a family
	var cap := SettlementCore.housing_capacity(record, data, cfg)
	var food_days := float(record.get("core", {}).get("stocks", {}).get("food", 0.0)) / maxf(1.0, float(people.size()))
	for r in people:
		var pid := str(person(r)["partner_id"])
		if pid == "" or str(r["npc_id"]) > pid or not by_id.has(pid):
			continue                                   # each couple once
		var q: Dictionary = by_id[pid]
		if str(r.get("home_id", "")) == "" or r.get("home_id", "") != q.get("home_id", ""):
			continue
		var a1 := SettlementCore.age_years(r, day, cfg)
		var a2 := SettlementCore.age_years(q, day, cfg)
		if a1 < 20.0 or a2 < 20.0 or a1 > 44.0 or a2 > 44.0 or (person(r)["children"] as Array).size() >= 3:
			continue
		var home := str(r["home_id"])
		var load := 0.0
		for x in people:
			if x.get("home_id", "") == home:
				load += 0.5 if is_child(x, day, cfg) else 1.0
		if load + 0.5 > float(cap.get(home, 0)) + 1.0 or food_days < 5.0:
			continue                                   # no room (children count half) / supply first
		var wants := _has_goal(r, "family") or _has_goal(q, "family")
		var p2 := float(sc.get("birth_per_day_wanting", 0.012)) if wants else float(sc.get("birth_per_day", 0.002))
		if not (person(r)["children"] as Array).is_empty():
			var last_child: Dictionary = by_id.get(person(r)["children"][-1], {})
			if not last_child.is_empty() and SettlementCore.age_years(last_child, day, cfg) < 2.0:
				continue
		if SettlementCore._chance("%s#birth#%s#%s#%d" % [sid, r["npc_id"], pid, day]) < p2:
			var child := _new_child(record, cfg, r, q, day)
			by_id[child["npc_id"]] = child
			events.append(SettlementCore._ev(t, "born", str(child["npc_id"]), {"parents": [r["npc_id"], pid]}))


static func _move_in_together(record: Dictionary, data: SettlementData, cfg: Dictionary, ra: Dictionary, rb: Dictionary, day: int, events: Array, t: int) -> void:
	var ha := str(ra.get("home_id", ""))
	var hb := str(rb.get("home_id", ""))
	if ha == hb and ha != "":
		return
	var cap := SettlementCore.housing_capacity(record, data, cfg)
	var used := {}
	for r in SettlementCore.alive_npcs(record):
		used[str(r.get("home_id", ""))] = int(used.get(str(r.get("home_id", "")), 0)) + 1
	# the one whose home has room takes the other in (children move with)
	for pair in [[ra, rb, ha], [rb, ra, hb]]:
		var home: String = pair[2]
		var mover: Dictionary = pair[1]
		var moving := 1 + (person(mover)["children"] as Array).size()
		if home != "" and int(used.get(home, 0)) + moving <= int(cap.get(home, 0)):
			_relocate(record, mover, home)
			events.append(SettlementCore._ev(t, "moved_in", str(mover["npc_id"]), {"home": home, "with": pair[0]["npc_id"]}))
			return
	# both homes full: a flat mate (no family) swaps homes with the one moving in
	for pair in [[ra, rb, ha, hb], [rb, ra, hb, ha]]:
		var home2: String = pair[2]
		var old_home: String = pair[3]
		var mover2: Dictionary = pair[1]
		if home2 == "" or old_home == "" or not (person(mover2)["children"] as Array).is_empty():
			continue
		for x in SettlementCore.alive_npcs(record):
			if x.get("home_id", "") != home2 or x["npc_id"] == pair[0]["npc_id"]:
				continue
			if str(person(x)["partner_id"]) != "" or not (person(x)["children"] as Array).is_empty() or not (person(x)["parents"] as Array).is_empty():
				continue
			x["home_id"] = old_home
			_relocate(record, mover2, home2)
			events.append(SettlementCore._ev(t, "moved_in", str(mover2["npc_id"]), {"home": home2, "with": pair[0]["npc_id"], "swapped_with": x["npc_id"]}))
			return


static func _relocate(record: Dictionary, mover: Dictionary, home: String) -> void:
	mover["home_id"] = home
	for cid in person(mover)["children"]:
		var c := SettlementCore._npc(record, cid)
		if not c.is_empty() and c.get("alive", true):
			c["home_id"] = home


static func _new_child(record: Dictionary, cfg: Dictionary, pa: Dictionary, pb: Dictionary, day: int) -> Dictionary:
	var sid := str(record.get("settlement_id", ""))
	var n: int = record.get("npcs", []).size()
	var rng := SettlementCore._rng("%s#child#%d#%d" % [sid, day, n])
	var rec := NpcRoster.make_identity(sid, n, "child", "", str(pa.get("home_id", "")), rng)
	rec["name"] = "%s %s" % [str(rec["name"]).get_slice(" ", 0), str(pa.get("name", "")).get_slice(" ", 1)]
	NpcBrain.ensure_profile(rec, cfg, 0)
	# personality: between the parents, with its own character
	for tr in NpcBrain.TRAITS:
		var mid := (SettlementCore.trait_of(pa, tr) + SettlementCore.trait_of(pb, tr)) * 0.5
		rec["personality"][tr] = snappedf(clampf(mid * 0.5 + float(rec["personality"][tr]) * 0.5, 0.03, 0.97), 0.01)
	rec["alive"] = true
	rec["arrived_day"] = day
	rec["age_at_arrival"] = 0.0
	rec["born_day"] = day
	rec["health"] = {"status": "healthy", "until_day": 0}
	rec["employment"] = {"workplace_id": "", "status": "child", "warnings": [], "since_day": day}
	var s := person(rec)
	s["parents"] = [pa["npc_id"], pb["npc_id"]]
	record["npcs"].append(rec)
	ensure_person(rec, day, cfg)
	for p in [pa, pb]:
		person(p)["children"].append(rec["npc_id"])
		remember(p, day, "child_born", rec["npc_id"], "Geburt von %s" % _first(rec), 1.0)
		var e := _family_edge(record, p, rec, day)
		e["affinity"] = 0.8
	state(record)["counters"]["births"] = int(state(record)["counters"].get("births", 0)) + 1
	# siblings
	for sib in person(pa)["children"]:
		if sib != rec["npc_id"]:
			var rs := SettlementCore._npc(record, sib)
			if not rs.is_empty() and rs.get("alive", true):
				_family_edge(record, rs, rec, day)
	return rec


static func _family_edge(record: Dictionary, ra: Dictionary, rb: Dictionary, day: int) -> Dictionary:
	var key := edge_key(str(ra["npc_id"]), str(rb["npc_id"]))
	var st := state(record)
	var e: Dictionary = st["edges"].get(key, {"a": key.get_slice("|", 0), "b": key.get_slice("|", 1), "affinity": 0.6, "trust": 0.7,
		"familiarity": 0.8, "colleague": false, "since_day": day, "last_day": day, "meetings": 0})
	e["kind"] = "family"
	e["family"] = true
	st["edges"][key] = e
	return e


static func _mourn(record: Dictionary, dead_id: String, by_id: Dictionary, day: int) -> void:
	var dead := SettlementCore._npc(record, dead_id)
	if dead.is_empty():
		return
	var st := state(record)
	for key in _sorted_keys(st["edges"]):
		if not (str(key).begins_with(dead_id + "|") or str(key).ends_with("|" + dead_id)):
			continue
		var e: Dictionary = st["edges"][key]
		var other := str(e["a"]) if str(e["b"]) == dead_id else str(e["b"])
		if by_id.has(other) and e["kind"] in ["friend", "close_friend", "partner", "family"]:
			remember(by_id[other], day, "death", dead_id, "Abschied von %s" % _first(dead), 1.0)
			if str(person(by_id[other])["partner_id"]) == dead_id:
				person(by_id[other])["partner_id"] = ""
		st["edges"].erase(key)
	for gid in person(dead)["groups"]:
		if st["groups"].has(gid):
			st["groups"][gid]["members"].erase(dead_id)


static func _goals_step(record: Dictionary, r: Dictionary, day: int, cfg: Dictionary, events: Array, t: int) -> void:
	var s := person(r)
	var id := str(r["npc_id"])
	for g in s["goals"]:
		if g.has("done_day"):
			continue
		var prog := 0.0
		match str(g["kind"]):
			"friends":
				prog = clampf(float(_friends.get(id, 0)) / 3.0, 0.0, 1.0)
			"partner":
				prog = 1.0 if str(s["partner_id"]) != "" else 0.0
			"family":
				prog = 1.0 if not (s["children"] as Array).is_empty() else 0.0
			"career":
				var pr: Dictionary = r.get("profession", {})
				var sk := maxf(float(pr.get("skill", 0.0)), float(pr.get("skill_now", 0.0)))
				prog = clampf(maxf(sk - float(g.get("skill_start", sk)), 0.0) / 0.1, 0.0, 1.0)
				if not g.has("skill_start"):
					g["skill_start"] = sk
			"community":
				prog = 1.0 if not (s["groups"] as Array).is_empty() else 0.0
			"helper":
				prog = clampf(float(s.get("helped", 0)) / 5.0, 0.0, 1.0)
			"calm":
				prog = clampf(float(day - int(g["since_day"])) / 60.0, 0.0, 1.0) if r["health"]["status"] == "healthy" else float(g["progress"])
		g["progress"] = snappedf(prog, 0.01)
		if prog >= 1.0:
			g["done_day"] = day
			remember(r, day, "goal_reached", g["kind"], "Ziel erreicht: %s" % GOALS.get(g["kind"], g["kind"]), 0.9)
			events.append(SettlementCore._ev(t, "goal_reached", id, {"goal": g["kind"]}))
	# a fulfilled goal makes room for a new one after a while
	var open: Array = s["goals"].filter(func(g): return not g.has("done_day"))
	if open.is_empty() and not is_child(r, day, cfg):
		var last := 0
		for g in s["goals"]:
			last = maxi(last, int(g.get("done_day", 0)))
		if day - last >= 14:
			_pick_goal(r, day, cfg, "")
	if (s["goals"] as Array).size() > 6:
		s["goals"] = s["goals"].slice(s["goals"].size() - 6)


## Keeps at most MAX_EDGES_PER_PERSON edges per person (weakest acquaintances go).
static func _prune(record: Dictionary, people: Array) -> void:
	var st := state(record)
	var count := {}
	for key in st["edges"]:
		for side in [st["edges"][key]["a"], st["edges"][key]["b"]]:
			count[side] = int(count.get(side, 0)) + 1
	for r in people:
		var id := str(r["npc_id"])
		if int(count.get(id, 0)) <= MAX_EDGES_PER_PERSON:
			continue
		var mine: Array = st["edges"].keys().filter(func(k): return (str(k).begins_with(id + "|") or str(k).ends_with("|" + id)) and st["edges"][k]["kind"] == "acquaintance")
		mine.sort()
		mine.sort_custom(func(a, b):
			var va := float(st["edges"][a]["familiarity"]) + float(st["edges"][a]["affinity"])
			var vb := float(st["edges"][b]["familiarity"]) + float(st["edges"][b]["affinity"])
			return va < vb or (va == vb and str(a) < str(b)))
		var excess := int(count[id]) - MAX_EDGES_PER_PERSON
		for k in mine.slice(0, excess):
			st["edges"].erase(k)


# --- queries -----------------------------------------------------------------------------------

static func relations_of(record: Dictionary, id: String) -> Array:
	var out: Array = []
	var edges: Dictionary = state(record)["edges"]
	for key in _sorted_keys(edges):
		var e: Dictionary = edges[key]
		if e["a"] == id or e["b"] == id:
			out.append({"other": e["b"] if e["a"] == id else e["a"], "edge": e})
	out.sort_custom(func(x, y): return _rank(x["edge"]) > _rank(y["edge"]) or (_rank(x["edge"]) == _rank(y["edge"]) and str(x["other"]) < str(y["other"])))
	return out


static func _rank(e: Dictionary) -> float:
	return {"partner": 5.0, "family": 4.0, "close_friend": 3.0, "friend": 2.0, "rival": 1.5, "acquaintance": 0.0}.get(e["kind"], 0.0) + float(e["affinity"])


static func count_kind(record: Dictionary, id: String, kinds: Array) -> int:
	return relations_of(record, id).filter(func(x): return x["edge"]["kind"] in kinds).size()


## Ties of everybody to a group of people in ONE pass over the edges
## (id -> sum of positive affinities to members of `group`, a Dictionary set).
static func ties_to(record: Dictionary, group: Dictionary) -> Dictionary:
	var out := {}
	if not record.has("social"):
		return out
	var edges: Dictionary = record["social"].get("edges", {})
	for key in edges:
		var e: Dictionary = edges[key]
		var aff := float(e["affinity"])
		if aff <= 0.0:
			continue
		if group.has(e["a"]) and not group.has(e["b"]):
			out[e["b"]] = float(out.get(e["b"], 0.0)) + aff
		elif group.has(e["b"]) and not group.has(e["a"]):
			out[e["a"]] = float(out.get(e["a"], 0.0)) + aff
	return out


## Social tie of a person to a set of people (sum of positive affinities):
## used where relationships influence decisions (substitutions, hiring).
static func tie(record: Dictionary, id: String, others: Array) -> float:
	var s := 0.0
	for o in others:
		var e := edge(record, id, str(o))
		if not e.is_empty():
			s += maxf(0.0, float(e["affinity"]))
	return s


# --- conversations (player ↔ NPC) ------------------------------------------------------------

## Does this person start a conversation with the player who comes close?
## Friends greet you (once a day), someone waiting for promised help calls
## you, very outgoing people introduce themselves; rivals do not. "" = no.
static func wants_to_talk(record: Dictionary, r: Dictionary, player_id: String, day: int) -> String:
	var s := person(r)
	if int(s.get("greeted_player_day", -1)) == day:
		return ""
	var e := edge(record, str(r["npc_id"]), player_id)
	var pr: Dictionary = s.get("promise", {})
	var why := ""
	if str(pr.get("by", "")) == player_id and day > int(pr.get("day", day)) and day <= int(pr.get("due_day", day)):
		why = "promise"
	elif not e.is_empty() and e["kind"] in ["friend", "close_friend", "partner"] and not bool(e.get("conflict", false)):
		why = "friend"
	elif e.is_empty() and SettlementCore.trait_of(r, "extraversion") > 0.72:
		why = "introduce"
	if why != "":
		s["greeted_player_day"] = day
	return why


## Conversation topics are dialogue nodes (data/dialog/dialog.json, DialogEngine).
static func topics_for(record: Dictionary, r: Dictionary, player_id: String, day: int, cfg: Dictionary, extra: Dictionary = {}, after := "") -> Array:
	return DialogEngine.options(DialogEngine.context(record, r, player_id, "", day, cfg, 0.6, extra), after)


static func is_topic(topic: String) -> bool:
	return topic == "farewell" or DialogEngine.data()["nodes"].has(topic)


## A conversation step: the dialogue engine answers from the context, the
## effects change the relationship. Returns {line, edge, first, next, opener}.
## Repeated talks on the same day count less (no grinding); a promise not
## kept in time leaves a small, fair dent and a conflict to talk about.
static func talk(record: Dictionary, r: Dictionary, player_id: String, player_name: String, topic: String, day: int, cfg: Dictionary, mood: float, extra: Dictionary = {}) -> Dictionary:
	var st := state(record)
	var id := str(r["npc_id"])
	var key := edge_key(id, player_id)
	var e: Dictionary = st["edges"].get(key, {})
	var first_meeting := e.is_empty()
	var ctx := DialogEngine.context(record, r, player_id, player_name, day, cfg, mood, extra)
	var opener := DialogEngine.opener(ctx)
	if first_meeting:
		e = {"a": key.get_slice("|", 0), "b": key.get_slice("|", 1), "kind": "acquaintance", "affinity": 0.0, "trust": 0.2,
			"familiarity": 0.0, "colleague": false, "family": false, "since_day": day, "last_day": day, "meetings": 0}
		st["edges"][key] = e
		remember(r, day, "met_player", player_id, "Kennengelernt: %s" % player_name, 0.6)
	var s := person(r)
	var talks: Dictionary = s.get("talks", {})
	if int(talks.get("day", -1)) != day:
		talks = {"day": day, "count": 0}
	talks["count"] = int(talks["count"]) + 1
	s["talks"] = talks
	var damp := 1.0 / (1.0 + maxf(0.0, float(talks["count"]) - 2.0))     # 3rd+ talk a day counts less
	# a promise that ran out long ago without a word: a small conflict (once)
	var pr: Dictionary = s.get("promise", {})
	if str(pr.get("by", "")) == player_id and day > int(pr.get("due_day", day)) + 7 and not bool(pr.get("noted", false)):
		pr["noted"] = true
		e["conflict"] = true
		e["trust"] = snappedf(maxf(0.0, float(e["trust"]) - 0.05), 0.001)
		remember(r, day, "promise_broken", player_id, "%s hat ein Versprechen nicht gehalten" % player_name, 0.7)
		ctx = DialogEngine.context(record, r, player_id, player_name, day, cfg, mood, extra)
	var ans := DialogEngine.answer(ctx, topic)
	var fx: Dictionary = ans["effects"]
	var line := str(ans["line"])
	e["affinity"] = snappedf(clampf(float(e["affinity"]) + float(fx.get("affinity", 0.0)) * damp, -1.0, 1.0), 0.001)
	e["trust"] = snappedf(clampf(float(e["trust"]) + float(fx.get("trust", 0.0)) * damp, 0.0, 1.0), 0.001)
	e["familiarity"] = snappedf(minf(1.0, float(e["familiarity"]) + float(fx.get("familiarity", 0.04)) * damp), 0.001)
	if fx.has("promise"):
		s["promise"] = {"by": player_id, "day": day, "due_day": day + int(fx["promise"])}
		remember(r, day, "promise", player_id, "%s hat Hilfe versprochen" % player_name, 0.8)
	if bool(fx.get("keep_promise", false)) and not s.get("promise", {}).is_empty():
		var late := day > int(s["promise"].get("due_day", day))
		s.erase("promise")
		s["helped_by_player"] = int(s.get("helped_by_player", 0)) + 1
		remember(r, day, "promise_kept", player_id, ("%s hat Wort gehalten" if not late else "%s hat doch noch geholfen") % player_name, 0.9)
	if bool(fx.get("resolve_conflict", false)) and bool(e.get("conflict", false)):
		e["conflict"] = false
		remember(r, day, "reconciled", player_id, "Versöhnt mit %s" % player_name, 0.7)
	if bool(fx.get("join_group", false)) and not (s["groups"] as Array).is_empty():
		var g: Dictionary = st["groups"].get(s["groups"][0], {})
		if not g.is_empty() and not (g["members"] as Array).has(player_id):
			g["members"].append(player_id)
			remember(r, day, "player_joined_group", player_id, "%s ist bei %s dabei" % [player_name, g["name"]], 0.6)
	e["last_day"] = day
	e["meetings"] = int(e.get("meetings", 0)) + 1
	var before := str(e["kind"])
	var aff := float(e["affinity"])
	if aff >= 0.42 and float(e["familiarity"]) >= 0.35 and before == "acquaintance":
		e["kind"] = "friend"
		remember(r, day, "friendship", player_id, "Freundschaft mit %s" % player_name, 0.8)
		line += " (Ihr seid jetzt befreundet.)"
	elif aff >= 0.62 and float(e["familiarity"]) >= 0.65 and before == "friend":
		e["kind"] = "close_friend"
	elif aff <= -0.35 and before in ["acquaintance", "friend"]:
		e["kind"] = "rival"
	# what was said (no repetition: recent topics, last variant per topic)
	var dl: Dictionary = s.get("dialog", {"recent": [], "last": {}})
	var recent: Array = dl.get("recent", [])
	recent.append(topic)
	dl["recent"] = recent.slice(maxi(0, recent.size() - 6))
	var last: Dictionary = dl.get("last", {})
	last[topic] = int(ans.get("variant", 0))
	dl["last"] = last
	if ans.has("said"):
		var said: Dictionary = dl.get("said", {})
		var lst: Array = said.get(topic, [])
		lst.append(int(ans["said"]))
		said[topic] = lst.slice(maxi(0, lst.size() - 4))
		dl["said"] = said
	s["dialog"] = dl
	var ctx2 := DialogEngine.context(record, r, player_id, player_name, day, cfg, mood, extra)
	return {"line": line, "edge": e, "first": first_meeting, "opener": opener,
		"next": DialogEngine.options(ctx2, topic) if topic != "farewell" else []}


static func _recent_memory(r: Dictionary, day: int) -> Dictionary:
	var mem: Array = person(r)["memories"]
	for i in range(mem.size() - 1, -1, -1):
		if day - int(mem[i]["day"]) <= 10 and mem[i]["kind"] != "met_player":
			return mem[i]
	return {}


## Text block for the NPC card (relationships, family, groups, goals, memories).
static func card_text(record: Dictionary, r: Dictionary, player_id: String, day: int, cfg: Dictionary) -> String:
	var lines := PackedStringArray()
	var id := str(r["npc_id"])
	var s := person(r)
	if is_child(r, day, cfg):
		lines.append("[b]Lebensphase:[/b] %s" % life_stage(r, day, cfg))
	var pe := edge(record, id, player_id)
	if not pe.is_empty():
		lines.append("[b]Zu dir:[/b] %s (Sympathie %+d, Vertrauen %d %%)" % [KIND_LABEL.get(pe["kind"], ""), int(float(pe["affinity"]) * 100.0), int(float(pe["trust"]) * 100.0)])
	var fam := PackedStringArray()
	if str(s["partner_id"]) != "":
		fam.append("Partner:in " + _first(SettlementCore._npc(record, str(s["partner_id"]))))
	for c in s["children"]:
		var rc := SettlementCore._npc(record, str(c))
		if not rc.is_empty() and rc.get("alive", true):
			fam.append("Kind " + _first(rc))
	for p in s["parents"]:
		var rp := SettlementCore._npc(record, str(p))
		if not rp.is_empty() and rp.get("alive", true):
			fam.append("Elternteil " + _first(rp))
	if not fam.is_empty():
		lines.append("[b]Familie:[/b] " + ", ".join(fam))
	var friends: Array = relations_of(record, id).filter(func(x): return x["edge"]["kind"] in ["friend", "close_friend"] and not str(x["other"]).begins_with("player:"))
	if not friends.is_empty():
		var names := PackedStringArray()
		for f in friends.slice(0, 4):
			names.append(_first(SettlementCore._npc(record, str(f["other"]))))
		lines.append("[b]Freunde:[/b] " + ", ".join(names) + (" …" if friends.size() > 4 else ""))
	if not (s["groups"] as Array).is_empty():
		var gn := PackedStringArray()
		for gid in s["groups"]:
			gn.append(str(state(record)["groups"].get(gid, {}).get("name", "")))
		lines.append("[b]Vereine:[/b] " + ", ".join(gn))
	var open: Array = (s["goals"] as Array).filter(func(g): return not g.has("done_day"))
	if not open.is_empty() and not pe.is_empty() and float(pe["familiarity"]) >= 0.12:
		lines.append("[b]Ziel:[/b] %s (%d %%)" % [GOALS.get(open[0]["kind"], ""), int(float(open[0]["progress"]) * 100.0)])
	var mem: Array = s["memories"]
	if not mem.is_empty() and not pe.is_empty() and float(pe["trust"]) >= 0.3:
		var m: Dictionary = mem[-1]
		lines.append("[i]Erinnert sich: %s[/i]" % m["text"])
	return "\n".join(lines)
