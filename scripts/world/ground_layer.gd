class_name GroundLayer
extends Node2D
## Draws the settlement ground as isometric tiles.
##
## PLACEHOLDER RENDERING: until the Penzilla ground tiles
## ("exterior.ground.tileset") are integrated, tiles are drawn procedurally.
## Drawing happens once; Godot caches the canvas commands, so the cost per
## frame is a single batched canvas item.

const COLORS := {
	"grass": Color("7fae5b"),
	"path": Color("c9b48a"),
	"road": Color("74787b"),
	"plaza": Color("cfc2a6"),
	"water": Color("4f8fb5"),
	"sand": Color("dbc994"),
	"field": Color("8a6a3f"),
}
const EDGE_DEPTH := 26.0

var data: SettlementData


func setup(settlement: SettlementData) -> void:
	data = settlement
	queue_redraw()


func _draw() -> void:
	if data == null:
		return
	_draw_edges()
	for y in data.size.y:
		for x in data.size.x:
			_draw_tile(x, y, data.get_tile(x, y))


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
