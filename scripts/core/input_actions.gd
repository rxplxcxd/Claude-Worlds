class_name InputActions
extends RefCounted
## Registers keyboard input actions in code (readable, versionable, no
## hand-edited InputEvent blobs in project.godot). Touch input is handled by
## the HUD (virtual joystick, gesture surface) and does not use actions.

const BINDINGS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"interact": [KEY_E, KEY_ENTER, KEY_SPACE],
	"zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	"recenter": [KEY_C],
	"toggle_menu": [KEY_ESCAPE],
	"toggle_debug": [KEY_F3],
}


static func ensure_registered() -> void:
	for action in BINDINGS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for keycode in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			if not InputMap.action_has_event(action, ev):
				InputMap.action_add_event(action, ev)
