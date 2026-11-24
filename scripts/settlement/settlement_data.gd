class_name SettlementData
extends RefCounted
## Parsed, validated settlement layout (pure data, no nodes).
##
## Phase 1 reads it from a JSON file. Later the same structure is filled from
## Firestore documents (settlements/{id}, buildings/{id}); see
## docs/FIREBASE_SCHEMA.md. Keeping this class free of scene code allows the
## future simulation server to reuse the format.

const BLOCKING_TILES := ["water"]
const BUILDABLE_TILES := ["grass", "path", "sand"]

var ids: Dictionary = {}
var settlement_name: String = ""
var region_name: String = ""
var development_status: String = ""
var size: Vector2i = Vector2i(16, 16)
var spawn: Vector2 = Vector2.ZERO
var buildings: Array[Dictionary] = []
var props: Array[Dictionary] = []
var scatter: Array[Dictionary] = []
var notice_board: Dictionary = {}

## Tile type name per cell, row-major (y * size.x + x).
var _tiles: PackedStringArray = []


static func load_from_file(path: String) -> SettlementData:
	if not FileAccess.file_exists(path):
		push_error("SettlementData: file not found " + path)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SettlementData: invalid JSON " + path)
		return null
	var data := SettlementData.new()
	data._parse(parsed)
	return data


func _parse(d: Dictionary) -> void:
	ids = d.get("ids", {})
	settlement_name = d.get("name", "Unbenannt")
	region_name = d.get("region_name", "")
	development_status = d.get("development_status", "")
	var s: Array = d.get("size", [16, 16])
	size = Vector2i(int(s[0]), int(s[1]))
	spawn = _vec(d.get("spawn", [size.x * 0.5, size.y * 0.5]))
	notice_board = d.get("notice_board", {})

	var ground: Dictionary = d.get("ground", {})
	_tiles.resize(size.x * size.y)
	_tiles.fill(ground.get("base", "grass"))
	for r in ground.get("rects", []):
		var rect: Array = r.get("rect", [0, 0, 0, 0])
		for y in range(int(rect[1]), int(rect[1]) + int(rect[3])):
			for x in range(int(rect[0]), int(rect[0]) + int(rect[2])):
				set_tile(x, y, r.get("tile", "grass"))

	for b in d.get("buildings", []):
		var entry: Dictionary = b.duplicate(true)
		entry["grid_v"] = _vec(b.get("grid", [0, 0]))
		entry["footprint_v"] = _vec(b.get("footprint", [1, 1]))
		buildings.append(entry)
	for p in d.get("props", []):
		var entry: Dictionary = p.duplicate(true)
		entry["grid_v"] = _vec(p.get("grid", [0, 0]))
		props.append(entry)
	for sc in d.get("scatter", []):
		scatter.append(sc)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < size.x and y < size.y


func get_tile(x: int, y: int) -> String:
	return _tiles[y * size.x + x] if in_bounds(x, y) else ""


func set_tile(x: int, y: int, tile: String) -> void:
	if in_bounds(x, y):
		_tiles[y * size.x + x] = tile


func get_building_cells(b: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var g: Vector2 = b["grid_v"]
	var f: Vector2 = b["footprint_v"]
	for y in range(int(g.y), int(g.y + f.y)):
		for x in range(int(g.x), int(g.x + f.x)):
			out.append(Vector2i(x, y))
	return out


## Returns a list of layout problems (empty = valid). Used by tests and at load.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	var occupied := {}
	var seen_ids := {}
	for b in buildings:
		var id: String = b.get("id", "")
		if id == "" or not Ids.has_prefix(id, "bld"):
			problems.append("building without valid id: %s" % b.get("name", "?"))
		if seen_ids.has(id):
			problems.append("duplicate building id: " + id)
		seen_ids[id] = true
		for c in get_building_cells(b):
			if not in_bounds(c.x, c.y):
				problems.append("%s out of bounds at %s" % [id, c])
				continue
			var t := get_tile(c.x, c.y)
			if not BUILDABLE_TILES.has(t):
				problems.append("%s placed on '%s' at %s" % [id, t, c])
			if occupied.has(c):
				problems.append("%s overlaps %s at %s" % [id, occupied[c], c])
			occupied[c] = id
	for p in props:
		var g: Vector2 = p["grid_v"]
		var c := Vector2i(int(floor(g.x)), int(floor(g.y)))
		if occupied.has(c):
			problems.append("prop %s inside building %s" % [p.get("kind", "?"), occupied[c]])
	var sp := Vector2i(int(floor(spawn.x)), int(floor(spawn.y)))
	if occupied.has(sp) or BLOCKING_TILES.has(get_tile(sp.x, sp.y)):
		problems.append("spawn point is blocked")
	return problems


## Lightweight summary for UI and the event bus (no node references).
func summary() -> Dictionary:
	return {
		"settlement_id": ids.get("settlement_id", ""),
		"region_id": ids.get("region_id", ""),
		"name": settlement_name,
		"region_name": region_name,
		"development_status": development_status,
		"building_count": buildings.size(),
	}


static func _vec(a: Variant) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO
