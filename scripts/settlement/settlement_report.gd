class_name SettlementReport
extends RefCounted
## Phase 4: texts for the settlement administration (town hall) and the
## building cards – read-only views of the authoritative state (record.core,
## record.npcs). Commands go through WorldState.client, never from here.

const FUNCTION_LABELS := {"verwaltung": "Verwaltung", "wasser": "Wasser", "energie": "Energie", "lebensmittel": "Lebensmittel",
	"medizin": "Medizin", "notfall": "Brand- & Notfallschutz", "bau": "Bau & Instandhaltung", "handwerk": "Handwerk", "handel": "Handel", "laden": "Läden"}
const RESOURCE_LABELS := {"food": "Nahrung", "water": "Wasser", "energy": "Energie"}
const PRIORITY_ACTIONS := {"admin_prio_lebensmittel": "lebensmittel", "admin_prio_bau": "bau", "admin_prio_medizin": "medizin"}


static func _names(record: Dictionary) -> Dictionary:
	var out := {}
	for r in record.get("npcs", []):
		out[r["npc_id"]] = str(r.get("name", ""))
	return out


static func _pct(v: float) -> String:
	return "%d %%" % int(round(v * 100.0))


## Town hall: overview of the settlement and the administration's decisions.
static func town_hall_text(record: Dictionary, data: SettlementData, cfg: Dictionary, t: int, offset_min: int) -> String:
	var core: Dictionary = record.get("core", {})
	var st: Dictionary = core.get("stats", {})
	var day := SettlementCore.day_index(t, offset_min)
	var alive := SettlementCore.alive_npcs(record)
	var ages := {"unter 30": 0, "30–49": 0, "50–66": 0, "ab 67": 0}
	var status := {"employed": 0, "pool": 0, "unemployed": 0, "retired": 0, "none": 0}
	for r in alive:
		var a := SettlementCore.age_years(r, day, cfg)
		ages["unter 30" if a < 30 else ("30–49" if a < 50 else ("50–66" if a < 67 else "ab 67"))] += 1
		var s := str(r.get("employment", {}).get("status", "none"))
		status[s] = int(status.get(s, 0)) + 1
	var lines := PackedStringArray()
	lines.append("[b]Bevölkerung:[/b] %d NPCs, %d Spieler:innen · Wohnraum frei: %d" % [alive.size(), record.get("resident_player_ids", []).size(), SettlementCore.housing_free(record, data, cfg)])
	lines.append("Alter: " + ", ".join(ages.keys().map(func(k): return "%s %d" % [k, ages[k]])))
	lines.append("Beschäftigt %d · Allgemeine Arbeitskräfte %d · arbeitssuchend %d · im Ruhestand %d · krank/verletzt %d" % [status["employed"], status["pool"], status["unemployed"], status["retired"], int(st.get("ill", 0))])
	var hist: Array = core.get("history", [])
	if hist.size() >= 2:
		var back: Dictionary = hist[maxi(0, hist.size() - 5)]
		lines.append("Entwicklung: vor %d Wochen %d Einwohner:innen, heute %d" % [hist.size() - 1 - maxi(0, hist.size() - 5), int(back["population"]), alive.size()])
	var cnt: Dictionary = core.get("counters", {})
	lines.append("Seit Gründung: %d Zugezogene, %d Todesfälle, %d Erkrankungen, %d Unfälle, %d Brände" % [cnt.get("arrivals", 0), cnt.get("deaths", 0), cnt.get("illnesses", 0), cnt.get("accidents", 0), cnt.get("fires", 0)])
	lines.append("")
	lines.append("[b]Grundversorgung[/b] (Vorrat · Erzeugung/Verbrauch pro Tag)")
	var stocks: Dictionary = core.get("stocks", {})
	for k in ["food", "water", "energy"]:
		var cons := maxf(0.001, float(st.get(k + "_cons", 1.0)))
		var flag := " [color=#c0392b]Engpass![/color]" if st.get(k + "_short", false) else ""
		lines.append("%s: %d (≈ %.0f Tage) · %.0f / %.0f%s" % [RESOURCE_LABELS[k], int(float(stocks.get(k, 0.0))), float(stocks.get(k, 0.0)) / cons, float(st.get(k + "_prod", 0.0)), cons, flag])
	var rf: Dictionary = record.get("region_factors", {})
	if not rf.is_empty():
		lines.append("[i]Standort: Böden %s, Wasser %s, Energie %s, Baumaterial %s[/i]" % [_pct(float(rf.get("food", 1))), _pct(float(rf.get("water", 1))), _pct(float(rf.get("energy", 1))), _pct(float(rf.get("materials", 1)))])
	lines.append("")
	lines.append("[b]Dienste heute[/b] (besetzte Stunden)")
	var cov: Dictionary = core.get("coverage", {})
	var parts := PackedStringArray()
	for fn in SettlementCore.FUNCTIONS:
		parts.append("%s %s" % [FUNCTION_LABELS[fn], _pct(float(cov.get(fn, 0.0)))])
	lines.append(" · ".join(parts))
	var vac := vacancies(record, data, cfg)
	if not vac.is_empty():
		lines.append("[b]Offene Stellen:[/b] " + ", ".join(vac.map(func(v): return "%s (%d)" % [v["name"], v["open"]])))
	var pol: Dictionary = core.get("policy", {})
	lines.append("")
	lines.append("[b]Verwaltung:[/b] Zuzug %s · Vorrang bei Stellen: %s" % ["offen" if pol.get("open_for_newcomers", true) else "geschlossen", ", ".join((pol.get("priorities", []) as Array).slice(0, 4).map(func(f): return FUNCTION_LABELS.get(f, f)))])
	lines.append("")
	lines.append("[b]Chronik[/b]")
	var names := _names(record)
	var evs: Array = core.get("events", [])
	var shown := 0
	for i in range(evs.size() - 1, -1, -1):
		var txt := event_text(evs[i], names, data)
		if txt == "":
			continue
		lines.append("· " + txt)
		shown += 1
		if shown >= 8:
			break
	if shown == 0:
		lines.append("[i]Noch keine besonderen Ereignisse.[/i]")
	return "\n".join(lines)


static func admin_actions(record: Dictionary, player_id: String) -> Array:
	if not player_id in WorldAuthority.admins_of(record):
		return []
	var open: bool = record.get("core", {}).get("policy", {}).get("open_for_newcomers", true)
	return [
		{"id": "admin_toggle_newcomers", "label": "Zuzug schließen" if open else "Zuzug öffnen"},
		{"id": "admin_prio_lebensmittel", "label": "Vorrang Nahrung"},
		{"id": "admin_prio_bau", "label": "Vorrang Instandhaltung"},
		{"id": "admin_prio_medizin", "label": "Vorrang Medizin"},
	]


## The command an administration button stands for ({} = not an admin action).
static func admin_command(record: Dictionary, action_id: String) -> Dictionary:
	var sid: String = record.get("settlement_id", "")
	if action_id == "admin_toggle_newcomers":
		var open: bool = record.get("core", {}).get("policy", {}).get("open_for_newcomers", true)
		return {"kind": "set_policy", "settlement_id": sid, "payload": {"open_for_newcomers": not open}}
	if PRIORITY_ACTIONS.has(action_id):
		var fn: String = PRIORITY_ACTIONS[action_id]
		var pr: Array = (record.get("core", {}).get("policy", {}).get("priorities", SettlementCore.FUNCTIONS) as Array).duplicate()
		pr.erase(fn)
		pr.push_front(fn)
		return {"kind": "set_priorities", "settlement_id": sid, "payload": {"priorities": pr}}
	return {}


static func vacancies(record: Dictionary, data: SettlementData, cfg: Dictionary) -> Array:
	var out := []
	var models: Dictionary = cfg.get("operating_models", {})
	for b in data.buildings:
		var m: Dictionary = models.get(b.get("type", ""), {})
		if m.is_empty():
			continue
		var open := SettlementCore.target_staff(m) - SettlementCore.staff_of(record, b["id"]).size()
		if open > 0:
			out.append({"building_id": b["id"], "name": b.get("name", b["id"]), "open": open})
	return out


## Building card: function, opening hours, open now, staff, condition.
static func building_text(record: Dictionary, data: SettlementData, cfg: Dictionary, bid: String, base_text: String, t: int, offset_min: int) -> String:
	var b: Dictionary = {}
	for e in data.buildings:
		if e.get("id", "") == bid:
			b = e
	var lines := PackedStringArray()
	if base_text != "":
		lines.append(base_text)
		lines.append("")
	var ty := str(b.get("type", ""))
	var m: Dictionary = cfg.get("operating_models", {}).get(ty, {})
	if not m.is_empty():
		var names := ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
		var h := NpcBrain.local_hour(t, offset_min)
		var wd := NpcBrain.weekday(t, offset_min)
		var open_now := false
		var hours := PackedStringArray()
		for sh in m.get("shifts", []):
			var days: Array = sh.get("days", [])
			var dtext := "täglich" if days.size() == 7 else "%s–%s" % [names[int(days[0])], names[int(days[days.size() - 1])]]
			hours.append("%s %s %s–%s" % [sh.get("name", ""), dtext, SettlementSim._hm(float(sh["start"]) * 60.0), SettlementSim._hm(float(sh["end"]) * 60.0)])
			var dd: Array = days.map(func(x): return int(x))
			if wd in dd and h >= float(sh["start"]) and h < float(sh["end"]):
				open_now = true
		lines.append("[b]%s[/b] · %s%s" % [FUNCTION_LABELS.get(m.get("function", ""), ""), "jetzt geöffnet" if open_now else "jetzt geschlossen", " · Rufbereitschaft nachts" if m.get("on_call_night", false) else ""])
		lines.append(" · ".join(hours))
		var staff := SettlementCore.staff_of(record, bid)
		var target := SettlementCore.target_staff(m)
		lines.append("Personal %d/%d: %s" % [staff.size(), target, ", ".join(staff.map(func(r): return str(r.get("name", "")).get_slice(" ", 0))) if not staff.is_empty() else "—"])
	if ty in ["house", "player_home"]:
		var cap: int = SettlementCore.housing_capacity(record, data, cfg).get(bid, 0)
		var res := SettlementCore.alive_npcs(record).filter(func(r): return r.get("home_id", "") == bid)
		lines.append("[b]Bewohner %d/%d:[/b] %s" % [res.size(), cap, ", ".join(res.map(func(r): return str(r.get("name", "")).get_slice(" ", 0))) if not res.is_empty() else "—"])
	var cond := float(record.get("core", {}).get("condition", {}).get(bid, 1.0))
	var vs := VisualEventRouter.visual_state_of(record, bid)
	var state := "gepflegt" if cond > 0.75 else ("etwas abgenutzt" if cond > 0.5 else ("verwahrlost" if cond > 0.3 else "baufällig"))
	if vs.fire > 0:
		state += ", Brandspuren"
	lines.append("Zustand: %s (%s)" % [state, _pct(cond)])
	return "\n".join(lines)


## One chronicle line per event (German, for players).
static func event_text(e: Dictionary, names: Dictionary, data: SettlementData) -> String:
	var who := str(names.get(e.get("npc", ""), "")).get_slice(" ", 0)
	var bname := ""
	if e.has("building"):
		for b in data.buildings:
			if b.get("id", "") == e["building"]:
				bname = str(b.get("name", ""))
	match str(e.get("kind", "")):
		"arrived":
			return "%s ist zugezogen." % who
		"died":
			return "%s ist mit %d Jahren gestorben." % [who, int(e.get("age", 0))]
		"retired":
			return "%s ist in den Ruhestand gegangen." % who
		"fell_ill":
			return "%s ist erkrankt." % who
		"accident":
			return "%s hatte einen Arbeitsunfall (%s)." % [who, bname]
		"dismissed":
			return "%s wurde nach wiederholtem Fehlen entlassen." % who
		"hired":
			return "%s arbeitet jetzt in: %s." % [who, bname]
		"substitution":
			return "%s springt ein: %s." % [who, bname]
		"fire":
			return "Brand in %s – %s." % [bname, "schnell gelöscht" if e.get("contained", false) else "großer Schaden"]
		"shortage_start":
			return "Engpass: %s wird knapp." % RESOURCE_LABELS.get(e.get("resource", ""), "")
		"shortage_end":
			return "Versorgung mit %s wieder gesichert." % RESOURCE_LABELS.get(e.get("resource", ""), "")
		"abandoned":
			return "Die Siedlung ist verlassen."
		"resettled":
			return "Die Siedlung ist wieder bewohnt."
		"player_joined":
			return "Ein:e Spieler:in ist zugezogen."
		"account_deleted":
			return "Ein Spielerkonto wurde gelöscht – die Siedlung besteht weiter."
	return ""
