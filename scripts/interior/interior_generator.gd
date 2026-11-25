class_name InteriorGenerator
extends RefCounted
## Dynamic interiors (docs/INTERIOR_STANDARD.md §8) – the regular basis for
## every settlement building (and later for every building a player builds):
## the building's real footprint (any shape: rectangles, L, U, courtyards),
## its type, storeys, a seed and the prosperity give rooms, corridors, doors,
## stairwells and furniture, in the layout format of InteriorScene.
##
## Pipeline
##   1. shape: footprint mask → wings (rectangles) + courtyards (enclosed holes)
##   2. rooms: the main wing (with the entrance) in east-west bands – front
##      band with hall/living room, side rooms and (for several storeys) the
##      stairwell, then corridors and room rows; side wings get a corridor or
##      a spine along the side where they join
##   3. doors: a connection graph over all touching rooms – circulation
##      (hall, corridors, stairwell) opens to each other, every room gets a
##      door to a corridor (else to a neighbour), until everything is
##      reachable from the entrance
##   4. furniture: rules per room kind (bought Penzilla pieces when the
##      build has them, own WORLDS art otherwise), walkways kept free
##   5. check: an occupancy grid; pieces are dropped until every room is
##      reachable (the tests also run the engine's real walk grid)
## Reproducible: a building persists only its key
##   gen:<type>:<W>x<H>:<seed>:<wealth %>[:w<x.y.w.h_…>][:c<x.y.w.h_…>][:s<storeys>][:f<floor>]
## and VERSION is part of the seed.

const VERSION := 2
const MIN_ROOM := 4.0
const CORRIDOR := 3.0
const DOOR_W := 2.0
const TILES_PER_CELL := Vector2(9.0, 8.0)    # settlement footprint cell → interior tiles
const MARGIN := Vector2(4.0, 3.0)

## Building types: room programme per band and floor, materials, wall height, storeys.
const TYPES := {
	"house": {"label": "Wohnhaus", "hall": "living", "front_side": ["kitchen"], "back": ["bedroom", "bath", "bedroom", "bedroom"],
		"upper": ["bedroom", "bath", "bedroom", "bedroom", "study"], "floor": "parquet_cream|wood_floor", "wall": "wall_cream|wall_plaster", "wall_tiles": 3.0},
	"shop": {"label": "Laden", "hall": "sales", "front_side": ["storage"], "back": ["storage", "office"], "upper": ["bedroom", "bath", "living"],
		"floor": "boards_cream|stone_flags", "wall": "wall_beige|wall_plaster", "wall_tiles": 3.0},
	"bakery": {"label": "Bäckerei", "hall": "bakery_shop", "front_side": ["storage"], "back": ["bakehouse", "storage"], "upper": ["bedroom", "bath", "living"],
		"floor": "tiles_orange|stone_flags", "wall": "wall_cream|wall_plaster", "wall_tiles": 3.0},
	"grocer": {"label": "Gemischtwaren", "hall": "grocer_shop", "front_side": ["storage"], "back": ["storage", "office"], "upper": ["bedroom", "bath", "living"],
		"floor": "boards_cream|stone_flags", "wall": "wall_beige|wall_plaster", "wall_tiles": 3.0},
	"smithy": {"label": "Schmiede", "hall": "forge_room", "front_side": ["storage"], "back": ["workshop", "storage"], "upper": ["bedroom", "bath"],
		"floor": "stone_flags", "wall": "wall_brick", "wall_tiles": 3.5},
	"office": {"label": "Rathaus", "hall": "reception", "front_side": ["office", "office"], "back": ["council_room", "office", "archive", "office"],
		"upper": ["office", "meeting", "archive", "office", "office"], "floor": "marble_floor", "wall": "wall_marble", "wall_tiles": 3.5, "storeys": 2},
	"clinic": {"label": "Praxis", "hall": "waiting", "front_side": ["office"], "back": ["treatment", "treatment", "storage", "bath"],
		"upper": ["ward", "ward", "office", "bath"], "floor": "clinic_tiles", "wall": "wall_tiles", "wall_tiles": 3.0},
	"workshop": {"label": "Werkstatt", "hall": "workshop", "front_side": ["storage"], "back": ["storage", "office"], "upper": ["storage", "office"],
		"floor": "stone_flags", "wall": "wall_brick", "wall_tiles": 4.0},
	"depot": {"label": "Depot", "hall": "storage", "front_side": ["office"], "back": ["storage", "storage"], "upper": ["storage"],
		"floor": "metal_plates|stone_flags", "wall": "wall_brick", "wall_tiles": 4.0},
	"emergency": {"label": "Rettungswache", "hall": "garage", "front_side": ["office"], "back": ["rest_room", "storage", "bath"], "upper": ["rest_room", "office"],
		"floor": "metal_plates|stone_flags", "wall": "wall_tiles", "wall_tiles": 3.5},
	"utility": {"label": "Technikgebäude", "hall": "plant_room", "front_side": ["office"], "back": ["plant_room", "storage"], "upper": ["storage"],
		"floor": "metal_plates", "wall": "wall_brick", "wall_tiles": 4.0},
	"palace": {"label": "Palast", "hall": "hall", "front_side": ["reception", "dining"], "back": ["chamber", "library", "bedroom", "bath", "kitchen", "chamber", "gallery"],
		"upper": ["bedroom", "chamber", "library", "bath", "bedroom", "gallery"], "floor": "marble_floor", "wall": "wall_fresco", "wall_tiles": 4.5, "storeys": 2, "courtyard": true},
}

## Room kinds: materials and furnishing rules [item(s), where, min_wealth].
## "a|b": the first piece this build has (bought Penzilla piece, else own art).
## where: back, centre, west/east, corner, wall (hung), floor (rug, flat).
const ROOMS := {
	"living": {"label": "Wohnraum", "items": [["rug_big|rug_long", "floor", 0.3], ["dining_set", "centre", 0.0], ["sofa_cushions|sofa|bench", "back", 0.0],
		["bookcase|scroll_shelf", "back", 0.35], ["lamp_floor|candelabrum", "corner", 0.0], ["plant|planter", "corner", 0.2], ["fireplace_lit|stove_wood", "back", 0.6],
		["window_4|mural", "wall", 0.0], ["picture|banner_blue", "wall", 0.3], ["clock_wall", "wall", 0.5]]},
	"kitchen": {"label": "Küche", "floor": "tiles_orange|stone_flags", "items": [["counter_sink|food_counter", "back", 0.0], ["cooker|bread_oven", "back", 0.0],
		["fridge|water_station", "back", 0.0], ["table_round|reading_table", "centre", 0.2], ["kitchen_upper|pot_shelf", "wall", 0.0], ["window_2", "wall", 0.0],
		["crate_big|barrel", "corner", 0.0]]},
	"bedroom": {"label": "Schlafzimmer", "items": [["rug_round", "floor", 0.3], ["@bed", "back", 0.0], ["nightstand", "back", 0.0], ["wardrobe|wardrobe_light", "back", 0.0],
		["dresser|wardrobe_light", "west", 0.5], ["plant|planter", "corner", 0.3], ["window_2|banner_blue", "wall", 0.0], ["painting|picture", "wall", 0.5]]},
	"study": {"label": "Arbeitszimmer", "items": [["desk|office_desk", "centre", 0.0], ["bookcase_dark|scroll_shelf", "back", 0.0], ["armchair|bench", "corner", 0.0],
		["lamp_floor|candelabrum", "corner", 0.0], ["window_4", "wall", 0.0], ["clock_wall|map_wall", "wall", 0.3]]},
	"bath": {"label": "Bad", "floor": "tiles_orange|clinic_tiles", "wall": "wall_beige|wall_tiles", "items": [["bathtub|shower_cabin", "back", 0.0], ["toilet|bath_shelf", "back", 0.0],
		["basin|water_station", "back", 0.0], ["towel_rack", "wall", 0.0], ["bath_cabinet", "wall", 0.3], ["window_small", "wall", 0.0]]},
	"sales": {"label": "Verkaufsraum", "items": [["shop_counter", "centre", 0.0], ["goods_shelf", "back", 0.0], ["goods_shelf|bread_shelf", "back", 0.3],
		["plant|planter", "corner", 0.3], ["notice_board|board", "wall", 0.0], ["window_4", "wall", 0.0]]},
	"bakery_shop": {"label": "Bäckerei", "items": [["shop_counter", "centre", 0.0], ["bread_shelf", "back", 0.0], ["bread_shelf", "back", 0.0],
		["table_round", "corner", 0.3], ["window_4", "wall", 0.0], ["clock_wall|notice_board", "wall", 0.0]]},
	"bakehouse": {"label": "Backstube", "floor": "tiles_orange|stone_flags", "items": [["bread_oven", "back", 0.0], ["workbench", "back", 0.0], ["sacks", "corner", 0.0],
		["barrel", "corner", 0.0], ["pot_shelf|kitchen_upper", "wall", 0.0]]},
	"grocer_shop": {"label": "Laden", "items": [["shop_counter", "centre", 0.0], ["veg_stand", "west", 0.0], ["goods_shelf", "back", 0.0], ["goods_shelf", "back", 0.0],
		["crate_big|barrel", "corner", 0.0], ["window_4", "wall", 0.0], ["notice_board|board", "wall", 0.0]]},
	"forge_room": {"label": "Schmiede", "items": [["forge", "back", 0.0], ["anvil", "centre", 0.0], ["workbench", "back", 0.0], ["tool_wall", "wall", 0.0],
		["barrel", "corner", 0.0], ["shop_counter", "east", 0.3]]},
	"storage": {"label": "Lager", "items": [["pallet_rack", "back", 0.0], ["equipment_rack|pallet_rack", "back", 0.0], ["crate_big|barrel", "corner", 0.0], ["sacks", "corner", 0.0]]},
	"office": {"label": "Büro", "items": [["office_desk|desk", "centre", 0.0], ["bookcase|filing_cabinet", "back", 0.0], ["archive_cabinet", "back", 0.2],
		["plant|planter", "corner", 0.3], ["window_4", "wall", 0.0], ["map_wall|board", "wall", 0.4], ["clock_wall", "wall", 0.3]]},
	"council_room": {"label": "Ratszimmer", "floor": "mosaic|marble_floor", "items": [["conference_table", "centre", 0.0], ["flag_stand", "back", 0.0],
		["flag_stand", "back", 0.0], ["banner_red", "wall", 0.0], ["map_wall", "wall", 0.0], ["plant|planter", "corner", 0.3]]},
	"reception": {"label": "Empfang", "items": [["rug_big", "floor", 0.3], ["reception_desk", "centre", 0.0], ["waiting_chairs", "west", 0.0], ["waiting_chairs", "east", 0.0],
		["flag_stand", "back", 0.2], ["notice_board", "wall", 0.0], ["plant|planter", "corner", 0.2], ["clock_wall", "wall", 0.0]]},
	"meeting": {"label": "Besprechung", "items": [["conference_table", "centre", 0.0], ["flag_stand", "back", 0.4], ["map_wall|board", "wall", 0.0], ["plant|planter", "corner", 0.3]]},
	"archive": {"label": "Archiv", "items": [["archive_cabinet", "back", 0.0], ["scroll_shelf|bookcase", "back", 0.0], ["archive_cabinet", "back", 0.0],
		["reading_table", "centre", 0.2], ["ladder", "back", 0.3]]},
	"waiting": {"label": "Wartebereich", "floor": "clinic_tiles", "items": [["reception_desk", "back", 0.0], ["waiting_chairs", "west", 0.0], ["waiting_chairs", "east", 0.0],
		["plant|planter", "corner", 0.0], ["notice_board", "wall", 0.0], ["clock_wall", "wall", 0.0]]},
	"treatment": {"label": "Behandlung", "floor": "clinic_tiles", "wall": "wall_tiles", "items": [["med_bed", "back", 0.0], ["med_cabinet", "back", 0.0],
		["med_screen", "centre", 0.2], ["basin|water_station", "back", 0.0]]},
	"ward": {"label": "Krankenzimmer", "floor": "clinic_tiles", "wall": "wall_tiles", "items": [["med_bed", "back", 0.0], ["med_bed", "back", 0.0], ["nightstand", "back", 0.0],
		["window_2", "wall", 0.0]]},
	"workshop": {"label": "Werkstatt", "items": [["workbench", "back", 0.0], ["tool_wall", "wall", 0.0], ["anvil", "centre", 0.4], ["barrel", "corner", 0.0], ["sacks", "corner", 0.0]]},
	"garage": {"label": "Fahrzeughalle", "items": [["stretcher", "back", 0.0], ["equipment_rack", "back", 0.0], ["hose_rack", "wall", 0.0], ["control_panel", "east", 0.0]]},
	"rest_room": {"label": "Bereitschaftsraum", "items": [["cot|mattress_floor", "back", 0.0], ["cot|mattress_floor", "back", 0.0], ["table_round|reading_table", "centre", 0.0],
		["window_2", "wall", 0.0]]},
	"plant_room": {"label": "Technikraum", "floor": "metal_plates", "items": [["generator|water_tank", "back", 0.0], ["control_panel", "back", 0.0], ["pump", "centre", 0.0],
		["equipment_rack", "corner", 0.0]]},
	"hall": {"label": "Halle", "floor": "mosaic", "items": [["fountain_small", "centre", 0.0], ["statue", "back", 0.0], ["statue_gold", "back", 0.7],
		["bench_marble", "west", 0.0], ["bench_marble", "east", 0.0], ["candelabrum", "corner", 0.0], ["mural", "wall", 0.0], ["banner_red", "wall", 0.4]]},
	"dining": {"label": "Speisesaal", "items": [["dining_set", "centre", 0.0], ["dining_set", "centre", 0.5], ["food_counter", "back", 0.0],
		["candelabrum", "corner", 0.0], ["mural", "wall", 0.3]]},
	"chamber": {"label": "Kammer", "floor": "mosaic", "items": [["reading_table", "centre", 0.0], ["bust", "back", 0.0], ["vitrine", "back", 0.3],
		["bench_marble", "back", 0.0], ["banner_gold", "wall", 0.0]]},
	"library": {"label": "Bibliothek", "items": [["scroll_shelf|bookcase", "back", 0.0], ["scroll_shelf|bookcase_dark", "back", 0.0], ["reading_table", "centre", 0.0],
		["ladder", "back", 0.0], ["candelabrum", "corner", 0.0]]},
	"gallery": {"label": "Galerie", "items": [["statue", "back", 0.0], ["bust", "back", 0.0], ["vitrine", "centre", 0.0], ["amphora", "corner", 0.0], ["mural", "wall", 0.0]]},
	"courtyard": {"label": "Innenhof", "floor": "stone_flags", "items": [["fountain_small", "centre", 0.0], ["planter", "corner", 0.0],
		["bench_marble", "west", 0.0], ["bench_marble", "east", 0.0], ["planter", "back", 0.0], ["planter", "back", 0.0]]},
	"corridor": {"label": "Flur", "items": [["rug_long", "floor", 0.6], ["plant|planter", "corner", 0.3], ["coat_rack", "back", 0.2], ["picture|painting", "wall", 0.4],
		["clock_tall|bust", "back", 0.7]]},
	"stairs": {"label": "Treppenhaus", "items": [["staircase", "back", 0.0], ["plant|planter", "corner", 0.4]]},
}

static var _cache: Dictionary = {}
static var debug_no_repair := false


# --- keys ----------------------------------------------------------------------------------

## Key of a generated interior. wings/courts: Rect2i lists (tiles); empty = one rectangle.
static func key_for(type: String, size: Vector2i, p_seed: int, wealth := 0.5, wings: Array = [], courts: Array = [], storeys := 0, floor_i := 0) -> String:
	var k := "gen:%s:%dx%d:%d:%d" % [type, size.x, size.y, p_seed, int(round(wealth * 100.0))]
	if not wings.is_empty():
		k += ":w" + _enc(wings)
	if not courts.is_empty():
		k += ":c" + _enc(courts)
	if storeys > 0:
		k += ":s%d" % storeys
	if floor_i > 0:
		k += ":f%d" % floor_i
	return k


## The same building, another floor.
static func with_floor(k: String, floor_i: int) -> String:
	var parts := Array(k.split(":")).filter(func(p): return not str(p).begins_with("f"))
	var out := ":".join(PackedStringArray(parts))
	return out + (":f%d" % floor_i if floor_i > 0 else "")


static func _enc(rects: Array) -> String:
	return "_".join(PackedStringArray(rects.map(func(r): return "%d.%d.%d.%d" % [r.position.x, r.position.y, r.size.x, r.size.y])))


static func _dec(s: String) -> Array:
	var out: Array = []
	for part in s.split("_"):
		var v := part.split(".")
		if v.size() == 4:
			out.append(Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3])))
	return out


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
	var size := Vector2i(clampi(int(wh[0]), 6, 80), clampi(int(wh[1]), 6, 80))
	var wealth := float(parts[4]) / 100.0 if parts.size() > 4 else 0.5
	var wings: Array = []
	var courts: Array = []
	var storeys := 0
	var floor_i := 0
	for p in parts.slice(5):
		if p.begins_with("w"):
			wings = _dec(p.substr(1))
		elif p.begins_with("c"):
			courts = _dec(p.substr(1))
		elif p.begins_with("s"):
			storeys = int(p.substr(1))
		elif p.begins_with("f"):
			floor_i = int(p.substr(1))
	var l := generate(parts[1], size, int(parts[3]), wealth, wings, courts, storeys, floor_i)
	l["key"] = k
	_cache[k] = l
	return l


# --- settlement buildings ----------------------------------------------------------------------

## Generator type of a settlement building ("" = no interior). Every regular
## settlement building – and later every building a player builds – gets a
## generated interior; only landmark interiors (Concordium) are hand-made.
static func type_for_building(building_type: String, entry: Dictionary = {}) -> String:
	match building_type:
		"house", "player_home":
			return "house"
		"shop":
			return {"bakery": "bakery", "grocer": "grocer", "smith": "smithy"}.get(str(entry.get("business", "")), "shop")
		"farm_shop":
			return "grocer"
		"trade_post":
			return "shop"
		"town_hall":
			return "office"
		"clinic":
			return "clinic"
		"workshop":
			return "workshop"
		"depot":
			return "depot"
		"emergency_post":
			return "emergency"
		"water_works", "energy_station":
			return "utility"
		"palace":
			return "palace"
	return ""


# --- the building's shape --------------------------------------------------------------------

## Interior key of a settlement building from its real footprint: the
## footprint cells (and, for complex buildings, the solid polygons of
## data/buildings/footprints.json) are rasterised to interior tiles and cut
## into wings; enclosed holes become courtyards.
static func key_for_building(type: String, footprint_cells: Vector2, spec: Dictionary, p_seed: int, wealth: float, storeys := 0) -> String:
	var size := Vector2i(int(round(footprint_cells.x * TILES_PER_CELL.x + MARGIN.x)), int(round(footprint_cells.y * TILES_PER_CELL.y + MARGIN.y)))
	size = Vector2i(clampi(size.x, 10, 80), clampi(size.y, 8, 80))
	var polys: Array = spec.get("solid", [])
	if polys.is_empty() and not bool(TYPES.get(type, {}).get("courtyard", false)):
		return key_for(type, size, p_seed, wealth, [], [], storeys)
	var mask := {}
	if polys.is_empty():
		for y in size.y:
			for x in size.x:
				mask[Vector2i(x, y)] = true
	else:
		var sx := float(size.x) / footprint_cells.x
		var sy := float(size.y) / footprint_cells.y
		for y in size.y:
			for x in size.x:
				var p := Vector2((x + 0.5) / sx, (y + 0.5) / sy)
				for poly in polys:
					var pts := PackedVector2Array()
					for q in poly:
						pts.append(Vector2(float(q[0]), float(q[1])))
					if Geometry2D.is_point_in_polygon(p, pts):
						mask[Vector2i(x, y)] = true
						break
	var shape := shape_from_mask(mask, size, bool(TYPES.get(type, {}).get("courtyard", false)))
	return key_for(type, size, p_seed, wealth, shape["wings"], shape["courts"], storeys)


## Wings (maximal rectangles, at least 5 tiles thick) and courtyards of a mask.
static func shape_from_mask(mask: Dictionary, size: Vector2i, want_courtyard := false) -> Dictionary:
	var m := mask.duplicate()
	var courts: Array = []
	if want_courtyard and size.x >= 24 and size.y >= 20:
		# a palace around a courtyard: the courtyard is cut from the middle
		var cw := int(size.x * 0.34)
		var ch := int(size.y * 0.3)
		var cr := Rect2i((size.x - cw) / 2, (size.y - ch) / 2 - 1, cw, ch)
		courts.append(cr)
		for y in range(cr.position.y, cr.end.y):
			for x in range(cr.position.x, cr.end.x):
				m.erase(Vector2i(x, y))
	var wings: Array = []
	var left := m.duplicate()
	while not left.is_empty():
		var best := _largest_rect(left, size)
		if best.size.x < 4 or best.size.y < 4:
			break                                   # slivers are left out (the walls close them)
		wings.append(best)
		for y in range(best.position.y, best.end.y):
			for x in range(best.position.x, best.end.x):
				left.erase(Vector2i(x, y))
	# the main wing (entrance) first: the one reaching furthest to the front, widest
	wings.sort_custom(func(a, b): return a.end.y > b.end.y or (a.end.y == b.end.y and a.size.x > b.size.x))
	return {"wings": wings, "courts": courts}


static func _largest_rect(cells: Dictionary, size: Vector2i) -> Rect2i:
	var best := Rect2i()
	var heights := PackedInt32Array()
	heights.resize(size.x)
	for y in size.y:
		for x in size.x:
			heights[x] = heights[x] + 1 if cells.has(Vector2i(x, y)) else 0
		for x in size.x:
			if heights[x] == 0:
				continue
			var hmin := heights[x]
			for x2 in range(x, size.x):
				if heights[x2] == 0:
					break
				hmin = mini(hmin, heights[x2])
				var area := hmin * (x2 - x + 1)
				if area > best.get_area():
					best = Rect2i(x, y - hmin + 1, x2 - x + 1, hmin)
	return best


# --- generation ------------------------------------------------------------------------------

static func generate(type: String, size: Vector2i, p_seed: int, wealth := 0.5, wings: Array = [], courts: Array = [], storeys := 0, floor_i := 0) -> Dictionary:
	var t: Dictionary = TYPES.get(type, TYPES["house"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|%d|%d|%s|%s|v%d" % [type, size.x, size.y, p_seed, _enc(wings), _enc(courts), VERSION])
	if wings.is_empty():
		wings = [Rect2i(Vector2i.ZERO, size)]
	if storeys <= 0:
		storeys = int(t.get("storeys", 2 if size.x * size.y >= 400 else 1))
	if wings[0].size.x < 14 or wings[0].size.y < 10:
		storeys = 1                                   # no room for a stairwell in the entrance wing
	floor_i = clampi(floor_i, 0, storeys - 1)
	var main: Rect2i = wings[0]
	var rooms: Array = []        # {kind, rect: Rect2, role}
	var entrance_x := floorf(main.position.x + main.size.x * 0.5)
	# 1. the main wing: bands from the front
	var stairs_rect := Rect2()
	if storeys > 1:
		var sw := 4.0
		stairs_rect = Rect2(main.end.x - sw, main.end.y - minf(6.0, main.size.y * 0.45), sw, minf(6.0, main.size.y * 0.45))
	_main_wing(rooms, Rect2(main), t, entrance_x, stairs_rect, floor_i, rng)
	for r in rooms:
		if r["kind"] == "stairs":
			stairs_rect = r["rect"]                # as built (full depth of the front band)
	# 2. side wings: corridor (or spine) along the side where they join
	for wi in range(1, wings.size()):
		_side_wing(rooms, Rect2(wings[wi]), Rect2(main), t, floor_i, rng)
	for cr in courts:
		rooms.append({"kind": "courtyard" if floor_i == 0 else "void", "rect": Rect2(cr), "role": "court"})
	rooms = rooms.filter(func(r): return r["kind"] != "void")
	# 3. doors
	var conn := _connect(rooms, entrance_x if floor_i == 0 else -1.0, stairs_rect, Rect2(main), rng)
	var partitions: Array = conn["partitions"]
	var clear: Array = conn["clear"]
	if floor_i == 0:
		clear.append(Rect2(entrance_x - 2.0, main.end.y - 3.5, 4.0, 3.5))
	else:
		clear.append(stairs_rect.grow(0.5))
	# 4. furniture
	var items: Array = []
	var placed: Array = []
	var own_only := true
	for r in rooms:
		var spec: Dictionary = ROOMS.get(r["kind"], ROOMS["corridor"])
		for rule in spec["items"]:
			if wealth < float(rule[2]):
				continue
			var id := _pick_item(str(rule[0]), r["rect"], rng)
			if id == "":
				continue
			if str(rule[0]) == "staircase":
				# stairwell: the flight on the back wall, the same place on every floor
				var e0 := {"item": id, "at": [r["rect"].position.x + 0.5, r["rect"].position.y + 0.2], "action": "stairs_down" if floor_i > 0 else "stairs_up", "label": "Treppe"}
				if floor_i > 0 and floor_i < storeys - 1:
					e0["action"] = "stairs_up"
				items.append(e0)
				placed.append(Rect2(r["rect"].position + Vector2(0.5, 0.2), footprint(InteriorScene.atlas_data()["items"].get(id, {}))))
				continue
			var e := _place(id, str(rule[1]), r["rect"], placed, clear, rng)
			if not e.is_empty():
				items.append(e)
				if not str(InteriorScene.atlas_data()["items"].get(id, {}).get("sheet", "")).begins_with("worlds/"):
					own_only = false
	var floor_tex := _pick_tex(str(t["floor"]), "floors")
	var wall_tex := _pick_tex(str(t["wall"]), "walls")
	var labels := {}
	var layout := {
		"label": str(t["label"]) + ("" if floor_i == 0 else " – %d. Obergeschoss" % floor_i if floor_i > 1 else " – Obergeschoss"),
		"generated": true, "generator_version": VERSION, "storeys": storeys, "floor": floor_i,
		"own_art_only": own_only, "size": [size.x, size.y], "wall_tiles": float(t["wall_tiles"]),
		"rooms": rooms.map(func(r): return {"name": str(ROOMS.get(r["kind"], {}).get("label", r["kind"])), "kind": r["kind"], "role": r["role"],
			"rect": [(r["rect"] as Rect2).position.x, (r["rect"] as Rect2).position.y, (r["rect"] as Rect2).size.x, (r["rect"] as Rect2).size.y],
			"floor": _pick_tex(str(ROOMS.get(r["kind"], {}).get("floor", t["floor"])), "floors"), "wall": _pick_tex(str(ROOMS.get(r["kind"], {}).get("wall", t["wall"])), "walls")}),
		"partitions": partitions, "items": items,
	}
	if floor_i == 0:
		layout["entrance"] = {"x": entrance_x}
	else:
		layout["arrive"] = [stairs_rect.position.x + stairs_rect.size.x * 0.5, stairs_rect.end.y - 1.0]
	if storeys > 1:
		layout["stairs_rect"] = [stairs_rect.position.x, stairs_rect.position.y, stairs_rect.size.x, stairs_rect.size.y]
	if not debug_no_repair:
		_repair(layout)
	return layout


static func _pick_tex(spec: String, part: String) -> String:
	var lib: Dictionary = InteriorScene.atlas_data().get(part, {})
	for id in spec.split("|"):
		if lib.has(id) and (str(lib[id].get("sheet", "")).begins_with("worlds/") or InteriorScene.assets_available()):
			return id
	return spec.split("|")[-1]


static func _pick_item(spec: String, room: Rect2, rng: RandomNumberGenerator) -> String:
	var items: Dictionary = InteriorScene.atlas_data().get("items", {})
	if spec == "@bed":
		var cols := ["red", "blue", "green", "ochre"]
		spec = ("bed_double_" if room.size.x >= 7.0 and rng.randf() < 0.6 else "bed_single_") + str(cols[rng.randi() % cols.size()])
	for id in spec.split("|"):
		if not items.has(id):
			continue
		if str(items[id].get("sheet", "")).begins_with("worlds/") or InteriorScene.assets_available():
			return id
	return ""


static func footprint(def: Dictionary) -> Vector2:
	if def.is_empty():
		return Vector2(1, 1)
	if def.has("footprint"):
		return Vector2(float(def["footprint"][0]), float(def["footprint"][1]))
	var r: Array = def["rect"]
	var solid: Array = def.get("solid", [0, r[3] * 0.55, r[2], r[3] * 0.45])
	return Vector2(maxf(0.5, float(r[2]) / 16.0), maxf(0.35, float(solid[3]) / 16.0))


static func _is_flat(def: Dictionary) -> bool:
	var r: Array = def["rect"]
	var solid: Array = def.get("solid", [0, r[3] * 0.55, r[2], r[3] * 0.45])
	return float(solid[2]) == 0.0 or float(solid[3]) == 0.0


## Main wing: front band (hall/living + side rooms + stairwell), then
## corridors and room rows (upper floors: a landing instead of the hall).
static func _main_wing(rooms: Array, wr: Rect2, t: Dictionary, entrance_x: float, stairs_rect: Rect2, floor_i: int, rng: RandomNumberGenerator) -> void:
	var w := wr.size.x
	var h := wr.size.y
	var small := w * h < 150.0 or w < 12.0
	var front_d := clampf(roundf(h * (0.48 if small else 0.38) + rng.randf_range(-1.0, 1.0)), 4.0, 12.0)
	if h - front_d < CORRIDOR + MIN_ROOM + 1.0:
		small = true
		front_d = clampf(roundf(h * 0.48), 4.0, h - MIN_ROOM)
	var y_front := wr.end.y - front_d
	var front_right := wr.end.x
	if stairs_rect.size.x > 0.0:
		stairs_rect.position.y = y_front
		stairs_rect.size.y = front_d
		rooms.append({"kind": "stairs", "rect": Rect2(wr.end.x - stairs_rect.size.x, y_front, stairs_rect.size.x, front_d), "role": "circulation"})
		front_right = wr.end.x - stairs_rect.size.x
	var upper := floor_i > 0
	var hall_kind := "corridor" if upper else str(t["hall"])
	var fw := front_right - wr.position.x
	var hall_w := fw if small or fw < 16.0 else clampf(roundf(fw * rng.randf_range(0.38, 0.5)), 8.0, fw - 2.0 * MIN_ROOM)
	var hx0 := clampf(roundf(entrance_x - hall_w * 0.5), wr.position.x, front_right - hall_w)
	if upper:
		hall_w = fw
		hx0 = wr.position.x
	rooms.append({"kind": hall_kind, "rect": Rect2(hx0, y_front, hall_w, front_d), "role": "circulation" if upper or not small else "hall", "hall": true})
	var side_kinds: Array = t["front_side"]
	var n_side := 0
	for side in [[wr.position.x, hx0], [hx0 + hall_w, front_right]]:
		var a := float(side[0])
		var b := float(side[1])
		if b - a < MIN_ROOM:
			if b - a > 0.0:
				var hr: Dictionary = rooms.filter(func(r): return r.get("hall", false))[0]
				hr["rect"] = (hr["rect"] as Rect2).merge(Rect2(a, y_front, b - a, front_d))
			continue
		var cuts := _split(a, b, maxi(1, int((b - a) / 7.0)), rng)
		for k in cuts.size() - 1:
			var kind := str(side_kinds[n_side % side_kinds.size()]) if not upper else str((t["upper"] as Array)[n_side % (t["upper"] as Array).size()])
			n_side += 1
			rooms.append({"kind": kind, "rect": Rect2(cuts[k], y_front, cuts[k + 1] - cuts[k], front_d), "role": "room"})
	# back part: corridor + room rows (bands)
	var programme: Array = (t["front_side"] as Array) + (t["back"] as Array) if small and not upper else (t["upper"] if upper else t["back"])
	_bands(rooms, Rect2(wr.position.x, wr.position.y, w, y_front - wr.position.y), programme, not small or upper, rng, n_side)


## Rows of rooms above y_end, with corridors in between (from the front).
static func _bands(rooms: Array, area: Rect2, programme: Array, corridors: bool, rng: RandomNumberGenerator, offset: int) -> void:
	var y := area.end.y
	var bi := offset
	while y > area.position.y + 0.01:
		if corridors:
			if y - area.position.y < CORRIDOR + MIN_ROOM:
				# too little left for a corridor and a row: the rest joins the row below
				break
			y -= CORRIDOR
			rooms.append({"kind": "corridor", "rect": Rect2(area.position.x, y, area.size.x, CORRIDOR), "role": "circulation"})
		var rest := y - area.position.y
		var d := rest if rest <= 14.0 else clampf(roundf(rng.randf_range(8.0, 11.0)), MIN_ROOM + 1.0, rest - CORRIDOR - MIN_ROOM - 1.0)
		if rest - d < CORRIDOR + MIN_ROOM + 1.0:
			d = rest
		y -= d
		var n := maxi(1, int(area.size.x / rng.randf_range(6.0, 9.0)))
		var cuts := _split(area.position.x, area.end.x, n, rng)
		for k in cuts.size() - 1:
			rooms.append({"kind": str(programme[bi % programme.size()]), "rect": Rect2(cuts[k], y, cuts[k + 1] - cuts[k], d), "role": "room"})
			bi += 1
	if y > area.position.y + 0.01 and not rooms.is_empty():
		# leftover strip: the room(s) right below grow into it
		for r in rooms:
			var rr: Rect2 = r["rect"]
			if absf(rr.position.y - y) < 0.01 and rr.position.x >= area.position.x - 0.01 and rr.end.x <= area.end.x + 0.01:
				r["rect"] = Rect2(rr.position.x, area.position.y, rr.size.x, rr.end.y - area.position.y)


## A side wing: a corridor along the side where it joins the main wing (or a
## spine for tall wings joined at the side), rooms in rows/columns.
static func _side_wing(rooms: Array, wr: Rect2, main: Rect2, t: Dictionary, floor_i: int, rng: RandomNumberGenerator) -> void:
	var programme: Array = t["upper"] if floor_i > 0 else t["back"]
	var joins_south := absf(wr.end.y - main.position.y) < 0.01
	var joins_west := absf(wr.end.x - main.position.x) < 0.01
	var joins_east := absf(wr.position.x - main.end.x) < 0.01
	if wr.size.x * wr.size.y < 60.0:
		rooms.append({"kind": str(programme[rng.randi() % programme.size()]), "rect": wr, "role": "room"})
		return
	if (joins_west or joins_east) and wr.size.y > wr.size.x:
		# spine: a north-south corridor on the joining side, rooms stacked beside it
		var cx := wr.end.x - CORRIDOR if joins_west else wr.position.x
		rooms.append({"kind": "corridor", "rect": Rect2(cx, wr.position.y, CORRIDOR, wr.size.y), "role": "circulation"})
		var rx := wr.position.x if joins_west else wr.position.x + CORRIDOR
		var cuts := _split(wr.position.y, wr.end.y, maxi(1, int(wr.size.y / rng.randf_range(5.0, 7.0))), rng)
		for k in cuts.size() - 1:
			rooms.append({"kind": str(programme[k % programme.size()]), "rect": Rect2(rx, cuts[k], wr.size.x - CORRIDOR, cuts[k + 1] - cuts[k]), "role": "room"})
		return
	if joins_south or wr.end.y <= main.position.y + 0.01:
		_bands(rooms, wr, programme, true, rng, rng.randi() % 3)
	else:
		# joined at its top or beside a short wing: corridor along the top
		rooms.append({"kind": "corridor", "rect": Rect2(wr.position.x, wr.position.y, wr.size.x, CORRIDOR), "role": "circulation"})
		var cuts := _split(wr.position.x, wr.end.x, maxi(1, int(wr.size.x / 7.0)), rng)
		for k in cuts.size() - 1:
			rooms.append({"kind": str(programme[k % programme.size()]), "rect": Rect2(cuts[k], wr.position.y + CORRIDOR, cuts[k + 1] - cuts[k], wr.size.y - CORRIDOR), "role": "room"})


## Doors over the graph of touching rooms; returns partitions and clear rects.
static func _connect(rooms: Array, entrance_x: float, stairs_rect: Rect2, main: Rect2, rng: RandomNumberGenerator) -> Dictionary:
	var n := rooms.size()
	var segs: Array = []        # {a, b, vertical, line, s0, s1}
	for i in n:
		for j in range(i + 1, n):
			var s := _shared(rooms[i]["rect"], rooms[j]["rect"])
			if not s.is_empty():
				s["a"] = i
				s["b"] = j
				s["open"] = []          # [pos, width, door?]
				segs.append(s)
	var linked := {}
	var add_link := func(sg: Dictionary, wide: bool) -> void:
		var length := float(sg["s1"]) - float(sg["s0"])
		var stairs_side: bool = rooms[sg["a"]]["kind"] == "stairs" or rooms[sg["b"]]["kind"] == "stairs"
		if stairs_side:
			wide = false
			if not sg["vertical"]:
				# the flight stands on the stairwell's back wall: no door from above into it
				var st: Rect2 = rooms[sg["a"]]["rect"] if rooms[sg["a"]]["kind"] == "stairs" else rooms[sg["b"]]["rect"]
				if absf(float(sg["line"]) - st.position.y) < 0.01:
					return
		var w := 4.0 if wide and length >= 6.0 else DOOR_W
		if length < w:
			return
		if length < w + 1.0:
			sg["open"].append([float(sg["s0"]) + (length - w) * 0.5, w, not wide])     # a door that just fits
			linked[[mini(sg["a"], sg["b"]), maxi(sg["a"], sg["b"])]] = true
			return
		var mid := (float(sg["s0"]) + float(sg["s1"])) * 0.5
		var pos := floorf(clampf(mid - w * 0.5 + rng.randf_range(-1.0, 1.0), float(sg["s0"]) + 0.5, float(sg["s1"]) - w - 0.5))
		if stairs_side and sg["vertical"]:
			pos = floorf(float(sg["s1"]) - w - 0.5)          # beside the flight: at the foot of the stairs
		sg["open"].append([pos, w, not wide])
		linked[[mini(sg["a"], sg["b"]), maxi(sg["a"], sg["b"])]] = true
	var circ := func(i: int) -> bool: return rooms[i]["role"] in ["circulation", "hall"] or rooms[i].get("hall", false)
	# circulation opens to circulation (wide openings, the stairwell gets a door)
	for sg in segs:
		if circ.call(sg["a"]) and circ.call(sg["b"]):
			add_link.call(sg, rooms[sg["a"]]["kind"] != "stairs" and rooms[sg["b"]]["kind"] != "stairs")
	# every room: a door to the longest touching circulation
	for i in n:
		if circ.call(i):
			continue
		var best: Dictionary = {}
		for sg in segs:
			if (sg["a"] == i and circ.call(sg["b"])) or (sg["b"] == i and circ.call(sg["a"])):
				if best.is_empty() or float(sg["s1"]) - float(sg["s0"]) > float(best["s1"]) - float(best["s0"]):
					best = sg
		if not best.is_empty():
			add_link.call(best, rooms[i]["role"] == "court")
	# whatever is still cut off: a door to a reachable neighbour
	var start := -1
	for i in n:
		if rooms[i].get("hall", false):
			start = i
	if start < 0:
		start = 0
	for guard in n + 2:
		var seen := {start: true}
		var q := [start]
		while not q.is_empty():
			var i: int = q.pop_back()
			for sg in segs:
				if (sg["open"] as Array).is_empty():
					continue
				var o := -1
				if sg["a"] == i:
					o = sg["b"]
				elif sg["b"] == i:
					o = sg["a"]
				if o >= 0 and not seen.has(o):
					seen[o] = true
					q.append(o)
		if seen.size() >= n:
			break
		var added := false
		for sg in segs:
			if (sg["open"] as Array).is_empty() and seen.has(sg["a"]) != seen.has(sg["b"]):
				var before: int = (sg["open"] as Array).size()
				add_link.call(sg, false)
				if (sg["open"] as Array).size() > before:
					added = true
					break
		if not added:
			break
	# partitions along every touching segment, with their doors/openings
	var partitions: Array = []
	var clear: Array = []
	for sg in segs:
		var p := {}
		var line := float(sg["line"])
		if sg["vertical"]:
			p = {"from": [line, sg["s0"]], "to": [line, sg["s1"]], "wall_tiles": 2.0}
		else:
			p = {"from": [sg["s0"], line], "to": [sg["s1"], line], "wall_tiles": 2.0}
		var doors: Array = []
		var openings: Array = []
		for o in sg["open"]:
			if bool(o[2]):
				doors.append([line, o[0]] if sg["vertical"] else [o[0], line])
			else:
				openings.append([line, o[0], o[1]] if sg["vertical"] else [o[0], line, o[1]])
			if sg["vertical"]:
				clear.append(Rect2(line - 2.0, float(o[0]) - 0.5, 4.0, float(o[1]) + 1.0))
			else:
				clear.append(Rect2(float(o[0]) - 0.5, line - 2.0, float(o[1]) + 1.0, 4.0))
		if not doors.is_empty():
			p["doors"] = doors
		if not openings.is_empty():
			p["openings"] = openings
		partitions.append(p)
	return {"partitions": partitions, "clear": clear}


## The segment two rooms share (empty if they only touch at a corner).
static func _shared(a: Rect2, b: Rect2) -> Dictionary:
	for pair in [[a, b], [b, a]]:
		var p: Rect2 = pair[0]
		var q: Rect2 = pair[1]
		if absf(p.end.y - q.position.y) < 0.01:
			var s0 := maxf(p.position.x, q.position.x)
			var s1 := minf(p.end.x, q.end.x)
			if s1 - s0 > 0.5:
				return {"vertical": false, "line": p.end.y, "s0": s0, "s1": s1}
		if absf(p.end.x - q.position.x) < 0.01:
			var s0 := maxf(p.position.y, q.position.y)
			var s1 := minf(p.end.y, q.end.y)
			if s1 - s0 > 0.5:
				return {"vertical": true, "line": p.end.x, "s0": s0, "s1": s1}
	return {}


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
	var fp := footprint(def)
	var flat := not is_wall and _is_flat(def)
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
	if flat or where == "floor":
		# rugs and mats: centred, flat (people walk over them), not blocking anything
		var c0 := room.get_center() - fp * 0.5
		if fp.x > room.size.x - 1.0 or fp.y > room.size.y - 1.0:
			return {}
		return {"item": id, "at": [snappedf(c0.x, 0.05), snappedf(c0.y + 0.3, 0.05)]}
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
		if _is_flat(d) or bool(d.get("wall", false)):
			continue
		var fp := footprint(d)
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
	# flood from the entrance (upper floors: from the stairs)
	var start := 0
	if layout.has("entrance"):
		var ex := int(float(layout["entrance"]["x"]) * res) + 1
		var by := 0
		for rr0 in layout["rooms"]:
			var q0: Array = rr0["rect"]
			if float(layout["entrance"]["x"]) >= float(q0[0]) and float(layout["entrance"]["x"]) < float(q0[0]) + float(q0[2]):
				by = maxi(by, int((float(q0[1]) + float(q0[3])) * res))
		start = (by - 2) * w + ex
	elif layout.has("arrive"):
		start = int(float(layout["arrive"][1]) * res) * w + int(float(layout["arrive"][0]) * res)
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
