class_name GeoIndex
extends RefCounted
## Hierarchical spatial index on the sphere (docs/TERRITORY_SYSTEM.md §3).
##
## Cube-sphere quadtree (S2-like): the unit sphere is projected onto the 6
## faces of a cube; each face is split into 2^level × 2^level cells.
## Token "f<face>:<level>:<i>:<j>". On a planet with R = 4 000 km a face edge
## is ≈ 6 300 km, level 8 ≈ 24 km, level 12 ≈ 1.5 km.
## Territories store the level-8 cells of their area plus a buffer
## (`cover_l8`); candidate checks only compare entries with a shared cell.
## The token format is stable and Firestore-friendly (array-contains-any).

const LEVEL := 8


static func face_uv(v: Vector3) -> Array:
	var a := v.abs()
	var face := 0
	var u := 0.0
	var w := 0.0
	if a.x >= a.y and a.x >= a.z:
		face = 0 if v.x > 0 else 1
		u = v.z / a.x
		w = v.y / a.x
	elif a.y >= a.z:
		face = 2 if v.y > 0 else 3
		u = v.x / a.y
		w = v.z / a.y
	else:
		face = 4 if v.z > 0 else 5
		u = v.x / a.z
		w = v.y / a.z
	return [face, u, w]


static func token(lat: float, lon: float, level: int = LEVEL) -> String:
	var f := face_uv(Geo.to_vec3(lat, lon))
	var n := 1 << level
	var i := clampi(int(floor((float(f[1]) + 1.0) * 0.5 * n)), 0, n - 1)
	var j := clampi(int(floor((float(f[2]) + 1.0) * 0.5 * n)), 0, n - 1)
	return "f%d:%d:%d:%d" % [f[0], level, i, j]


## Edge length (km) of a cell at `level` (centre of a face, the largest).
static func cell_km(radius_km: float, level: int = LEVEL) -> float:
	return PI * 0.5 * radius_km / (1 << level)


## Tokens of all cells touching a disc of `radius_km` around (lat, lon).
## Sampled densely enough (half a cell) to never miss a cell.
static func cover(lat: float, lon: float, radius_km: float, planet_radius_km: float, level: int = LEVEL) -> PackedStringArray:
	var step := cell_km(planet_radius_km, level) * 0.45
	var out := {}
	var n := int(ceil(radius_km / step))
	for yi in range(-n, n + 1):
		for xi in range(-n, n + 1):
			var x := xi * step
			var y := yi * step
			if Vector2(x, y).length() > radius_km + step:
				continue
			var p := Geo.offset(lat, lon, x, y, planet_radius_km)
			out[token(p.x, p.y, level)] = true
	return PackedStringArray(out.keys())


static func shares_cell(a: Array, b: Array) -> bool:
	if a.size() > b.size():
		var t := a
		a = b
		b = t
	var lookup := {}
	for x in b:
		lookup[x] = true
	for x in a:
		if lookup.has(x):
			return true
	return false
