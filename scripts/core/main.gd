extends Node
## Application entry point.
##
## Flow: new player -> character editor -> globe ("found": choose a site and
## name) -> settlement scene. Returning player -> settlement scene directly.
## From the settlement, the HUD opens the globe ("browse"); the settlement is
## paused and hidden meanwhile. The editor can be reopened from the menu.
## Also adapts the logical resolution to the orientation.

const LANDSCAPE := Vector2i(960, 540)
const PORTRAIT := Vector2i(540, 960)
const SETTLEMENT_SCENE := preload("res://scenes/settlement/settlement.tscn")

var settlement: SettlementScene
var editor: CharacterEditor
var globe: GlobeScreen
## "Beitreten oder Gründen" (Paket 2.1).
var start_choice: StartChoice
var _choice_layer: CanvasLayer
var _editor_layer: CanvasLayer

@onready var hud: Hud = $HUD


func _enter_tree() -> void:
	InputActions.ensure_registered()


func _ready() -> void:
	get_window().size_changed.connect(_update_content_scale)
	_update_content_scale()
	hud.edit_character_requested.connect(func() -> void: open_character_editor("edit"))
	hud.map_requested.connect(func() -> void: open_globe("browse"))
	if _qa_gallery():
		return
	if _qa_quickstart():
		pass
	elif needs_character_creation():
		hud.visible = false
		open_character_editor("create")
	elif needs_founding():
		hud.visible = false
		open_start_choice()
	else:
		_start_world()


## QA hook (web only): "?gallery=living" opens the Living-Assets test gallery,
## "?gallery=cookedfx" the Cooked-FX evaluation gallery, instead of the game.
func _qa_gallery() -> bool:
	if not OS.has_feature("web"):
		return false
	var q := str(JavaScriptBridge.eval("location.search", true))
	var g: Node2D = null
	if q.contains("gallery=living"):
		g = LivingGallery.new()
	elif q.contains("gallery=anim"):
		g = AnimGallery.new()       # character animation library (QA)
	elif q.contains("gallery=cookedfx"):
		g = CookedFxGallery.new()   # evaluation of the Cooked FX pack (private files)
	if g == null:
		return false
	hud.visible = false
	g.name = "Gallery"
	add_child(g)
	return true


## QA hook (web only, for automated measurements): "?qa_quickstart=1" creates
## the default character if none exists and founds at the best free site.
## Never active without the URL parameter.
func _qa_quickstart() -> bool:
	if not OS.has_feature("web") or not str(JavaScriptBridge.eval("location.search", true)).contains("qa_quickstart=1"):
		return false
	if not LocalProfile.has_character() and CharacterCatalog.is_available():
		LocalProfile.set_character(CharacterCatalog.default_appearance(), "")
	if needs_founding():
		var record := WorldState.found_settlement(SettlementScene.DEFAULT_TEMPLATE, LocalProfile.player_id, "")
		if record.is_empty():
			return false
		_start_world(true)
	else:
		_start_world()
	return true


## The player has no settlement yet: they must found one (empty planet rule).
func needs_founding() -> bool:
	return WorldState.get_settlement_of(LocalProfile.player_id).is_empty()


## New player without a settlement: choose between joining (marked as not
## yet available – no shared world exists) and founding (globe).
func open_start_choice() -> void:
	if start_choice:
		return
	_choice_layer = CanvasLayer.new()
	_choice_layer.layer = 25
	add_child(_choice_layer)
	start_choice = StartChoice.new()
	start_choice.name = "StartChoice"
	_choice_layer.add_child(start_choice)
	start_choice.found_chosen.connect(func() -> void:
		_choice_layer.queue_free()
		_choice_layer = null
		start_choice = null
		open_globe("found"))


func open_globe(mode: String) -> void:
	if globe or editor:
		return
	globe = GlobeScreen.new()
	globe.name = "Globe"
	globe.open(mode)
	if settlement:
		settlement.player.cancel_move_target()
		settlement.visible = false
		settlement.process_mode = Node.PROCESS_MODE_DISABLED
	hud.visible = false
	add_child(globe)
	globe.closed.connect(close_globe)
	globe.found_requested.connect(found_from_globe)
	globe.landmark_view_requested.connect(open_landmark)


var landmark_view: CouncilSiteView


## World Council development preview (from the globe); closing returns to the globe.
func open_landmark(landmark_id: String) -> void:
	if landmark_view or globe == null:
		return
	_set_globe_shown(false)
	landmark_view = CouncilSiteView.new()
	landmark_view.landmark_id = landmark_id
	add_child(landmark_view)
	landmark_view.camera.make_current()
	landmark_view.closed.connect(func() -> void:
		landmark_view.queue_free()
		landmark_view = null
		if globe:
			_set_globe_shown(true)
			globe.view.make_current())


## The globe is a plain Node holding a 3D view and UI layers: hiding it means
## hiding the 3D view (else its camera keeps rendering behind 2D scenes, e.g.
## around the Concordium interiors) and the layers, and pausing it.
func _set_globe_shown(on: bool) -> void:
	globe.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if globe.view:
		globe.view.visible = on
		if not on and globe.view.camera:
			globe.view.camera.clear_current(false)
	for c in globe.get_children():
		if c is CanvasLayer:
			c.visible = on


func close_globe() -> void:
	if globe == null or settlement == null:
		return # in founding mode the map can only be left by founding
	globe.queue_free()
	globe = null
	settlement.visible = true
	settlement.process_mode = Node.PROCESS_MODE_INHERIT
	settlement.camera.make_current()
	hud.visible = true


## Founds the settlement at the site chosen on the globe and enters it.
func found_from_globe(site: Dictionary, settlement_name: String) -> Dictionary:
	var record := WorldState.found_settlement(SettlementScene.DEFAULT_TEMPLATE, LocalProfile.player_id, settlement_name, site)
	if record.is_empty():
		EventBus.toast_requested.emit("Hier ist keine Gründung möglich.")
		return {}
	if globe:
		globe.queue_free()
		globe = null
	hud.visible = true
	_start_world(true)
	return record


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
		if needs_founding():
			open_start_choice()
		else:
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


func _start_world(founded_now: bool = false) -> void:
	settlement = SETTLEMENT_SCENE.instantiate()
	settlement.name = "Settlement"
	settlement.founded_now = founded_now
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
