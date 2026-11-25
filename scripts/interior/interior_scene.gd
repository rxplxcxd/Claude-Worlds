class_name InteriorScene
extends Node2D
## An enterable interior in the WORLDS INTERIOR STANDARD (docs/INTERIOR_STANDARD.md):
## straight, raised 3/4 view – the projection the interior art is drawn in
## (Penzilla "Top-Down Retro Interior", own WORLDS pixel art):
##   * rectangular rooms, room axes horizontal/vertical on screen,
##   * square floor tiles (16 px art × S), x → right, y (south) → down,
##   * height drawn straight up: back walls are front-facing faces WALL_TILES
##     high above the top edge of the floor, side walls are narrow caps, the
##     front wall is cut away to a low cap with the entrance gap,
##   * furniture is front-facing; its footprint (rect width × solid depth)
##     stands on the grid, the sprite's bottom edge = the footprint's front
##     edge, y-sorted by that edge together with the people.
## Layouts are data (data/interiors/layouts.json); pieces come from the atlas
## (data/interiors/atlas.json + generated data/interiors/worlds_items.json).
## Variants (floors, walls, colour sheet, optional pieces) follow a seed and
## the settlement's prosperity, so not every house looks the same.

signal leave_requested

const LAYOUTS := "res://data/interiors/layouts.json"
const ATLAS := "res://data/interiors/atlas.json"
const ATLAS_WORLDS := "res://data/interiors/worlds_items.json"
const SHEETS := "res://assets/penzilla/interior/"
const OWN := "res://assets/interior/"
const SRC_TILE := 16.0
const S := 2.0                          # art px → world px
const T := SRC_TILE * S                 # one floor tile in world px (≈ 0.6 m)
const WALL_TILES := 3.0                 # wall height in tiles (a Penzilla door is 48 px = 3 tiles)
const CAP := 8.0                        # wall cap thickness (world px)
const OUTLINE := Color("3b2318")
const CAP_COLOR := Color("5a3a24")
const MOVE_Y_SCALE := 1.0               # square floor tiles: no vertical squash inside
const PERSON_SCALE := 1.45              # a person ≈ 1.7 m next to a 2.1 m door

var key := ""
var layout: Dictionary = {}
var atlas: Dictionary = {}
var variant_seed := 0
var wealth := 0.5
var size_t := Vector2i(10, 8)
var wall_tiles := WALL_TILES
var cells: Dictionary = {}              # Vector2i -> room index
var objects: Node2D                     # y-sorted: furniture, partitions, people
var floor_layer: Node2D
var wall_layer: Node2D
var spawn_point := Vector2.ZERO
var exit_point := Vector2.ZERO
var item_nodes: Array = []
var placed: Array = []                  # [{id, rect (tiles), wall}] for checks
var _doors: Array = []
var _textures: Dictionary = {}
var _staff: Array = []
var _sheet_swap := {}

static var _layouts: Dictionary = {}
static var _atlas: Dictionary = {}


static func layouts() -> Dictionary:
	if _layouts.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(LAYOUTS))
		_layouts = d if d is Dictionary else {}
	return _layouts


## Bought + own pieces in one atlas.
static func atlas_data() -> Dictionary:
	if _atlas.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(ATLAS))
		_atlas = d if d is Dictionary else {}
		var w = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_WORLDS)) if FileAccess.file_exists(ATLAS_WORLDS) else {}
		if w is Dictionary:
			for part in ["items", "floors", "walls"]:
				var dst: Dictionary = _atlas.get(part, {})
				for k in w.get(part, {}).keys():
					dst[k] = w[part][k]
				_atlas[part] = dst
	return _atlas


## Resolves aliases ("house_1" → "house_small").
static func resolve(p_key: String) -> Dictionary:
	var l: Dictionary = layouts().get(p_key, {})
	var guard := 0
	while l.has("alias") and guard < 4:
		l = layouts().get(str(l["alias"]), {})
		guard += 1
	return l


static func has_layout(p_key: String) -> bool:
	return not p_key.begins_with("_") and not resolve(p_key).is_empty()


## The bought Penzilla interior sheets are imported (not in the public build).
static func assets_available() -> bool:
	return ResourceLoader.exists(SHEETS + "TopDownHouse_FurnitureState1.png")


## Interiors that use only own WORLDS art (Concordium) work without them.
static func layout_available(p_key: String) -> bool:
	return has_layout(p_key) and (assets_available() or bool(resolve(p_key).get("own_art_only", false)))


## staff: [{appearance, name, npc_id, role_label, text}] – people on duty now.
## p_seed / p_wealth (0..1) pick the variant of this particular building.
static func create(p_key: String, staff: Array = [], p_seed: int = 0, p_wealth: float = 0.5) -> InteriorScene:
	var s := InteriorScene.new()
	s.key = p_key
	s.layout = resolve(p_key)
	s.atlas = atlas_data()
	s._staff = staff
	s.variant_seed = p_seed
	s.wealth = p_wealth
	s.name = "Interior_" + p_key
	return s


## Interior grid (tiles) → local world px (floor level).
static func to_px(g: Vector2) -> Vector2:
	return g * T


static func from_px(w: Vector2) -> Vector2:
	return w / T


func _ready() -> void:
	var sz: Array = layout.get("size", [10, 8])
	size_t = Vector2i(int(sz[0]), int(sz[1]))
	wall_tiles = float(layout.get("wall_tiles", WALL_TILES))
	if _pick(layout.get("palette", ["state1"]), "palette") == "state2":
		_sheet_swap = {"TopDownHouse_FurnitureState1.png": "TopDownHouse_FurnitureState2.png"}
	floor_layer = Node2D.new()
	floor_layer.name = "Floor"
	floor_layer.z_index = -2
	add_child(floor_layer)
	wall_layer = Node2D.new()
	wall_layer.name = "Walls"
	wall_layer.z_index = -1
	add_child(wall_layer)
	objects = Node2D.new()
	objects.name = "Objects"
	objects.y_sort_enabled = true
	add_child(objects)
	_build_cells()
	_build_floors()
	_build_walls()
	_build_partitions()
	_build_items()
	_build_entrance()
	_build_staff()


## Camera bounds in global coordinates (the room plus its back wall).
func bounds() -> Rect2:
	return Rect2(global_position + Vector2(-CAP, -wall_tiles * T), Vector2(size_t.x * T + CAP * 2, (size_t.y + wall_tiles) * T + CAP * 2)).grow(48)


# --- variants -----------------------------------------------------------------------

## Deterministic choice from a list (or a plain value) for this building.
func _pick(v: Variant, salt: String) -> Variant:
	if not v is Array:
		return v
	var arr: Array = v
	if arr.is_empty():
		return null
	var h := SettlementCore.mix("%d#%s#%s" % [variant_seed, key, salt])
	return arr[posmod(h, arr.size())]


func _wanted(e: Dictionary) -> bool:
	if e.has("min_wealth") and wealth < float(e["min_wealth"]):
		return false
	if e.has("max_wealth") and wealth > float(e["max_wealth"]):
		return false
	if e.has("chance"):
		var h := SettlementCore.mix("%d#%s#%s" % [variant_seed, key, str(e.get("at", e.get("wall", "")))])
		return float(posmod(h, 1000)) / 1000.0 < float(e["chance"])
	return true


# --- geometry -----------------------------------------------------------------------

func _build_cells() -> void:
	var rooms: Array = layout.get("rooms", [])
	for i in rooms.size():
		var r: Array = rooms[i]["rect"]
		for y in range(int(r[1]), int(r[1]) + int(r[3])):
			for x in range(int(r[0]), int(r[0]) + int(r[2])):
				cells[Vector2i(x, y)] = i
	for c in layout.get("shape_cut", []):
		for y in range(int(c[1]), int(c[1]) + int(c[3])):
			for x in range(int(c[0]), int(c[0]) + int(c[2])):
				cells.erase(Vector2i(x, y))
	if layout.has("shape_circle"):
		var sc: Dictionary = layout["shape_circle"]
		var cc := Vector2(float(sc["centre"][0]), float(sc["centre"][1]))
		for c in cells.keys():
			if sc.has("room") and int(cells[c]) != int(sc["room"]):
				continue
			if (Vector2(c) + Vector2(0.5, 0.5)).distance_to(cc) > float(sc["r"]):
				cells.erase(c)


func is_inside(cell: Vector2i) -> bool:
	return cells.has(cell)


func _tex(sheet: String) -> Texture2D:
	sheet = _sheet_swap.get(sheet, sheet)
	if not _textures.has(sheet):
		var path := (OWN + sheet) if sheet.begins_with("worlds/") else (SHEETS + sheet)
		_textures[sheet] = load(path) if ResourceLoader.exists(path) else null
	return _textures[sheet]


## A repeatable texture cut from a patch of a sheet (floors, walls).
func _patch(def: Dictionary) -> Texture2D:
	var id := "patch:" + str(def.get("sheet", "")) + str(def.get("rect", []))
	if _textures.has(id):
		return _textures[id]
	var tex := _tex(str(def.get("sheet", "")))
	if tex == null:
		return null
	var r: Array = def["rect"]
	var out := ImageTexture.create_from_image(tex.get_image().get_region(Rect2i(r[0], r[1], r[2], r[3])))
	_textures[id] = out
	return out


func _rect_poly(tex: Texture2D, r: Rect2, uv_origin: Vector2, parent: Node, shade := Color.WHITE) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	p.color = shade
	if tex:
		p.texture = tex
		p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var o := uv_origin
		var sz := r.size / S
		p.uv = PackedVector2Array([o, o + Vector2(sz.x, 0), o + sz, o + Vector2(0, sz.y)])
	parent.add_child(p)
	return p


func _room(i: int) -> Dictionary:
	var rooms: Array = layout.get("rooms", [])
	return rooms[i] if i >= 0 and i < rooms.size() else {}


func _floor_tex(i: int) -> Texture2D:
	return _patch(atlas.get("floors", {}).get(str(_pick(_room(i).get("floor", "planks_dark"), "floor%d" % i)), {}))


func _wall_tex(i: int) -> Texture2D:
	return _patch(atlas.get("walls", {}).get(str(_pick(_room(i).get("wall", "wall_cream"), "wall%d" % i)), {}))


## Floors: one textured strip per run of cells in a row (few nodes).
func _build_floors() -> void:
	for y in range(size_t.y):
		var x := 0
		while x < size_t.x:
			var c := Vector2i(x, y)
			if not cells.has(c):
				x += 1
				continue
			var room: int = cells[c]
			var x1 := x
			while x1 < size_t.x and cells.get(Vector2i(x1, y), -1) == room:
				x1 += 1
			_rect_poly(_floor_tex(room), Rect2(Vector2(x, y) * T, Vector2(x1 - x, 1) * T), Vector2(x, y) * SRC_TILE, floor_layer)
			x = x1


## Back walls above every floor cell without a cell to the north (merged
## along the row); side caps; collision along the outline.
func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	add_child(body)
	var wh := wall_tiles * T
	for y in range(size_t.y):
		var x := 0
		while x < size_t.x:
			var c := Vector2i(x, y)
			if not cells.has(c) or cells.has(c + Vector2i(0, -1)):
				x += 1
				continue
			var room: int = cells[c]
			var x1 := x
			while x1 < size_t.x and cells.get(Vector2i(x1, y), -1) == room and not cells.has(Vector2i(x1, y - 1)):
				x1 += 1
			var r := Rect2(Vector2(x * T, y * T - wh), Vector2((x1 - x) * T, wh))
			if _is_arc_step(room, y):
				# round rooms: the curve below the top band is a low cap, not a wall face
				_rect_poly(null, Rect2(Vector2(x * T, y * T - CAP), Vector2((x1 - x) * T, CAP)), Vector2.ZERO, wall_layer, CAP_COLOR)
				_add_rect(body, Rect2(Vector2(x * T, y * T - T), Vector2((x1 - x) * T, T + 6)))
				x = x1
				continue
			_rect_poly(_wall_tex(room), r, Vector2(x * SRC_TILE, 0), wall_layer)
			_rect_poly(null, Rect2(r.position - Vector2(0, CAP), Vector2(r.size.x, CAP)), Vector2.ZERO, wall_layer, CAP_COLOR)
			_rect_poly(null, Rect2(Vector2(r.position.x, y * T - 2), Vector2(r.size.x, 2)), Vector2.ZERO, wall_layer, Color(0, 0, 0, 0.22))
			_add_rect(body, Rect2(Vector2(x * T, y * T - T), Vector2((x1 - x) * T, T + 6)))
			x = x1
	for c in cells:
		var full_wall := not cells.has(c + Vector2i(0, -1)) and not _is_arc_step(int(cells[c]), c.y)
		var top: float = c.y * T - (wh + CAP if full_wall else 0.0)
		if not cells.has(c + Vector2i(-1, 0)):
			_rect_poly(null, Rect2(Vector2(c.x * T - CAP, top), Vector2(CAP, (c.y + 1) * T - top)), Vector2.ZERO, wall_layer, CAP_COLOR)
			_add_rect(body, Rect2(Vector2(c.x * T - T, c.y * T - 4), Vector2(T + 4, T + 8)))
		if not cells.has(c + Vector2i(1, 0)):
			_rect_poly(null, Rect2(Vector2((c.x + 1) * T, top), Vector2(CAP, (c.y + 1) * T - top)), Vector2.ZERO, wall_layer, CAP_COLOR)
			_add_rect(body, Rect2(Vector2((c.x + 1) * T - 4, c.y * T - 4), Vector2(T + 4, T + 8)))
		if not cells.has(c + Vector2i(0, 1)):
			# low front cap (the front wall is cut away); the entrance stays open
			if not _is_entrance_cell(c):
				var cap := Polygon2D.new()
				cap.polygon = PackedVector2Array([Vector2(c.x * T - CAP, 0), Vector2((c.x + 1) * T + CAP, 0), Vector2((c.x + 1) * T + CAP, CAP), Vector2(c.x * T - CAP, CAP)])
				cap.color = CAP_COLOR
				var holder := Node2D.new()
				holder.position = Vector2(0, (c.y + 1) * T)
				holder.add_child(cap)
				objects.add_child(holder)
				_add_rect(body, Rect2(Vector2(c.x * T, (c.y + 1) * T - 4), Vector2(T, T)))


## In a round room only the top band (2 rows) carries full wall faces.
func _is_arc_step(room: int, y: int) -> bool:
	var sc: Dictionary = layout.get("shape_circle", {})
	if sc.is_empty() or (sc.has("room") and int(sc["room"]) != room):
		return false
	var top := size_t.y
	for c in cells:
		if int(cells[c]) == room:
			top = mini(top, c.y)
	return y > top + 1


func _entrance() -> Dictionary:
	return layout.get("entrance", {"x": 1.0})


## The entrance: a 2-tile gap in the front wall at x (bottom row of that column).
func _is_entrance_cell(c: Vector2i) -> bool:
	var ex := float(_entrance().get("x", 1.0))
	if absf(float(c.x) + 0.5 - ex) > 1.0:
		return false
	return cells.has(c) and not cells.has(c + Vector2i(0, 1))


func _add_rect(body: StaticBody2D, r: Rect2) -> void:
	var sh := CollisionPolygon2D.new()
	sh.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	body.add_child(sh)


## Inner walls: horizontal ones are full-height front faces (y-sorted with the
## people), vertical ones narrow full-height strips; openings and doors.
func _build_partitions() -> void:
	var body := StaticBody2D.new()
	body.name = "Partitions"
	add_child(body)
	for p in layout.get("partitions", []):
		var wh := float(p.get("wall_tiles", wall_tiles)) * T     # an inner wall may be lower than the hall
		var a := Vector2(p["from"][0], p["from"][1])
		var b := Vector2(p["to"][0], p["to"][1])
		var vertical := is_equal_approx(a.x, b.x)
		var gaps: Array = []
		for o in p.get("openings", []):
			gaps.append([float(o[1]) if vertical else float(o[0]), float(o[2])])
		for dd in p.get("doors", []):
			gaps.append([float(dd[1]) if vertical else float(dd[0]), 2.0])
		var n := int(round((b.y - a.y) if vertical else (b.x - a.x)))
		for i in n:
			var along := (a.y if vertical else a.x) + i
			if gaps.any(func(gp): return along >= gp[0] - 0.01 and along < gp[0] + gp[1] - 0.01):
				continue
			var holder := Node2D.new()
			if vertical:
				holder.position = Vector2(a.x * T, (along + 1) * T)
				_rect_poly(null, Rect2(Vector2(-CAP * 0.5, -T - wh), Vector2(CAP, T + wh)), Vector2.ZERO, holder, CAP_COLOR)
				_add_rect(body, Rect2(Vector2(a.x * T - 5, along * T), Vector2(10, T)))
			else:
				holder.position = Vector2(along * T, a.y * T)
				var room: int = cells.get(Vector2i(int(along), int(a.y)), cells.get(Vector2i(int(along), int(a.y) - 1), 0))
				_rect_poly(_wall_tex(room), Rect2(Vector2(0, -wh), Vector2(T, wh)), Vector2(along * SRC_TILE, 0), holder)
				_rect_poly(null, Rect2(Vector2(0, -wh - CAP), Vector2(T, CAP)), Vector2.ZERO, holder, CAP_COLOR)
				_add_rect(body, Rect2(Vector2(along * T, a.y * T - 10), Vector2(T, 14)))
			objects.add_child(holder)
		if not vertical:
			for dd in p.get("doors", []):
				_add_inner_door(Vector2(float(dd[0]), float(dd[1])))


## An inner door (Penzilla door art, drawn front-on in its 2-tile gap); it
## swings open (closed → ajar → open) when someone comes close.
func _add_inner_door(cell: Vector2) -> void:
	var holder := Node2D.new()
	holder.name = "InnerDoor"
	holder.position = Vector2((cell.x + 1.0) * T, cell.y * T)
	var spr := Sprite2D.new()
	spr.texture = _tex("TopDownHouse_DoorsAndWindows.png")
	spr.region_enabled = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(S, S)
	spr.centered = false
	holder.add_child(spr)
	objects.add_child(holder)
	_doors.append({"node": spr, "pos": holder.position, "state": -1})
	_set_door_frame(_doors[_doors.size() - 1], 0)


func _set_door_frame(d: Dictionary, frame: int) -> void:
	if int(d["state"]) == frame:
		return
	d["state"] = frame
	var item: Dictionary = atlas.get("items", {}).get(["door_closed", "door_half", "door_open"][frame], {})
	var r: Array = item.get("rect", [0, 0, 1, 1])
	var spr: Sprite2D = d["node"]
	spr.region_rect = Rect2(r[0], r[1], r[2], r[3])
	spr.position = Vector2(-r[2] * S * 0.5, -r[3] * S)


func _process(_delta: float) -> void:
	if _doors.is_empty():
		return
	var people: Array = []
	for n in objects.get_children():
		if n is Player or n is CharacterRig or n is CharacterBody2D:
			people.append(n.position)
	for d in _doors:
		var near := INF
		for p in people:
			near = minf(near, (p as Vector2).distance_to(d["pos"]))
		_set_door_frame(d, 2 if near < T * 1.6 else (1 if near < T * 2.8 else 0))


# --- furniture -------------------------------------------------------------------------

func item_texture(def: Dictionary, id: String) -> Texture2D:
	if def.get("sheet", "") == "own":
		return InteriorArt.texture(id)
	return _tex(str(def.get("sheet", "")))


## Footprint of a piece in tiles: width = art width, depth = solid height.
func footprint(def: Dictionary) -> Vector2:
	var r: Array = def["rect"]
	var solid: Array = def.get("solid", [0, r[3] * 0.55, r[2], r[3] * 0.45])
	return Vector2(maxf(0.5, float(r[2]) / SRC_TILE), maxf(0.35, float(solid[3]) / SRC_TILE))


## Row of the back wall above column x (first cell from the north).
func _wall_row(x: float) -> int:
	var cx := int(floor(x))
	for y in range(size_t.y):
		if cells.has(Vector2i(cx, y)):
			return y
	return 0


func _build_items() -> void:
	var defs: Dictionary = atlas.get("items", {})
	var body := StaticBody2D.new()
	body.name = "Furniture"
	add_child(body)
	var actions: Dictionary = ActionLibrary.actions()
	var list: Array = layout.get("items", [])
	for i in list.size():
		var e: Dictionary = list[i]
		if not _wanted(e):
			continue
		var id := str(_pick(e.get("item", ""), "item%d" % i))
		var def: Dictionary = defs.get(id, {})
		var tex := item_texture(def, id)
		if def.is_empty() or tex == null:
			continue
		var r: Array = def["rect"]
		var size := Vector2(r[2], r[3]) * S
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.scale = Vector2(S, S)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if def.get("sheet", "") != "own" and not str(def.get("sheet", "")).begins_with("worlds/"):
			spr.region_enabled = true
			spr.region_rect = Rect2(r[0], r[1], r[2], r[3])
		var holder := Node2D.new()
		holder.name = "%s_%d" % [id, i]
		holder.add_child(spr)
		var fp := footprint(def)
		var solid: Array = def.get("solid", [0, r[3] * 0.55, r[2], r[3] * 0.45])
		var flat: bool = (float(solid[2]) == 0.0 or float(solid[3]) == 0.0) and not e.has("wall") and not bool(def.get("wall", false)) and not e.has("lift")
		var g := Vector2.ZERO
		if e.has("wall"):
			# on the back wall: x (tiles) and height of the bottom edge above the floor (tiles)
			var wx := float(e["wall"][0])
			var hgt := float(e["wall"][1])
			var row := int(e.get("row", _wall_row(wx + fp.x * 0.5)))
			if e.has("row"):
				# on an inner wall face: drawn right after that face (y-sorted)
				holder.position = Vector2(wx * T, row * T + 0.5)
				spr.position = Vector2(0, -hgt * T - size.y - 0.5)
				objects.add_child(holder)
			else:
				holder.position = Vector2(wx * T, row * T - hgt * T)
				spr.position = Vector2(0, -size.y)
				wall_layer.add_child(holder)
			g = Vector2(wx, row)
			placed.append({"id": id, "rect": Rect2(Vector2(wx, row - hgt - size.y / T), size / T), "wall": true})
		elif flat:
			g = Vector2(float(e["at"][0]), float(e["at"][1]))
			holder.position = g * T
			holder.z_index = 1
			floor_layer.add_child(holder)
			fp = size / T
			placed.append({"id": id, "rect": Rect2(g, fp), "flat": true})
		else:
			g = Vector2(float(e["at"][0]), float(e["at"][1]))
			var lift := float(e.get("lift", -1.0))
			holder.position = Vector2((g.x + fp.x * 0.5) * T, (g.y + fp.y) * T)
			spr.position = Vector2(-size.x * 0.5, -size.y - maxf(lift, 0.0) * S)
			if lift >= 0.0:
				holder.position.y += 1.0            # small things on furniture: drawn just after it
			else:
				_add_rect(body, Rect2(g * T + Vector2(2, 2), fp * T - Vector2(4, 4)))
				placed.append({"id": id, "rect": Rect2(g, fp)})
			objects.add_child(holder)
		item_nodes.append(holder)
		var act := str(e.get("action", def.get("action", "")))
		if act != "" and actions.has(act):
			_add_item_interaction(e, def, id, i, act, actions[act], g, fp, e.has("wall") or bool(def.get("wall", false)))


func _add_item_interaction(e: Dictionary, def: Dictionary, id: String, i: int, act: String, adef: Dictionary, g: Vector2, fp: Vector2, on_wall: bool) -> void:
	var label := str(e.get("label", def.get("label", id)))
	# the interaction area is the footprint (plus a small margin) – the button
	# only appears right at the object
	var m := 0.4
	var area := Rect2((g - Vector2(m, m)) * T, (fp + Vector2(m, m) * 2.0) * T)
	if on_wall:
		area = Rect2(Vector2(g.x - m, g.y - 0.2) * T, Vector2(fp.x + m * 2, 1.4) * T)
	var poly := PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
	var it := Interactable.create("int:%s:%d" % [id, i], label, poly)
	it.kind = "interior"
	it.subtitle = str(layout.get("label", ""))
	var notes := PackedStringArray()
	if e.has("upgrade"):
		notes.append("[i]%s[/i]" % e["upgrade"])
	if e.has("text"):
		notes.append(str(e["text"]))
	if adef.has("note"):
		notes.append("[i]%s[/i]" % adef["note"])
	it.text = "\n".join(notes)
	it.actions = [{"id": act, "label": adef.get("label", act)}]
	it.verb = adef.get("label", "Benutzen")
	it.approach_offset = Vector2((g.x + fp.x * 0.5) * T, (g.y + (0.9 if on_wall else fp.y + 0.6)) * T)
	it.set_meta("pose_point", Vector2((g.x + fp.x * 0.5) * T, (g.y + fp.y * 0.5) * T))
	it.set_meta("action", act)
	floor_layer.add_child(it)


func _build_entrance() -> void:
	var ex := float(_entrance().get("x", 1.0))
	var by := 0
	for y in range(size_t.y):
		if cells.has(Vector2i(int(floor(ex)), y)):
			by = y
	var at := Vector2(ex, by + 1.0)
	spawn_point = (at - Vector2(0, 0.7)) * T
	exit_point = (at + Vector2(0, 0.9)) * T
	var mat := Sprite2D.new()
	mat.texture = InteriorArt.texture("doormat")
	mat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mat.scale = Vector2(S, S) * 1.2
	mat.position = (at - Vector2(0, 0.45)) * T
	floor_layer.add_child(mat)
	# exit interaction only at the doorway
	var r := Rect2((at - Vector2(1.0, 1.1)) * T, Vector2(2.0, 1.5) * T)
	var it := Interactable.create("int:exit", "Ausgang", PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
	it.kind = "interior_exit"
	it.subtitle = str(layout.get("label", ""))
	it.verb = "Verlassen"
	it.actions = [{"id": "leave", "label": "Verlassen"}]
	it.approach_offset = spawn_point
	floor_layer.add_child(it)


## People on duty here (from the duty roster), drawn with the shared rig and
## clip library.
func _build_staff() -> void:
	if _staff.is_empty() or not layout.has("staff_spot"):
		return
	var sp: Array = layout["staff_spot"]
	for i in _staff.size():
		var rig := CharacterRig.new()
		rig.appearance = CharacterCatalog.normalize(_staff[i].get("appearance", {}))
		rig.world_per_src = Iso.WORLD_PER_SRC_PX * 0.62 * PERSON_SCALE
		rig.position = Vector2(float(sp[0]) + i * 1.6, float(sp[1])) * T
		rig.name = "Staff_%d" % i
		objects.add_child(rig)
		rig.set_facing(6)
		var it := Interactable.create(str(_staff[i].get("npc_id", "staff")), str(_staff[i].get("name", "")), PackedVector2Array([Vector2(-24, -20), Vector2(24, -20), Vector2(24, 24), Vector2(-24, 24)]))
		it.kind = "npc"
		it.subtitle = str(_staff[i].get("role_label", ""))
		it.verb = "Ansprechen"
		it.text = str(_staff[i].get("text", ""))
		it.actions = [{"id": "talk", "label": "Grüßen"}]
		it.approach_offset = Vector2(0, 46)
		rig.add_child(it)
		var tm := Timer.new()
		tm.wait_time = 4.0 + i
		tm.autostart = true
		tm.timeout.connect(func() -> void:
			if is_instance_valid(rig):
				rig.play(["use", "idle", "look_at", "nod"][randi() % 4], true))
		rig.add_child(tm)


## Quality checks used by the tests and the asset QA: pieces that overlap each
## other, stand outside the room or block the entrance.
func layout_problems() -> PackedStringArray:
	var out := PackedStringArray()
	var solid := placed.filter(func(p): return not p.get("wall", false) and not p.get("flat", false))
	for a in solid.size():
		var ra: Rect2 = solid[a]["rect"]
		for cx in range(int(floor(ra.position.x)), int(ceil(ra.end.x - 0.01))):
			for cy in range(int(floor(ra.position.y)), int(ceil(ra.end.y - 0.01))):
				if not cells.has(Vector2i(cx, cy)):
					out.append("%s outside the room at %d,%d" % [solid[a]["id"], cx, cy])
		for b in range(a + 1, solid.size()):
			var rb: Rect2 = solid[b]["rect"]
			if ra.grow(-0.08).intersects(rb.grow(-0.08)):
				out.append("%s overlaps %s" % [solid[a]["id"], solid[b]["id"]])
	var ex := float(_entrance().get("x", 1.0))
	var door := Rect2(Vector2(ex - 1.0, spawn_point.y / T - 1.2), Vector2(2.0, 1.7))
	for p in solid:
		if (p["rect"] as Rect2).intersects(door):
			out.append("%s blocks the entrance" % p["id"])
	return out
