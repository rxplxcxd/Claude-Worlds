class_name PlanetGenerator
extends RefCounted
## Deterministic planet genesis: nature only (WORLD_DESIGN.md §1).
##
## Same seed + same GENERATOR_VERSION = same planet on every device and on the
## future server. Changing the algorithm REQUIRES a new version number and a
## migration of stored positions/region IDs (docs/GEOGRAPHY_SYSTEM.md §6).
##
## Steps: elevation (3D noise on the sphere, no pole distortion) → sea level by
## land fraction → oceans/lakes (connected components) → distance to the sea →
## temperature (latitude + altitude) and rainfall (noise + coast) → rivers
## (steepest descent) → biomes → continents (land components, small islands
## join the nearest continent) → regions (seeded flood fill over land) →
## region statistics, names and resources.

const GENERATOR_VERSION := 2
const DEFAULT_WIDTH := 512
const DEFAULT_HEIGHT := 256
const LAND_FRACTION := 0.34
## Land masses smaller than this share of all land become islands.
const CONTINENT_MIN_SHARE := 0.04
const REGION_SPACING_KM := 620.0
const RIVER_COUNT := 70

const N4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const N8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]

const SYL_A := ["Al", "Bel", "Cor", "Dra", "El", "Fen", "Gal", "Har", "Ise", "Kal", "Lor", "Mar", "Nor", "Or", "Pel", "Quen", "Ros", "Sel", "Tar", "Ul", "Val", "Wen", "Yr", "Zan", "Ash", "Bri", "Cal", "Del", "Eri", "Fal"]
const SYL_B := ["a", "e", "i", "o", "u", "ia", "ea", "or", "an", "en", "ir", "ar", "el", "on", "is"]
const SYL_C := ["dor", "ris", "nas", "thal", "mir", "vek", "lin", "gard", "wen", "ros", "dal", "tia", "nor", "mar", "sund", "heim", "ven", "lis", "brand", "rok"]

var _rng := RandomNumberGenerator.new()
var _used_names := {}
var _land_comp := PackedInt32Array()


## Generates the planet described in data/world/genesis.json ("planet").
func generate(spec: Dictionary, width: int = DEFAULT_WIDTH, height: int = DEFAULT_HEIGHT) -> PlanetData:
	var p := PlanetData.new()
	p.planet_id = spec.get("planet_id", "pln_aurel")
	p.name = spec.get("planet_name", "Aurel")
	p.seed = int(spec.get("seed", 1))
	p.radius_km = float(spec.get("radius_km", 4000.0))
	p.generator_version = GENERATOR_VERSION
	p.width = width
	p.height = height
	_rng.seed = p.seed
	_used_names.clear()
	var n := width * height
	var raw := _elevation(p)
	_sea_level(p, raw)
	var water := _water_bodies(p, raw)
	var sea_dist := _distance_to_ocean(p, water)
	_climate(p, raw, sea_dist)
	_rivers(p, water)
	_biomes(p, water)
	_continents(p)
	_regions(p)
	return p


# --- elevation -------------------------------------------------------------

func _elevation(p: PlanetData) -> PackedFloat32Array:
	var cont := FastNoiseLite.new()
	cont.seed = p.seed
	cont.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	cont.fractal_type = FastNoiseLite.FRACTAL_FBM
	cont.fractal_octaves = 5
	cont.frequency = 0.85
	# Domain warp (inside the noise library) gives organic coastlines.
	cont.domain_warp_enabled = true
	cont.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	cont.domain_warp_amplitude = 0.55
	cont.domain_warp_frequency = 1.1
	cont.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	cont.domain_warp_fractal_octaves = 2
	var ridge := FastNoiseLite.new()
	ridge.seed = p.seed + 13
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4
	ridge.frequency = 1.7
	var raw := PackedFloat32Array()
	raw.resize(p.width * p.height)
	for y in p.height:
		var lat := Geo.row_lat(y, p.height)
		# Polar seas: keeps the poles mostly ocean with sea ice coasts.
		var polar := smoothstep(58.0, 85.0, absf(lat)) * 0.42
		for x in p.width:
			var v := Geo.to_vec3(lat, Geo.col_lon(x, p.width))
			var e := cont.get_noise_3dv(v)
			var r := ridge.get_noise_3dv(v)
			# Mountain ridges only rise on land-ish ground.
			e += maxf(r, 0.0) * 0.26 * clampf((e + 0.04) * 4.0, 0.0, 1.0)
			raw[y * p.width + x] = e - polar
	return raw


func _sea_level(p: PlanetData, raw: PackedFloat32Array) -> void:
	# Area-weighted quantile so the land FRACTION (not cell count) matches.
	var samples: Array = []
	for y in p.height:
		var wgt := cos(deg_to_rad(Geo.row_lat(y, p.height)))
		var step := maxi(1, int(round(1.0 / maxf(wgt, 0.05))))
		for x in range(0, p.width, step):
			samples.append(raw[y * p.width + x])
	samples.sort()
	p.sea_level_raw = samples[int(samples.size() * (1.0 - LAND_FRACTION))]
	var hi: float = samples[samples.size() - 1]
	var lo: float = samples[0]
	p.elevation_m.resize(raw.size())
	for i in raw.size():
		var e := raw[i]
		if e >= p.sea_level_raw:
			p.elevation_m[i] = pow((e - p.sea_level_raw) / maxf(hi - p.sea_level_raw, 0.001), 1.35) * 4800.0 + 2.0
		else:
			p.elevation_m[i] = -pow((p.sea_level_raw - e) / maxf(p.sea_level_raw - lo, 0.001), 0.8) * 5200.0 - 2.0


## 0 = land, 1 = ocean, 2 = lake. Large connected water bodies are oceans.
func _water_bodies(p: PlanetData, raw: PackedFloat32Array) -> PackedByteArray:
	var n := raw.size()
	var water := PackedByteArray()
	water.resize(n)
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var sizes: Array[int] = []
	for start in n:
		if p.elevation_m[start] >= 0.0 or comp[start] >= 0:
			continue
		var id := sizes.size()
		var count := _flood(p, start, id, comp, func(i: int) -> bool: return p.elevation_m[i] < 0.0, N4)
		sizes.append(count)
	for i in n:
		if comp[i] >= 0:
			water[i] = 1 if sizes[comp[i]] > n / 200 else 2
	return water


## Generic flood fill (x wraps around, y is clamped). Returns the cell count.
func _flood(p: PlanetData, start: int, id: int, comp: PackedInt32Array, accept: Callable, dirs: Array) -> int:
	var queue := PackedInt32Array([start])
	comp[start] = id
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % p.width
		var y := i / p.width
		for d in dirs:
			var ny: int = y + d.y
			if ny < 0 or ny >= p.height:
				continue
			var j := ny * p.width + posmod(x + d.x, p.width)
			if comp[j] < 0 and accept.call(j):
				comp[j] = id
				queue.append(j)
	return queue.size()


func _distance_to_ocean(p: PlanetData, water: PackedByteArray) -> PackedInt32Array:
	var n := water.size()
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var queue := PackedInt32Array()
	for i in n:
		if water[i] == 1:
			dist[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % p.width
		var y := i / p.width
		for d in N4:
			var ny: int = y + d.y
			if ny < 0 or ny >= p.height:
				continue
			var j := ny * p.width + posmod(x + d.x, p.width)
			if dist[j] < 0:
				dist[j] = dist[i] + 1
				queue.append(j)
	p.coastal.resize(n)
	for i in n:
		if water[i] == 0 and dist[i] == 1:
			p.coastal[i] = 1
	return dist


func _climate(p: PlanetData, raw: PackedFloat32Array, sea_dist: PackedInt32Array) -> void:
	var wet := FastNoiseLite.new()
	wet.seed = p.seed + 29
	wet.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wet.fractal_octaves = 3
	wet.frequency = 1.4
	var n := raw.size()
	p.temperature_c.resize(n)
	p.rainfall.resize(n)
	for y in p.height:
		var lat := Geo.row_lat(y, p.height)
		var t_lat := 29.0 - 52.0 * pow(absf(lat) / 90.0, 1.25)
		# Dry belts around 25° (subtropical highs), wet tropics and mid-latitudes.
		var belt := 0.2 * cos(deg_to_rad(minf(absf(lat), 60.0) * 7.2)) - 0.03
		for x in p.width:
			var i := y * p.width + x
			var alt := maxf(p.elevation_m[i], 0.0)
			p.temperature_c[i] = t_lat - alt * 0.0065
			var v := Geo.to_vec3(lat, Geo.col_lon(x, p.width))
			var r := 0.5 + wet.get_noise_3dv(v) * 0.55 + belt
			r += 0.25 * exp(-float(maxi(sea_dist[i], 0)) / 6.0) # moist coasts
			p.rainfall[i] = clampf(r, 0.0, 1.0)


func _rivers(p: PlanetData, water: PackedByteArray) -> void:
	p.river.resize(water.size())
	var made := 0
	var tries := 0
	while made < RIVER_COUNT and tries < RIVER_COUNT * 40:
		tries += 1
		var i := _rng.randi_range(0, water.size() - 1)
		if water[i] != 0 or p.elevation_m[i] < 900.0 or p.rainfall[i] < 0.45 or p.temperature_c[i] < -8.0:
			continue
		var path := PackedInt32Array()
		var cur := i
		var reached := false
		for step in 400:
			path.append(cur)
			if water[cur] != 0 or (p.river[cur] == 1 and step > 0):
				reached = true
				break
			var x := cur % p.width
			var y := cur / p.width
			var best := -1
			var best_e := p.elevation_m[cur]
			for d in N8:
				var ny: int = y + d.y
				if ny < 0 or ny >= p.height:
					continue
				var j := ny * p.width + posmod(x + d.x, p.width)
				if p.elevation_m[j] < best_e:
					best_e = p.elevation_m[j]
					best = j
			if best < 0:
				# Sink: the river ends in a small lake.
				water[cur] = 2
				reached = true
				break
			cur = best
		if reached and path.size() >= 6:
			for c in path:
				if water[c] == 0:
					p.river[c] = 1
			made += 1


func _biomes(p: PlanetData, water: PackedByteArray) -> void:
	var n := water.size()
	p.biome.resize(n)
	for i in n:
		if water[i] == 1:
			p.biome[i] = PlanetData.Biome.OCEAN
			continue
		if water[i] == 2:
			p.biome[i] = PlanetData.Biome.LAKE
			continue
		var t := p.temperature_c[i]
		var e := p.elevation_m[i]
		var r := p.rainfall[i]
		var b := PlanetData.Biome.PLAIN
		if t < -9.0:
			b = PlanetData.Biome.ICE
		elif e > 2300.0:
			b = PlanetData.Biome.MOUNTAIN
		elif t < 0.5:
			b = PlanetData.Biome.TUNDRA
		elif e > 1050.0:
			b = PlanetData.Biome.HILLS
		elif r < 0.36 and t > 11.0:
			b = PlanetData.Biome.DESERT
		elif r > 0.6:
			b = PlanetData.Biome.FOREST
		p.biome[i] = b


# --- continents & regions --------------------------------------------------

func _continents(p: PlanetData) -> void:
	var n := p.biome.size()
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var areas: Array = []
	var total := 0.0
	for start in n:
		if not p.is_land(start) or comp[start] >= 0:
			continue
		var id := areas.size()
		_flood(p, start, id, comp, func(i: int) -> bool: return p.is_land(i), N8)
		areas.append(0.0)
	_land_comp = comp
	for i in n:
		if comp[i] >= 0:
			var a := cos(deg_to_rad(Geo.row_lat(i / p.width, p.height)))
			areas[comp[i]] += a
			total += a
	# Big land masses become continents, largest first.
	var big: Array = []
	for id in areas.size():
		if areas[id] >= total * CONTINENT_MIN_SHARE:
			big.append(id)
	big.sort_custom(func(a, b): return areas[a] > areas[b])
	var cont_index := {}
	for k in big.size():
		cont_index[big[k]] = k
	p.continent_of.resize(n)
	var queue := PackedInt32Array()
	for i in n:
		if comp[i] >= 0 and cont_index.has(comp[i]):
			p.continent_of[i] = cont_index[comp[i]] + 1
			queue.append(i)
	# Small islands join the nearest continent (spread over all cells).
	var head := 0
	var seen := PackedByteArray()
	seen.resize(n)
	for i in queue:
		seen[i] = 1
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % p.width
		var y := i / p.width
		for d in N4:
			var ny: int = y + d.y
			if ny < 0 or ny >= p.height:
				continue
			var j := ny * p.width + posmod(x + d.x, p.width)
			if seen[j] == 0:
				seen[j] = 1
				p.continent_of[j] = p.continent_of[i]
				queue.append(j)
	for i in n:
		if not p.is_land(i):
			p.continent_of[i] = 0
	for k in big.size():
		p.continents.append({
			"continent_id": "cnt_%02d" % (k + 1),
			"name": _unique_name(3),
			"area_km2": 0.0,
			"region_ids": [],
			"center": Vector2.ZERO,
			"_sum": Vector3.ZERO,
		})


func _regions(p: PlanetData) -> void:
	var n := p.biome.size()
	# Seeds: random land cells, at least REGION_SPACING_KM apart.
	var seeds: Array[int] = []
	var seed_vecs: Array[Vector3] = []
	var min_angle := REGION_SPACING_KM / p.radius_km
	for attempt in 6000:
		var i := _rng.randi_range(0, n - 1)
		if not p.is_land(i):
			continue
		var ll := p.cell_lat_lon(i)
		var v := Geo.to_vec3(ll.x, ll.y)
		var ok := true
		for s in seed_vecs:
			if s.angle_to(v) < min_angle:
				ok = false
				break
		if ok:
			seeds.append(i)
			seed_vecs.append(v)
	# Regions = Voronoi cells on the sphere: every land cell belongs to the
	# nearest seed (great-circle distance, slightly noise-warped so borders
	# look natural) on the SAME land mass; land masses without a seed take
	# the nearest seed anywhere.
	var seeds_by_comp := {}
	for k in seeds.size():
		var c := _land_comp[seeds[k]]
		if not seeds_by_comp.has(c):
			seeds_by_comp[c] = []
		seeds_by_comp[c].append(k)
	var all_seeds: Array = range(seeds.size())
	var border_noise := FastNoiseLite.new()
	border_noise.seed = p.seed + 53
	border_noise.frequency = 4.0
	border_noise.fractal_octaves = 2
	p.region_of.resize(n)
	for i in n:
		if not p.is_land(i):
			continue
		var ll := p.cell_lat_lon(i)
		var v := Geo.to_vec3(ll.x, ll.y)
		var wobble := border_noise.get_noise_3dv(v) * 0.035
		var cands: Array = seeds_by_comp.get(_land_comp[i], all_seeds)
		var best_k := 0
		var best_d := INF
		for k in cands:
			var d := v.angle_to(seed_vecs[k]) * (1.0 + wobble * (1.0 if k % 2 == 0 else -1.0))
			if d < best_d:
				best_d = d
				best_k = k
		p.region_of[i] = best_k + 1
	# Statistics.
	var stats: Array = []
	for k in seeds.size():
		stats.append({"area": 0.0, "sum": Vector3.ZERO, "elev": 0.0, "temp": 0.0, "rain": 0.0, "biomes": {}, "coast": 0, "river": 0, "lake": 0, "cells": 0, "cont": {}})
	var cell_km2 := (2.0 * PI * p.radius_km / p.width) * (PI * p.radius_km / p.height)
	for i in n:
		var r := p.region_of[i]
		if r == 0:
			continue
		var s: Dictionary = stats[r - 1]
		var ll := p.cell_lat_lon(i)
		var a := cos(deg_to_rad(ll.x))
		s["area"] += a * cell_km2
		s["sum"] += Geo.to_vec3(ll.x, ll.y) * a
		s["elev"] += p.elevation_m[i] * a
		s["temp"] += p.temperature_c[i] * a
		s["rain"] += p.rainfall[i] * a
		var b: String = PlanetData.BIOME_IDS[p.biome[i]]
		s["biomes"][b] = s["biomes"].get(b, 0.0) + a
		s["cells"] += 1
		s["coast"] += p.coastal[i]
		s["river"] += p.river[i]
		s["cont"][p.continent_of[i]] = s["cont"].get(p.continent_of[i], 0) + 1
		var x := i % p.width
		var y := i / p.width
		for d in N4:
			var ny: int = y + d.y
			if ny >= 0 and ny < p.height and p.biome[ny * p.width + posmod(x + d.x, p.width)] == PlanetData.Biome.LAKE:
				s["lake"] += 1
				break
	var res_noise := FastNoiseLite.new()
	res_noise.seed = p.seed + 41
	res_noise.frequency = 2.2
	for k in seeds.size():
		var s: Dictionary = stats[k]
		var w: float = maxf(s["area"] / cell_km2, 0.0001)
		var center := Geo.from_vec3(s["sum"])
		var biomes: Dictionary = s["biomes"]
		var dominant := ""
		var best := -1.0
		for b in biomes.keys():
			if biomes[b] > best:
				best = biomes[b]
				dominant = b
		var cells: int = s["cells"]
		var coast_share := float(s["coast"]) / maxf(cells, 1)
		var terrain := dominant
		if dominant in ["plain", "lake"] and coast_share > 0.3:
			terrain = "coast"
		var water_access := "none"
		if s["coast"] > 0:
			water_access = "coast"
		elif s["lake"] > 0:
			water_access = "lake"
		elif s["river"] > 0:
			water_access = "river"
		var cont_idx := 0
		var cbest := -1
		for c in s["cont"].keys():
			if s["cont"][c] > cbest:
				cbest = s["cont"][c]
				cont_idx = c
		var region := {
			"region_id": "reg_%03d" % (k + 1),
			"continent_id": p.continents[cont_idx - 1]["continent_id"] if cont_idx > 0 else "",
			"name": "",
			"center": center,
			"area_km2": roundf(s["area"]),
			"terrain": terrain,
			"biome_shares": _shares(biomes, w),
			"elevation_m": roundf(s["elev"] / w),
			"climate": {"temperature_c": snappedf(s["temp"] / w, 0.1), "rainfall": snappedf(s["rain"] / w, 0.01), "zone": _zone(s["temp"] / w, s["rain"] / w)},
			"water_access": water_access,
			"river_cells": s["river"],
			"coast_share": snappedf(coast_share, 0.01),
			"resources": [],
			"development": "wild",
			"territory_id": "",
		}
		region["resources"] = _resources(region, biomes, w, res_noise)
		region["name"] = _region_name(terrain)
		p.regions.append(region)
		if cont_idx > 0:
			var c: Dictionary = p.continents[cont_idx - 1]
			c["region_ids"].append(region["region_id"])
			c["area_km2"] += region["area_km2"]
			c["_sum"] += Geo.to_vec3(center.x, center.y) * region["area_km2"]
	for c in p.continents:
		c["center"] = Geo.from_vec3(c["_sum"])
		c.erase("_sum")
		c["area_km2"] = roundf(c["area_km2"])


func _grow(p: PlanetData, queue: PackedInt32Array, land_only: bool) -> void:
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % p.width
		var y := i / p.width
		for d in N4:
			var ny: int = y + d.y
			if ny < 0 or ny >= p.height:
				continue
			var j := ny * p.width + posmod(x + d.x, p.width)
			if p.region_of[j] != 0:
				continue
			if land_only and not p.is_land(j):
				continue
			p.region_of[j] = p.region_of[i]
			queue.append(j)


static func _shares(biomes: Dictionary, total: float) -> Dictionary:
	var out := {}
	for b in biomes.keys():
		out[b] = snappedf(biomes[b] / total, 0.01)
	return out


static func _zone(t: float, r: float) -> String:
	if t < -5.0:
		return "polar"
	if t < 4.0:
		return "subpolar"
	if t < 14.0:
		return "gemäßigt" if r > 0.4 else "kühl-trocken"
	if t < 21.0:
		return "warm-gemäßigt" if r > 0.4 else "steppe"
	return "tropisch" if r > 0.5 else "trocken-heiß"


func _resources(region: Dictionary, biomes: Dictionary, w: float, noise: FastNoiseLite) -> Array:
	var c: Vector2 = region["center"]
	var v := Geo.to_vec3(c.x, c.y)
	var share := func(b: String) -> float: return biomes.get(b, 0.0) / w
	var rnd := func(k: float) -> float: return 0.5 + 0.5 * noise.get_noise_3dv(v * (1.0 + k))
	var out: Array = []
	var add := func(type: String, amount: float) -> void:
		if amount >= 0.15:
			out.append({"type": type, "abundance": snappedf(clampf(amount, 0.0, 1.0), 0.01)})
	add.call("wood", share.call("forest") * 1.4 + share.call("plain") * 0.2)
	add.call("stone", share.call("hills") * 1.2 + share.call("mountain"))
	add.call("ore", (share.call("mountain") + share.call("hills") * 0.5) * rnd.call(1.0) * 1.6)
	add.call("fertile_soil", (share.call("plain") * 1.1 + share.call("forest") * 0.3) * clampf(region["climate"]["rainfall"] * 1.6, 0.0, 1.0) * (1.0 if region["climate"]["temperature_c"] > 4.0 else 0.3))
	add.call("fish", float(region["coast_share"]) * 2.5)
	add.call("fresh_water", 0.8 if region["water_access"] in ["river", "lake"] else (0.4 if region["river_cells"] > 0 else 0.0))
	add.call("clay", (0.5 if region["river_cells"] > 0 else 0.0) * rnd.call(2.0) * 1.5)
	add.call("sand", share.call("desert") * 1.2 + float(region["coast_share"]) * 0.6)
	add.call("salt", share.call("desert") * rnd.call(3.0) * 1.4)
	add.call("game", (share.call("forest") + share.call("tundra") * 0.6) * 0.9)
	out.sort_custom(func(a, b): return a["abundance"] > b["abundance"])
	return out


func _unique_name(parts: int) -> String:
	for attempt in 50:
		var s: String = SYL_A[_rng.randi_range(0, SYL_A.size() - 1)]
		if parts >= 3 or _rng.randf() < 0.5:
			s += SYL_B[_rng.randi_range(0, SYL_B.size() - 1)]
		s += SYL_C[_rng.randi_range(0, SYL_C.size() - 1)]
		if not _used_names.has(s):
			_used_names[s] = true
			return s
	return "Region %d" % _used_names.size()


func _region_name(terrain: String) -> String:
	var base := _unique_name(2)
	match terrain:
		"plain": return base + "-Ebene"
		"hills": return base + "er Hügelland"
		"mountain": return base + "-Gebirge"
		"forest": return base + "er Wald"
		"coast": return base + "-Küste"
		"desert": return base + "-Wüste"
		"tundra": return base + "-Tundra"
		"ice": return base + "-Eisfeld"
	return base
