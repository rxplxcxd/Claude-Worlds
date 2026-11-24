class_name Geo
extends RefCounted
## Geographic coordinates on a spherical planet (docs/GEOGRAPHY_SYSTEM.md §2).
##
## Positions are latitude/longitude in DEGREES (lat −90..90, north positive;
## lon −180..180, east positive). The 3D convention (unit sphere, y = north
## pole) is shared by the planet generator, the globe view and its shader:
##     v = (cos(lat)·cos(lon), sin(lat), −cos(lat)·sin(lon))
## Planet data is stored on an equirectangular grid: column x ↔ longitude,
## row y ↔ latitude (row 0 = north edge).

## Converts latitude/longitude (degrees) to a point on the unit sphere.
static func to_vec3(lat: float, lon: float) -> Vector3:
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return Vector3(cos(la) * cos(lo), sin(la), -cos(la) * sin(lo))


## Converts a direction (any length) to Vector2(lat, lon) in degrees.
static func from_vec3(v: Vector3) -> Vector2:
	# atan2 instead of asin: stays exact near the poles in single precision
	# (y ≈ 1 is no longer representable there, x and z still are).
	return Vector2(rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length())), rad_to_deg(atan2(-v.z, v.x)))


## Great-circle distance in km.
static func distance_km(lat1: float, lon1: float, lat2: float, lon2: float, radius_km: float) -> float:
	var a := to_vec3(lat1, lon1)
	var b := to_vec3(lat2, lon2)
	return radius_km * a.angle_to(b)


static func wrap_lon(lon: float) -> float:
	return fposmod(lon + 180.0, 360.0) - 180.0


## Latitude of the centre of grid row `y` (grid height `h`).
static func row_lat(y: int, h: int) -> float:
	return 90.0 - (y + 0.5) * 180.0 / h


## Longitude of the centre of grid column `x` (grid width `w`).
static func col_lon(x: int, w: int) -> float:
	return -180.0 + (x + 0.5) * 360.0 / w


static func lat_row(lat: float, h: int) -> int:
	return clampi(int((90.0 - lat) / 180.0 * h), 0, h - 1)


static func lon_col(lon: float, w: int) -> int:
	return posmod(int(floor((wrap_lon(lon) + 180.0) / 360.0 * w)), w)


## Human-readable position, e.g. "48,2° N · 12,5° O".
static func format(lat: float, lon: float) -> String:
	var ns := "N" if lat >= 0.0 else "S"
	var eo := "O" if lon >= 0.0 else "W"
	return ("%.1f° %s · %.1f° %s" % [absf(lat), ns, absf(lon), eo]).replace(".", ",")


# --- geodesy on the sphere (Paket 2.1, docs/TERRITORY_SYSTEM.md §2) ---------
# The planet is a sphere, so geodesics are great circles. All distances are
# exact surface distances (km); no planar shortcut is used for the rules.
# Vector3 is single precision: unit vectors resolve ~0.3 m on this planet,
# which is ample for kilometre rules; tolerances below are chosen for that.
const ARC_EPS := 2e-6

## Unit vector pointing east at (lat, lon). Defined at the poles too (there
## the frame follows the given longitude, normally 0).
static func east(lat: float, lon: float) -> Vector3:
	var lo := deg_to_rad(lon)
	return Vector3(-sin(lo), 0.0, -cos(lo))


## Unit vector pointing north at (lat, lon).
static func north(lat: float, lon: float) -> Vector3:
	return to_vec3(lat, lon).cross(east(lat, lon))


## Point reached from (lat, lon) by going x km east and y km north in the
## local tangent frame (azimuthal equidistant: exact distance from the origin).
static func offset(lat: float, lon: float, x_km: float, y_km: float, radius_km: float) -> Vector2:
	var d := sqrt(x_km * x_km + y_km * y_km) / radius_km
	if d < 1e-12:
		return Vector2(lat, lon)
	var c := to_vec3(lat, lon)
	var dir := (east(lat, lon) * x_km + north(lat, lon) * y_km).normalized()
	return from_vec3(c * cos(d) + dir * sin(d))


## Inverse of offset(): local (x, y) in km of point p relative to origin c.
static func local_xy(origin_lat: float, origin_lon: float, lat: float, lon: float, radius_km: float) -> Vector2:
	var c := to_vec3(origin_lat, origin_lon)
	var p := to_vec3(lat, lon)
	var d := c.angle_to(p) * radius_km
	var proj := p - c * p.dot(c)
	if proj.length() < 1e-12:
		return Vector2.ZERO
	proj = proj.normalized()
	return Vector2(proj.dot(east(origin_lat, origin_lon)), proj.dot(north(origin_lat, origin_lon))) * d


## Surface distance (km) from point p to the great-circle arc a→b (unit vectors).
static func point_arc_km(p: Vector3, a: Vector3, b: Vector3, radius_km: float) -> float:
	var n := a.cross(b)
	if n.length() < 1e-12:
		return p.angle_to(a) * radius_km
	n = n.normalized()
	var foot := p - n * p.dot(n)
	if foot.length() > 1e-12:
		foot = foot.normalized()
		# Foot point lies on the arc if it is "between" a and b.
		if absf(a.angle_to(foot) + foot.angle_to(b) - a.angle_to(b)) < ARC_EPS:
			return asin(clampf(absf(p.dot(n)), 0.0, 1.0)) * radius_km
	return minf(p.angle_to(a), p.angle_to(b)) * radius_km


## Ring of [lat, lon] → unit vectors.
static func ring_vectors(ring: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for pt in ring:
		out.append(to_vec3(float(pt[0]), float(pt[1])))
	return out


## Point inside a (small, convex or concave) spherical polygon? Uses the
## winding of the edges seen from the point (sum of signed angles ≈ ±2π).
static func point_in_ring(p: Vector3, ring: Array[Vector3]) -> bool:
	var total := 0.0
	for i in ring.size():
		var a := ring[i] - p * ring[i].dot(p)
		var b := ring[(i + 1) % ring.size()] - p * ring[(i + 1) % ring.size()].dot(p)
		if a.length() < 1e-12 or b.length() < 1e-12:
			return true # on a vertex
		total += a.signed_angle_to(b, p)
	return absf(total) > PI


## Do the great-circle arcs a1→a2 and b1→b2 intersect?
static func arcs_intersect(a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3) -> bool:
	var na := a1.cross(a2)
	var nb := b1.cross(b2)
	var line := na.cross(nb)
	if line.length() < 1e-14:
		return false
	line = line.normalized()
	for cand in [line, -line]:
		var on_a: bool = absf(a1.angle_to(cand) + cand.angle_to(a2) - a1.angle_to(a2)) < ARC_EPS
		var on_b: bool = absf(b1.angle_to(cand) + cand.angle_to(b2) - b1.angle_to(b2)) < ARC_EPS
		if on_a and on_b:
			return true
	return false


## Minimum surface distance (km) between two rings; 0 if they touch,
## intersect or one contains the other.
static func ring_distance_km(ra: Array[Vector3], rb: Array[Vector3], radius_km: float) -> float:
	if rings_overlap(ra, rb):
		return 0.0
	var best := INF
	for i in ra.size():
		var a1 := ra[i]
		var a2 := ra[(i + 1) % ra.size()]
		for p in rb:
			best = minf(best, point_arc_km(p, a1, a2, radius_km))
	for i in rb.size():
		var b1 := rb[i]
		var b2 := rb[(i + 1) % rb.size()]
		for p in ra:
			best = minf(best, point_arc_km(p, b1, b2, radius_km))
	return best


## Interiors or borders overlap (edge crossing or containment).
static func rings_overlap(ra: Array[Vector3], rb: Array[Vector3]) -> bool:
	for i in ra.size():
		for k in rb.size():
			if arcs_intersect(ra[i], ra[(i + 1) % ra.size()], rb[k], rb[(k + 1) % rb.size()]):
				return true
	return point_in_ring(ra[0], rb) or point_in_ring(rb[0], ra)


## Area (km²) of a small polygon given as [[lat, lon], …]: shoelace formula in
## the local tangent frame of its first vertex (accurate for polygons up to
## a few hundred km; spherical excess would drown in single precision).
static func ring_area_km2(ring: Array, radius_km: float) -> float:
	if ring.size() < 3:
		return 0.0
	var o: Array = ring[0]
	var pts: Array[Vector2] = []
	for pt in ring:
		pts.append(local_xy(float(o[0]), float(o[1]), float(pt[0]), float(pt[1]), radius_km))
	var a := 0.0
	for i in pts.size():
		var p1 := pts[i]
		var p2 := pts[(i + 1) % pts.size()]
		a += p1.x * p2.y - p2.x * p1.y
	return absf(a) * 0.5
