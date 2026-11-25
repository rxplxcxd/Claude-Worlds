class_name CameraRig
extends Camera2D
## Settlement camera: smooth follow, free pan, zoom (pinch / wheel / buttons),
## and clamping to the settlement bounds.

const MIN_ZOOM := 0.45
const MAX_ZOOM := 1.8
const DEFAULT_ZOOM := 0.95
const FOLLOW_SHARPNESS := 7.0
const ZOOM_SHARPNESS := 12.0

var target: Node2D
var free_pan := false
var bounds := Rect2()
var target_zoom := DEFAULT_ZOOM


func _ready() -> void:
	zoom = Vector2.ONE * target_zoom
	position_smoothing_enabled = false


func _process(delta: float) -> void:
	var z := lerpf(zoom.x, target_zoom, 1.0 - exp(-ZOOM_SHARPNESS * delta))
	zoom = Vector2(z, z)
	if target and not free_pan:
		position = position.lerp(target.global_position + Vector2(0, -24), 1.0 - exp(-FOLLOW_SHARPNESS * delta))
	position = _clamp(position)


func snap_to_target() -> void:
	if target:
		position = _clamp(target.global_position + Vector2(0, -24))


## Moves the camera by a screen-space drag delta.
func pan_screen(delta: Vector2) -> void:
	free_pan = true
	position = _clamp(position - delta / zoom.x)


func recenter() -> void:
	free_pan = false


func zoom_step(direction: int) -> void:
	set_target_zoom(target_zoom * (1.2 if direction > 0 else 1.0 / 1.2))


func set_target_zoom(value: float) -> void:
	target_zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)


## Zooms by `factor` keeping the world point under `screen_point` in place.
func zoom_at(factor: float, screen_point: Vector2) -> void:
	var before := screen_to_world(screen_point)
	var new_zoom := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(new_zoom, new_zoom)
	target_zoom = new_zoom
	var after := screen_to_world(screen_point)
	if free_pan:
		position = _clamp(position + (before - after))


func screen_to_world(screen_point: Vector2) -> Vector2:
	var vp_size := get_viewport_rect().size
	# No smoothing, drag margins or limits are used, so the screen centre is
	# exactly the camera position.
	return global_position + (screen_point - vp_size * 0.5) / zoom.x


## Inside rooms: keep the whole view inside the bounds and centre rooms that
## are smaller than the screen (outside, only the centre is clamped).
var fit_view := false


func _clamp(p: Vector2) -> Vector2:
	if bounds.size == Vector2.ZERO:
		return p
	if fit_view:
		var half := get_viewport_rect().size * 0.5 / zoom.x
		var out := p
		for i in 2:
			var lo := bounds.position[i] + half[i]
			var hi := bounds.end[i] - half[i]
			out[i] = (bounds.position[i] + bounds.end[i]) * 0.5 if lo > hi else clampf(p[i], lo, hi)
		return out
	return Vector2(clampf(p.x, bounds.position.x, bounds.end.x), clampf(p.y, bounds.position.y, bounds.end.y))
