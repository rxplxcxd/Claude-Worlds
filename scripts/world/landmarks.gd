class_name Landmarks
extends RefCounted
## Fixed world landmarks (data/world/landmarks.json): uninhabited historic
## sites that are part of the persistent world definition – first of all the
## World Council seat on Kalistia (docs/WORLD_COUNCIL.md).
##
## Definitions never change at runtime and are identical on every client and
## the future server. The changeable state of a landmark (development stage,
## condition of its components, restorations, damage, decisions, history)
## is kept by WorldState (`landmark_state`) and – like settlements – will be
## changed only by the world authority (server) through commands
## (planned: restoration Phase 7, world council Phase 10, see
## docs/WORLD_COUNCIL_ROADMAP.md).

const PATH := "res://data/world/landmarks.json"
const WORLD_COUNCIL := "lmk_world_council"

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


## The landmark whose reserved ground contains (lat, lon), or {}.
## `margin_km` widens the test (e.g. half the start square of a settlement).
static func reserved_at(lat: float, lon: float, radius_km: float, margin_km: float = 0.0) -> Dictionary:
	for d in all():
		var p: Dictionary = d.get("position", {})
		var km := Geo.distance_km(lat, lon, float(p.get("lat", 0.0)), float(p.get("lon", 0.0)), radius_km)
		if km < float(d.get("reserve_radius_km", 0.0)) + margin_km:
			return d
	return {}


## Initial (genesis) state of a landmark – what exists before anybody acted.
static func initial_state(landmark_id: String) -> Dictionary:
	var d := get_def(landmark_id)
	var comps := {}
	for c in d.get("components", []):
		comps[c["id"]] = {"condition": float(c.get("condition", 1.0)), "access": str(c.get("access", "open")), "restored": 0.0, "built": true}
	return {"landmark_id": landmark_id, "stage": int(d.get("initial_stage", 1)), "components": comps, "extensions": [], "decisions": [], "history": [], "version": 0}


## Next annual assembly (24 June, world time UTC) at or after unix time `now`.
## Returns {start, end, year}. World time – never the device's clock zone.
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
	var when := ""
	if not nxt.is_empty():
		if now >= int(nxt["start"]):
			when = "Die Weltversammlung findet heute statt (24. Juni, Weltzeit)."
		else:
			when = "Nächste Weltversammlung: 24. Juni %d (Weltzeit) – in %d Tagen." % [int(nxt["year"]), int(ceil((int(nxt["start"]) - now) / 86400.0))]
	return "%s – %s\n%s, Kontinent %s\nHistorische Anlage aus unbekannter Zeit, teils verfallen und überwuchert.\n%s" % [d["name"], d["subtitle"], d.get("site_name", ""), d.get("continent_name", ""), when]
