class_name PlanetData
extends RefCounted
## Generated geography of the planet (pure data, no nodes).
##
## Produced deterministically by PlanetGenerator from the world seed, so every
## client and the future server derive the identical planet; only player-made
## state (settlements, territories) is stored (WorldState / Firestore).
## Grid: equirectangular, `width` × `height` cells (see Geo).

enum Biome { OCEAN, LAKE, ICE, TUNDRA, MOUNTAIN, HILLS, DESERT, FOREST, PLAIN }

const BIOME_IDS := ["ocean", "lake", "ice", "tundra", "mountain", "hills", "desert", "forest", "plain"]
const BIOME_LABELS := ["Ozean", "See", "Eis", "Tundra", "Gebirge", "Hügelland", "Wüste", "Wald", "Ebene"]
const TERRAIN_LABELS := {
	"plain": "Ebene", "hills": "Hügelland", "mountain": "Gebirge", "forest": "Wald", "coast": "Küste",
	"desert": "Wüste", "tundra": "Tundra", "ice": "Eisfeld",
}
const WATER_LABELS := {"none": "kein", "river": "Fluss", "lake": "See", "coast": "Küste"}
const RESOURCE_LABELS := {
	"wood": "Holz", "stone": "Stein", "ore": "Erz", "fertile_soil": "Fruchtbarer Boden", "fish": "Fisch",
	"fresh_water": "Süßwasser", "clay": "Ton", "sand": "Sand", "salt": "Salz", "game": "Wild",
}
const DEVELOPMENT_LABELS := {"wild": "Wildnis", "sparse": "dünn erschlossen", "settled": "besiedelt", "urban": "städtisch"}

var planet_id := ""
var name := ""
var seed := 0
var generator_version := 0
var radius_km := 4000.0
var width := 0
var height := 0
var sea_level_raw := 0.0

## Per cell (index = y * width + x).
var elevation_m := PackedFloat32Array()
var temperature_c := PackedFloat32Array()
var rainfall := PackedFloat32Array() # 0..1
var biome := PackedByteArray()
var river := PackedByteArray() # 1 = river cell
var coastal := PackedByteArray() # 1 = land next to the ocean
var region_of := PackedInt32Array() # region index + 1, 0 = water
var continent_of := PackedInt32Array() # continent index + 1, 0 = water

## Region / continent records (index order is stable for a given seed).
var regions: Array[Dictionary] = []
var continents: Array[Dictionary] = []
var _region_index := {}


func index(x: int, y: int) -> int:
	return y * width + posmod(x, width)


func cell_of(lat: float, lon: float) -> int:
	return index(Geo.lon_col(lon, width), Geo.lat_row(lat, height))


func cell_lat_lon(i: int) -> Vector2:
	return Vector2(Geo.row_lat(i / width, height), Geo.col_lon(i % width, width))


func is_land(i: int) -> bool:
	return biome[i] > Biome.LAKE


func region(region_id: String) -> Dictionary:
	if _region_index.is_empty():
		for k in regions.size():
			_region_index[regions[k]["region_id"]] = k
	return regions[_region_index[region_id]] if _region_index.has(region_id) else {}


func region_at(lat: float, lon: float) -> Dictionary:
	var r := region_of[cell_at(lat, lon)]
	return regions[r - 1] if r > 0 else {}


func continent(continent_id: String) -> Dictionary:
	for c in continents:
		if c["continent_id"] == continent_id:
			return c
	return {}


# --- what the globe SHOWS (consistent picking) -----------------------------------
## The globe draws the coast from the bilinearly interpolated height texture
## (PlanetTextures.height_image + shaders/globe.gdshader, sea at 128/255).
## Land/water at a precise point is decided the same way, so a tap on drawn
## land is land and a tap on drawn water is water – also between the 49-km
## cell centres. Cell centres give exactly the cell value (no change there).
const SEA_LEVEL := 128.0 / 255.0
var _disp := PackedFloat32Array()


func display_level(i: int) -> float:
	var e := elevation_m[i]
	var v := 128.0 + (e / 4800.0 * 127.0 if e >= 0.0 else e / 5200.0 * 128.0)
	if biome[i] == Biome.LAKE:
		v = minf(v, 120.0)
	elif biome[i] != Biome.OCEAN:
		v = maxf(v, 131.0)
	return clampf(v, 0.0, 255.0) / 255.0


func _texels(lat: float, lon: float) -> Array:
	if _disp.size() != elevation_m.size():
		_disp.resize(elevation_m.size())
		for k in elevation_m.size():
			_disp[k] = display_level(k)
	var fx: float = (Geo.wrap_lon(lon) + 180.0) / 360.0 * width - 0.5
	var fy: float = (90.0 - lat) / 180.0 * height - 0.5
	var x0 := int(floor(fx))
	var y0 := clampi(int(floor(fy)), 0, height - 1)
	var y1 := clampi(y0 + 1, 0, height - 1)
	var tx: float = fx - floor(fx)
	var ty: float = clampf(fy - floor(fy), 0.0, 1.0) if fy >= 0.0 else 0.0
	return [[index(x0, y0), (1.0 - tx) * (1.0 - ty)], [index(x0 + 1, y0), tx * (1.0 - ty)], [index(x0, y1), (1.0 - tx) * ty], [index(x0 + 1, y1), tx * ty]]


## Interpolated display height 0..1 (sea level 128/255) at a precise point.
func display_value_at(lat: float, lon: float) -> float:
	var v := 0.0
	for t in _texels(lat, lon):
		v += _disp[int(t[0])] * float(t[1])
	return v


func is_land_at(lat: float, lon: float) -> bool:
	return display_value_at(lat, lon) >= SEA_LEVEL


## The data cell for a precise point: the nearest cell, unless the drawn
## coast puts the point on the other side – then the heaviest neighbouring
## cell of the drawn kind (land or water).
func cell_at(lat: float, lon: float) -> int:
	var i := cell_of(lat, lon)
	var land := is_land_at(lat, lon)
	if is_land(i) == land:
		return i
	var best := -1
	var best_w := -1.0
	for t in _texels(lat, lon):
		if is_land(int(t[0])) == land and float(t[1]) > best_w:
			best_w = float(t[1])
			best = int(t[0])
	return best if best >= 0 else i


## Everything known about one point (for the info panel and site rating).
## Consistent with what the globe shows at that exact point.
func sample(lat: float, lon: float) -> Dictionary:
	var i := cell_at(lat, lon)
	var r := region_of[i]
	var c := continent_of[i]
	return {
		"lat": lat, "lon": lon,
		"biome": BIOME_IDS[biome[i]],
		"biome_label": BIOME_LABELS[biome[i]],
		"land": is_land_at(lat, lon),
		"elevation_m": elevation_m[i],
		"temperature_c": temperature_c[i],
		"rainfall": rainfall[i],
		"river": river[i] == 1,
		"coastal": coastal[i] == 1 or (is_land_at(lat, lon) and _texels(lat, lon).any(func(t): return not is_land(int(t[0])))),
		"region_id": regions[r - 1]["region_id"] if r > 0 else "",
		"continent_id": continents[c - 1]["continent_id"] if c > 0 else "",
	}


# --- persistence (baked genesis data) --------------------------------------
# planet.json: meta, continents, regions (readable, diff-friendly)
# planet_cells.bin: per-cell layers, deflate-compressed, little endian:
#   elevation int16 (m) · temperature int8 (°C) · rainfall u8 · biome u8 ·
#   flags u8 (1 river, 2 coastal) · region u16 · continent u8  = 9 bytes/cell

const CELL_BYTES := 9


func save_to(dir: String) -> Error:
	DirAccess.make_dir_recursive_absolute(dir)
	var n := width * height
	var raw := PackedByteArray()
	raw.resize(n * CELL_BYTES)
	for i in n:
		var o := i * CELL_BYTES
		raw.encode_s16(o, clampi(int(round(elevation_m[i])), -32000, 32000))
		raw.encode_s8(o + 2, clampi(int(round(temperature_c[i])), -127, 127))
		raw[o + 3] = clampi(int(round(rainfall[i] * 255.0)), 0, 255)
		raw[o + 4] = biome[i]
		raw[o + 5] = river[i] | (coastal[i] << 1)
		raw.encode_u16(o + 6, region_of[i])
		raw[o + 8] = continent_of[i]
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var f := FileAccess.open(dir.path_join("planet_cells.bin"), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_32(raw.size())
	f.store_buffer(packed)
	f.close()
	var meta := {
		"_comment": "GENERATED by scripts/geography/planet_bake.gd from data/world/genesis.json - do not edit by hand. Nature only: no settlements, territories or roads (WORLD_DESIGN.md section 1).",
		"planet_id": planet_id, "name": name, "seed": seed, "generator_version": generator_version,
		"radius_km": radius_km, "width": width, "height": height,
		"continents": _json_ready(continents), "regions": _json_ready(regions),
	}
	var j := FileAccess.open(dir.path_join("planet.json"), FileAccess.WRITE)
	if j == null:
		return FileAccess.get_open_error()
	j.store_string(JSON.stringify(meta, "\t", false))
	j.close()
	return OK


static func load_from(dir: String) -> PlanetData:
	var meta_path := dir.path_join("planet.json")
	var bin_path := dir.path_join("planet_cells.bin")
	if not FileAccess.file_exists(meta_path) or not FileAccess.file_exists(bin_path):
		return null
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if typeof(meta) != TYPE_DICTIONARY:
		return null
	var p := PlanetData.new()
	p.planet_id = meta["planet_id"]
	p.name = meta["name"]
	p.seed = int(meta["seed"])
	p.generator_version = int(meta["generator_version"])
	p.radius_km = float(meta["radius_km"])
	p.width = int(meta["width"])
	p.height = int(meta["height"])
	for c in meta["continents"]:
		p.continents.append(_from_json(c))
	for r in meta["regions"]:
		p.regions.append(_from_json(r))
	var f := FileAccess.open(bin_path, FileAccess.READ)
	var raw_size := f.get_32()
	var raw := f.get_buffer(f.get_length() - 4).decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	var n := p.width * p.height
	if raw.size() != n * CELL_BYTES:
		push_error("PlanetData: corrupt cell file")
		return null
	p.elevation_m.resize(n)
	p.temperature_c.resize(n)
	p.rainfall.resize(n)
	p.biome.resize(n)
	p.river.resize(n)
	p.coastal.resize(n)
	p.region_of.resize(n)
	p.continent_of.resize(n)
	for i in n:
		var o := i * CELL_BYTES
		p.elevation_m[i] = raw.decode_s16(o)
		p.temperature_c[i] = raw.decode_s8(o + 2)
		p.rainfall[i] = raw[o + 3] / 255.0
		p.biome[i] = raw[o + 4]
		p.river[i] = raw[o + 5] & 1
		p.coastal[i] = (raw[o + 5] >> 1) & 1
		p.region_of[i] = raw.decode_u16(o + 6)
		p.continent_of[i] = raw[o + 8]
	return p


## Stable fingerprint of the cell layers + region table (determinism test).
func fingerprint() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(biome)
	ctx.update(region_of.to_byte_array())
	ctx.update(river)
	ctx.update(JSON.stringify(_json_ready(regions)).to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


static func _json_ready(list: Array) -> Array:
	var out: Array = []
	for d in list:
		var e: Dictionary = d.duplicate(true)
		if e.get("center") is Vector2:
			e["center"] = [snappedf(e["center"].x, 0.001), snappedf(e["center"].y, 0.001)]
		out.append(e)
	return out


static func _from_json(d: Dictionary) -> Dictionary:
	var e := d.duplicate(true)
	if e.get("center") is Array:
		e["center"] = Vector2(e["center"][0], e["center"][1])
	for k in ["area_km2", "elevation_m", "river_cells"]:
		if e.has(k):
			e[k] = float(e[k]) if k != "river_cells" else int(e[k])
	return e
