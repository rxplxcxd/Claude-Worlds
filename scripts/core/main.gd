extends Node
## Application entry point.
##
## Flow: new player -> character editor -> (founding) settlement scene.
## Returning player -> settlement scene directly. The editor can be reopened
## from the menu. Also adapts the logical resolution to the orientation.

const LANDSCAPE := Vector2i(960, 540)
const PORTRAIT := Vector2i(540, 960)
const SETTLEMENT_SCENE := preload("res://scenes/settlement/settlement.tscn")

var settlement: SettlementScene
var editor: CharacterEditor
var _editor_layer: CanvasLayer

@onready var hud: Hud = $HUD


func _enter_tree() -> void:
	InputActions.ensure_registered()
	if LocalProfile.saved_game_minutes >= 0.0:
		GameClock.set_total_minutes(LocalProfile.saved_game_minutes)


func _ready() -> void:
	get_window().size_changed.connect(_update_content_scale)
	_update_content_scale()
	hud.edit_character_requested.connect(func() -> void: open_character_editor("edit"))
	if needs_character_creation():
		hud.visible = false
		open_character_editor("create")
	else:
		_start_world()


## A new player first creates a character (only if the character art exists;
## without imported assets the game starts directly with placeholders).
func needs_character_creation() -> bool:
	return not LocalProfile.has_character() and CharacterCatalog.is_available()


func open_character_editor(mode: String) -> void:
	if editor:
		return
	_editor_layer = CanvasLayer.new()
	_editor_layer.layer = 30
	add_child(_editor_layer)
	editor = CharacterEditor.new()
	editor.name = "CharacterEditor"
	editor.open(mode, LocalProfile.character, LocalProfile.display_name if LocalProfile.display_name != "Siedler:in" else "")
	_editor_layer.add_child(editor)
	editor.confirmed.connect(_on_character_confirmed)
	editor.cancelled.connect(_close_editor)
	if settlement:
		settlement.player.cancel_move_target()
		settlement.set_input_enabled(false)


func _on_character_confirmed(appearance: Dictionary, name_text: String) -> void:
	LocalProfile.set_character(CharacterCatalog.normalize(appearance), name_text)
	_close_editor()
	if settlement == null:
		hud.visible = true
		_start_world()
	else:
		settlement.player.refresh_appearance()
		EventBus.toast_requested.emit("Deine Figur wurde gespeichert.")


func _close_editor() -> void:
	if _editor_layer:
		_editor_layer.queue_free()
	_editor_layer = null
	editor = null
	if settlement:
		settlement.set_input_enabled(true)


func _start_world() -> void:
	settlement = SETTLEMENT_SCENE.instantiate()
	settlement.name = "Settlement"
	add_child(settlement)
	move_child(settlement, 0)
	hud.world_tapped.connect(func(p: Vector2) -> void:
		if not hud.is_panel_open() and editor == null:
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
