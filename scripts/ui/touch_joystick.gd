class_name TouchJoystick
extends Control
## On-screen analogue stick for touch devices (multi-touch safe: it tracks its
## own touch index, so the camera or the interact button can be used at the
## same time). Output goes to EventBus.move_vector_changed (screen space).

const RADIUS := 62.0
const KNOB_RADIUS := 28.0
const DEAD_ZONE := 0.12

var _touch_index := -1
var _mouse_active := false
var _knob := Vector2.ZERO # offset from centre, clamped to RADIUS


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(RADIUS * 2.0 + 56.0, RADIUS * 2.0 + 56.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_update(event.position)
		elif not event.pressed and event.index == _touch_index:
			_release()
		accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _touch_index:
			_update(event.position)
		accept_event()
	elif event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_active = event.pressed
		if event.pressed:
			_update(event.position)
		else:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and _mouse_active:
		_update(event.position)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_release()


func _center() -> Vector2:
	return size * 0.5


func _update(local_pos: Vector2) -> void:
	_knob = (local_pos - _center()).limit_length(RADIUS)
	var v := _knob / RADIUS
	if v.length() < DEAD_ZONE:
		v = Vector2.ZERO
	EventBus.move_vector_changed.emit(v)
	queue_redraw()


func _release() -> void:
	_touch_index = -1
	_mouse_active = false
	_knob = Vector2.ZERO
	EventBus.move_vector_changed.emit(Vector2.ZERO)
	queue_redraw()


func _draw() -> void:
	var c := _center()
	draw_circle(c, RADIUS + 6.0, Color(0.07, 0.09, 0.125, 0.45))
	draw_arc(c, RADIUS + 6.0, 0, TAU, 48, Color(1, 1, 1, 0.18), 2.0, true)
	draw_circle(c + _knob, KNOB_RADIUS, Color(0.95, 0.93, 0.88, 0.85 if _touch_index != -1 or _mouse_active else 0.55))
	draw_arc(c + _knob, KNOB_RADIUS, 0, TAU, 32, Color(UiTheme.ACCENT, 0.9), 2.0, true)
