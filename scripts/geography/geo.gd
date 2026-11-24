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
	var n := v.normalized()
	return Vector2(rad_to_deg(asin(clampf(n.y, -1.0, 1.0))), rad_to_deg(atan2(-n.z, n.x)))


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
