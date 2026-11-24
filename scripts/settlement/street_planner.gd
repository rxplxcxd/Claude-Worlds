class_name StreetPlanner
extends RefCounted
## Rule-based placement of street furniture (docs/SETTLEMENT_SYSTEM.md §7).
##
## Instead of hand-placed coordinates, lamps, hydrants, signs, the bus stop,
## mailboxes and bins are derived from the road network:
##   * CURB cells = sidewalk cells that touch a road. Lamps and hydrants stand
##     only there, at the curb edge, never on the road or in front of doors.
##   * Lamps: every LAMP_SPACING cells along each road, staggered on the two
##     sides; the arm points towards the road.
##   * Hydrants: every HYDRANT_SPACING cells (offset from the lamps), plus one
##     near every junction; never closer than 1.5 cells to a lamp.
##   * Street-name sign at every junction corner, "give way" sign on side roads.
##   * Bus stop on the main road's curb, facing the road.
##   * Mailbox beside each house entrance, bins beside benches / bus stop.
## validate() re-checks all rules (used by tests and at runtime).

const LAMP_SPACING := 4
const HYDRANT_SPACING := 6
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var data: SettlementData
var _building_cells := {}
var _entrance_cells := {}
var _used := {}


func _init(settlement: SettlementData) -> void:
	data = settlement
	for b in data.buildings:
		for c in data.get_building_cells(b):
			_building_cells[c] = b.get("id", "")
		for c in entrance_cells(b):
			_entrance_cells[c] = b.get("id", "")


## Cells directly in front of a building's two visible faces (+y and +x),
## centred on the face: kept free as entrances.
static func entrance_cells(b: Dictionary) -> Array[Vector2i]:
	var g: Vector2 = b["grid_v"]
	var f: Vector2 = b["footprint_v"]
	var out: Array[Vector2i] = []
	for i in range(int(f.x)):
		out.append(Vector2i(int(g.x) + i, int(g.y + f.y)))
	for i in range(int(f.y)):
		out.append(Vector2i(int(g.x + f.x), int(g.y) + i))
	return out


func is_road(c: Vector2i) -> bool:
	return data.get_tile(c.x, c.y) == "road"


func road_dir_of(c: Vector2i) -> Vector2i:
	for d in DIRS:
		if is_road(c + d):
			return d
	return Vector2i.ZERO


func is_curb(c: Vector2i) -> bool:
	return data.get_tile(c.x, c.y) == "sidewalk" and road_dir_of(c) != Vector2i.ZERO


func curb_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in data.size.y:
		for x in data.size.x:
			var c := Vector2i(x, y)
			if is_curb(c):
				out.append(c)
	return out


func _free(c: Vector2i) -> bool:
	return not _used.has(c) and not _entrance_cells.has(c) and not _building_cells.has(c)


## Generates furniture entries: {kind, grid_v, road_dir?}.
func plan() -> Array:
	var out: Array = []
	var curbs := curb_cells()
	var lamps: Array[Vector2] = []
	var hydrants: Array[Vector2] = []
	# Lamps, staggered: side A on multiples of LAMP_SPACING, side B halfway.
	for c in curbs:
		var d := road_dir_of(c)
		var along := c.x if d.x == 0 else c.y
		var side_b := d.y < 0 or d.x < 0
		var phase := (LAMP_SPACING / 2) if side_b else 0
		if posmod(along + phase, LAMP_SPACING * 2) != 0 or not _free(c):
			continue
		var pos := Vector2(c) + Vector2(0.5, 0.5) + Vector2(d) * 0.34
		out.append({"kind": "street_lamp", "grid_v": pos, "road_dir": d})
		lamps.append(pos)
		_used[c] = "lamp"
	# Hydrants at regular spacing, away from lamps.
	for c in curbs:
		var d := road_dir_of(c)
		var along := c.x if d.x == 0 else c.y
		if posmod(along + 3, HYDRANT_SPACING) != 0 or not _free(c):
			continue
		var pos := _side_pos(c, d, 0.3)
		if _near(lamps, pos, 1.5) or _near(hydrants, pos, HYDRANT_SPACING - 1.0):
			continue
		out.append({"kind": "hydrant", "grid_v": pos})
		hydrants.append(pos)
		_used[c] = "hydrant"
	# Every junction gets a hydrant within 3 cells (fire brigade access).
	for j in junction_cells():
		if _near(hydrants, Vector2(j) + Vector2(0.5, 0.5), 3.5):
			continue
		for c in curbs:
			var pos := _side_pos(c, road_dir_of(c), 0.3)
			if Vector2(c).distance_to(Vector2(j)) <= 3.0 and _free(c) and not _near(lamps, pos, 1.5):
				out.append({"kind": "hydrant", "grid_v": pos})
				hydrants.append(pos)
				_used[c] = "hydrant"
				break
	# Junctions: street-name sign + give-way sign on the side road.
	for j in junction_cells():
		var placed_sign := false
		for corner in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var c: Vector2i = j + corner
			if is_curb(c) and _free(c) and not placed_sign:
				out.append({"kind": "street_sign", "grid_v": Vector2(c) + Vector2(0.5, 0.5) - Vector2(corner) * 0.25})
				_used[c] = "sign"
				placed_sign = true
		var side := _side_branch(j)
		if side != Vector2i.ZERO:
			var right := Vector2i(-side.y, side.x)
			var c: Vector2i = j + side * 2 + right
			if is_curb(c) and _free(c):
				out.append({"kind": "traffic_sign", "grid_v": _side_pos(c, road_dir_of(c), 0.3)})
				_used[c] = "traffic_sign"
	# Bus stop on the first free north curb of the longest x-road near the plaza.
	var best: Vector2i = Vector2i(-1, -1)
	for c in curbs:
		if road_dir_of(c) == Vector2i(0, 1) and _free(c) and c.x > data.size.x / 2 + 3:
			best = c
			break
	if best.x >= 0:
		out.append({"kind": "bus_stop", "grid_v": Vector2(best) + Vector2(0.5, 0.62), "name": "Haltestelle", "text": "Bushaltestelle von {settlement}.\n\n[i]Busverbindungen entstehen, sobald es weitere Siedlungen gibt (Phase 8).[/i]"})
		_used[best] = "bus_stop"
		var bin := best + Vector2i(1, 0)
		if _free(bin) and data.get_tile(bin.x, bin.y) == "sidewalk":
			out.append({"kind": "trash_small", "grid_v": Vector2(bin) + Vector2(0.3, 0.3)})
			_used[bin] = "bin"
	# Mailboxes beside house entrances (on the side, not blocking the door).
	for b in data.buildings:
		if b.get("type", "") not in ["house", "player_home"]:
			continue
		for c in entrance_cells(b):
			var t := data.get_tile(c.x, c.y)
			if t in ["sidewalk", "path", "grass"] and not _used.has(c):
				var g: Vector2 = b["grid_v"]
				var pos := Vector2(c) + (Vector2(0.18, 0.5) if c.y == int(g.y + b["footprint_v"].y) else Vector2(0.5, 0.18))
				out.append({"kind": "mailbox", "grid_v": pos})
				_used[c] = "mailbox"
				break
	return out


## Road cells with three or four road neighbours (plaza counts as road).
func junction_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in data.size.y:
		for x in data.size.x:
			var c := Vector2i(x, y)
			if not is_road(c):
				continue
			var n := 0
			for d in DIRS:
				if is_road(c + d):
					n += 1
			if n >= 3:
				out.append(c)
	return out


func _side_branch(j: Vector2i) -> Vector2i:
	# The branch without an opposite branch is the side road of a T-junction.
	for d in DIRS:
		if is_road(j + d) and not is_road(j - d):
			return d
	return Vector2i.ZERO


func _side_pos(c: Vector2i, d: Vector2i, curb: float) -> Vector2:
	var perp := Vector2(-d.y, d.x) * 0.22
	return Vector2(c) + Vector2(0.5, 0.5) + Vector2(d) * curb + perp


static func _near(points: Array[Vector2], p: Vector2, dist: float) -> bool:
	for q in points:
		if q.distance_to(p) < dist:
			return true
	return false


## Checks the placement rules for a list of furniture entries.
## Returns human readable problems (empty = valid).
func validate(items: Array) -> PackedStringArray:
	var problems: PackedStringArray = []
	var lamps: Array[Vector2] = []
	for it in items:
		var g: Vector2 = it["grid_v"]
		var c := Vector2i(int(floor(g.x)), int(floor(g.y)))
		var t := data.get_tile(c.x, c.y)
		var kind: String = it["kind"]
		if t in ["road", "water", ""] or _building_cells.has(c):
			problems.append("%s at %s stands on %s" % [kind, c, t if not _building_cells.has(c) else "a building"])
		if kind in ["street_lamp", "hydrant", "bus_stop"] and not is_curb(c):
			problems.append("%s at %s is not at a curb" % [kind, c])
		if _entrance_cells.has(c) and kind != "mailbox":
			problems.append("%s at %s blocks the entrance of %s" % [kind, c, _entrance_cells[c]])
		if kind == "street_lamp":
			var d: Vector2i = it.get("road_dir", Vector2i.ZERO)
			if not is_road(c + d):
				problems.append("lamp at %s does not face the road" % c)
			lamps.append(g)
	for it in items:
		if it["kind"] == "hydrant" and _near(lamps, it["grid_v"], 1.5):
			problems.append("hydrant at %s too close to a lamp" % it["grid_v"])
	for i in lamps.size():
		for k in range(i + 1, lamps.size()):
			if lamps[i].distance_to(lamps[k]) < 2.0:
				problems.append("lamps too close at %s / %s" % [lamps[i], lamps[k]])
	return problems
