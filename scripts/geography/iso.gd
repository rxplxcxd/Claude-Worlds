class_name Iso
extends RefCounted
## Isometric projection helpers, matching the Penzilla Giant City Builder
## grid (512 x 292 px per tile, i.e. a 1.753:1 diamond).
##
## Grid space:  x grows towards screen bottom-right, y towards bottom-left.
## World space: Godot 2D pixels. One tile = TILE_W x TILE_H diamond.
## Height (z) is drawn as a vertical screen offset of -z pixels.

const TILE_W := 128.0
const TILE_H := 73.0
## Width of one tile in the original Penzilla artwork.
const SRC_TILE_W := 512.0
## World units per original artwork pixel (0.25).
const WORLD_PER_SRC_PX := TILE_W / SRC_TILE_W
## Screen-space vertical movement is scaled so walking "up" covers the same
## ground distance as walking "sideways".
const MOVE_Y_SCALE := TILE_H / TILE_W


static func grid_to_world(g: Vector2) -> Vector2:
	return Vector2((g.x - g.y) * TILE_W * 0.5, (g.x + g.y) * TILE_H * 0.5)


static func world_to_grid(w: Vector2) -> Vector2:
	return Vector2(w.x / TILE_W + w.y / TILE_H, w.y / TILE_H - w.x / TILE_W)


## Corners (top, right, bottom, left) of a grid rectangle in world space.
static func rect_corners(origin: Vector2, size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		grid_to_world(origin),
		grid_to_world(origin + Vector2(size.x, 0)),
		grid_to_world(origin + size),
		grid_to_world(origin + Vector2(0, size.y)),
	])


## Converts a screen-space input direction into a world-space velocity
## direction (keeps magnitude for analogue sticks).
static func screen_input_to_world(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * MOVE_Y_SCALE)


## 8-way facing index (0 = east/right, counter-clockwise in screen space:
## 0 E, 1 NE, 2 N, 3 NW, 4 W, 5 SW, 6 S, 7 SE).
static func facing_index(dir: Vector2) -> int:
	if dir.length_squared() < 0.0001:
		return 6
	var angle := atan2(-dir.y, dir.x)
	return posmod(int(round(angle / (PI / 4.0))), 8)


## Like facing_index, but keeps `current` until the direction is clearly
## (by more than `margin` beyond the 22.5° sector edge) in another sector.
static func facing_with_hysteresis(dir: Vector2, current: int, margin_deg: float = 9.0) -> int:
	var angle := atan2(-dir.y, dir.x)
	var centre := current * PI / 4.0
	var diff := absf(wrapf(angle - centre, -PI, PI))
	if diff <= deg_to_rad(22.5 + margin_deg):
		return current
	return facing_index(dir)


static func facing_name(index: int) -> String:
	return ["e", "ne", "n", "nw", "w", "sw", "s", "se"][clampi(index, 0, 7)]
