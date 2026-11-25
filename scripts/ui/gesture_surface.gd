class_name GestureSurface
extends Control
## Full-screen, invisible input surface BEHIND all HUD widgets.
##
## Translates touch and mouse input on the world into high-level gestures:
##   tapped(pos)              – short tap / click without movement
##   panned(delta)            – one-finger drag, mouse drag, two-finger move
##   pinched(factor, center)  – two-finger pinch, mouse wheel, trackpad magnify
## Because HUD widgets sit above this control, touches on buttons never reach
## the world. Emulated mouse events (generated from touches) are ignored so
## every gesture is handled exactly once.

signal tapped(position: Vector2)
signal panned(delta: Vector2)
signal pinched(factor: float, center: Vector2)

const TAP_SLOP := 14.0
const TAP_MAX_TIME := 0.45
const WHEEL_STEP := 1.12

var _touches: Dictionary = {} # index -> Vector2
var _start_pos := Vector2.ZERO
var _start_time := 0.0
var _tap_candidate := false
var _dragging := false
var _pinch_dist := 0.0
var _pinch_center := Vector2.ZERO

var _multi_seq := false        # this touch sequence had 2+ fingers at some point
var _block_tap_until := 0.0    # no taps shortly after a pinch / multi-touch
const TAP_COOLDOWN := 0.35

var _mouse_down := false
var _mouse_pan_button := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
		accept_event()
	elif event is InputEventScreenDrag:
		_on_drag(event)
		accept_event()
	elif event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event() # already handled as touch
	elif event is InputEventMouseButton:
		_on_mouse_button(event)
		accept_event()
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event)
	elif event is InputEventMagnifyGesture:
		pinched.emit(event.factor, event.position)
		accept_event()
	elif event is InputEventPanGesture:
		panned.emit(-event.delta * 8.0)
		accept_event()


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_start_pos = e.position
			_start_time = _now()
			_tap_candidate = not _multi_seq
			_dragging = false
		elif _touches.size() >= 2:
			_mark_multi()
			_begin_pinch()
	else:
		var was_single := _touches.size() == 1
		_touches.erase(e.index)
		# a tap = one finger, short, hardly moved, never part of a pinch
		if was_single and _tap_candidate and not _multi_seq and _now() - _start_time <= TAP_MAX_TIME \
				and e.position.distance_to(_start_pos) <= TAP_SLOP and _now() >= _block_tap_until:
			tapped.emit(e.position)
		_tap_candidate = false
		if _touches.is_empty():
			if _multi_seq:
				_block_tap_until = _now() + TAP_COOLDOWN
			_multi_seq = false
		if _touches.size() == 1:
			# Continue as a one-finger drag without jumping.
			_start_pos = _touches.values()[0]
			_dragging = true
		elif _touches.size() >= 2:
			_begin_pinch()


func _mark_multi() -> void:
	_multi_seq = true
	_tap_candidate = false


func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index) and not _touches.is_empty():
		# a second finger whose "down" event did not arrive (seen on Safari)
		_mark_multi()
	_touches[e.index] = e.position
	if _touches.size() == 1:
		if not _dragging and e.position.distance_to(_start_pos) > TAP_SLOP:
			_dragging = true
			_tap_candidate = false
		if _dragging:
			panned.emit(e.relative)
	elif _touches.size() >= 2:
		var pts: Array = _touches.values()
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var dist := maxf(a.distance_to(b), 1.0)
		var center := (a + b) * 0.5
		if _pinch_dist > 0.0:
			pinched.emit(dist / _pinch_dist, center)
			panned.emit(center - _pinch_center)
		_pinch_dist = dist
		_pinch_center = center


func _begin_pinch() -> void:
	var pts: Array = _touches.values()
	_pinch_dist = maxf((pts[0] as Vector2).distance_to(pts[1]), 1.0)
	_pinch_center = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5


func _on_mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				pinched.emit(WHEEL_STEP, e.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				pinched.emit(1.0 / WHEEL_STEP, e.position)
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			if e.pressed:
				_mouse_down = true
				_mouse_pan_button = e.button_index != MOUSE_BUTTON_LEFT
				_start_pos = e.position
				_start_time = _now()
				_dragging = _mouse_pan_button
			else:
				if _mouse_down and not _dragging and e.button_index == MOUSE_BUTTON_LEFT:
					tapped.emit(e.position)
				_mouse_down = false
				_dragging = false


func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	if not _mouse_down:
		return
	if not _dragging and e.position.distance_to(_start_pos) > TAP_SLOP:
		_dragging = true
	if _dragging:
		panned.emit(e.relative)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
