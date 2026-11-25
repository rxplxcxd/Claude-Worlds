class_name LocalTerrain
extends RefCounted
## The land AROUND a settlement, derived from the planet (Geography): what
## lies at the site and in eight directions up to ~60 km (ocean, lake, river,
## mountains, forest, desert, ice) decides what surrounds the built area –
## the coast is on the side where the ocean really is, mountains rise towards
## the real highlands. Deterministic (seed = settlement id), scene-free, so a
## server and later systems (walking out, building, expansions – Phase 7,
## weather with seasons) use the same data.
##
## Result: {cells: {Vector2i: {tile, h, deco}}, climate: {...}, features: [...]}
##   tile: grass | meadow | dirt | sand | water | snow | rock
##   h:    height level 0..5 (stacked blocks; mountains)
##   deco: "" | tree | pine | bush | rock_small
## Climate (temperature, rainfall, zone) is stored with it so seasons and
## regional weather can build on it (docs/GEOGRAPHY_SYSTEM.md §Klima).

const PROBE_KM := [12.0, 30.0, 55.0]
const DIRS := [Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1)]


## Probes the planet around (lat, lon). Grid directions map to compass:
## grid +x = east-south-east, +y = south-south-west (isometric view, north up-right).
static func probe(lat: float, lon: float) -> Dictionary:
	var p := Geography.planet()
	if p == null:
		return {}
	var here := p.sample(lat, lon)
	var dirs := []
	for d in DIRS:
		var info := {"dir": d, "water_km": INF, "water": "", "mountain_km": INF, "rise_m": 0.0}
		# grid direction -> compass: x towards east, y towards south
		var compass := Vector2(d.x - d.y * 0.0, d.y).normalized()
		for km in PROBE_KM:
			var dlat: float = -compass.y * km / 111.0
			var dlon: float = compass.x * km / (111.0 * maxf(0.2, cos(deg_to_rad(lat))))
			var s := p.sample(clampf(lat + dlat, -89.0, 89.0), wrapf(lon + dlon, -180.0, 180.0))
			if s["biome"] in ["ocean", "lake"] and km < info["water_km"]:
				info["water_km"] = km
				info["water"] = s["biome"]
			if (s["biome"] == "mountain" or float(s["elevation_m"]) - float(here["elevation_m"]) > 500.0) and km < info["mountain_km"]:
				info["mountain_km"] = km
			info["rise_m"] = maxf(float(info["rise_m"]), float(s["elevation_m"]) - float(here["elevation_m"]))
		dirs.append(info)
	return {"here": here, "dirs": dirs}


## Climate summary for the site (for weather and seasons later).
static func climate_of(here: Dictionary, lat: float) -> Dictionary:
	var t := float(here.get("temperature_c", 12.0))
	var rain := float(here.get("rainfall", 0.5))
	var elev := maxf(0.0, float(here.get("elevation_m", 0.0)))
	var zone := "gemäßigt"
	if here.get("biome", "") == "ice" or t < -5.0:
		zone = "polar"
	elif t < 3.0:
		zone = "subpolar"
	elif here.get("biome", "") == "desert" or rain < 0.18:
		zone = "trocken"
	elif t > 22.0 and rain > 0.6:
		zone = "tropisch"
	elif t > 15.0 and rain < 0.45:
		zone = "mediterran"
	return {"zone": zone, "temperature_c": t, "rainfall": rain, "elevation_m": elev, "latitude": lat,
		"snow_possible": t < 12.0 or elev > 1200.0, "snow_cover": clampf((2.0 - t) / 10.0, 0.0, 1.0)}


## Builds the ring of `ring` tiles around a settlement grid of `size`.
static func generate(record: Dictionary, size: Vector2i, ring: int = 12) -> Dictionary:
	var pos: Dictionary = record.get("position", {})
	var lat := float(pos.get("lat", 48.0))
	var lon := float(pos.get("lon", 10.0))
	var pr := probe(lat, lon)
	var here: Dictionary = pr.get("here", {"biome": "plain", "temperature_c": 12.0, "rainfall": 0.5, "elevation_m": 200.0})
	var dirs: Array = pr.get("dirs", [])
	var climate := climate_of(here, lat)
	var biome := str(here.get("biome", "plain"))
	var rng := RandomNumberGenerator.new()
	rng.seed = SettlementCore.mix(str(record.get("settlement_id", "")) + "#terrain")
	var centre := Vector2(size) * 0.5
	var features := []
	# water: the nearest ocean/lake direction becomes a shore in the ring
	var water_dir := Vector2.ZERO
	var water_kind := ""
	var best := INF
	for d in dirs:
		if float(d["water_km"]) < best:
			best = float(d["water_km"])
			water_dir = d["dir"]
			water_kind = d["water"]
	if here.get("coastal", false) and water_dir == Vector2.ZERO:
		water_dir = Vector2(1, 1)
		water_kind = "ocean"
	var has_water: bool = water_dir != Vector2.ZERO and (best <= 30.0 or here.get("coastal", false))
	if has_water:
		features.append({"kind": "coast" if water_kind == "ocean" else "lake", "dir": [water_dir.x, water_dir.y], "probe_km": best})
	var river := bool(here.get("river", false))
	var river_axis := Vector2(1, -1).normalized() if rng.randf() < 0.5 else Vector2(1, 1).normalized()
	if river:
		features.append({"kind": "river"})
	# mountains: the direction with the strongest rise
	var mtn_dir := Vector2.ZERO
	var rise := 300.0
	for d in dirs:
		if float(d["rise_m"]) > rise:
			rise = float(d["rise_m"])
			mtn_dir = d["dir"]
	if biome in ["mountain", "hills"] and mtn_dir == Vector2.ZERO:
		mtn_dir = Vector2(-1, -1)
		rise = 600.0
	if mtn_dir != Vector2.ZERO:
		features.append({"kind": "mountains", "dir": [mtn_dir.x, mtn_dir.y], "rise_m": rise})
	var cells := {}
	for y in range(-ring, size.y + ring):
		for x in range(-ring, size.x + ring):
			if x >= 0 and y >= 0 and x < size.x and y < size.y:
				continue
			var c := Vector2i(x, y)
			var rel := (Vector2(x, y) + Vector2(0.5, 0.5) - centre)
			var out_d := _outside_distance(Vector2i(x, y), size)       # tiles beyond the settlement edge
			var n := _noise(x, y, rng.seed)
			var tile := "grass"
			var h := 0
			var deco := ""
			match biome:
				"desert":
					tile = "sand"
				"ice":
					tile = "snow"
				"tundra":
					tile = "snow" if n < climate["snow_cover"] + 0.2 else "meadow"
				_:
					tile = "meadow" if n > 0.62 else "grass"
			# mountains rise towards the real highlands
			if mtn_dir != Vector2.ZERO:
				var along := rel.normalized().dot(mtn_dir.normalized())
				if along > 0.35 and out_d >= 2:
					var hh := (out_d - 1) * along * clampf(rise / 900.0, 0.5, 1.6) * 0.7 + (n - 0.5) * 1.2
					h = clampi(int(round(hh)), 0, 5)
					if h >= 3:
						tile = "snow" if (climate["temperature_c"] - h * 3.0 < 2.0) else "rock"
					elif h >= 1:
						tile = "rock" if n > 0.55 else tile
			# shore: water beyond a beach on the side of the real water
			if has_water:
				var along_w := rel.normalized().dot(water_dir.normalized())
				var shore := 4.0 + (1.0 - along_w) * 10.0 + (n - 0.5) * 2.0
				if along_w > 0.3 and float(out_d) >= shore:
					tile = "water"
					h = 0
				elif along_w > 0.3 and float(out_d) >= shore - 1.6 and tile != "snow":
					tile = "sand"
					h = 0
			# river crossing the ring
			if river:
				var across := absf(rel.dot(Vector2(-river_axis.y, river_axis.x)))
				if across < 1.1 and out_d >= 1:
					tile = "water"
					h = 0
			if tile in ["grass", "meadow", "snow", "rock"] and h <= 2:
				var dens: float = {"forest": 0.34, "plain": 0.07, "hills": 0.12, "mountain": 0.08, "tundra": 0.05, "desert": 0.02, "ice": 0.0}.get(biome, 0.06)
				var r2 := _noise(x * 7 + 3, y * 5 + 1, rng.seed + 17)
				if out_d >= 1 and r2 < dens:
					deco = "pine" if biome in ["mountain", "tundra", "hills"] or climate["temperature_c"] < 6.0 or (biome == "forest" and r2 < dens * 0.4) else "tree"
				elif out_d >= 1 and r2 < dens + 0.05:
					deco = "bush" if tile != "rock" else "rock_small"
			if tile == "sand" and biome == "desert" and _noise(x * 3, y * 11, rng.seed + 5) < 0.04:
				deco = "rock_small"
			cells[c] = {"tile": tile, "h": h, "deco": deco}
	return {"cells": cells, "climate": climate, "features": features, "biome": biome, "ring": ring}


static func _outside_distance(c: Vector2i, size: Vector2i) -> int:
	var dx := 0
	if c.x < 0:
		dx = -c.x
	elif c.x >= size.x:
		dx = c.x - size.x + 1
	var dy := 0
	if c.y < 0:
		dy = -c.y
	elif c.y >= size.y:
		dy = c.y - size.y + 1
	return maxi(dx, dy)


## Smooth value noise 0..1 (cell-sized blobs).
static func _noise(x: int, y: int, seed: int) -> float:
	var fx := float(x) / 4.0
	var fy := float(y) / 4.0
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var tx := fx - ix
	var ty := fy - iy
	var a := _h(ix, iy, seed)
	var b := _h(ix + 1, iy, seed)
	var c := _h(ix, iy + 1, seed)
	var d := _h(ix + 1, iy + 1, seed)
	var sx := tx * tx * (3.0 - 2.0 * tx)
	var sy := ty * ty * (3.0 - 2.0 * ty)
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)


static func _h(x: int, y: int, seed: int) -> float:
	var n := x * 374761393 + y * 668265263 + seed * 1442695041
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0
