extends Node
## Application entry point: wires the settlement scene and the HUD together
## and adapts the logical resolution to the device orientation.

const LANDSCAPE := Vector2i(960, 540)
const PORTRAIT := Vector2i(540, 960)

@onready var settlement: SettlementScene = $Settlement
@onready var hud: Hud = $HUD


func _enter_tree() -> void:
	InputActions.ensure_registered()
	if LocalProfile.saved_game_minutes >= 0.0:
		GameClock.set_total_minutes(LocalProfile.saved_game_minutes)


func _ready() -> void:
	get_window().size_changed.connect(_update_content_scale)
	_update_content_scale()

	hud.world_tapped.connect(func(p: Vector2) -> void:
		if not hud.is_panel_open():
			settlement.handle_tap(p))
	hud.world_panned.connect(func(d: Vector2) -> void: settlement.camera.pan_screen(d))
	hud.world_pinched.connect(func(f: float, c: Vector2) -> void: settlement.camera.zoom_at(f, c))
	hud.modal_changed.connect(func(open: bool) -> void:
		if open:
			settlement.player.cancel_move_target())
	EventBus.camera_zoom_step.connect(func(dir: int) -> void: settlement.camera.zoom_step(dir))
	EventBus.camera_recenter_requested.connect(func() -> void: settlement.camera.recenter())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		LocalProfile.save_profile()


## Keeps UI readable on phones: the short screen side always maps to 540
## logical pixels, in landscape and in portrait.
func _update_content_scale() -> void:
	var s := get_window().size
	get_window().content_scale_size = PORTRAIT if s.y > s.x else LANDSCAPE
