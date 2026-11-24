extends Node
## Global, decoupled signal hub.
##
## Only cross-cutting events live here (UI <-> world). Systems that belong
## together talk directly to each other. Keep this list short and documented.

## The interactable the player can currently use changed (null = none).
signal interaction_focus_changed(interactable: Node)
## The player triggered an interaction. `info` is a plain Dictionary
## (id, title, subtitle, text, actions) so the UI never depends on world nodes.
signal interaction_opened(info: Dictionary)
## A UI action button inside an interaction panel was pressed.
signal interaction_action(interaction_id: String, action_id: String)
## Request a short notification ("toast") in the HUD.
signal toast_requested(text: String)
## The local settlement finished building its scene.
signal settlement_ready(summary: Dictionary)
## Virtual joystick output in screen space, length 0..1.
signal move_vector_changed(vector: Vector2)
## The on-screen interact button (or key) was pressed.
signal interact_pressed
## Camera commands from the HUD.
signal camera_zoom_step(direction: int)
signal camera_recenter_requested
