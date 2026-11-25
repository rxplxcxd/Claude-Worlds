class_name InteriorGenerator
extends RefCounted
## Dynamic interiors (docs/INTERIOR_STANDARD.md §7): footprint + building type
## + seed → rooms, corridors, doors and furniture, in the same layout format
## as the hand-made interiors (data/interiors/layouts.json).
##
## * Reproducible: the layout is a pure function of (type, size, seed, wealth,
##   VERSION). A building persists only its key "gen:<type>:<w>x<h>:<seed>[:<wealth %>]";
##   the same key always yields the same rooms and furniture.
## * Valid: every room, door and the entrance stay connected – the generator
##   checks its own occupancy grid and drops the least important pieces
##   until everything is reachable (tests run the real walk grid as well).
## * Own art only: works in every build (no bought sheets needed).
##
## The straight 3/4 camera looks north: rooms are laid out in east-west bands
## (front band with the entrance, corridors, back bands). Horizontal walls are
## frontal faces, so corridors run east-west and doors open north-south.

const VERSION := 1
const MIN_ROOM := 4.0          # tiles (≈ 2.4 m)
const CORRIDOR := 3.0
const DOOR_W := 2.0

## Building types: room programme per band, materials, wall height.
const TYPES := {
	"house": {"label": "Wohnhaus", "hall": "living", "front_side": ["kitchen"], "back": ["bedroom", "bath", "bedroom", "bedroom"],
		"floor": "wood_floor", "wall": "wall_plaster", "wall_tiles": 3.0},
	"shop": {"label": "Laden", "hall": "sales", "front_side": ["office"], "back": ["storage", "storage", "office"],
		"floor": "stone_flags", "wall": "wall_plaster", "wall_tiles": 3.0},
	"office": {"label": "Amtsgebäude", "hall": "reception", "front_side": ["office", "office"], "back": ["meeting", "office", "archive", "office"],
		"floor": "marble_floor", "wall": "wall_marble", "wall_tiles": 3.5},
	"clinic": {"label": "Praxis", "hall": "waiting", "front_side": ["office"], "back": ["treatment", "treatment", "storage"],
		"floor": "clinic_tiles", "wall": "wall_tiles", "wall_tiles": 3.0},
	"workshop": {"label": "Werkstatt", "hall": "workshop", "front_side": ["storage"], "back": ["storage", "office"],
		"floor": "stone_flags", "wall": "wall_brick", "wall_tiles": 4.0},
	"palace": {"label": "Palast", "hall": "hall", "front_side": ["reception", "dining"], "back": ["chamber", "library", "bedroom", "bath", "kitchen", "chamber", "gallery"],
		"floor": "marble_floor", "wall": "wall_fresco", "wall_tiles": 4.5, "courtyard": true},
}

## Room kinds: materials and furnishing rules [item, where, min_wealth].
## where: back (along the back wall), centre, west/east (side walls), corner
## (front corners), wall (hung on the back wall).
const ROOMS := {
	"living": {"label": "Wohnraum", "items": [["dining_set", "centre", 0.0], ["wardrobe_light", "back", 0.3], ["bench", "back", 0.0],
		["planter", "corner", 0.4], ["candelabrum", "corner", 0.6], ["mural", "wall", 0.5]]},
	"kitchen": {"label": "Küche", "floor": "stone_flags", "items": [["bread_oven", "back", 0.0], ["pot_shelf", "wall", 0.0], ["barrel", "corner", 0.0],
		["sacks", "corner", 0.2], ["water_station", "back", 0.0]]},
	"bedroom": {"label": "Schlafzimmer", "items": [["@bed", "back", 0.0], ["wardrobe", "back", 0.0], ["planter", "corner", 0.5], ["banner_blue", "wall", 0.7]]},
	"bath": {"label": "Bad", "floor": "clinic_tiles", "wall": "wall_tiles", "items": [["shower_cabin", "back", 0.0], ["bath_shelf", "back", 0.0],
		["water_station", "back", 0.0], ["towel_rack", "wall", 0.0], ["bath_cabinet", "wall", 0.3]]},
	"sales": {"label": "Verkaufsraum", "items": [["shop_counter", "centre", 0.0], ["goods_shelf", "back", 0.0], ["bread_shelf", "back", 0.0],
		["veg_stand", "west", 0.2], ["notice_board", "wall", 0.0]]},
	"storage": {"label": "Lager", "items": [["pallet_rack", "back", 0.0], ["barrel", "corner", 0.0], ["sacks", "corner", 0.0], ["equipment_rack", "back", 0.0]]},
	"office": {"label": "Büro", "items": [["office_desk", "centre", 0.0], ["filing_cabinet", "back", 0.0], ["archive_cabinet", "back", 0.2],
		["planter", "corner", 0.5], ["map_wall", "wall", 0.4]]},
	"reception": {"label": "Empfang", "items": [["reception_desk", "centre", 0.0], ["waiting_chairs", "west", 0.0], ["waiting_chairs", "east", 0.0],
		["flag_stand", "back", 0.3], ["notice_board", "wall", 0.0], ["planter", "corner", 0.4]]},
	"meeting": {"label": "Besprechung", "items": [["conference_table", "centre", 0.0], ["flag_stand", "back", 0.4], ["map_wall", "wall", 0.0]]},
	"archive": {"label": "Archiv", "items": [["archive_cabinet", "back", 0.0], ["scroll_shelf", "back", 0.3], ["archive_cabinet", "back", 0.0],
		["reading_table", "centre", 0.2], ["ladder", "back", 0.3]]},
	"waiting": {"label": "Wartebereich", "items": [["reception_desk", "back", 0.0], ["waiting_chairs", "west", 0.0], ["waiting_chairs", "east", 0.0],
		["planter", "corner", 0.3], ["notice_board", "wall", 0.0]]},
	"treatment": {"label": "Behandlung", "floor": "clinic_tiles", "wall": "wall_tiles", "items": [["med_bed", "back", 0.0], ["med_cabinet", "back", 0.0],
		["med_screen", "centre", 0.2], ["water_station", "back", 0.0]]},
	"workshop": {"label": "Werkstatt", "items": [["workbench", "back", 0.0], ["forge", "back", 0.3], ["anvil", "centre", 0.3], ["tool_wall", "wall", 0.0],
		["barrel", "corner", 0.0], ["sacks", "corner", 0.0]]},
	"hall": {"label": "Halle", "floor": "mosaic", "items": [["fountain_small", "centre", 0.0], ["statue", "back", 0.0], ["statue_gold", "back", 0.7],
		["bench_marble", "west", 0.0], ["bench_marble", "east", 0.0], ["candelabrum", "corner", 0.0], ["mural", "wall", 0.0], ["banner_red", "wall", 0.4]]},
	"dining": {"label": "Speisesaal", "items": [["dining_set", "centre", 0.0], ["dining_set", "centre", 0.5], ["food_counter", "back", 0.0],
		["candelabrum", "corner", 0.0], ["mural", "wall", 0.3]]},
	"chamber": {"label": "Kammer", "floor": "mosaic", "items": [["reading_table", "centre", 0.0], ["bust", "back", 0.0], ["vitrine", "back", 0.3],
		["bench_marble", "back", 0.0], ["banner_gold", "wall", 0.0]]},
	"library": {"label": "Bibliothek", "items": [["scroll_shelf", "back", 0.0], ["scroll_shelf", "back", 0.0], ["reading_table", "centre", 0.0],
		["ladder", "back", 0.0], ["candelabrum", "corner", 0.0]]},
	"gallery": {"label": "Galerie", "items": [["statue", "back", 0.0], ["bust", "back", 0.0], ["vitrine", "centre", 0.0], ["amphora", "corner", 0.0],
		["mural", "wall", 0.0]]},
	"courtyard": {"label": "Innenhof", "floor": "stone_flags", "items": [["fountain_small", "centre", 0.0], ["planter", "corner", 0.0],
		["bench_marble", "west", 0.0], ["bench_marble", "east", 0.0], ["planter", "back", 0.0], ["planter", "back", 0.0]]},
	"corridor": {"label": "Flur", "items": [["planter", "corner", 0.5], ["bust", "back", 0.8]]},
}

static var _cache: Dictionary = {}


## "gen:<type>:<w>x<h>:<seed>[:<wealth %>]" – the persistent key of a generated interior.
static func key_for(type: String, size: Vector2i, p_seed: int, wealth := 0.5) -> String:
	return "gen:%s:%dx%d:%d:%d" % [type, size.x, size.y, p_seed, int(round(wealth * 100.0))]


static func is_generated_key(k: String) -> bool:
	return k.begins_with("gen:")


## The layout for a key (cached; identical for identical keys).
static func layout_for_key(k: String) -> Dictionary:
	if _cache.has(k):
		return _cache[k]
	var parts := k.split(":")
	if parts.size() < 4 or not TYPES.has(parts[1]):
		return {}
	var wh := parts[2].split("x")
	if wh.size() != 2:
		return {}
	var size := Vector2i(clampi(int(wh[0]), 6, 60), clampi(int(wh[1]), 6, 60))
	var wealth := float(parts[4]) / 100.0 if parts.size() > 4 else 0.5
	var l := generate(parts[1], size, int(parts[3]), wealth)
	_cache[k] = l
	return l


static func generate(type: String, size: Vector2i, p_seed: int, wealth := 0.5) -> Dictionary:
	var t: Dictionary = TYPES.get(type, TYPES["house"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|%d|%d|v%d" % [type, size.x, size.y, p_seed, VERSION])
	var w := float(size.x)
	var h := float(size.y)
	var rooms: Array = []           # {name, kind, rect: Rect2}
	var partitions: Array = []
	var clear: Array = []           # Rect2 kept free of furniture (doors, entrance, passages)
	var entrance_x := floorf(w * 0.5)
	clear.append(Rect2(entrance_x - 2.0, h - 3.5, 4.0, 3.5))          # the entrance gap is cells ex-1, ex
	# --- bands, south (front) to north (back)
	var small := w * h < 150.0 or w < 12.0
	var front_d := clampf(roundf(h * (0.48 if small else 0.38) + rng.randf_range(-1.0, 1.0)), 4.0, 12.0)
	var y_front := h - front_d
	if y_front < CORRIDOR + MIN_ROOM + 1.0:
		small = true
		front_d = clampf(roundf(h * 0.48), 4.0, h - MIN_ROOM)
		y_front = h - front_d
	var bands: Array = []           # [y0, depth, kind] kind = rooms / corridor
	var y := y_front
	if small:
		bands.push_front([0.0, y, "rooms"])
	else:
		while y > 0.0:
			y -= CORRIDOR
			bands.push_front([y, CORRIDOR, "corridor"])
			var rest := y
			var d := rest if rest <= 14.0 else clampf(roundf(rng.randf_range(8.0, 11.0)), MIN_ROOM + 1.0, rest - CORRIDOR - MIN_ROOM - 1.0)
			if rest - d < CORRIDOR + MIN_ROOM + 1.0:
				d = rest
			y -= d
			bands.push_front([y, d, "rooms"])
		# clamp the top band to start at 0
		bands[0][1] = float(bands[0][1]) + float(bands[0][0])
		bands[0][0] = 0.0
	# --- front band: the hall (or living room) around the entrance, side rooms
	var hall_w := w if small or w < 16.0 else clampf(roundf(w * rng.randf_range(0.38, 0.5)), 8.0, w - 2.0 * MIN_ROOM)
	var hx0 := clampf(roundf(entrance_x - hall_w * 0.5), 0.0, w - hall_w)
	var hall := {"kind": str(t["hall"]), "rect": Rect2(hx0, y_front, hall_w, front_d)}
	rooms.append(hall)
	var side_kinds: Array = (t["front_side"] as Array).duplicate()
	for side in [[0.0, hx0], [hx0 + hall_w, w]]:
		var a := float(side[0])
		var b := float(side[1])
		if b - a < MIN_ROOM:
			if b - a > 0.0:
				hall["rect"] = (hall["rect"] as Rect2).merge(Rect2(a, y_front, b - a, front_d))
			continue
		var n := maxi(1, int((b - a) / 7.0))
		var cuts := _split(a, b, n, rng)
		for k in cuts.size() - 1:
			var kind := str(side_kinds[(rooms.size() - 1) % side_kinds.size()])
			rooms.append({"kind": kind, "rect": Rect2(cuts[k], y_front, cuts[k + 1] - cuts[k], front_d)})
	# --- the other bands
	var courtyard_done := false
	var back_kinds: Array = t["back"]
	if small:
		back_kinds = (t["front_side"] as Array) + (t["back"] as Array)     # no side rooms in front: kitchen etc. go back
	var bi := 0
	for band in bands:
		var by := float(band[0])
		var bd := float(band[1])
		if band[2] == "corridor":
			rooms.append({"kind": "corridor", "rect": Rect2(0, by, w, bd)})
			continue
		var n := maxi(1, int(w / rng.randf_range(6.0, 9.0)))
		var cuts := _split(0.0, w, n, rng)
		for k in cuts.size() - 1:
			var kind := str(back_kinds[bi % back_kinds.size()])
			bi += 1
			if bool(t.get("courtyard", false)) and not courtyard_done and k == (cuts.size() - 1) / 2 and bd >= 8.0 and cuts[k + 1] - cuts[k] >= 8.0:
				kind = "courtyard"
				courtyard_done = true
			rooms.append({"kind": kind, "rect": Rect2(cuts[k], by, cuts[k + 1] - cuts[k], bd)})
	# --- partitions: horizontal walls between bands (doors per room), vertical walls inside bands
	var lines := {}
	for r in rooms:
		var rr: Rect2 = r["rect"]
		if rr.position.y > 0.0:
			lines[rr.position.y] = true
	for ly in lines.keys():
		var doors: Array = []
		var openings: Array = []
		# every room touching this line from below or above gets a door into its neighbour band
		for r in rooms:
			var rr: Rect2 = r["rect"]
			if absf(rr.end.y - ly) < 0.01 or absf(rr.position.y - ly) < 0.01:
				if r["kind"] == "corridor":
					continue
				var dx := _door_x(rr, rng)
				if r == hall and small:
					continue                                       # the back rooms' doors open into it
				if r == hall:
					openings.append([dx - 1.0, ly, 4.0])           # the hall opens wide to the corridor
					clear.append(Rect2(dx - 1.5, ly - 2.0, 5.0, 4.0))
				elif not _has_door_near(doors, dx):
					doors.append([dx, ly])
					clear.append(Rect2(dx - 0.5, ly - 2.0, DOOR_W + 1.0, 4.0))
		# inner walls lower than the outer ones: the camera looks over them into the back rooms
		var p := {"from": [0, ly], "to": [w, ly], "wall_tiles": minf(2.0, float(t["wall_tiles"]))}
		if not doors.is_empty():
			p["doors"] = doors
		if not openings.is_empty():
			p["openings"] = openings
		partitions.append(p)
	for r in rooms:
		var rr: Rect2 = r["rect"]
		if rr.position.x > 0.0 and r["kind"] != "corridor":
			var p := {"from": [rr.position.x, rr.position.y], "to": [rr.position.x, rr.end.y], "wall_tiles": minf(2.0, float(t["wall_tiles"]))}
			# front side rooms also open into the hall
			if small and rr.position.y == y_front:
				pass
			partitions.append(p)
	# a small house: the back rooms open straight into the living room (doors above)
	# --- furnishing
	var items: Array = []
	var placed: Array = []          # Rect2 (tiles)
	var pri: Array = []             # placement order for the reachability repair
	for i in rooms.size():
		var r: Dictionary = rooms[i]
		var spec: Dictionary = ROOMS.get(r["kind"], ROOMS["corridor"])
		for rule in spec["items"]:
			if wealth < float(rule[2]):
				continue
			var id := str(rule[0])
			if id == "@bed":
				var cols := ["red", "blue", "green", "ochre"]
				id = ("bed_double_" if (r["rect"] as Rect2).size.x >= 7.0 and rng.randf() < 0.6 else "bed_single_") + str(cols[rng.randi() % cols.size()])
			var e := _place(id, str(rule[1]), r["rect"], placed, clear, rng)
			if not e.is_empty():
				items.append(e)
				pri.append(items.size() - 1)
	var layout := {
		"label": str(t["label"]), "generated": key_for(type, size, p_seed, wealth), "generator_version": VERSION,
		"own_art_only": true, "size": [size.x, size.y], "wall_tiles": float(t["wall_tiles"]),
		"rooms": rooms.map(func(r): return {"name": str(ROOMS.get(r["kind"], {}).get("label", r["kind"])), "kind": r["kind"],
			"rect": [(r["rect"] as Rect2).position.x, (r["rect"] as Rect2).position.y, (r["rect"] as Rect2).size.x, (r["rect"] as Rect2).size.y],
			"floor": str(ROOMS.get(r["kind"], {}).get("floor", t["floor"])), "wall": str(ROOMS.get(r["kind"], {}).get("wall", t["wall"]))}),
		"partitions": partitions, "entrance": {"x": entrance_x}, "items": items,
	}
	_repair(layout)
	return layout


## n+1 cut positions from a to b, every room at least MIN_ROOM wide, jittered.
static func _split(a: float, b: float, n: int, rng: RandomNumberGenerator) -> Array:
	n = maxi(1, mini(n, int((b - a) / MIN_ROOM)))
	var out := [a]
	for k in range(1, n):
		var x := roundf(a + (b - a) * float(k) / n + rng.randf_range(-1.0, 1.0))
		x = clampf(x, float(out[-1]) + MIN_ROOM, b - MIN_ROOM * (n - k))
		out.append(x)
	out.append(b)
	return out


static func _door_x(rr: Rect2, rng: RandomNumberGenerator) -> float:
	var lo := rr.position.x + 1.0
	var hi := rr.end.x - DOOR_W - 1.0
	if hi <= lo:
		return floorf(rr.position.x + (rr.size.x - DOOR_W) * 0.5)
	return floorf(lerpf(lo, hi, 0.5 + rng.randf_range(-0.25, 0.25)))


static func _has_door_near(doors: Array, x: float) -> bool:
	for d in doors:
		if absf(float(d[0]) - x) < DOOR_W + 1.0:
			return true
	return false


## Places one piece by its rule; returns the layout entry or {}.
static func _place(id: String, where: String, room: Rect2, placed: Array, clear: Array, rng: RandomNumberGenerator) -> Dictionary:
	var def: Dictionary = InteriorScene.atlas_data().get("items", {}).get(id, {})
	if def.is_empty():
		return {}
	var r: Array = def["rect"]
	var is_wall := bool(def.get("wall", false))
	var fp := Vector2(float(r[2]) / 16.0, float(def.get("solid", [0, 0, 0, 16])[3]) / 16.0)
	if is_wall:
		var x := room.position.x + 0.6 + rng.randf_range(0.0, maxf(0.0, room.size.x - fp.x - 1.2))
		if x + fp.x > room.end.x - 0.3:
			return {}
		var wr := Rect2(x, room.position.y - 3.0, fp.x, 0.1)
		for p in placed:
			if (p as Rect2).intersects(wr):
				return {}
		for q in clear:                         # not over a door in this wall
			if (q as Rect2).intersects(Rect2(x - 0.3, room.position.y - 1.0, fp.x + 0.6, 1.2)):
				return {}
		placed.append(wr)
		var e := {"item": id, "wall": [snappedf(x, 0.1), 1.2]}
		if room.position.y > 0.0:
			e["row"] = int(room.position.y)
		return e
	var cands: Array = []
	var m := 0.3
	match where:
		"back":
			var x := room.position.x + m
			while x + fp.x <= room.end.x - m:
				cands.append(Vector2(x, room.position.y + 0.15))
				x += 0.5
		"centre":
			var c := room.get_center() - fp * 0.5
			for dx in [0.0, -1.0, 1.0, -2.0, 2.0]:
				for dy in [0.0, 0.5, -0.5, 1.0]:
					cands.append(c + Vector2(dx, dy))
		"west", "east":
			var x2 := room.position.x + m if where == "west" else room.end.x - fp.x - m
			var yy := room.position.y + 2.0
			while yy + fp.y <= room.end.y - m:
				cands.append(Vector2(x2, yy))
				yy += 0.5
		"corner":
			for p in [Vector2(room.end.x - fp.x - m, room.end.y - fp.y - m), Vector2(room.position.x + m, room.end.y - fp.y - m),
					Vector2(room.end.x - fp.x - m, room.position.y + 0.15), Vector2(room.position.x + m, room.position.y + 0.15)]:
				cands.append(p)
	if where == "back" and cands.size() > 2:
		# start somewhere along the wall, deterministic
		var k0 := rng.randi() % cands.size()
		cands = cands.slice(k0) + cands.slice(0, k0)
	for c in cands:
		var rect := Rect2(c, fp)
		if rect.position.x < room.position.x + 0.1 or rect.end.x > room.end.x - 0.1 or rect.position.y < room.position.y or rect.end.y > room.end.y - 0.2:
			continue
		var walk := rect.grow(0.45)              # keep a narrow walkway around each piece
		var ok := true
		for p in placed:
			if (p as Rect2).intersects(walk):
				ok = false
				break
		if ok:
			for q in clear:
				if (q as Rect2).intersects(rect):
					ok = false
					break
		if ok:
			placed.append(rect)
			return {"item": id, "at": [snappedf(c.x, 0.05), snappedf(c.y, 0.05)]}
	return {}


## Checks that all rooms and doors are connected on a 0.5-tile occupancy grid;
## drops furniture (last placed first) until they are.
static func _repair(layout: Dictionary) -> void:
	var guard := 0
	while guard < 200:
		var bad := unreachable_rooms(layout)
		if bad.is_empty():
			return
		var items: Array = layout["items"]
		var dropped := false
		for k in range(items.size() - 1, -1, -1):
			var e: Dictionary = items[k]
			if e.has("at"):
				items.remove_at(k)
				dropped = true
				break
		if not dropped:
			return
		guard += 1


## Room indices that cannot be reached from the entrance (generator grid).
static func unreachable_rooms(layout: Dictionary) -> Array:
	var res := 2
	var w := int(layout["size"][0]) * res
	var h := int(layout["size"][1]) * res
	var g := PackedByteArray()
	g.resize(w * h)
	g.fill(0)
	var at: Dictionary = InteriorScene.atlas_data().get("items", {})
	for e in layout["items"]:
		if not e.has("at"):
			continue
		var d: Dictionary = at.get(e["item"], {})
		if d.is_empty():
			continue
		var fp := Vector2(float(d["rect"][2]) / 16.0, float(d.get("solid", [0, 0, 0, 16])[3]) / 16.0)
		if fp.y <= 0.0:
			continue
		_mark(g, w, h, res, Rect2(Vector2(float(e["at"][0]), float(e["at"][1])), fp).grow(0.28))
	for p in layout.get("partitions", []):
		var a := Vector2(float(p["from"][0]), float(p["from"][1]))
		var b := Vector2(float(p["to"][0]), float(p["to"][1]))
		var vertical := absf(a.x - b.x) < 0.01
		var gaps: Array = []
		for o in p.get("openings", []):
			gaps.append([float(o[1]) if vertical else float(o[0]), float(o[2])])
		for dd in p.get("doors", []):
			gaps.append([float(dd[1]) if vertical else float(dd[0]), DOOR_W])
		var t0 := a.y if vertical else a.x
		var t1 := b.y if vertical else b.x
		var s := t0
		while s < t1:
			var open := false
			for gp in gaps:
				if s + 0.25 >= float(gp[0]) and s + 0.25 <= float(gp[0]) + float(gp[1]):
					open = true
			if not open:
				var cell := Rect2(a.x - 0.3, s, 0.6, 0.5) if vertical else Rect2(s, a.y - 0.3, 0.5, 0.6)
				_mark(g, w, h, res, cell)
			s += 0.5
	# flood from the entrance
	var ex := int(float(layout["entrance"]["x"]) * res) + 1
	var start := (h - 2) * w + ex
	var seen := PackedByteArray()
	seen.resize(w * h)
	seen.fill(0)
	var q := [start]
	if g[start] == 0:
		seen[start] = 1
	else:
		q = []
	while not q.is_empty():
		var k: int = q.pop_back()
		var i := k % w
		var j := k / w
		for dv: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni := i + dv.x
			var nj := j + dv.y
			if ni < 0 or nj < 0 or ni >= w or nj >= h:
				continue
			var nk := nj * w + ni
			if seen[nk] == 0 and g[nk] == 0:
				seen[nk] = 1
				q.append(nk)
	var bad: Array = []
	var rooms: Array = layout["rooms"]
	for ri in rooms.size():
		var rr: Array = rooms[ri]["rect"]
		var any := false
		for j in range(int(float(rr[1]) * res), int((float(rr[1]) + float(rr[3])) * res)):
			for i in range(int(float(rr[0]) * res), int((float(rr[0]) + float(rr[2])) * res)):
				if i >= 0 and j >= 0 and i < w and j < h and seen[j * w + i] == 1:
					any = true
					break
			if any:
				break
		if not any:
			bad.append(ri)
	return bad


static func _mark(g: PackedByteArray, w: int, h: int, res: int, r: Rect2) -> void:
	for j in range(maxi(0, int(floor(r.position.y * res))), mini(h, int(ceil(r.end.y * res)))):
		for i in range(maxi(0, int(floor(r.position.x * res))), mini(w, int(ceil(r.end.x * res)))):
			g[j * w + i] = 1
