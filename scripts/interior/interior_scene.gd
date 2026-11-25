class_name InteriorScene
extends Node2D
## An enterable interior, drawn ISOMETRIC like the world outside, with a
## slightly steeper view (diamond 1.45 : 1 instead of 1.75 : 1).
## Built from data/interiors/layouts.json; art from Penzilla "Top-Down Retro
## Interior" plus own pieces (InteriorArt).
##
## The retro pack is drawn front-on (3/4 view). Floors, wall faces, windows,
## pictures and inner doors are therefore PROJECTED onto the isometric planes
## (texture mapping on Polygon2D); furniture stands as front-facing sprites on
## an isometric footprint (collision = diamond). The outline follows the
## building outside (L-shapes via cuts, long/square rooms) and the entrance
## is on the same face as the door outside.
## Back walls (north-west / north-east) are drawn, the front walls are cut
## away so the room can be seen (dark low edge only).

signal leave_requested

const LAYOUTS := "res://data/interiors/layouts.json"
const ATLAS := "res://data/interiors/atlas.json"
const SHEETS := "res://assets/penzilla/interior/"
const TW := 48.0                   # iso diamond width of one interior tile (≈ 0.55 m)
const TH := 33.0                   # … height (1.45 : 1, steeper than outside)
const WALL_H := 120.0              # wall height in world px (≈ 2.6 m next to a 77 px person)
const OUTLINE := Color("4a2b17")
const WALL_TOP := Color("6b4226")
const MOVE_Y_SCALE := TH / TW      # player input squash inside (like Iso.MOVE_Y_SCALE outside)
const PERSON_SCALE := 1.25         # characters are drawn a bit larger inside

var key := ""
var layout: Dictionary = {}
var atlas: Dictionary = {}
var S := 2.0                       # sheet px → world px for furniture sprites
var size_t := Vector2i(10, 8)
var cells: Dictionary = {}         # Vector2i -> room index
var objects: Node2D                # y-sorted: furniture, people
var floor_layer: Node2D
var wall_layer: Node2D
var spawn_point := Vector2.ZERO
var exit_point := Vector2.ZERO
var item_nodes: Array = []
var _doors: Array = []
var _textures: Dictionary = {}
var _staff: Array = []

static var _layouts: Dictionary = {}
static var _atlas: Dictionary = {}


static func layouts() -> Dictionary:
	if _layouts.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(LAYOUTS))
		_layouts = d if d is Dictionary else {}
	return _layouts


static func atlas_data() -> Dictionary:
	if _atlas.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(ATLAS))
		_atlas = d if d is Dictionary else {}
	return _atlas


static func has_layout(p_key: String) -> bool:
	return layouts().has(p_key) and not p_key.begins_with("_")


static func assets_available() -> bool:
	return ResourceLoader.exists(SHEETS + "TopDownHouse_FurnitureState1.png")


## staff: [{appearance, name, npc_id, role_label, text}] – people on duty now.
static func create(p_key: String, staff: Array = []) -> InteriorScene:
	var s := InteriorScene.new()
	s.key = p_key
	s.layout = layouts().get(p_key, {})
	s.atlas = atlas_data()
	s._staff = staff
	s.name = "Interior_" + p_key
	return s


## Interior grid (tiles) → local world px.
static func iso(g: Vector2) -> Vector2:
	return Vector2((g.x - g.y) * TW * 0.5, (g.x + g.y) * TH * 0.5)


static func iso_inv(w: Vector2) -> Vector2:
	return Vector2(w.x / TW + w.y / TH, w.y / TH - w.x / TW)


func _ready() -> void:
	S = float(atlas.get("scale", 2))
	var sz: Array = layout.get("size", [10, 8])
	size_t = Vector2i(int(sz[0]), int(sz[1]))
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
	queue_redraw()


func bounds() -> Rect2:
	var r := Rect2(global_position + iso(Vector2.ZERO), Vector2.ZERO)
	for g in [Vector2(size_t.x, 0), Vector2(0, size_t.y), Vector2(size_t)]:
		r = r.expand(global_position + iso(g))
	r.position.y -= WALL_H
	r.size.y += WALL_H
	return r.grow(60)


# --- geometry ----------------------------------------------------------------------

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


func is_inside(cell: Vector2i) -> bool:
	return cells.has(cell)


func _tex(sheet: String) -> Texture2D:
	if not _textures.has(sheet):
		_textures[sheet] = load(SHEETS + sheet) if ResourceLoader.exists(SHEETS + sheet) else null
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


## Textured quad: corners (world) + matching UVs (texture px); repeats.
func _quad(tex: Texture2D, pts: PackedVector2Array, uv: PackedVector2Array, parent: Node, shade := Color.WHITE) -> Polygon2D:
	var p := Polygon2D.new()
	p.texture = tex
	p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.polygon = pts
	p.uv = uv
	p.color = shade
	parent.add_child(p)
	return p


func _build_floors() -> void:
	var rooms: Array = layout.get("rooms", [])
	var px := float(atlas.get("tile", 16))     # texture px per tile
	for c in cells:
		var tex := _patch(atlas.get("floors", {}).get(rooms[cells[c]].get("floor", "planks_dark"), {}))
		if tex == null:
			continue
		var g := Vector2(c)
		_quad(tex, PackedVector2Array([iso(g), iso(g + Vector2(1, 0)), iso(g + Vector2(1, 1)), iso(g + Vector2(0, 1))]),
			PackedVector2Array([g * px, (g + Vector2(1, 0)) * px, (g + Vector2(1, 1)) * px, (g + Vector2(0, 1)) * px]), floor_layer)


## Back walls: along the north-east edge of every cell whose y-1 neighbour is
## outside, and the north-west edge where x-1 is outside. Light from the
## front-left: the left wall is a little darker.
func _build_walls() -> void:
	var rooms: Array = layout.get("rooms", [])
	var body := StaticBody2D.new()
	body.name = "Walls"
	add_child(body)
	var px := float(atlas.get("tile", 16))
	for c in cells:
		var g := Vector2(c)
		var def: Dictionary = atlas.get("walls", {}).get(rooms[cells[c]].get("wall", "wall_cream"), {})
		var tex := _patch(def)
		var th := float(def.get("rect", [0, 0, 16, 32])[3])
		var up := Vector2(0, -WALL_H)
		if not cells.has(c + Vector2i(0, -1)):
			var a := iso(g)
			var b := iso(g + Vector2(1, 0))
			if tex:
				_quad(tex, PackedVector2Array([a + up, b + up, b, a]), PackedVector2Array([Vector2(g.x * px, 0), Vector2((g.x + 1) * px, 0), Vector2((g.x + 1) * px, th), Vector2(g.x * px, th)]), wall_layer)
			_add_poly(body, PackedVector2Array([a, b, b + Vector2(-TW * 0.25, -TH * 0.25), a + Vector2(-TW * 0.25, -TH * 0.25)]).duplicate())
			_add_poly(body, PackedVector2Array([a + Vector2(0, -2), b + Vector2(0, -2), b + Vector2(0, 14), a + Vector2(0, 14)]))
		if not cells.has(c + Vector2i(-1, 0)):
			var a2 := iso(g)
			var b2 := iso(g + Vector2(0, 1))
			if tex:
				_quad(tex, PackedVector2Array([a2 + up, b2 + up, b2, a2]), PackedVector2Array([Vector2(g.y * px, 0), Vector2((g.y + 1) * px, 0), Vector2((g.y + 1) * px, th), Vector2(g.y * px, th)]), wall_layer, Color(0.82, 0.8, 0.84))
			_add_poly(body, PackedVector2Array([a2 + Vector2(0, -2), b2 + Vector2(0, -2), b2 + Vector2(0, 14), a2 + Vector2(0, 14)]))
		# front edges: walkable up to the edge, blocked beyond (except the entrance)
		if not cells.has(c + Vector2i(1, 0)):
			_add_poly(body, PackedVector2Array([iso(g + Vector2(1, 0)), iso(g + Vector2(1.4, 0)), iso(g + Vector2(1.4, 1)), iso(g + Vector2(1, 1))]))
		if not cells.has(c + Vector2i(0, 1)) and not _is_entrance_cell(c):
			_add_poly(body, PackedVector2Array([iso(g + Vector2(0, 1)), iso(g + Vector2(1, 1)), iso(g + Vector2(1, 1.4)), iso(g + Vector2(0, 1.4))]))


func _entrance() -> Dictionary:
	return layout.get("entrance", {"x": 1.0, "face": "left"})


## The entrance lies on the front face matching the exterior door:
## left face → along the south-west edge (y = max), right face → along the
## south-east edge (x = max).
func _is_entrance_cell(c: Vector2i) -> bool:
	var e := _entrance()
	var t := float(e.get("x", 1.0))
	if e.get("face", "left") == "left":
		return c.y == size_t.y - 1 and absf(float(c.x) + 0.5 - t) < 0.75 and cells.has(c)
	return c.x == size_t.x - 1 and absf(float(c.y) + 0.5 - _right_t()) < 0.75 and cells.has(c)


func _right_t() -> float:
	return float(_entrance().get("y", float(size_t.y) - 1.5))


func _add_poly(body: StaticBody2D, pts: PackedVector2Array) -> void:
	var sh := CollisionPolygon2D.new()
	sh.polygon = pts
	body.add_child(sh)


func _draw() -> void:
	# dark contour of the cut-away front walls and the wall tops
	for c in cells:
		var g := Vector2(c)
		if not cells.has(c + Vector2i(1, 0)):
			draw_line(iso(g + Vector2(1, 0)), iso(g + Vector2(1, 1)), OUTLINE, 6.0)
		if not cells.has(c + Vector2i(0, 1)) and not _is_entrance_cell(c):
			draw_line(iso(g + Vector2(0, 1)), iso(g + Vector2(1, 1)), OUTLINE, 6.0)
		var up := Vector2(0, -WALL_H)
		if not cells.has(c + Vector2i(0, -1)):
			draw_line(iso(g) + up, iso(g + Vector2(1, 0)) + up, OUTLINE, 6.0)
		if not cells.has(c + Vector2i(-1, 0)):
			draw_line(iso(g) + up, iso(g + Vector2(0, 1)) + up, OUTLINE, 6.0)
	# vertical edges of the back walls
	for c in cells:
		var g := Vector2(c)
		if not cells.has(c + Vector2i(0, -1)) and not cells.has(c + Vector2i(1, -1)) and not cells.has(c + Vector2i(1, 0)):
			draw_line(iso(g + Vector2(1, 0)), iso(g + Vector2(1, 0)) + Vector2(0, -WALL_H), OUTLINE, 4.0)
		if not cells.has(c + Vector2i(-1, 0)) and not cells.has(c + Vector2i(-1, 1)) and not cells.has(c + Vector2i(0, 1)):
			draw_line(iso(g + Vector2(0, 1)), iso(g + Vector2(0, 1)) + Vector2(0, -WALL_H), OUTLINE, 4.0)


## Inner walls (low cut-away walls so the room behind stays visible) with
## openings; doors on them open when someone passes.
func _build_partitions() -> void:
	var body := StaticBody2D.new()
	body.name = "Partitions"
	add_child(body)
	for p in layout.get("partitions", []):
		var a := Vector2(p["from"][0], p["from"][1])
		var b := Vector2(p["to"][0], p["to"][1])
		var gaps: Array = []
		for o in p.get("openings", []):
			gaps.append([float(o[0]), float(o[1]), float(o[2])])
		for dd in p.get("doors", []):
			gaps.append([float(dd[0]), float(dd[1]), 1.0])
		var vertical := is_equal_approx(a.x, b.x)
		var n := int(round((b.y - a.y) if vertical else (b.x - a.x)))
		for i in n:
			var s := (a + Vector2(0, i)) if vertical else (a + Vector2(i, 0))
			var e := s + (Vector2(0, 1) if vertical else Vector2(1, 0))
			var along := s.y if vertical else s.x
			var is_gap := gaps.any(func(gp): return (is_equal_approx(gp[0], a.x) if vertical else is_equal_approx(gp[1], a.y)) and along >= (gp[1] if vertical else gp[0]) and along < (gp[1] if vertical else gp[0]) + gp[2])
			if is_gap:
				continue
			var h := Vector2(0, -WALL_H * 0.42)
			var face := Polygon2D.new()
			face.polygon = PackedVector2Array([iso(s) + h, iso(e) + h, iso(e), iso(s)])
			face.color = Color("8a6040") if vertical else Color("9c6c48")
			objects.add_child(face)
			face.position = Vector2.ZERO
			var top := Line2D.new()
			top.points = PackedVector2Array([iso(s) + h, iso(e) + h])
			top.width = 5.0
			top.default_color = OUTLINE
			face.add_child(top)
			_add_poly(body, PackedVector2Array([iso(s) + Vector2(0, -4), iso(e) + Vector2(0, -4), iso(e) + Vector2(0, 4), iso(s) + Vector2(0, 4)]))
		for dd in p.get("doors", []):
			_add_inner_door(Vector2(float(dd[0]), float(dd[1])), vertical)


## An inner door: the retro door art projected onto the wall plane; it swings
## open (closed → ajar → open) when someone comes close.
func _add_inner_door(cell: Vector2, vertical: bool) -> void:
	var holder := Node2D.new()
	holder.name = "InnerDoor"
	objects.add_child(holder)
	var s := cell
	var e := cell + (Vector2(0, 1) if vertical else Vector2(1, 0))
	var h := Vector2(0, -WALL_H * 0.62)
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([iso(s) + h, iso(e) + h, iso(e), iso(s)])
	poly.texture = _tex("TopDownHouse_DoorsAndWindows.png")
	poly.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.add_child(poly)
	_doors.append({"node": poly, "pos": iso(cell + (Vector2(0, 0.5) if vertical else Vector2(0.5, 0))), "state": -1})
	_set_door_frame(_doors[_doors.size() - 1], 0)


func _set_door_frame(d: Dictionary, frame: int) -> void:
	if int(d["state"]) == frame:
		return
	d["state"] = frame
	var item: Dictionary = atlas.get("items", {}).get(["door_closed", "door_half", "door_open"][frame], {})
	var r: Array = item.get("rect", [0, 0, 1, 1])
	(d["node"] as Polygon2D).uv = PackedVector2Array([Vector2(r[0], r[1]), Vector2(r[0] + r[2], r[1]), Vector2(r[0] + r[2], r[1] + r[3]), Vector2(r[0], r[1] + r[3])])


func _process(_delta: float) -> void:
	var people: Array = []
	for n in objects.get_children():
		if n is Player or n is CharacterRig:
			people.append(n.position)
	for d in _doors:
		var near := INF
		for p in people:
			near = minf(near, (p as Vector2).distance_to(d["pos"]))
		_set_door_frame(d, 2 if near < TW * 1.2 else (1 if near < TW * 2.2 else 0))


# --- furniture ---------------------------------------------------------------------------

func item_texture(def: Dictionary, id: String) -> Texture2D:
	if def.get("sheet", "") == "own":
		return InteriorArt.texture(id)
	return _tex(str(def.get("sheet", "")))


## Footprint of a piece in interior tiles (width along x, depth along y).
func footprint(def: Dictionary) -> Vector2:
	var r: Array = def["rect"]
	var solid: Array = def.get("solid", [0, r[3] * 0.55, r[2], r[3] * 0.45])
	var t := float(atlas.get("tile", 16))
	return Vector2(maxf(0.6, float(r[2]) / t), maxf(0.6, maxf(float(solid[3]), 6.0) / t))


func _build_items() -> void:
	var defs: Dictionary = atlas.get("items", {})
	var body := StaticBody2D.new()
	body.name = "Furniture"
	add_child(body)
	var actions: Dictionary = ActionLibrary.actions()
	for i in layout.get("items", []).size():
		var e: Dictionary = layout["items"][i]
		var id := str(e.get("item", ""))
		var def: Dictionary = defs.get(id, {})
		var tex := item_texture(def, id)
		if def.is_empty() or tex == null:
			continue
		var r: Array = def["rect"]
		var size := Vector2(r[2], r[3]) * S
		var gp := Vector2(float(e["pos"][0]), float(e["pos"][1]))
		var on_wall := bool(def.get("wall", false)) or gp.y < -1.0
		var solid: Array = def.get("solid", [0, r[3] * 0.55, r[2], r[3] * 0.45])
		var lay_flat := bool(def.get("flat_solid", false))
		var lift := float(e.get("lift", -1.0))
		var flat: bool = (solid[2] == 0 or lay_flat) and not on_wall and lift < 0.0
		var holder := Node2D.new()
		holder.name = "%s_%d" % [id, i]
		var fp := footprint(def)
		var g := Vector2(gp.x, maxf(0.0, gp.y))
		if on_wall:
			# projected onto the back-right wall plane at height ~1.2 m
			var poly := Polygon2D.new()
			# the back wall at this x (further forward where an L-shape cuts in)
			var wy := 0
			while wy < size_t.y and not cells.has(Vector2i(int(gp.x + 0.5), wy)):
				wy += 1
			var s0 := iso(Vector2(gp.x, wy))
			var s1 := iso(Vector2(gp.x + float(r[2]) / 16.0, wy))
			var base := Vector2(0, -WALL_H * 0.38)
			var hh := Vector2(0, -float(r[3]) * S * 0.9)
			poly.polygon = PackedVector2Array([s0 + base + hh, s1 + base + hh, s1 + base, s0 + base])
			poly.texture = tex
			poly.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			poly.uv = PackedVector2Array([Vector2(r[0], r[1]), Vector2(r[0] + r[2], r[1]), Vector2(r[0] + r[2], r[1] + r[3]), Vector2(r[0], r[1] + r[3])])
			holder.add_child(poly)
			wall_layer.add_child(holder)
		elif flat:
			# rugs, boards, mats: projected flat onto the floor
			var poly2 := Polygon2D.new()
			var w := float(r[2]) / 16.0
			var d := float(r[3]) / 16.0
			poly2.polygon = PackedVector2Array([iso(g), iso(g + Vector2(w, 0)), iso(g + Vector2(w, d)), iso(g + Vector2(0, d))])
			poly2.texture = tex
			poly2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if def.get("sheet", "") == "own":
				poly2.uv = PackedVector2Array([Vector2(0, 0), Vector2(r[2], 0), Vector2(r[2], r[3]), Vector2(0, r[3])])
			else:
				poly2.uv = PackedVector2Array([Vector2(r[0], r[1]), Vector2(r[0] + r[2], r[1]), Vector2(r[0] + r[2], r[1] + r[3]), Vector2(r[0], r[1] + r[3])])
			holder.add_child(poly2)
			holder.z_index = 1
			floor_layer.add_child(holder)
			if lay_flat:
				_add_poly(body, PackedVector2Array([iso(g), iso(g + Vector2(w, 0)), iso(g + Vector2(w, d)), iso(g + Vector2(0, d))]))
				fp = Vector2(w, d)
		else:
			# standing piece: front-facing sprite on its iso footprint, y-sorted
			var centre := g + fp * 0.5
			holder.position = iso(centre) + Vector2(0, fp.y * TH * 0.25)
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.centered = false
			spr.scale = Vector2(S, S)
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			if def.get("sheet", "") != "own":
				spr.region_enabled = true
				spr.region_rect = Rect2(r[0], r[1], r[2], r[3])
			spr.position = Vector2(-size.x * 0.5, -size.y - maxf(lift, 0.0))
			holder.add_child(spr)
			objects.add_child(holder)
			if lift >= 0.0:
				holder.position += Vector2(0, 2)   # small things on furniture: drawn just after it
			else:
				_add_poly(body, PackedVector2Array([iso(g), iso(g + Vector2(fp.x, 0)), iso(g + fp), iso(g + Vector2(0, fp.y))]))
		item_nodes.append(holder)
		var act := str(e.get("action", ""))
		if act != "" and actions.has(act):
			_add_item_interaction(e, def, id, i, act, actions[act], g, fp, size, on_wall)


func _add_item_interaction(e: Dictionary, def: Dictionary, id: String, i: int, act: String, adef: Dictionary, g: Vector2, fp: Vector2, size: Vector2, on_wall: bool) -> void:
	var label := str(e.get("label", def.get("label", id)))
	# the interaction area is the footprint (plus a small margin) – the button
	# only appears right at the object
	var m := 0.35
	var poly := PackedVector2Array([iso(g - Vector2(m, m)), iso(g + Vector2(fp.x + m, -m)), iso(g + fp + Vector2(m, m)), iso(g + Vector2(-m, fp.y + m))])
	var it := Interactable.create("int:%s:%d" % [id, i], label, poly)
	it.kind = "interior"
	it.subtitle = str(layout.get("label", ""))
	var notes := PackedStringArray()
	if e.has("upgrade"):
		notes.append("[i]%s[/i]" % e["upgrade"])
	if adef.has("note"):
		notes.append("[i]%s[/i]" % adef["note"])
	it.text = "\n".join(notes)
	it.actions = [{"id": act, "label": adef.get("label", act)}]
	it.verb = adef.get("label", "Benutzen")
	it.approach_offset = iso(g + Vector2(fp.x * 0.5, fp.y + 0.6))
	it.set_meta("pose_point", iso(g + fp * 0.5))
	it.set_meta("action", act)
	floor_layer.add_child(it)


func _build_entrance() -> void:
	var e := _entrance()
	var ex := float(e.get("x", 1.0))
	var at: Vector2
	var out: Vector2
	if e.get("face", "left") == "left":
		at = Vector2(ex, size_t.y - 0.5)
		out = Vector2(0, 1)
	else:
		at = Vector2(size_t.x - 0.5, _right_t())
		out = Vector2(1, 0)
	spawn_point = iso(at - out * 0.3)
	exit_point = iso(at + out * 0.8)
	# door mat projected on the floor
	var mat := Polygon2D.new()
	var w := Vector2(0.6, 0.6)
	mat.polygon = PackedVector2Array([iso(at - w), iso(at + Vector2(w.x, -w.y)), iso(at + w), iso(at + Vector2(-w.x, w.y))])
	mat.texture = InteriorArt.texture("doormat")
	mat.uv = PackedVector2Array([Vector2(0, 0), Vector2(26, 0), Vector2(26, 10), Vector2(0, 10)])
	mat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor_layer.add_child(mat)
	# exit interaction only at the doorway
	var m := 0.7
	var poly := PackedVector2Array([iso(at - Vector2(m, m)), iso(at + Vector2(m, -m)), iso(at + Vector2(m, m)), iso(at + Vector2(-m, m))])
	var it := Interactable.create("int:exit", "Ausgang", poly)
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
		rig.position = iso(Vector2(float(sp[0]) + i * 1.4, float(sp[1])))
		rig.name = "Staff_%d" % i
		objects.add_child(rig)
		rig.set_facing(7)
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
