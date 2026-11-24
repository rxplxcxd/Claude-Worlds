class_name IsoPainter
extends RefCounted
## Static drawing helpers for PLACEHOLDER isometric geometry.
##
## Everything drawn here is a stand-in until the matching Penzilla sprite is
## registered in data/asset_manifest.json. Shapes are kept simple and readable
## (block volumes, roofs, windows) so scale and layout can already be judged.

const LEFT_SHADE := 0.10
const RIGHT_SHADE := 0.26


## Draws an isometric box. `corners` = ground corners T, R, B, L (relative).
## Returns the top corners for further decoration.
static func box(ci: CanvasItem, corners: PackedVector2Array, height: float, wall: Color, top: Color) -> PackedVector2Array:
	var up := Vector2(0, -height)
	var t := PackedVector2Array([corners[0] + up, corners[1] + up, corners[2] + up, corners[3] + up])
	ci.draw_colored_polygon(PackedVector2Array([corners[3], corners[2], t[2], t[3]]), wall.darkened(LEFT_SHADE))
	ci.draw_colored_polygon(PackedVector2Array([corners[2], corners[1], t[1], t[2]]), wall.darkened(RIGHT_SHADE))
	ci.draw_colored_polygon(t, top)
	# Crisp silhouette edges.
	var edge := wall.darkened(0.45)
	edge.a = 0.55
	ci.draw_line(corners[2], t[2], edge, 1.0, true)
	ci.draw_polyline(PackedVector2Array([t[3], t[2], t[1]]), edge, 1.0, true)
	return t


## Soft contact shadow / ambient occlusion around a footprint.
static func contact_shadow(ci: CanvasItem, corners: PackedVector2Array, grow: float = 1.12) -> void:
	var m := (corners[0] + corners[2]) * 0.5
	var poly := PackedVector2Array()
	for p in corners:
		poly.append(m + (p - m) * grow + Vector2(0, 4))
	ci.draw_colored_polygon(poly, Color(0, 0, 0, 0.18))


## Point on a wall face: `a`->`b` along the ground, `v` = 0..1 of `height`.
static func face_point(a: Vector2, b: Vector2, height: float, u: float, v: float) -> Vector2:
	return a.lerp(b, u) + Vector2(0, -height * v)


static func face_quad(ci: CanvasItem, a: Vector2, b: Vector2, height: float, u0: float, v0: float, u1: float, v1: float, color: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([
		face_point(a, b, height, u0, v0), face_point(a, b, height, u1, v0),
		face_point(a, b, height, u1, v1), face_point(a, b, height, u0, v1)]), color)


## Row of windows on a wall face. `count` windows evenly spaced.
static func windows(ci: CanvasItem, a: Vector2, b: Vector2, height: float, count: int, v0: float, v1: float, color: Color, skip_center: bool = false) -> void:
	for i in count:
		if skip_center and count % 2 == 1 and i == count / 2:
			continue
		var u0 := (i + 0.28) / count
		var u1 := (i + 0.72) / count
		face_quad(ci, a, b, height, u0, v0, u1, v1, color)
		var frame := color.darkened(0.5)
		frame.a = 0.6
		ci.draw_line(face_point(a, b, height, (u0 + u1) * 0.5, v0), face_point(a, b, height, (u0 + u1) * 0.5, v1), frame, 1.0, true)


## Gable roof on top of a box. `top` = top corners T, R, B, L.
static func gable_roof(ci: CanvasItem, top: PackedVector2Array, along_x: bool, roof_h: float, roof: Color, wall: Color) -> void:
	var m := (top[0] + top[2]) * 0.5
	var o := PackedVector2Array()
	for p in top:
		o.append(m + (p - m) * 1.08) # eave overhang
	var up := Vector2(0, -roof_h)
	if along_x:
		var r_l := (o[0] + o[3]) * 0.5 + up
		var r_r := (o[1] + o[2]) * 0.5 + up
		ci.draw_colored_polygon(PackedVector2Array([o[0], o[1], r_r, r_l]), roof.lightened(0.12))
		ci.draw_colored_polygon(PackedVector2Array([top[1], top[2], (top[1] + top[2]) * 0.5 + up]), wall.darkened(RIGHT_SHADE))
		ci.draw_colored_polygon(PackedVector2Array([r_l, r_r, o[2], o[3]]), roof)
		ci.draw_line(r_l, r_r, roof.lightened(0.3), 2.0, true)
	else:
		var r_t := (o[0] + o[1]) * 0.5 + up
		var r_b := (o[3] + o[2]) * 0.5 + up
		ci.draw_colored_polygon(PackedVector2Array([o[0], r_t, r_b, o[3]]), roof.lightened(0.12))
		ci.draw_colored_polygon(PackedVector2Array([top[3], top[2], (top[3] + top[2]) * 0.5 + up]), wall.darkened(LEFT_SHADE))
		ci.draw_colored_polygon(PackedVector2Array([r_t, o[1], o[2], r_b]), roof.darkened(0.1))
		ci.draw_line(r_t, r_b, roof.lightened(0.3), 2.0, true)


## Flat roof with a raised parapet.
static func flat_roof(ci: CanvasItem, top: PackedVector2Array, roof: Color) -> void:
	var m := (top[0] + top[2]) * 0.5
	var inner := PackedVector2Array()
	for p in top:
		inner.append(m + (p - m) * 0.86 + Vector2(0, 3))
	ci.draw_colored_polygon(inner, roof.darkened(0.12))


static func ellipse(ci: CanvasItem, center: Vector2, radius: Vector2, color: Color, segments: int = 20) -> void:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	ci.draw_colored_polygon(pts, color)


## Vertical cylinder (tanks, wells). Base center at `base`.
static func cylinder(ci: CanvasItem, base: Vector2, radius: float, height: float, side: Color, top: Color) -> void:
	var ry := radius * 0.5
	var up := Vector2(0, -height)
	ellipse(ci, base, Vector2(radius, ry), side.darkened(0.2))
	ci.draw_colored_polygon(PackedVector2Array([
		base + Vector2(-radius, 0), base + Vector2(radius, 0),
		base + Vector2(radius, 0) + up, base + Vector2(-radius, 0) + up]), side)
	# Simple shading band on the right half.
	ci.draw_colored_polygon(PackedVector2Array([
		base + Vector2(radius * 0.35, ry * 0.94), base + Vector2(radius, 0),
		base + Vector2(radius, 0) + up, base + Vector2(radius * 0.35, ry * 0.94) + up]), side.darkened(0.18))
	ellipse(ci, base + up, Vector2(radius, ry), top)
