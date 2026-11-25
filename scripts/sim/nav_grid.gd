class_name NavGrid
extends RefCounted
## Phase 3 – walkable grid, places and travel times of ONE settlement.
## Pure data (no scene): usable by the client and later by a headless server.
##
## Pathfinding: Godot's native AStarGrid2D on the settlement tiles (fast,
## C++). Buildings, water and blocking props are solid; roads are walkable
## but more expensive (NPCs prefer sidewalks and cross where needed).
## Places: every building door ("home:<id>", "work:<id>", "bld:<id>"), the
## plaza and the green spots; each has standing spots for visible NPCs.

const SQRT2 := 1.41421356

var data: SettlementData
var astar := AStarGrid2D.new()
var costs: Dictionary = {}
var walk_tiles_per_second := 0.3
## place_id -> {"cell": Vector2i, "spots": Array[Vector2i], "building_id": String, "kind": String, "type": String}
var places: Dictionary = {}
var _path_cache: Dictionary = {}
var _time_cache: Dictionary = {}
var version := 0                  # map version (record.nav_changes.version)
var closed: Dictionary = {}        # Vector2i -> true: temporary closures (construction sites, …)
var _base_solid: Dictionary = {}   # Vector2i -> true: solid by the map itself
var stats := {"paths": 0, "cache_hits": 0, "invalidated": 0}


static func build(p_data: SettlementData, config: Dictionary) -> NavGrid:
	var g := NavGrid.new()
	g.data = p_data
	g.costs = config.get("walk_costs", {})
	g.walk_tiles_per_second = float(config.get("walk_tiles_per_second", 0.3))
	g._build_grid()
	g._build_places(config.get("places", {}))
	for y in p_data.size.y:
		for x in p_data.size.x:
			if g.astar.is_point_solid(Vector2i(x, y)):
				g._base_solid[Vector2i(x, y)] = true
	return g


## Dynamic map changes: the set of closed cells (cells that are solid by the
## map stay solid). Cached paths are invalidated selectively: a closure only
## drops the cached routes that cross it; an opening may shorten any route,
## so all are recomputed lazily. Returns the cells whose state changed.
func set_closed(cells: Array, p_version: int) -> Array[Vector2i]:
	var want := {}
	for c in cells:
		var v := Vector2i(int(c[0]), int(c[1]))
		if data.in_bounds(v.x, v.y) and not _base_solid.has(v):
			want[v] = true
	var changed: Array[Vector2i] = []
	var opened := false
	for v in closed.keys():
		if not want.has(v):
			astar.set_point_solid(v, false)
			changed.append(v)
			opened = true
	for v in want:
		if not closed.has(v):
			astar.set_point_solid(v, true)
			changed.append(v)
	closed = want
	version = p_version
	if opened:
		stats["invalidated"] = int(stats["invalidated"]) + _path_cache.size()
		_path_cache.clear()
		_time_cache.clear()
	elif not changed.is_empty():
		var hit := {}
		for v in changed:
			hit[v] = true
		for key in _path_cache.keys():
			for cell in _path_cache[key]:
				if hit.has(cell):
					_path_cache.erase(key)
					_time_cache.erase(key)
					stats["invalidated"] = int(stats["invalidated"]) + 1
					break
	return changed


## Path from an arbitrary cell to a place (rerouting during a journey).
func path_from_cell(c: Vector2i, b: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if places.has(b) and data.in_bounds(c.x, c.y):
		var start := c
		if astar.is_point_solid(start):
			start = nearest_walkable(c)
		out = astar.get_id_path(start, places[b]["cell"])
	return out


func nearest_walkable(c: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var v := c + Vector2i(dx, dy)
				if is_walkable(v):
					return v
	return c


## Walking time of an explicit cell path.
func seconds_of(p: Array) -> int:
	if p.size() < 2:
		return 1
	var cost := 0.0
	for i in range(1, p.size()):
		var a := Vector2i(p[i - 1][0], p[i - 1][1]) if p[i - 1] is Array else Vector2i(p[i - 1])
		var b := Vector2i(p[i][0], p[i][1]) if p[i] is Array else Vector2i(p[i])
		var step := SQRT2 if (b - a).abs() == Vector2i.ONE else 1.0
		cost += step * astar.get_point_weight_scale(b)
	return maxi(1, int(ceil(cost / walk_tiles_per_second)))


func _build_grid() -> void:
	astar.region = Rect2i(Vector2i.ZERO, data.size)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in data.size.y:
		for x in data.size.x:
			var t := data.get_tile(x, y)
			if t in SettlementData.BLOCKING_TILES or t == "":
				astar.set_point_solid(Vector2i(x, y), true)
			else:
				astar.set_point_weight_scale(Vector2i(x, y), float(costs.get(t, 1.2)))
	for b in data.buildings:
		for c in data.get_building_cells(b):
			if data.in_bounds(c.x, c.y):
				astar.set_point_solid(c, true)
	for p in data.props:
		for c in _prop_cells(p):
			if data.in_bounds(c.x, c.y):
				astar.set_point_solid(c, true)


static func _prop_cells(p: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var g: Vector2 = p.get("grid_v", Vector2.ZERO)
	var f: Vector2 = p.get("footprint_v", Vector2.ZERO)
	if f != Vector2.ZERO:
		for y in range(int(floor(g.y - f.y * 0.5)), int(ceil(g.y + f.y * 0.5))):
			for x in range(int(floor(g.x - f.x * 0.5)), int(ceil(g.x + f.x * 0.5))):
				out.append(Vector2i(x, y))
	elif p.get("kind", "") in ["bench", "notice_board", "market_stall", "water_tower", "electrical_tower", "tent", "cart"]:
		out.append(Vector2i(int(floor(g.x)), int(floor(g.y))))
	return out


func is_walkable(c: Vector2i) -> bool:
	return data.in_bounds(c.x, c.y) and not astar.is_point_solid(c)


func _build_places(cfg: Dictionary) -> void:
	for b in data.buildings:
		var bid: String = b.get("id", "")
		var door := _door_cell(b)
		if door.x < 0:
			continue
		places["bld:" + bid] = {"cell": door, "spots": _spots_around(b, door), "building_id": bid, "kind": "building", "type": b.get("type", "")}
	# plaza: every free plaza tile is a spot
	var plaza_spots: Array[Vector2i] = []
	for y in data.size.y:
		for x in data.size.x:
			if data.get_tile(x, y) == cfg.get("plaza_tile", "plaza") and is_walkable(Vector2i(x, y)):
				plaza_spots.append(Vector2i(x, y))
	if not plaza_spots.is_empty():
		places["plaza"] = {"cell": _centre_of(plaza_spots), "spots": plaza_spots, "building_id": "", "kind": "plaza", "type": "plaza"}
	# green spots: free cells next to fountain, garden, benches
	var park_spots: Array[Vector2i] = []
	for p in data.props:
		if not p.get("kind", "") in cfg.get("park_props", []):
			continue
		var g: Vector2 = p.get("grid_v", Vector2.ZERO)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var c := Vector2i(int(floor(g.x)) + dx, int(floor(g.y)) + dy)
				if is_walkable(c) and data.get_tile(c.x, c.y) != "road" and not park_spots.has(c):
					park_spots.append(c)
	if not park_spots.is_empty():
		places["park"] = {"cell": _centre_of(park_spots), "spots": park_spots, "building_id": "", "kind": "park", "type": "park"}


func _centre_of(cells: Array[Vector2i]) -> Vector2i:
	var s := Vector2.ZERO
	for c in cells:
		s += Vector2(c)
	s /= cells.size()
	var best := cells[0]
	for c in cells:
		if Vector2(c).distance_to(s) < Vector2(best).distance_to(s):
			best = c
	return best


static var _door_spec: Dictionary = {}


## The cell in front of the door that is drawn on the building sprite
## (data/doors/doors.json → nav_by_type), so people walk to the real door.
static func door_spec(building_type: String) -> Dictionary:
	if _door_spec.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/doors/doors.json"))
		_door_spec = d.get("nav_by_type", {}) if d is Dictionary else {}
	return _door_spec.get(building_type, {})


static func door_front_cell(b: Dictionary) -> Vector2i:
	var spec := door_spec(str(b.get("type", "")))
	var g: Vector2 = b["grid_v"]
	var f: Vector2 = b["footprint_v"]
	if spec.is_empty():
		return Vector2i(-1, -1)
	var t := clampf(float(spec.get("t", 0.5)), 0.0, 0.999)
	if spec.get("face", "left") == "left":
		return Vector2i(int(g.x) + int(t * f.x), int(g.y + f.y))
	return Vector2i(int(g.x + f.x), int(g.y + f.y) - 1 - int(t * f.y))


func _door_cell(b: Dictionary) -> Vector2i:
	var front := door_front_cell(b)
	if front.x >= 0 and is_walkable(front):
		return front
	for c in StreetPlanner.entrance_cells(b):
		if is_walkable(c):
			return c
	# fallback: nearest walkable cell to the front of the building
	var g: Vector2 = b["grid_v"]
	var f: Vector2 = b["footprint_v"]
	var front_v := Vector2(g.x + f.x * 0.5, g.y + f.y + 0.5)
	var best := Vector2i(-1, -1)
	for y in range(int(g.y) - 2, int(g.y + f.y) + 3):
		for x in range(int(g.x) - 2, int(g.x + f.x) + 3):
			var c := Vector2i(x, y)
			if is_walkable(c) and (best.x < 0 or Vector2(c).distance_to(front_v) < Vector2(best).distance_to(front_v)):
				best = c
	return best


## Visible standing spots around a building: beside (never on) the door,
## visible sides first, not on roads.
func _spots_around(b: Dictionary, door: Vector2i) -> Array[Vector2i]:
	var g: Vector2 = b["grid_v"]
	var f: Vector2 = b["footprint_v"]
	var cand: Array = []
	for y in range(int(g.y) - 1, int(g.y + f.y) + 2):
		for x in range(int(g.x) - 1, int(g.x + f.x) + 2):
			var c := Vector2i(x, y)
			if c == door or not is_walkable(c) or data.get_tile(x, y) == "road":
				continue
			var front := y >= int(g.y + f.y) or x >= int(g.x + f.x)
			cand.append([Vector2(c).distance_to(Vector2(door)) + (0.0 if front else 3.0), c])
	cand.sort_custom(func(a, b2): return a[0] < b2[0])
	var out: Array[Vector2i] = []
	for e in cand.slice(0, 6):
		out.append(e[1])
	if out.is_empty():
		out.append(door)
	return out


## Cell path between two places (cached). Empty if unreachable.
func path_between(a: String, b: String) -> Array[Vector2i]:
	var key := a + "|" + b
	if _path_cache.has(key):
		stats["cache_hits"] = int(stats["cache_hits"]) + 1
		return _path_cache[key]
	var out: Array[Vector2i] = []
	if places.has(a) and places.has(b):
		out = astar.get_id_path(places[a]["cell"], places[b]["cell"])
		stats["paths"] = int(stats["paths"]) + 1
	_path_cache[key] = out
	return out


## Walking time in seconds between two places (weighted path length).
func travel_seconds(a: String, b: String) -> int:
	if a == b:
		return 0
	var key := a + "|" + b
	if _time_cache.has(key):
		return _time_cache[key]
	var p := path_between(a, b)
	var secs := 0
	if p.size() < 2:
		# unreachable: estimate by straight distance (never blocks the simulation)
		if places.has(a) and places.has(b):
			secs = int(Vector2(places[a]["cell"]).distance_to(Vector2(places[b]["cell"])) * 1.6 / walk_tiles_per_second)
	else:
		var cost := 0.0
		for i in range(1, p.size()):
			var step := SQRT2 if (p[i] - p[i - 1]).abs() == Vector2i.ONE else 1.0
			cost += step * astar.get_point_weight_scale(p[i])
		secs = int(ceil(cost / walk_tiles_per_second))
	_time_cache[key] = secs
	return secs


## Position (grid coordinates, tile centre) along the path at fraction 0..1,
## distributed by weighted cost so the walking speed matches travel_seconds.
func position_on_path(a: String, b: String, frac: float) -> Vector2:
	var p := path_between(a, b)
	if p.is_empty():
		return Vector2(places.get(b, places.get(a, {"cell": Vector2i.ZERO}))["cell"]) + Vector2(0.5, 0.5)
	return position_on_cells(p, frac)


## Position along an explicit cell path ([Vector2i] or [[x, y]]).
func position_on_cells(path: Array, frac: float) -> Vector2:
	var p: Array[Vector2i] = []
	for c in path:
		p.append(Vector2i(int(c[0]), int(c[1])) if c is Array else Vector2i(c))
	if p.is_empty():
		return Vector2.ZERO
	if p.size() == 1 or frac <= 0.0:
		return Vector2(p[0]) + Vector2(0.5, 0.5)
	if frac >= 1.0:
		return Vector2(p[p.size() - 1]) + Vector2(0.5, 0.5)
	var seg_costs: Array[float] = []
	var total := 0.0
	for i in range(1, p.size()):
		var step := SQRT2 if (p[i] - p[i - 1]).abs() == Vector2i.ONE else 1.0
		var c := step * astar.get_point_weight_scale(p[i])
		seg_costs.append(c)
		total += c
	var target := frac * total
	for i in seg_costs.size():
		if target <= seg_costs[i]:
			var t := target / maxf(seg_costs[i], 1e-6)
			return Vector2(p[i]).lerp(Vector2(p[i + 1]), t) + Vector2(0.5, 0.5)
		target -= seg_costs[i]
	return Vector2(p[p.size() - 1]) + Vector2(0.5, 0.5)


func places_of_type(types: Array) -> Array[String]:
	var out: Array[String] = []
	for id in places:
		if places[id]["kind"] == "building" and places[id]["type"] in types:
			out.append(id)
	out.sort()
	return out
