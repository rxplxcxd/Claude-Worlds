extends Node
## Autoload "Geography": access to the baked planet and location rules.
##
## The planet (PlanetData) is loaded lazily – only when the globe opens, a
## settlement is founded or an old save is migrated – so starting the game in
## a settlement costs nothing. Player-made state (settlements, territories)
## lives in WorldState; this node only answers questions about NATURE plus the
## site rules for founding (docs/GEOGRAPHY_SYSTEM.md §4).

const PLANET_DIR := "res://data/world/planet"
## Founding rules (proposal, docs/GEOGRAPHY_SYSTEM.md §7 [OFFEN] for final values).
const MIN_SETTLEMENT_DISTANCE_KM := 300.0
const MAX_FOUNDING_LATITUDE := 62.0
const IDEAL_NEIGHBOUR_KM := Vector2(400.0, 1600.0)

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
## Returns {valid, score (0..100), factors {name: 0..1}, reasons [], sample,
## region}. Factors: water, climate, soil, resources, terrain, neighbours.
func rate_site(lat: float, lon: float, settlements: Array, territories: Array, ignore_settlement_id: String = "") -> Dictionary:
	var p := planet()
	var out := {"valid": false, "score": 0, "factors": {}, "reasons": [], "sample": {}, "region": {}}
	if p == null:
		out["reasons"].append("Planetendaten fehlen.")
		return out
	var s := p.sample(lat, lon)
	var region := p.region(s["region_id"]) if s["region_id"] != "" else {}
	out["sample"] = s
	out["region"] = region
	var reasons: Array = out["reasons"]
	if not s["land"]:
		reasons.append("Hier ist Wasser.")
		return out
	var biome: String = s["biome"]
	if biome == "ice":
		reasons.append("Auf Eis kann keine Siedlung entstehen.")
	if biome == "mountain":
		reasons.append("Das Hochgebirge ist zu steil für eine Gründung.")
	if absf(lat) > MAX_FOUNDING_LATITUDE:
		reasons.append("Zu nah am Pol (max. %d° Breite)." % int(MAX_FOUNDING_LATITUDE))
	# Distance to other settlements and foreign territory.
	var nearest := INF
	for st in settlements:
		if st.get("settlement_id", "") == ignore_settlement_id or not st.has("position"):
			continue
		var pos: Dictionary = st["position"]
		nearest = minf(nearest, Geo.distance_km(lat, lon, pos["lat"], pos["lon"], p.radius_km))
	if nearest < MIN_SETTLEMENT_DISTANCE_KM:
		reasons.append("Zu nah an einer anderen Siedlung (%d km, mindestens %d km)." % [int(nearest), int(MIN_SETTLEMENT_DISTANCE_KM)])
	for t in territories:
		if t.get("owner_settlement_id", "") != ignore_settlement_id and (t.get("region_ids", []) as Array).has(s["region_id"]):
			reasons.append("Die Region gehört bereits zum Gebiet einer anderen Siedlung.")
	var f := {}
	# Water: river right here > lake/coast nearby > region access.
	var water := 0.2
	if _near_flag(p, lat, lon, "river", 1):
		water = 1.0
	elif _near_biome(p, lat, lon, PlanetData.Biome.LAKE, 1):
		water = 0.9
	elif s["coastal"] or _near_biome(p, lat, lon, PlanetData.Biome.OCEAN, 1):
		water = 0.8
	elif region.get("water_access", "none") != "none":
		water = 0.5
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
	f["terrain"] = {"plain": 1.0, "forest": 0.75, "hills": 0.6, "desert": 0.3, "tundra": 0.25, "mountain": 0.05, "ice": 0.0}.get(biome, 0.5)
	if nearest == INF:
		f["neighbours"] = 0.7 # first settlement: no trade partners yet, no conflict either
	elif nearest < MIN_SETTLEMENT_DISTANCE_KM:
		f["neighbours"] = 0.0
	else:
		f["neighbours"] = 1.0 if nearest <= IDEAL_NEIGHBOUR_KM.y else clampf(1.0 - (nearest - IDEAL_NEIGHBOUR_KM.y) / 3000.0, 0.3, 1.0)
	out["factors"] = f
	var weights := {"water": 0.24, "climate": 0.2, "soil": 0.18, "resources": 0.14, "terrain": 0.14, "neighbours": 0.1}
	var score := 0.0
	for k in weights.keys():
		score += weights[k] * float(f[k])
	out["score"] = int(round(score * 100.0))
	out["valid"] = reasons.is_empty()
	return out


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
