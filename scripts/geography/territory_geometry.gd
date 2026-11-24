class_name TerritoryGeometry
extends RefCounted
## Territory shapes and the founding distance rule (docs/TERRITORY_SYSTEM.md).
##
## Four area notions are kept apart:
##   settlement area  – the locally playable grid (SettlementArea, record["settlement_area"])
##   territory        – claimed area, a spherical polygon (this class); basis of all rules
##   built area       – derived from buildings/roads, never authoritative (later phases)
##   expansion        – separate claims added to a territory (later phases; record["expansions"])
## A new settlement claims exactly START_SIZE_KM × START_SIZE_KM, aligned to
## the local east/north frame (at a pole: the frame of longitude 0).

const START_SIZE_KM := 1.0
## Minimum distance between the new start territory and every existing
## territory border (geodesic, border to border).
const MIN_FOUNDING_GAP_KM := 20.0
## Index buffer: gap + a margin so neighbouring cells are always included.
const INDEX_BUFFER_KM := 21.5


## Corner ring [[lat, lon] × 4] of the start square centred on (lat, lon).
static func start_square(lat: float, lon: float, radius_km: float, size_km: float = START_SIZE_KM) -> Array:
	var h := size_km * 0.5
	var ring: Array = []
	for c in [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]:
		var p := Geo.offset(lat, lon, c.x, c.y, radius_km)
		ring.append([p.x, p.y])
	return ring


## All rings of a territory (core + granted expansions).
static func rings_of(territory: Dictionary) -> Array:
	var out: Array = []
	var g: Dictionary = territory.get("geometry", {})
	for r in g.get("rings", []):
		out.append(r)
	for e in territory.get("expansions", []):
		if e.get("state", "") == "granted":
			for r in e.get("geometry", {}).get("rings", []):
				out.append(r)
	return out


## Builds a new territory record for a settlement founded at (lat, lon).
static func make_territory(territory_id: String, settlement_id: String, player_id: String, lat: float, lon: float, radius_km: float, now_unix: int) -> Dictionary:
	var ring := start_square(lat, lon, radius_km)
	return {
		"territory_id": territory_id,
		"owner_settlement_id": settlement_id,
		"owner_player_id": player_id,
		"kind": "settlement",
		"status": "active",
		"geometry": {"type": "polygon", "rings": [ring]},
		"core": {"center": [lat, lon], "size_km": START_SIZE_KM, "frame": "east_north"},
		"area_km2": snappedf(Geo.ring_area_km2(ring, radius_km), 0.0001),
		"cover_l8": GeoIndex.cover(lat, lon, INDEX_BUFFER_KM, radius_km),
		"expansions": [],
		"version": 1,
		"history": [{"version": 1, "at_unix": now_unix, "change": "founded", "by": player_id}],
		"claimed_at_unix": now_unix,
	}


## Smallest border-to-border distance (km) between a candidate ring and all
## territories; returns {distance_km, territory}. Uses the spatial index to
## skip far-away territories.
static func nearest_border(ring: Array, territories: Array, radius_km: float, ignore_owner: String = "") -> Dictionary:
	var rv := Geo.ring_vectors(ring)
	var c := Geo.from_vec3(rv[0] + rv[1] + rv[2] + rv[3])
	var cand_cover := GeoIndex.cover(c.x, c.y, INDEX_BUFFER_KM, radius_km)
	var best := {"distance_km": INF, "territory": {}}
	for t in territories:
		if ignore_owner != "" and t.get("owner_settlement_id", "") == ignore_owner:
			continue
		var tc: Array = t.get("cover_l8", [])
		if not tc.is_empty() and not GeoIndex.shares_cell(cand_cover, tc):
			continue # certainly farther away than the index buffer
		for r in rings_of(t):
			var d := Geo.ring_distance_km(rv, Geo.ring_vectors(r), radius_km)
			if d < best["distance_km"]:
				best = {"distance_km": d, "territory": t}
	return best


## Pairwise overlap check for validation (territories must never overlap).
static func overlapping_pairs(territories: Array) -> Array:
	var out: Array = []
	for i in territories.size():
		for k in range(i + 1, territories.size()):
			var a: Dictionary = territories[i]
			var b: Dictionary = territories[k]
			if not GeoIndex.shares_cell(a.get("cover_l8", []), b.get("cover_l8", [])):
				continue
			for ra in rings_of(a):
				for rb in rings_of(b):
					if Geo.rings_overlap(Geo.ring_vectors(ra), Geo.ring_vectors(rb)):
						out.append([a.get("territory_id", "?"), b.get("territory_id", "?")])
	return out
