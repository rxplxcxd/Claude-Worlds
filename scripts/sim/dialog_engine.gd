class_name DialogEngine
extends RefCounted
## Rule-based dialogue (docs/DIALOG_SYSTEM.md) – no AI, no external service.
##
## Data: data/dialog/dialog.json – openers, nodes (player options) with
## conditions, answer groups (first matching group wins: specific before
## general) with text variants, effects and follow-up options.
## Context: everything the NPC "knows" right now – relationship to the
## player, shared memories, promises and conflicts, mood and needs, goals,
## family, clubs, job, place, time of day, recent settlement news, what was
## already said today. The same context always gives the same choice
## (seeded by NPC, day and the number of talks), variants are not repeated
## back to back, recently used topics step back.

const LEVELS := ["rival", "stranger", "acquaintance", "friend", "close", "partner"]
const WEEKDAYS := ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialog/dialog.json"))
		_data = d if d is Dictionary else {"openers": [], "nodes": {}}
	return _data


## Builds the context of a conversation. extra: {hour, place, needs, names}.
static func context(record: Dictionary, r: Dictionary, player_id: String, player_name: String, day: int, cfg: Dictionary, mood: float, extra: Dictionary = {}) -> Dictionary:
	var id := str(r["npc_id"])
	var s := SocialCore.person(r)
	var e := SocialCore.edge(record, id, player_id)
	var kind := str(e.get("kind", ""))
	var rel: String = "stranger" if e.is_empty() else {"acquaintance": "acquaintance", "friend": "friend", "close_friend": "close", "partner": "partner", "rival": "rival", "family": "close"}.get(kind, "acquaintance")
	var hour := float(extra.get("hour", 12.0))
	var child := SocialCore.is_child(r, day, cfg)
	var vars := {"first": _first(r), "player": player_name, "you": "du", "your": "dein"}
	vars["daytime"] = "Morgen" if hour >= 5.0 and hour < 11.0 else ("Tag" if hour < 17.0 else ("Abend" if hour < 22.0 else "Nacht"))
	var formal: bool = rel == "stranger" and SettlementCore.age_years(r, day, cfg) > 45.0
	vars["greet"] = {"Morgen": "Guten Morgen", "Tag": "Guten Tag" if formal else "Hallo", "Abend": "Guten Abend", "Nacht": "N'Abend"}[vars["daytime"]]
	var facts := {"rel": rel, "child": child, "first_meeting": e.is_empty(), "hour": hour, "mood": mood,
		"familiarity": float(e.get("familiarity", 0.0)), "trust": float(e.get("trust", 0.2)),
		"conflict": bool(e.get("conflict", false)) or kind == "rival", "needs": extra.get("needs", {}),
		"talked_today": int(s.get("talks", {}).get("count", 0)) if int(s.get("talks", {}).get("day", -1)) == day else 0,
		"recent": s.get("dialog", {}).get("recent", []), "r": r}
	# place
	var place := str(extra.get("place", ""))
	var wp := str(r.get("employment", {}).get("workplace_id", r.get("workplace_id", "")))
	facts["place"] = "work" if wp != "" and place.ends_with(wp) else ("home" if r.get("home_id", "") != "" and place.ends_with(str(r["home_id"])) else ("plaza" if place.contains("plaza") else ("park" if place.contains("park") else "other")))
	var names: Dictionary = extra.get("names", {})
	vars["workplace"] = str(names.get(wp, "der Arbeit"))
	vars["place"] = str(names.get(place.trim_prefix("bld:"), place))
	vars["job"] = str(r.get("profession", {}).get("title", ""))
	facts["has:job"] = wp != "" and r.get("employment", {}).get("status", "") == "employed"
	# family, friends, clubs
	var pid := str(s.get("partner_id", ""))
	facts["has:partner"] = pid != ""
	vars["partner"] = _first(SettlementCore._npc(record, pid)) if pid != "" else ""
	var kids: Array = (s["children"] as Array).filter(func(c): return SettlementCore._npc(record, str(c)).get("alive", false))
	facts["has:child"] = not kids.is_empty()
	if not kids.is_empty():
		var kid := SettlementCore._npc(record, str(kids[-1]))
		vars["child"] = _first(kid)
		vars["stage"] = SocialCore.life_stage(kid, day, cfg)
	else:
		vars["stage"] = SocialCore.life_stage(r, day, cfg)
	var friends: Array = SocialCore.relations_of(record, id).filter(func(x): return x["edge"]["kind"] in ["friend", "close_friend"] and not str(x["other"]).begins_with("player:"))
	facts["has:friend"] = not friends.is_empty()
	vars["friend"] = _first(SettlementCore._npc(record, str(friends[0]["other"]))) if not friends.is_empty() else ""
	var groups: Array = s["groups"]
	facts["has:group"] = not groups.is_empty()
	if not groups.is_empty():
		var g: Dictionary = SocialCore.state(record)["groups"].get(groups[0], {})
		vars["group"] = str(g.get("name", "unserem Verein"))
		vars["group_day"] = "am " + WEEKDAYS[int(g.get("weekday", 0)) % 7]
		vars["group_hour"] = str(int(g.get("hour", 18)))
		facts["player_in_group"] = (g.get("members", []) as Array).has(player_id)
	var ints: Array = s["interests"]
	vars["interest"] = str(SocialCore.INTERESTS.get(ints[0], {}).get("label", "")).to_lower() if not ints.is_empty() else "vieles"
	facts["has:interest2"] = ints.size() > 1
	vars["interest2"] = str(SocialCore.INTERESTS.get(ints[1], {}).get("label", "")).to_lower() if ints.size() > 1 else ""
	var open: Array = (s["goals"] as Array).filter(func(gg): return not gg.has("done_day"))
	facts["has:goal"] = not open.is_empty()
	if not open.is_empty():
		vars["goal"] = str(SocialCore.GOALS.get(open[0]["kind"], "")).to_lower()
		vars["progress"] = "%d %%" % int(float(open[0]["progress"]) * 100.0)
	var mem := _recent_memory(r, day)
	facts["has:memory"] = not mem.is_empty()
	vars["memory"] = str(mem.get("text", ""))
	var news := _news(record, day, id)
	facts["has:news"] = news != ""
	vars["news"] = news
	# promises
	var pr: Dictionary = s.get("promise", {})
	facts["promise"] = ""
	if str(pr.get("by", "")) == player_id:
		facts["promise"] = "open" if day <= int(pr.get("day", day)) else ("due" if day <= int(pr.get("due_day", day)) else "late")
	return {"facts": facts, "vars": vars, "npc": id, "day": day}


static func _first(r: Dictionary) -> String:
	return str(r.get("name", "")).get_slice(" ", 0)


static func _recent_memory(r: Dictionary, day: int) -> Dictionary:
	var mem: Array = SocialCore.person(r)["memories"]
	for i in range(mem.size() - 1, -1, -1):
		if day - int(mem[i]["day"]) <= 10 and not mem[i]["kind"] in ["met_player", "promise", "promise_kept"]:
			return mem[i]
	return {}


## Something people talk about: recent events of the settlement (7 days).
static func _news(record: Dictionary, day: int, npc_id: String) -> String:
	var evs: Array = record.get("core", {}).get("events", [])
	for i in range(evs.size() - 1, maxi(-1, evs.size() - 60), -1):
		var ev: Dictionary = evs[i]
		var k := str(ev.get("kind", ""))
		var who := SettlementCore._npc(record, str(ev.get("npc", "")))
		var name := _first(who) if not who.is_empty() and str(ev.get("npc", "")) != npc_id else ""
		match k:
			"born":
				if name != "":
					return "%s ist geboren – die Familie ist ganz glücklich." % name
			"partnership":
				if name != "":
					return "%s ist jetzt mit jemandem zusammen!" % name
			"group_founded":
				return "Es gibt einen neuen Verein: %s." % str(SocialCore.state(record)["groups"].get(ev.get("data", {}).get("group", ev.get("group", "")), {}).get("name", "ein Verein"))
			"fire":
				return "Neulich hat es gebrannt – zum Glück war die Wache schnell da."
			"arrived":
				if name != "":
					return "%s ist neu zu uns gezogen." % name
			"died":
				if name != "":
					return "%s ist gestorben. Das hat viele getroffen." % name
			"shortage_start":
				return "Die Vorräte werden knapp, hab ich gehört."
	return ""


## Does a condition hold?
static func check(cond: String, ctx: Dictionary) -> bool:
	var f: Dictionary = ctx["facts"]
	if cond.begins_with("not:"):
		return not check(cond.substr(4), ctx)
	if cond.begins_with("rel:"):
		return f["rel"] == cond.substr(4)
	if cond.begins_with("rel_min:"):
		return LEVELS.find(f["rel"]) >= LEVELS.find(cond.substr(8))
	if cond.begins_with("mood>"):
		return float(f["mood"]) > float(cond.substr(5))
	if cond.begins_with("mood<"):
		return float(f["mood"]) < float(cond.substr(5))
	if cond.begins_with("familiarity>"):
		return float(f["familiarity"]) > float(cond.substr(12))
	if cond.begins_with("trust>"):
		return float(f["trust"]) > float(cond.substr(6))
	if cond.begins_with("trust<"):
		return float(f["trust"]) < float(cond.substr(6))
	if cond.begins_with("talked_today>"):
		return int(f["talked_today"]) > int(cond.substr(13))
	if cond.begins_with("need:"):
		return float(f["needs"].get(cond.substr(5), 1.0)) < 0.3
	if cond.begins_with("time:"):
		var h := float(f["hour"])
		return {"morning": h >= 5.0 and h < 11.0, "day": h >= 11.0 and h < 17.0, "evening": h >= 17.0 and h < 22.0, "night": h >= 22.0 or h < 5.0}.get(cond.substr(5), false)
	if cond.begins_with("place:"):
		return f["place"] == cond.substr(6)
	if cond.begins_with("promise:"):
		return f["promise"] == cond.substr(8) or (cond == "promise:open" and f["promise"] in ["open", "due"])
	if cond.begins_with("trait:"):
		var spec := cond.substr(6)
		var op := ">" if spec.contains(">") else "<"
		var v := SettlementCore.trait_of(f["r"], spec.get_slice(op, 0))
		return v > float(spec.get_slice(op, 1)) if op == ">" else v < float(spec.get_slice(op, 1))
	if cond.begins_with("used:"):
		return (f["recent"] as Array).has(cond.substr(5))
	match cond:
		"first_meeting", "child", "conflict", "player_in_group":
			return bool(f.get(cond, false))
		"adult":
			return not bool(f["child"])
	return bool(f.get(cond, false))


static func all(conds: Array, ctx: Dictionary) -> bool:
	for c in conds:
		if not check(str(c), ctx):
			return false
	return true


## Fills {variables}; unknown ones are left out cleanly.
static func fill(text: String, ctx: Dictionary) -> String:
	var v: Dictionary = ctx["vars"]
	for k in v:
		text = text.replace("{%s}" % k, str(v[k]))
	return text


static func _variant(texts: Array, ctx: Dictionary, salt: String) -> int:
	if texts.size() <= 1:
		return 0
	var r: Dictionary = ctx["facts"]["r"]
	var last := int(SocialCore.person(r).get("dialog", {}).get("last", {}).get(salt, -1))
	var i := int(SettlementCore._chance("%s#dlg#%s#%d#%d" % [ctx["npc"], salt, ctx["day"], int(ctx["facts"]["talked_today"])]) * texts.size()) % texts.size()
	if i == last:
		i = (i + 1) % texts.size()                    # never the same line twice in a row
	return i


## How the NPC opens the conversation.
static func opener(ctx: Dictionary) -> String:
	for o in data()["openers"]:
		if all(o["when"], ctx):
			var texts: Array = o["text"]
			return fill(str(texts[_variant(texts, ctx, "open")]), ctx)
	return ""


## The options the player has now (node ids). after: the node just answered
## (its follow-ups come first).
static func options(ctx: Dictionary, after := "", limit := 5) -> Array:
	var nodes: Dictionary = data()["nodes"]
	var out: Array = []
	var recent: Array = ctx["facts"]["recent"]
	if after != "" and nodes.has(after):
		for n in nodes[after].get("next", []):
			if out.size() < limit - 1 and nodes.has(n) and all(nodes[n]["when"], ctx) and not out.has(n) \
					and not recent.slice(maxi(0, recent.size() - 1)).has(n):
				out.append(n)
	# urgent nodes (weight >= 3: a promise is due, a conflict) first; the
	# ordinary ones rotate per conversation, so every topic comes up
	var rest: Array = nodes.keys()
	var seed := "%s#opt#%d#%d" % [ctx["npc"], ctx["day"], int(ctx["facts"]["talked_today"])]
	rest.sort_custom(func(a, b):
		var wa := int(nodes[a].get("weight", 1))
		var wb := int(nodes[b].get("weight", 1))
		if wa != wb:
			return wa > wb
		return SettlementCore._chance(seed + a) < SettlementCore._chance(seed + b))
	for n in rest:
		if out.size() >= limit:
			break
		if out.has(n) or not all(nodes[n]["when"], ctx):
			continue
		if recent.slice(maxi(0, recent.size() - 2)).has(n) and int(nodes[n].get("weight", 1)) < 3:
			continue                                   # just talked about it
		out.append(n)
	return out.slice(0, limit)


static func label(node: String) -> String:
	if node == "farewell":
		return str(data().get("farewell", {}).get("label", "Verabschieden"))
	return str(data()["nodes"].get(node, {}).get("label", node))


## The NPC's answer to a node: {line, effects, next}.
static func answer(ctx: Dictionary, node: String) -> Dictionary:
	if node == "farewell":
		var ft: Array = data().get("farewell", {}).get("text", ["Tschüss!"])
		return {"line": fill(str(ft[_variant(ft, ctx, "bye")]), ctx), "effects": {}, "next": []}
	var nd: Dictionary = data()["nodes"].get(node, {})
	if nd.is_empty():
		return {"line": "", "effects": {}, "next": []}
	# candidate lines: the first matching group decides (e.g. a refusal); with
	# "mix" all matching context groups are pooled (place, time, mood,
	# memory …) and the generic group only fills up a small pool
	var pool: Array = []                              # [group index, text]
	var groups: Array = nd.get("answers", [])
	for gi in groups.size():
		var grp: Dictionary = groups[gi]
		if not all(grp.get("when", []), ctx):
			continue
		if (grp.get("when", []) as Array).is_empty() and bool(nd.get("mix", false)) and pool.size() >= 3:
			continue
		for tx in grp["text"]:
			pool.append([gi, str(tx)])
		if not bool(nd.get("mix", false)):
			break
	if pool.is_empty():
		return {"line": "", "effects": {}, "next": []}
	# never what this person said to you lately on this topic
	var said: Array = SocialCore.person(ctx["facts"]["r"]).get("dialog", {}).get("said", {}).get(node, [])
	var start := int(SettlementCore._chance("%s#dlg#%s#%d#%d" % [ctx["npc"], node, ctx["day"], int(ctx["facts"]["talked_today"])]) * pool.size()) % pool.size()
	var pick := start
	var oldest := 1 << 30
	for k in pool.size():
		var c: int = (start + k) % pool.size()
		var pos := said.find(str(pool[c][1]).hash())       # -1: not said lately
		if pos < 0:
			pick = c
			break
		if pos < oldest:                                     # else the one said longest ago
			oldest = pos
			pick = c
	var fx: Dictionary = (nd.get("effects", {}) as Dictionary).duplicate()
	fx.merge(groups[int(pool[pick][0])].get("effects", {}), true)
	return {"line": fill(str(pool[pick][1]), ctx), "effects": fx, "next": nd.get("next", []), "variant": pick, "said": str(pool[pick][1]).hash()}
