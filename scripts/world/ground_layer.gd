class_name GroundLayer
extends Node2D
## Draws the settlement ground as isometric tiles.
##
## With the Penzilla Giant City Builder tiles imported ("exterior.tile.*"),
## every cell is drawn as its textured block, back to front, so the earth
## sides of the front row form the diorama edge. Roads and dirt paths are
## auto-tiled from their neighbours (9 Penzilla variants + mirroring).
## Without the imported assets, the procedural PLACEHOLDER drawing is used.
## Drawing happens once; Godot caches the canvas commands.

const COLORS := {
	"grass": Color("7fae5b"),
	"path": Color("c9b48a"),
	"road": Color("74787b"),
	"plaza": Color("cfc2a6"),
	"water": Color("4f8fb5"),
	"sand": Color("dbc994"),
	"field": Color("8a6a3f"),
	"sidewalk": Color("b9b3a8"),
}
const EDGE_DEPTH := 26.0

## Tile type -> manifest key for textured mode.
const TILE_KEYS := {
	"grass": "exterior.tile.grass",
	"sand": "exterior.tile.dirt",
	"field": "exterior.tile.low_dirt",
	"water": "exterior.tile.water",
	"plaza": "exterior.tile.concrete",
	"sidewalk": "exterior.tile.concrete",
	"road": "exterior.tile.road",
	"path": "exterior.tile.path",
}
## Open sides bit mask -> [variant index (0-based), mirrored].
## Bits: 1 = -y, 2 = +x, 4 = +y, 8 = -x (grid directions).
const AUTOTILE := {
	15: [0, false], 13: [1, false], 11: [1, true], 14: [2, false], 7: [2, true],
	9: [3, false], 12: [4, false], 3: [4, true], 6: [5, false], 5: [6, false],
	10: [6, true], 8: [7, false], 1: [7, true], 4: [8, false], 2: [8, true], 0: [6, false],
}
const CONNECTS := {
	"road": ["road", "plaza"],
	"path": ["path", "road", "plaza", "sidewalk", "building"],
}

var data: SettlementData
var _building_cells := {}


func setup(settlement: SettlementData) -> void:
	data = settlement
	_building_cells.clear()
	for b in data.buildings:
		for c in data.get_building_cells(b):
			_building_cells[c] = true
	queue_redraw()


## True when the imported Penzilla ground tiles are available.
func is_textured() -> bool:
	return AssetRegistry.get_texture("exterior.tile.grass") != null


func _draw() -> void:
	if data == null:
		return
	if is_textured():
		_draw_textured()
		return
	_draw_edges()
	for y in data.size.y:
		for x in data.size.x:
			_draw_tile(x, y, data.get_tile(x, y))


func _draw_textured() -> void:
	# Back-to-front: rows of equal x + y, left to right.
	for d in data.size.x + data.size.y - 1:
		for x in range(maxi(0, d - data.size.y + 1), mini(d, data.size.x - 1) + 1):
			var y := d - x
			_draw_textured_tile(x, y, data.get_tile(x, y))


func _draw_textured_tile(x: int, y: int, tile: String) -> void:
	var key: String = TILE_KEYS.get(tile, "exterior.tile.grass")
	var variant := 0
	var mirrored := false
	if CONNECTS.has(tile):
		var rule: Array = AUTOTILE[autotile_mask(x, y, tile)]
		variant = rule[0]
		mirrored = rule[1]
	var sprite := AssetRegistry.get_sprite(key, variant)
	if sprite.is_empty():
		sprite = AssetRegistry.get_sprite("exterior.tile.grass")
	var tex: Texture2D = sprite["texture"]
	var size := Vector2(tex.get_width(), tex.get_height()) * float(sprite["scale"])
	# Canvas anchor = bottom vertex of the tile diamond.
	var bottom := Iso.grid_to_world(Vector2(x + 1, y + 1))
	if mirrored:
		draw_set_transform(bottom, 0.0, Vector2(-1, 1))
		draw_texture_rect(tex, Rect2(sprite["offset"], size), false)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect(tex, Rect2(bottom + sprite["offset"], size), false)
	if tile == "sidewalk":
		# Penzilla paving slabs on top of the concrete block.
		var slabs := AssetRegistry.get_sprite("exterior.tile.sidewalk")
		if not slabs.is_empty():
			var st: Texture2D = slabs["texture"]
			draw_texture_rect(st, Rect2(bottom + slabs["offset"], Vector2(st.get_width(), st.get_height()) * float(slabs["scale"])), false)


## Bit mask of neighbours a road/path connects to (1 -y, 2 +x, 4 +y, 8 -x).
func autotile_mask(x: int, y: int, tile: String) -> int:
	var mask := 0
	var dirs := [[Vector2i(0, -1), 1], [Vector2i(1, 0), 2], [Vector2i(0, 1), 4], [Vector2i(-1, 0), 8]]
	for d in dirs:
		var n: Vector2i = Vector2i(x, y) + d[0]
		var other := "building" if _building_cells.has(n) else data.get_tile(n.x, n.y)
		if (CONNECTS[tile] as Array).has(other):
			mask |= d[1]
	return mask


func _draw_tile(x: int, y: int, tile: String) -> void:
	var c := Iso.rect_corners(Vector2(x, y), Vector2.ONE)
	var base: Color = COLORS.get(tile, COLORS["grass"])
	var h := _hash(x, y)
	# Subtle per-tile variation keeps large areas from looking flat.
	var col := base.lightened((h - 0.5) * 0.06) if tile != "water" else base
	draw_colored_polygon(c, col)

	match tile:
		"grass":
			if h > 0.72:
				var p := _center(x, y) + Vector2((h - 0.86) * 60.0, (h - 0.8) * 20.0)
				for i in 3:
					draw_line(p + Vector2(i * 4 - 4, 0), p + Vector2(i * 4 - 5, -6), base.darkened(0.25), 1.5, true)
		"road":
			draw_polyline(_inset(c, 0.92), base.lightened(0.12), 1.5, true)
		"plaza":
			draw_polyline(_close(_inset(c, 0.8)), base.darkened(0.08), 1.2, true)
		"field":
			for i in range(1, 4):
				var t := i / 4.0
				var a := c[0].lerp(c[3], t)
				var b := c[1].lerp(c[2], t)
				draw_line(a, b, Color("6f9a45"), 4.0, true)
		"water":
			var p := _center(x, y)
			var w := 14.0 + h * 10.0
			draw_line(p + Vector2(-w, h * 6.0), p + Vector2(w, h * 6.0), base.lightened(0.25), 1.5, true)
		"path":
			draw_polyline(_close(c), base.darkened(0.06), 1.0, true)
	# Tile grid, very faint, helps reading the isometric space.
	if tile != "water":
		draw_polyline(_close(c), Color(0, 0, 0, 0.05), 1.0, true)


## Front-facing earth edges make the settlement read like a diorama.
func _draw_edges() -> void:
	var down := Vector2(0, EDGE_DEPTH)
	for x in data.size.x:
		var c := Iso.rect_corners(Vector2(x, data.size.y - 1), Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([c[3], c[2], c[2] + down, c[3] + down]), Color("6b4f36"))
	for y in data.size.y:
		var c := Iso.rect_corners(Vector2(data.size.x - 1, y), Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([c[2], c[1], c[1] + down, c[2] + down]), Color("543d2a"))


func _center(x: int, y: int) -> Vector2:
	return Iso.grid_to_world(Vector2(x + 0.5, y + 0.5))


func _inset(c: PackedVector2Array, f: float) -> PackedVector2Array:
	var m := (c[0] + c[2]) * 0.5
	var out := PackedVector2Array()
	for p in c:
		out.append(m + (p - m) * f)
	return out


func _close(c: PackedVector2Array) -> PackedVector2Array:
	var out := c.duplicate()
	out.append(c[0])
	return out


## Deterministic 0..1 noise per cell.
static func _hash(x: int, y: int) -> float:
	var n := x * 374761393 + y * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0
