class_name Landmarks
extends RefCounted
## Fixed world landmarks (data/world/landmarks.json): uninhabited historic
## sites that are part of the persistent world definition – first of all the
## CONCORDIUM, seat of the World Council on Kalistia (docs/WORLD_COUNCIL.md).
##
## Definitions never change at runtime and are identical on every client and
## the future server. The changeable state (stage, condition of components,
## restorations, damage, extensions, PROPERTY BOUNDARY, decisions, history)
## is kept by WorldState (`landmark_state`) and is changed only by the world
## authority (server): restoration Phase 7, world council Phase 10, conflict
## Phase 11 (docs/WORLD_COUNCIL_ROADMAP.md).
##
## Neutral zone = exactly the property polygon (site metres: +x east, +y south
## around `position`). Outside it the normal rules apply.

const PATH := "res://data/world/landmarks.json"
const WORLD_COUNCIL := "lmk_world_council"
## Issuer id of the server-side world authority (only it may change boundaries).
const AUTHORITY_ISSUER := "srv_world_authority"

static var _defs: Array = []


static func all() -> Array:
	if _defs.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_defs = parsed.get("landmarks", [])
	return _defs


static func get_def(landmark_id: String) -> Dictionary:
	for d in all():
		if d.get("landmark_id", "") == landmark_id:
			return d
	return {}


static func position_of(landmark_id: String) -> Vector2:
	var p: Dictionary = get_def(landmark_id).get("position", {})
	return Vector2(float(p.get("lat", 0.0)), float(p.get("lon", 0.0)))


# --- names (official vs. interface) ----------------------------------------------

## Official name of the place: "Concordium" (never translated).
static func site_name(landmark_id: String = WORLD_COUNCIL) -> String:
	return str(get_def(landmark_id).get("site_name", ""))


## Ceremonial name of the annual assembly: "Concilium Mundi" – used on
## inscriptions, invitations, posters, documents, information boards.
static func assembly_official_name(landmark_id: String = WORLD_COUNCIL) -> String:
	return str(get_def(landmark_id).get("assembly", {}).get("official_name", ""))


## Everyday interface name of the assembly in the player's language
## ("Weltversammlung" / "World Assembly"); the official name stays separate.
static func assembly_ui_name(lang: String = "de", landmark_id: String = WORLD_COUNCIL) -> String:
	var names: Dictionary = get_def(landmark_id).get("assembly", {}).get("ui_name", {})
	return str(names.get(lang, names.get("de", "")))


## Interface name of the institution ("Weltrat" / "World Council").
static func institution_ui_name(lang: String = "de", landmark_id: String = WORLD_COUNCIL) -> String:
	var names: Dictionary = get_def(landmark_id).get("institution", {}).get("ui_name", {})
	return str(names.get(lang, names.get("de", "")))


## Ceremonial heading, e.g. for information boards and invitations:
## "CONCORDIUM\nConcilium Mundi\nDer Ort, an dem die Welt zusammenkommt."
static func ceremonial_heading(lang: String = "de", landmark_id: String = WORLD_COUNCIL) -> String:
	var d := get_def(landmark_id)
	return "%s\n%s\n%s" % [str(d.get("name", "")), assembly_official_name(landmark_id), str(d.get("tagline", {}).get(lang, ""))]


# --- property boundary = neutral zone --------------------------------------------

## Lat/lon -> site metres (+x east, +y south) around the landmark position.
static func to_site(landmark_id: String, lat: float, lon: float, radius_km: float) -> Vector2:
	var c := position_of(landmark_id)
	var km := Geo.local_xy(c.x, c.y, lat, lon, radius_km)
	return Vector2(km.x, -km.y) * 1000.0


## Site metres -> lat/lon.
static func from_site(landmark_id: String, site_m: Vector2, radius_km: float) -> Vector2:
	var c := position_of(landmark_id)
	return Geo.offset(c.x, c.y, site_m.x / 1000.0, -site_m.y / 1000.0, radius_km)


## The current property polygon (site metres). The state (server) may hold an
## extended boundary; otherwise the definition's genesis boundary applies.
static func property_polygon(landmark_id: String, state: Dictionary = {}) -> PackedVector2Array:
	var src: Array = state.get("property", {}).get("polygon_m", get_def(landmark_id).get("property", {}).get("polygon_m", []))
	var out := PackedVector2Array()
	for pt in src:
		out.append(Vector2(float(pt[0]), float(pt[1])))
	return out


static func inside_property(landmark_id: String, site_m: Vector2, state: Dictionary = {}) -> bool:
	var poly := property_polygon(landmark_id, state)
	return poly.size() >= 3 and Geometry2D.is_point_in_polygon(site_m, poly)


## The landmark whose neutral property contains (lat, lon), or {}.
static func zone_at(lat: float, lon: float, radius_km: float, states: Dictionary = {}) -> Dictionary:
	for d in all():
		var id: String = d["landmark_id"]
		if inside_property(id, to_site(id, lat, lon, radius_km), states.get(id, {})):
			return d
	return {}


## Whether a settlement's start ring (lat/lon corners) overlaps a landmark
## property. Returns the landmark definition or {}.
static func property_overlapping(ring: Array, radius_km: float, states: Dictionary = {}) -> Dictionary:
	for d in all():
		var id: String = d["landmark_id"]
		var poly := property_polygon(id, states.get(id, {}))
		var r := PackedVector2Array()
		for c in ring:
			r.append(to_site(id, float(c[0]), float(c[1]), radius_km))
		if r.size() < 3 or poly.size() < 3:
			continue
		if not Geometry2D.intersect_polygons(r, poly).is_empty() or Geometry2D.is_point_in_polygon(poly[0], r):
			return d
	return {}


## Area of the property in m².
static func property_area_m2(landmark_id: String, state: Dictionary = {}) -> float:
	var poly := property_polygon(landmark_id, state)
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


## Checks a boundary change (only by the world authority after a resolution;
## the new property must contain the old one – the neutral core never shrinks).
static func check_property_change(landmark_id: String, state: Dictionary, polygon: PackedVector2Array, issuer: String, resolution_id: String) -> String:
	if issuer != AUTHORITY_ISSUER:
		return "Nur die Weltautorität (Server) kann Grundstücksgrenzen ändern."
	if resolution_id.strip_edges() == "":
		return "Eine Grenzänderung braucht einen gültigen Beschluss."
	if polygon.size() < 3 or Geometry2D.triangulate_polygon(polygon).is_empty():
		return "Ungültiges Grenzpolygon."
	for p in property_polygon(landmark_id, state):
		if Geometry2D.is_point_in_polygon(p, polygon):
			continue
		var on_edge := false
		for i in polygon.size():
			if Geometry2D.get_closest_point_to_segment(p, polygon[i], polygon[(i + 1) % polygon.size()]).distance_to(p) < 0.01:
				on_edge = true
		if not on_edge:
			return "Das neue Gelände muss das bisherige vollständig enthalten."
	return ""


# --- neutrality (world law) ----------------------------------------------------------

## Classifies a hostile act for the neutrality system:
##   "normal"    – outside the property: ordinary rules apply,
##   "prevented" – inside: blocked by the server (no damage happens),
##   "violation" – inside: deliberate breach, logged, security intervenes,
##   "crisis"    – extraordinary, declared attack of a state (only when the
##                 Phase-11 conflict system is enabled and every requirement holds).
## ctx: {inside: bool, repeat: bool, declared_by_state_government: bool,
##       server_validated: bool, crisis_enabled: bool}
static func classify_act(kind: String, ctx: Dictionary, landmark_id: String = WORLD_COUNCIL) -> String:
	if not ctx.get("inside", false):
		return "normal"
	var n: Dictionary = get_def(landmark_id).get("neutrality", {})
	var rule: Dictionary = n.get("acts", {}).get(kind, {"tier": "prevented", "then": "violation_on_repeat"})
	var tier := str(rule.get("tier", "prevented"))
	if tier == "crisis":
		var enabled: bool = bool(ctx.get("crisis_enabled", n.get("crisis_enabled", false)))
		if enabled and ctx.get("declared_by_state_government", false) and ctx.get("server_validated", false):
			return "crisis"
		return "violation"   # an attempted attack without the requirements is a breach, nothing more
	if tier == "prevented":
		var then := str(rule.get("then", ""))
		if then == "violation" or (then == "violation_on_repeat" and ctx.get("repeat", false)):
			return "violation"
		return "prevented"
	return tier


# --- state ---------------------------------------------------------------------------------

## Initial (genesis) state of a landmark – what exists before anybody acted.
static func initial_state(landmark_id: String) -> Dictionary:
	var d := get_def(landmark_id)
	var comps := {}
	for c in d.get("components", []):
		comps[c["id"]] = {"condition": float(c.get("condition", 1.0)), "access": str(c.get("access", "open")), "restored": 0.0, "built": true}
	var prop: Dictionary = d.get("property", {})
	return {"landmark_id": landmark_id, "stage": int(d.get("initial_stage", 1)), "components": comps,
		"property": {"version": int(prop.get("version", 1)), "polygon_m": (prop.get("polygon_m", []) as Array).duplicate(true)},
		"neutral": true, "extensions": [], "decisions": [], "incidents": [], "history": [], "version": 0}


## Next annual Concilium Mundi (24 June, world time UTC) at or after unix
## time `now`. Returns {start, end, year}. World time – never the device clock.
static func next_assembly(landmark_id: String, now: int) -> Dictionary:
	var a: Dictionary = get_def(landmark_id).get("assembly", {"month": 6, "day": 24, "duration_days": 1})
	var year := int(Time.get_datetime_dict_from_unix_time(now)["year"])
	for y in [year, year + 1]:
		var start := Time.get_unix_time_from_datetime_dict({"year": y, "month": int(a["month"]), "day": int(a["day"]), "hour": 0, "minute": 0, "second": 0})
		var end := start + int(a.get("duration_days", 1)) * 86400
		if end > now:
			return {"start": start, "end": end, "year": y}
	return {}


## Short German text for info panels.
static func describe(landmark_id: String, now: int) -> String:
	var d := get_def(landmark_id)
	if d.is_empty():
		return ""
	var nxt := next_assembly(landmark_id, now)
	var official := assembly_official_name(landmark_id)
	var ui := assembly_ui_name("de", landmark_id)
	var when := ""
	if not nxt.is_empty():
		if now >= int(nxt["start"]):
			when = "Heute tagt das %s (%s, 24. Juni, Weltzeit)." % [official, ui]
		else:
			when = "Nächstes %s (%s): 24. Juni %d (Weltzeit) – in %d Tagen." % [official, ui, int(nxt["year"]), int(ceil((int(nxt["start"]) - now) / 86400.0))]
	return "%s – %s\n%s, Kontinent %s · Sitz des %ss · neutrales Gelände\nHistorische Anlage aus unbekannter Zeit, teils verfallen und überwuchert.\n%s" % [d["name"], d["subtitle"], site_name(landmark_id), d.get("continent_name", ""), institution_ui_name("de", landmark_id), when]
