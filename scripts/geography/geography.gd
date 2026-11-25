extends Node
## Autoload "Geography": access to the baked planet and location rules.
##
## The planet (PlanetData) is loaded lazily – only when the globe opens, a
## settlement is founded or an old save is migrated – so starting the game in
## a settlement costs nothing. Player-made state (settlements, territories)
## lives in WorldState; this node only answers questions about NATURE plus the
## site rules for founding (docs/GEOGRAPHY_SYSTEM.md §4).

const PLANET_DIR := "res://data/world/planet"
## Paket 2.1 (DESIGN_DIRECTIVES.md §2–3): no geographic bans. The whole planet
## is settleable; the environment decides the DIFFICULTY. Only water cannot be
## founded on (there is no land). Distance rule: 20 km border to border
## (TerritoryGeometry.MIN_FOUNDING_GAP_KM).
const IDEAL_NEIGHBOUR_KM := Vector2(20.0, 400.0)
const DIFFICULTY_CLASSES := ["leicht", "mittel", "schwer", "extrem"]

var _planet: PlanetData


func planet() -> PlanetData:
	if _planet == null:
		var t := Time.get_ticks_msec()
		_planet = PlanetData.load_from(PLANET_DIR)
		if _planet == null:
			push_error("Geography: baked planet missing (%s) - run scripts/geography/planet_bake.gd" % PLANET_DIR)
		else:
			print("Geography: planet %s loaded in %d ms" % [_planet.name, Time.get_ticks_msec() - t])
	return _planet


func is_loaded() -> bool:
	return _planet != null


## Rates a founding site. `settlements` / `territories` = WorldState records.
## Returns {valid, score (0..100, attractiveness), factors {name: 0..1},
## reasons [] (why invalid), sample, region, difficulty {class, hardness,
## drivers, requirements, label}, nearest_border_km, nearest_name, ring}.
func rate_site(lat: float, lon: float, settlements: Array, territories: Array, ignore_settlement_id: String = "") -> Dictionary:
	var p := planet()
	var out := {"valid": false, "score": 0, "factors": {}, "reasons": [], "sample": {}, "region": {}, "difficulty": {}, "nearest_border_km": INF, "nearest_name": "", "ring": []}
	if p == null:
		out["reasons"].append("Planetendaten fehlen.")
		return out
	var s := p.sample(lat, lon)
	var region := p.region(s["region_id"]) if s["region_id"] != "" else {}
	out["sample"] = s
	out["region"] = region
	var reasons: Array = out["reasons"]
	var ring := TerritoryGeometry.start_square(lat, lon, p.radius_km)
	out["ring"] = ring
	# 1) Land: the start square must lie on land. (Planet cells are ~49 km;
	#    finer coasts follow with the terrain refinement in Phase 4.)
	var land_ok: bool = s["land"]
	for c in ring:
		land_ok = land_ok and p.is_land_at(float(c[0]), float(c[1]))
	if not land_ok:
		reasons.append("Hier ist Wasser – eine Siedlung braucht Land.")
	# The neutral property of a world landmark (Concordium) cannot be part of a
	# settlement territory. Only the exact property – the land around it
	# follows the normal rules (WORLD_COUNCIL.md §3).
	var lm := Landmarks.property_overlapping(ring, p.radius_km)
	if not lm.is_empty():
		reasons.append("Das Gelände des %s ist neutrales Gebiet – es kann zu keiner Siedlung gehören." % lm.get("site_name", ""))
		out["landmark"] = lm["landmark_id"]
	# 2) 20 km between territory borders (geodesic), no overlap.
	var nb := TerritoryGeometry.nearest_border(ring, territories, p.radius_km, ignore_settlement_id)
	var gap: float = nb["distance_km"]
	out["nearest_border_km"] = gap
	if not nb["territory"].is_empty():
		var owner := _settlement_name(settlements, nb["territory"].get("owner_settlement_id", ""))
		out["nearest_name"] = owner
		if gap <= 0.0:
			reasons.append("Der Ort liegt im Gebiet von %s." % owner)
		elif gap < TerritoryGeometry.MIN_FOUNDING_GAP_KM:
			reasons.append("Nur %s km bis zur Gebietsgrenze von %s – mindestens %d km nötig." % [_km(gap), owner, int(TerritoryGeometry.MIN_FOUNDING_GAP_KM)])
	if not land_ok:
		out["valid"] = false
		return out
	# 3) Attractiveness factors (unchanged idea from Phase 2).
	var f := {}
	var biome: String = s["biome"]
	var water := 0.2
	if _near_flag(p, lat, lon, "river", 1):
		water = 1.0
	elif _near_biome(p, lat, lon, PlanetData.Biome.LAKE, 1):
		water = 0.9
	elif s["coastal"] or _near_biome(p, lat, lon, PlanetData.Biome.OCEAN, 1):
		water = 0.8
	elif region.get("water_access", "none") != "none":
		water = 0.5
	if biome == "ice":
		water = maxf(water, 0.35) # ice can be melted – at an energy cost
	f["water"] = water
	var t_c: float = s["temperature_c"]
	var rain: float = s["rainfall"]
	f["climate"] = clampf(1.0 - absf(t_c - 14.0) / 20.0, 0.0, 1.0) * clampf(1.0 - absf(rain - 0.55) * 1.6, 0.2, 1.0)
	var soil := 0.0
	for r in region.get("resources", []):
		if r["type"] == "fertile_soil":
			soil = float(r["abundance"])
	f["soil"] = clampf(soil * 0.7 + (0.3 if biome == "plain" else (0.15 if biome == "forest" else 0.0)), 0.0, 1.0)
	var res_sum := 0.0
	var res: Array = region.get("resources", [])
	for k in mini(4, res.size()):
		res_sum += float(res[k]["abundance"])
	f["resources"] = clampf(res_sum / 3.0, 0.0, 1.0)
	f["terrain"] = {"plain": 1.0, "forest": 0.75, "hills": 0.6, "desert": 0.3, "tundra": 0.25, "mountain": 0.1, "ice": 0.05}.get(biome, 0.5)
	if gap == INF:
		f["neighbours"] = 0.7 # first settlement: no partners yet, no conflict either
	elif gap < TerritoryGeometry.MIN_FOUNDING_GAP_KM:
		f["neighbours"] = 0.0
	else:
		f["neighbours"] = 1.0 if gap <= IDEAL_NEIGHBOUR_KM.y else clampf(1.0 - (gap - IDEAL_NEIGHBOUR_KM.y) / 3000.0, 0.3, 1.0)
	out["factors"] = f
	var weights := {"water": 0.24, "climate": 0.2, "soil": 0.18, "resources": 0.14, "terrain": 0.14, "neighbours": 0.1}
	var score := 0.0
	for k in weights.keys():
		score += weights[k] * float(f[k])
	out["score"] = int(round(score * 100.0))
	out["difficulty"] = difficulty(s, region, f, gap)
	out["valid"] = reasons.is_empty()
	return out


## Founding difficulty from the environment (TERRITORY_SYSTEM.md §6). No site
## on land is forbidden; harder sites need more resources, technology and
## logistics. Returns {class, index 0..3, hardness 0..1, drivers {name: 0..1},
## requirements [text], label}.
func difficulty(s: Dictionary, region: Dictionary, f: Dictionary, gap_km: float) -> Dictionary:
	var t: float = s["temperature_c"]
	var biome: String = s["biome"]
	var elev: float = maxf(float(s["elevation_m"]), 0.0)
	var d := {}
	d["cold_heat"] = clampf((8.0 - t) / 30.0, 0.0, 1.0) + clampf((t - 30.0) / 12.0, 0.0, 1.0)
	d["water"] = clampf(1.0 - float(f.get("water", 0.0)), 0.0, 1.0)
	d["food"] = clampf(1.0 - float(f.get("soil", 0.0)) * 1.4, 0.0, 1.0)
	d["terrain"] = {"plain": 0.0, "forest": 0.2, "hills": 0.35, "desert": 0.45, "tundra": 0.5, "mountain": 0.8, "ice": 0.9}.get(biome, 0.3) + clampf((elev - 2500.0) / 3000.0, 0.0, 0.3)
	d["energy"] = clampf(float(d["cold_heat"]) * 1.1 + (0.2 if biome == "ice" else 0.0), 0.0, 1.0)
	var access := 0.65
	if s["coastal"] or s["river"]:
		access = 0.25
	elif region.get("water_access", "none") != "none":
		access = 0.45
	d["transport"] = access
	d["resources"] = clampf(1.0 - float(f.get("resources", 0.0)), 0.0, 1.0)
	var w := {"cold_heat": 0.22, "water": 0.14, "food": 0.18, "terrain": 0.16, "energy": 0.12, "transport": 0.1, "resources": 0.08}
	var h := 0.0
	for k in w.keys():
		h += w[k] * clampf(float(d[k]), 0.0, 1.0)
	var idx := 0
	if h >= 0.62:
		idx = 3
	elif h >= 0.45:
		idx = 2
	elif h >= 0.3:
		idx = 1
	var req: Array = []
	if float(d["cold_heat"]) > 0.5:
		req.append("Isolierte, beheizte Gebäude und Kälteschutz")
	if float(d["energy"]) > 0.55:
		req.append("Hoher Energiebedarf (Heizung%s)" % (", Eisschmelze" if biome == "ice" else ""))
	if float(d["water"]) > 0.6:
		req.append("Wasserversorgung aufwendig (Brunnen, Leitungen oder Schmelze)")
	if float(d["food"]) > 0.7:
		req.append("Kaum eigene Landwirtschaft – Nahrung muss eingeführt oder in Gewächshäusern erzeugt werden")
	if float(d["terrain"]) > 0.6:
		req.append("Schwieriges Gelände – höhere Baukosten")
	if float(d["transport"]) > 0.6:
		req.append("Abgelegen – lange, teure Versorgungswege")
	if t > 32.0:
		req.append("Hitzeschutz und Kühlung")
	return {"class": DIFFICULTY_CLASSES[idx], "index": idx, "hardness": snappedf(h, 0.01), "drivers": d, "requirements": req,
		"label": ["Leichter Start", "Mittlerer Aufwand", "Schwieriger Standort", "Extremer Standort"][idx]}


func _settlement_name(settlements: Array, settlement_id: String) -> String:
	for st in settlements:
		if st.get("settlement_id", "") == settlement_id:
			return str(st.get("name", "einer Siedlung"))
	return "einer Siedlung"


static func _km(v: float) -> String:
	return ("%.1f" % v).replace(".", ",")


## Best valid site on the planet (deterministic): region centres and a few
## sample cells per region are rated, the highest score wins.
func best_site(settlements: Array, territories: Array) -> Dictionary:
	var p := planet()
	if p == null:
		return {}
	var best := {}
	var best_score := -1
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed + 101
	for region in p.regions:
		var c: Vector2 = region["center"]
		var candidates: Array[Vector2] = [c]
		for k in 3:
			candidates.append(Vector2(c.x + rng.randf_range(-3.0, 3.0), c.y + rng.randf_range(-4.0, 4.0)))
		for cand in candidates:
			var r := rate_site(cand.x, cand.y, settlements, territories)
			if r["valid"] and r["sample"]["region_id"] == region["region_id"] and int(r["score"]) > best_score:
				best_score = r["score"]
				best = r
	return best


## Several good, DIFFERENT founding sites (best first), at least
## `min_sep_km` apart, one per natural region at most. The globe cycles
## through them with the "Vorschlag" button.
func good_sites(settlements: Array, territories: Array, count: int = 30, min_sep_km: float = 400.0) -> Array:
	var p := planet()
	if p == null:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = p.seed + 101
	var all := []
	for region in p.regions:
		var c: Vector2 = region["center"]
		var candidates: Array[Vector2] = [c]
		for k in 3:
			candidates.append(Vector2(c.x + rng.randf_range(-3.0, 3.0), c.y + rng.randf_range(-4.0, 4.0)))
		var best := {}
		for cand in candidates:
			var r := rate_site(cand.x, cand.y, settlements, territories)
			if r["valid"] and r["sample"]["region_id"] == region["region_id"] and (best.is_empty() or int(r["score"]) > int(best["score"])):
				best = r
		if not best.is_empty():
			all.append(best)
	all.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	var out := []
	for r in all:
		var s: Dictionary = r["sample"]
		var ok := true
		for o in out:
			if Geo.distance_km(s["lat"], s["lon"], o["sample"]["lat"], o["sample"]["lon"], p.radius_km) < min_sep_km:
				ok = false
				break
		if ok:
			out.append(r)
			if out.size() >= count:
				break
	return out


func _near_flag(p: PlanetData, lat: float, lon: float, flag: String, radius: int) -> bool:
	var cx := Geo.lon_col(lon, p.width)
	var cy := Geo.lat_row(lat, p.height)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var y := cy + dy
			if y < 0 or y >= p.height:
				continue
			if flag == "river" and p.river[p.index(cx + dx, y)] == 1:
				return true
	return false


func _near_biome(p: PlanetData, lat: float, lon: float, b: int, radius: int) -> bool:
	var cx := Geo.lon_col(lon, p.width)
	var cy := Geo.lat_row(lat, p.height)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var y := cy + dy
			if y >= 0 and y < p.height and p.biome[p.index(cx + dx, y)] == b:
				return true
	return false
