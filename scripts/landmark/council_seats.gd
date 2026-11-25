class_name CouncilSeats
extends RefCounted
## Seats of the Great Council Chamber (docs/WORLD_COUNCIL_INTERIORS.md §1).
##
## The 1182 delegate places have fixed ids (D<row>-<sector>-<no.>), positions
## and access points (InteriorScene.seats). This module keeps who a seat
## belongs to – persistently, in the landmark state of the world:
##   landmark_state.seats[seat_id] = {holder, substitutes[], since, by, history[]}
##
## WHO gets which seat is not decided here: in Phase 10 the institutions of
## the world assign seats (by nation, by resolution). Until then the
## development preview lets a player reserve ONE free seat for themselves
## ("preview" rule, `rule` field), so the mechanics can be played.
## Substitutes: the holder (later: the institution) names authorised
## substitutes; a substitute may take the seat while the holder is absent.

const RULE_PREVIEW := "preview_self_reservation"

static var _ids: Dictionary = {}


## All seat ids of the chamber (from its layout data).
static func valid_ids() -> Dictionary:
	if _ids.is_empty():
		for e in InteriorScene.resolve("concordium_chamber").get("items", []):
			if e.has("seat"):
				_ids[str(e["seat"])] = {"row": int(e.get("row", 0)), "sector": int(e.get("sector", 0))}
	return _ids


static func table(st: Dictionary) -> Dictionary:
	if not st.has("seats"):
		st["seats"] = {}
	return st["seats"]


static func holder_of(st: Dictionary, seat_id: String) -> String:
	return str(table(st).get(seat_id, {}).get("holder", ""))


static func seat_of(st: Dictionary, player_id: String) -> String:
	var t := table(st)
	for id in t:
		if str(t[id].get("holder", "")) == player_id:
			return id
	return ""


## Reserves a free seat. Returns "" or the reason it was refused.
static func reserve(st: Dictionary, seat_id: String, player_id: String, t: int, rule := RULE_PREVIEW) -> String:
	if not valid_ids().has(seat_id):
		return "Diesen Platz gibt es nicht."
	if player_id == "":
		return "Unbekannte Person."
	var holder := holder_of(st, seat_id)
	if holder == player_id:
		return "Dieser Platz gehört dir bereits."
	if holder != "":
		return "Dieser Platz ist bereits reserviert."
	if rule == RULE_PREVIEW and seat_of(st, player_id) != "":
		return "Du hast schon einen Platz (%s). Gib ihn zuerst frei." % seat_of(st, player_id)
	table(st)[seat_id] = {"holder": player_id, "substitutes": [], "since": t, "by": player_id, "rule": rule,
		"history": [{"t": t, "kind": "reserved", "by": player_id}]}
	return ""


static func release(st: Dictionary, seat_id: String, player_id: String) -> String:
	if holder_of(st, seat_id) != player_id:
		return "Nur wer den Platz innehat, kann ihn freigeben."
	table(st).erase(seat_id)
	return ""


## The holder names (or removes) an authorised substitute.
static func set_substitute(st: Dictionary, seat_id: String, holder: String, substitute: String, add: bool, t: int) -> String:
	if holder_of(st, seat_id) != holder:
		return "Nur wer den Platz innehat, kann eine Vertretung benennen."
	if substitute == "" or substitute == holder:
		return "Ungültige Vertretung."
	var s: Dictionary = table(st)[seat_id]
	var subs: Array = s.get("substitutes", [])
	if add and not subs.has(substitute):
		subs.append(substitute)
	elif not add:
		subs.erase(substitute)
	s["substitutes"] = subs
	(s["history"] as Array).append({"t": t, "kind": "substitute_added" if add else "substitute_removed", "who": substitute, "by": holder})
	return ""


## May this person sit here now? Free seats: everybody (temporarily);
## reserved seats: the holder, or a named substitute while the holder is not
## in the chamber (holder_present = false).
static func may_sit(st: Dictionary, seat_id: String, player_id: String, holder_present: bool) -> String:
	var holder := holder_of(st, seat_id)
	if holder == "" or holder == player_id:
		return ""
	var subs: Array = table(st)[seat_id].get("substitutes", [])
	if subs.has(player_id):
		return "" if not holder_present else "Die Delegierte / der Delegierte ist selbst anwesend."
	return "Dieser Platz ist reserviert."
