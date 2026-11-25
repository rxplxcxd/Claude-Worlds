class_name Surroundings
extends Node2D
## Draws the land around the settlement (LocalTerrain): ground tiles,
## stacked blocks for hills and mountains, water and shores, trees and rocks,
## and a far ground plane in the biome colour – no black void at the edge.
## Two layers: behind the settlement (z −1) and in front of it (z +1, so a
## tree in front of the town edge covers what stands behind it).
## Not walkable yet: the bounds stay at the settlement area; walking out and
## building there come with territory expansions (Phase 7).

const LEVEL_H := 30.0
const FAR_COLORS := {"desert": Color("c9b07a"), "ice": Color("dfe6ec"), "tundra": Color("a7b39a"), "mountain": Color("7d8a63"), "forest": Color("4f7a3e"), "hills": Color("6f9a4f"), "plain": Color("6f9a4f")}

var terrain: Dictionary = {}
var size := Vector2i.ZERO
var front: Node2D
var _front_cells: Array = []
var _back_cells: Array = []


func setup(p_terrain: Dictionary, p_size: Vector2i) -> void:
	terrain = p_terrain
	size = p_size
	z_index = -1
	# far ground: the biome colour far beyond the ring
	var far := Polygon2D.new()
	var R := 400.0
	far.polygon = PackedVector2Array([Iso.grid_to_world(Vector2(-R, -R)), Iso.grid_to_world(Vector2(R + size.x, -R)), Iso.grid_to_world(Vector2(R + size.x, R + size.y)), Iso.grid_to_world(Vector2(-R, R + size.y))])
	far.color = FAR_COLORS.get(str(terrain.get("biome", "plain")), Color("6f9a4f")).darkened(0.12)
	far.z_index = -2
	far.z_as_relative = true
	add_child(far)
	var cells: Dictionary = terrain.get("cells", {})
	var keys: Array = cells.keys()
	# back to front by x + y, then x
	keys.sort_custom(func(a, b): return (a.x + a.y < b.x + b.y) or (a.x + a.y == b.x + b.y and a.x < b.x))
	for c in keys:
		if c.x >= size.x or c.y >= size.y:
			_front_cells.append(c)
		else:
			_back_cells.append(c)
	front = Node2D.new()
	front.name = "SurroundingsFront"
	front.z_index = 2
	front.z_as_relative = false
	front.draw.connect(func() -> void: _draw_cells(front, _front_cells))
	add_child(front)
	queue_redraw()
	front.queue_redraw()


func _draw() -> void:
	_draw_cells(self, _back_cells)


func _draw_cells(ci: CanvasItem, list: Array) -> void:
	var cells: Dictionary = terrain.get("cells", {})
	for c in list:
		var e: Dictionary = cells[c]
		var h := int(e["h"])
		for lvl in range(0, h + 1):
			var top := lvl == h
			_tile(ci, c, str(e["tile"]) if top else "earth", lvl)
		if str(e["deco"]) != "":
			_deco(ci, c, str(e["deco"]), h)


func _tile(ci: CanvasItem, c: Vector2i, tile: String, lvl: int) -> void:
	var key: String = {"grass": "exterior.tile.grass", "meadow": "exterior.tile.grass", "dirt": "exterior.tile.dirt", "sand": "exterior.tile.concrete",
		"water": "exterior.tile.water", "snow": "exterior.tile.concrete", "rock": "exterior.tile.dirt", "earth": "exterior.tile.low_dirt"}.get(tile, "exterior.tile.grass")
	var mod: Color = {"meadow": Color(1.03, 1.02, 0.9), "sand": Color(1.08, 0.92, 0.62), "snow": Color(1.12, 1.14, 1.2), "rock": Color(0.78, 0.74, 0.72), "earth": Color(0.72, 0.64, 0.58)}.get(tile, Color.WHITE)
	var sprite := AssetRegistry.get_sprite(key, 0)
	var bottom := Iso.grid_to_world(Vector2(c.x + 1, c.y + 1)) + Vector2(0, -lvl * LEVEL_H)
	if sprite.is_empty():
		var col: Color = {"grass": Color("7fae5b"), "meadow": Color("9bb865"), "sand": Color("dbc994"), "water": Color("4f8fb5"), "snow": Color("eef2f6"), "rock": Color("8d8a86"), "earth": Color("6b4f36"), "dirt": Color("b89b6a")}.get(tile, Color("7fae5b"))
		var pts := Iso.rect_corners(Vector2(c), Vector2.ONE)
		for i in pts.size():
			pts[i] += Vector2(0, -lvl * LEVEL_H)
		ci.draw_colored_polygon(pts, col)
		return
	var tex: Texture2D = sprite["texture"]
	var sz := Vector2(tex.get_width(), tex.get_height()) * float(sprite["scale"])
	ci.draw_texture_rect(tex, Rect2(bottom + sprite["offset"], sz), false, mod)


func _deco(ci: CanvasItem, c: Vector2i, deco: String, h: int) -> void:
	var hseed := GroundLayer._hash(c.x * 13 + 1, c.y * 7 + 2)
	var at := Iso.grid_to_world(Vector2(c.x + 0.5, c.y + 0.5) + Vector2(hseed - 0.5, 0.5 - hseed) * 0.4) + Vector2(0, -h * LEVEL_H)
	match deco:
		"tree", "pine":
			var paths := AssetRegistry.get_paths("exterior.prop.tree")
			var variant := (6 + int(hseed * 3.0)) if deco == "pine" else int(hseed * 6.0)
			if variant >= paths.size():
				variant = 0
			var sp := AssetRegistry.get_sprite("exterior.prop.tree", variant)
			if not sp.is_empty():
				var tex: Texture2D = sp["texture"]
				ci.draw_texture_rect(tex, Rect2(at + sp["offset"], Vector2(tex.get_width(), tex.get_height()) * float(sp["scale"])), false)
		"bush":
			var sb := AssetRegistry.get_sprite("exterior.prop.bush", int(hseed * 4.0))
			if not sb.is_empty():
				var tb: Texture2D = sb["texture"]
				ci.draw_texture_rect(tb, Rect2(at + sb["offset"], Vector2(tb.get_width(), tb.get_height()) * float(sb["scale"])), false)
		"rock_small":
			# own small rock in the Penzilla look: dark contour, two tones
			var r := 9.0 + hseed * 6.0
			var poly := PackedVector2Array([at + Vector2(-r, 0), at + Vector2(-r * 0.6, -r * 0.8), at + Vector2(r * 0.2, -r), at + Vector2(r, -r * 0.3), at + Vector2(r * 0.8, r * 0.2), at + Vector2(-r * 0.4, r * 0.3)])
			ci.draw_colored_polygon(poly, Color("8e8a85"))
			ci.draw_colored_polygon(PackedVector2Array([poly[1], poly[2], poly[3], at + Vector2(0, -r * 0.3)]), Color("aaa6a0"))
			var outline := poly.duplicate()
			outline.append(poly[0])
			ci.draw_polyline(outline, Color("330022"), 2.0, true)
