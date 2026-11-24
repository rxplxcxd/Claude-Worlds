class_name TouchButton
extends PanelContainer
## Button that reacts to its own touch (any finger) as well as real mouse
## clicks. Used for actions that must work while another finger is on the
## joystick (standard Buttons only receive the emulated first touch).

signal activated

var label: Label
var _style_normal: StyleBoxFlat
var _style_pressed: StyleBoxFlat


func _init(text: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	_style_normal = UiTheme.panel_style(Color(UiTheme.ACCENT, 0.92))
	_style_pressed = UiTheme.panel_style(Color(UiTheme.ACCENT.darkened(0.25), 0.95))
	add_theme_stylebox_override("panel", _style_normal)
	label.add_theme_color_override("font_color", UiTheme.ACCENT_DARK)


func set_text(text: String) -> void:
	label.text = text


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_set_pressed_look(event.pressed)
		if event.pressed:
			activated.emit()
		accept_event()
	elif event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_set_pressed_look(event.pressed)
		if event.pressed:
			activated.emit()
		accept_event()


func _set_pressed_look(pressed: bool) -> void:
	add_theme_stylebox_override("panel", _style_pressed if pressed else _style_normal)
