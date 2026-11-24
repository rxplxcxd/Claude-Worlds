class_name Hud
extends CanvasLayer
## Heads-up display: settlement info, clock, camera buttons, interaction
## prompt and panel, toasts, menu and debug overlay.
##
## The HUD only talks to the world through EventBus signals and the gesture
## signals below (wired by main.gd). It never reads world nodes directly.

signal world_tapped(screen_pos: Vector2)
signal world_panned(delta: Vector2)
signal world_pinched(factor: float, center: Vector2)
## Emitted when a modal panel opens/closes (main pauses direct control).
signal modal_changed(open: bool)

const SPEEDS := [1.0, 4.0, 0.0]
const SPEED_LABELS := ["1×", "4×", "II"]

var root: Control
var gesture: GestureSurface
var joystick: TouchJoystick
var interact_button: TouchButton

var _name_label: Label
var _status_label: Label
var _clock_label: Label
var _speed_button: Button
var _toast_box: VBoxContainer
var _panel: PanelContainer
var _panel_title: Label
var _panel_subtitle: Label
var _panel_text: RichTextLabel
var _panel_actions: HBoxContainer
var _menu: PanelContainer
var _menu_text: RichTextLabel
var _debug_label: Label
var _hint_label: Label
var _open_info: Dictionary = {}
var _speed_index := 0
var _focused: Node = null


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.build()
	add_child(root)

	gesture = GestureSurface.new()
	gesture.name = "GestureSurface"
	root.add_child(gesture)
	gesture.tapped.connect(func(p: Vector2) -> void: world_tapped.emit(p))
	gesture.panned.connect(func(d: Vector2) -> void: world_panned.emit(d))
	gesture.pinched.connect(func(f: float, c: Vector2) -> void: world_pinched.emit(f, c))

	_build_info_panel()
	_build_top_right()
	_build_bottom()
	_build_toasts()
	_build_interaction_panel()
	_build_menu()
	_build_debug()

	EventBus.settlement_ready.connect(_on_settlement_ready)
	EventBus.interaction_focus_changed.connect(_on_focus_changed)
	EventBus.interaction_opened.connect(open_panel)
	EventBus.toast_requested.connect(show_toast)
	GameClock.minute_changed.connect(func(_m: int) -> void: _update_clock())
	_update_clock()
	_set_debug_visible(bool(LocalProfile.get_setting("show_debug", false)))
	_apply_speed(SPEEDS.find(float(LocalProfile.get_setting("time_speed", 1.0))))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_menu"):
		if _panel.visible:
			close_panel()
		else:
			_toggle_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_debug"):
		_set_debug_visible(not _debug_label.visible)
	elif event.is_action_pressed("zoom_in"):
		EventBus.camera_zoom_step.emit(1)
	elif event.is_action_pressed("zoom_out"):
		EventBus.camera_zoom_step.emit(-1)
	elif event.is_action_pressed("recenter"):
		EventBus.camera_recenter_requested.emit()


func _process(_delta: float) -> void:
	if _debug_label.visible:
		_debug_label.text = "FPS %d · Draw calls %d · Objekte %d · %s" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			str(get_viewport().get_visible_rect().size.round())]


# --- building -------------------------------------------------------------

func _build_info_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "InfoPanel"
	panel.position = Vector2(14, 14)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	_name_label = Label.new()
	_name_label.text = "WORLDS"
	_name_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_name_label)
	_status_label = Label.new()
	_status_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_status_label.add_theme_font_size_override("font_size", 14)
	box.add_child(_status_label)
	var summary := AssetRegistry.get_status_summary()
	if summary["placeholders"] > 0:
		var badge := Label.new()
		badge.name = "PlaceholderBadge"
		badge.text = "Platzhaltergrafik · Penzilla-Assets ausstehend"
		badge.add_theme_color_override("font_color", UiTheme.ACCENT)
		badge.add_theme_font_size_override("font_size", 12)
		box.add_child(badge)


func _build_top_right() -> void:
	var col := VBoxContainer.new()
	col.name = "TopRight"
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)

	var clock := PanelContainer.new()
	clock.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(clock)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	clock.add_child(row)
	_clock_label = Label.new()
	_clock_label.custom_minimum_size = Vector2(118, 0)
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_clock_label)
	_speed_button = _make_button("1×", "Spielgeschwindigkeit")
	_speed_button.pressed.connect(func() -> void: _apply_speed((_speed_index + 1) % SPEEDS.size()))
	row.add_child(_speed_button)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_child(buttons)
	var menu := _make_button("Menü", "Menü")
	menu.pressed.connect(_toggle_menu)
	buttons.add_child(menu)
	var center := _make_button("Fokus", "Kamera auf Spielfigur zentrieren")
	center.pressed.connect(func() -> void: EventBus.camera_recenter_requested.emit())
	buttons.add_child(center)
	var zin := _make_button("+", "Hineinzoomen")
	zin.pressed.connect(func() -> void: EventBus.camera_zoom_step.emit(1))
	buttons.add_child(zin)
	var zout := _make_button("–", "Herauszoomen")
	zout.pressed.connect(func() -> void: EventBus.camera_zoom_step.emit(-1))
	buttons.add_child(zout)
	col.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)


func _build_bottom() -> void:
	joystick = TouchJoystick.new()
	joystick.name = "Joystick"
	joystick.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(joystick)
	joystick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 8)
	joystick.visible = DisplayServer.is_touchscreen_available()

	_hint_label = Label.new()
	_hint_label.name = "DesktopHint"
	_hint_label.text = "WASD/Pfeile: gehen · Klick: dorthin gehen · Ziehen: Kamera · Mausrad: Zoom · E: benutzen · Esc: Menü"
	_hint_label.add_theme_color_override("font_color", Color(UiTheme.TEXT, 0.75))
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint_label.add_theme_constant_override("outline_size", 4)
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.visible = not joystick.visible
	root.add_child(_hint_label)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)

	interact_button = TouchButton.new("")
	interact_button.name = "InteractButton"
	interact_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	interact_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	interact_button.custom_minimum_size = Vector2(190, 64)
	interact_button.visible = false
	interact_button.activated.connect(func() -> void: EventBus.interact_pressed.emit())
	root.add_child(interact_button)
	interact_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)


func _build_toasts() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.name = "Toasts"
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(_toast_box)
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 96)


func _build_interaction_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "InteractionPanel"
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.BG_SOLID))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	_panel_title = Label.new()
	_panel_title.add_theme_font_size_override("font_size", 24)
	_panel_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_panel_title)
	_panel_subtitle = Label.new()
	_panel_subtitle.add_theme_color_override("font_color", UiTheme.ACCENT)
	_panel_subtitle.add_theme_font_size_override("font_size", 14)
	titles.add_child(_panel_subtitle)
	var close := _make_button("×", "Schließen")
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(close_panel)
	head.add_child(close)
	_panel_text = RichTextLabel.new()
	_panel_text.bbcode_enabled = true
	_panel_text.fit_content = false
	_panel_text.scroll_active = true
	_panel_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_panel_text)
	_panel_actions = HBoxContainer.new()
	_panel_actions.add_theme_constant_override("separation", 8)
	box.add_child(_panel_actions)


func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.name = "Menu"
	_menu.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.BG_SOLID))
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.visible = false
	root.add_child(_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_menu.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "WORLDS · Menü"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _make_button("×", "Schließen")
	close.pressed.connect(_toggle_menu)
	head.add_child(close)
	_menu_text = RichTextLabel.new()
	_menu_text.bbcode_enabled = true
	_menu_text.fit_content = false
	_menu_text.scroll_active = true
	_menu_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_menu_text)
	var debug_toggle := CheckButton.new()
	debug_toggle.text = "Leistungsanzeige (FPS)"
	debug_toggle.button_pressed = bool(LocalProfile.get_setting("show_debug", false))
	debug_toggle.toggled.connect(_set_debug_visible)
	box.add_child(debug_toggle)
	var joy_toggle := CheckButton.new()
	joy_toggle.text = "Virtueller Joystick"
	joy_toggle.button_pressed = DisplayServer.is_touchscreen_available()
	joy_toggle.toggled.connect(func(on: bool) -> void:
		joystick.visible = on
		_hint_label.visible = not on)
	box.add_child(joy_toggle)


func _build_debug() -> void:
	_debug_label = Label.new()
	_debug_label.name = "Debug"
	_debug_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_debug_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_debug_label.add_theme_font_size_override("font_size", 12)
	_debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_debug_label.add_theme_constant_override("outline_size", 4)
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_debug_label)
	_debug_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 8)


func _make_button(text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(52, 52)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22 if text.length() <= 2 else 16)
	return b


# --- behaviour ------------------------------------------------------------

func get_settlement_label() -> String:
	return _name_label.text


func open_panel(info: Dictionary) -> void:
	_menu.visible = false
	_open_info = info
	_panel_title.text = info.get("title", "")
	_panel_subtitle.text = info.get("subtitle", "")
	_panel_subtitle.visible = _panel_subtitle.text != ""
	_panel_text.text = info.get("text", "")
	for c in _panel_actions.get_children():
		c.queue_free()
	for a in info.get("actions", []):
		var b := _make_button(a.get("label", "?"), "")
		b.add_theme_font_size_override("font_size", 17)
		var accent := UiTheme.panel_style(Color(UiTheme.ACCENT, 0.92))
		accent.shadow_size = 0
		b.add_theme_stylebox_override("normal", accent)
		b.add_theme_stylebox_override("hover", accent)
		b.add_theme_color_override("font_color", UiTheme.ACCENT_DARK)
		b.add_theme_color_override("font_hover_color", UiTheme.ACCENT_DARK)
		var action_id: String = a.get("id", "")
		b.pressed.connect(func() -> void:
			EventBus.interaction_action.emit(info.get("id", ""), action_id)
			close_panel())
		_panel_actions.add_child(b)
	_panel_actions.visible = _panel_actions.get_child_count() > 0
	_panel.visible = true
	interact_button.visible = false
	_layout_modal(_panel, _panel_text)
	modal_changed.emit(true)


func close_panel() -> void:
	if not _panel.visible:
		return
	_panel.visible = false
	_open_info = {}
	_on_focus_changed(_focused)
	modal_changed.emit(false)


func is_panel_open() -> bool:
	return _panel.visible


func get_open_interaction_id() -> String:
	return _open_info.get("id", "")


func show_toast(text: String) -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	p.add_child(l)
	_toast_box.add_child(p)
	while _toast_box.get_child_count() > 3:
		_toast_box.get_child(0).free()
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func _on_settlement_ready(summary: Dictionary) -> void:
	var settlement: String = summary.get("name", "")
	_name_label.text = settlement
	var founder := "von dir gegründet" if summary.get("founder_player_id", "") == LocalProfile.player_id else "gegründet"
	_status_label.text = "%s · %s · %s" % [summary.get("region_name", ""), summary.get("development_status", ""), founder]
	if summary.get("just_founded", false):
		if int(summary.get("order_on_planet", 0)) == 1:
			show_toast("Du hast %s gegründet – die erste Siedlung auf %s." % [settlement, summary.get("planet_name", "")])
		else:
			show_toast("Du hast %s gegründet." % settlement)
	else:
		show_toast("Willkommen zurück in %s." % settlement)


func _on_focus_changed(it: Node) -> void:
	_focused = it
	if _panel.visible and (it == null or (it as Interactable).interaction_id != get_open_interaction_id()):
		close_panel()
		return
	if it == null or _panel.visible:
		interact_button.visible = false
		return
	var inter := it as Interactable
	interact_button.set_text("%s\n%s" % [inter.verb, inter.title])
	interact_button.visible = true


func _toggle_menu() -> void:
	if _menu.visible:
		_menu.visible = false
		modal_changed.emit(false)
		return
	close_panel()
	var s := AssetRegistry.get_status_summary()
	_menu_text.text = (
		"[b]Steuerung[/b]\n"
		+ "Touch: Joystick unten links · Tippen = dorthin gehen · Ziehen = Kamera · zwei Finger = Zoom · gelbe Taste = benutzen\n"
		+ "Tastatur: WASD/Pfeile · Klick = gehen · Maus ziehen = Kamera · Mausrad/+/− = Zoom · E = benutzen · C = zentrieren · F3 = FPS\n\n"
		+ "[b]Asset-Status[/b]\n%d von %d Asset-Einträgen integriert · %d Platzhalter · %d Art-Direction-Verstöße\n\n" % [s["resolved"], s["total"], s["placeholders"], s["violations"]]
		+ "[b]Projekt[/b]\nVersion %s · Phase 1 (World Foundation) · Godot %s\nSpieler-ID (lokal): %s" % [
			ProjectSettings.get_setting("application/config/version", "?"),
			Engine.get_version_info().get("string", "?"), LocalProfile.player_id])
	_menu.visible = true
	_layout_modal(_menu, _menu_text)
	modal_changed.emit(true)


func _layout_modal(panel: Control, text: RichTextLabel) -> void:
	var vp := root.get_viewport_rect().size
	var w := minf(560.0, vp.x - 32.0)
	panel.custom_minimum_size = Vector2(w, 0)
	text.custom_minimum_size = Vector2(0, 40)
	panel.reset_size()
	# Measure the text at the final width, then cap the panel to the screen.
	await get_tree().process_frame
	var chrome := panel.size.y - text.size.y
	var max_text := maxf(80.0, minf(vp.y * 0.8, 560.0) - chrome)
	text.custom_minimum_size = Vector2(0, minf(text.get_content_height() + 4.0, max_text))
	panel.reset_size()
	await get_tree().process_frame
	panel.position = ((vp - panel.size) * 0.5).max(Vector2(16, 16))


func _update_clock() -> void:
	_clock_label.text = "Tag %d · %s" % [GameClock.get_day(), GameClock.format_time()]


func _apply_speed(index: int) -> void:
	_speed_index = clampi(index, 0, SPEEDS.size() - 1)
	GameClock.speed = SPEEDS[_speed_index]
	_speed_button.text = SPEED_LABELS[_speed_index]
	LocalProfile.set_setting("time_speed", SPEEDS[_speed_index])


func _set_debug_visible(on: bool) -> void:
	_debug_label.visible = on
	if bool(LocalProfile.get_setting("show_debug", false)) != on:
		LocalProfile.set_setting("show_debug", on)
