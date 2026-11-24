class_name CharacterEditor
extends Control
## Character editor (create on first start, edit later from the menu).
##
## Built entirely on the real Penzilla Ultimate Protagonist layers via the
## CharacterCatalog (no invented options). The animated preview is the centre
## of the screen; categories, options and colours are always visible, every
## change shows immediately, and Undo / Random / Reset / Done are one tap
## away. Layout switches between landscape (preview left) and portrait
## (preview top). See docs/CHARACTER_SYSTEM.md.

signal confirmed(appearance: Dictionary, name_text: String)
signal cancelled

## Zoom region per category for the option cards (normalised frame coords).
const CATEGORY_REGIONS := {
	"body": Rect2(0.12, 0.08, 0.76, 0.9),
	"head": Rect2(0.16, 0.06, 0.68, 0.46),
	"top": Rect2(0.12, 0.26, 0.76, 0.56),
	"bottom": Rect2(0.12, 0.46, 0.76, 0.54),
	"shoes": Rect2(0.2, 0.72, 0.6, 0.28),
	"accessories": Rect2(0.1, 0.18, 0.8, 0.66),
	"outfits": Rect2(0.08, 0.06, 0.84, 0.94),
}
const ANIMS := [["idle", "Stehen"], ["walk", "Gehen"], ["interact", "Benutzen"]]
const CARD_SIZE := Vector2(96, 118)
const UNDO_LIMIT := 40

var mode := "create"
var app: Dictionary = {}

var _initial: Dictionary = {}
var _undo: Array = []
var _category := "body"
var _anim := "idle"
var _auto_rotate := false
var _rotate_time := 0.0
var _drag := 0.0

var _bg: TextureRect
var _backdrop: TextureRect
var _stage: Control
var _stage_root: Node2D
var _platform: Sprite2D
var _rig: CharacterRig
var _title: Label
var _subtitle: Label
var _name_edit: LineEdit
var _controls: HBoxContainer
var _left_button: Button
var _right_button: Button
var _anim_buttons := {}
var _auto_button: Button
var _panel: PanelContainer
var _tab_scroll: ScrollContainer
var _tabs: HBoxContainer
var _tab_buttons := {}
var _content_scroll: ScrollContainer
var _content: VBoxContainer
var _undo_button: Button
var _cancel_button: Button
var _done_button: Button
var _last_width := 0.0


## mode: "create" (first start) or "edit".
func open(p_mode: String, current: Dictionary, name_text: String) -> void:
	mode = p_mode
	app = CharacterCatalog.normalize(current) if not current.is_empty() else CharacterCatalog.default_appearance()
	_initial = app.duplicate(true)
	_undo.clear()
	if _name_edit:
		_name_edit.text = name_text
		_refresh_all()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.build()
	if app.is_empty():
		app = CharacterCatalog.default_appearance()
		_initial = app.duplicate(true)
	_build_background()
	_build_stage()
	_build_panel()
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()
	_refresh_all()


func _process(delta: float) -> void:
	if _auto_rotate and _rig:
		_rotate_time += delta
		if _rotate_time > 1.3:
			_rotate_time = 0.0
			_rotate(1)


# --- building -------------------------------------------------------------

func _build_background() -> void:
	var g := Gradient.new()
	g.set_color(0, Color("1b2633"))
	g.set_color(1, Color("2f4a3c"))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	_bg = TextureRect.new()
	_bg.texture = gt
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	# Hand-painted ground texture (Stylized Grass and Dirt) as a soft backdrop.
	var tex := AssetRegistry.get_texture("ui.editor_backdrop")
	if tex:
		_backdrop = TextureRect.new()
		_backdrop.texture = tex
		_backdrop.stretch_mode = TextureRect.STRETCH_TILE
		_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_backdrop.modulate = Color(1, 1, 1, 0.16)
		_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_backdrop)


func _build_stage() -> void:
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.gui_input.connect(_on_stage_input)
	add_child(_stage)

	var head := VBoxContainer.new()
	head.name = "Header"
	head.add_theme_constant_override("separation", 4)
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 18)
	_stage.add_child(head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 14)
	_subtitle.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_subtitle)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(name_row)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name deiner Figur"
	_name_edit.max_length = 24
	_name_edit.custom_minimum_size = Vector2(240, 44)
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.text = LocalProfile.display_name if LocalProfile.display_name != "Siedler:in" else ""
	name_row.add_child(_name_edit)

	var grass := AssetRegistry.get_texture("exterior.tile.grass")
	if grass:
		# Penzilla grass block as a small stage under the character.
		_platform = Sprite2D.new()
		_platform.name = "Platform"
		_platform.texture = grass
		_stage.add_child(_platform)
	_stage_root = Node2D.new()
	_stage_root.name = "StageRoot"
	_stage.add_child(_stage_root)
	_rig = CharacterRig.new()
	_rig.name = "PreviewRig"
	_rig.use_composite = false
	_rig.appearance = app
	_stage_root.add_child(_rig)
	_rig.animation_finished.connect(func(_a: String) -> void: _set_anim("idle" if _anim == "interact" else _anim))

	_controls = HBoxContainer.new()
	_controls.name = "PreviewControls"
	_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	_controls.add_theme_constant_override("separation", 6)
	_stage.add_child(_controls)
	_left_button = _icon_button("ui.icon.arrow", true, "<", "Nach links drehen")
	_left_button.custom_minimum_size = Vector2(56, 56)
	_left_button.pressed.connect(func() -> void: _rotate(-1))
	_stage.add_child(_left_button)
	_right_button = _icon_button("ui.icon.arrow", false, ">", "Nach rechts drehen")
	_right_button.custom_minimum_size = Vector2(56, 56)
	_right_button.pressed.connect(func() -> void: _rotate(1))
	_stage.add_child(_right_button)
	for a in ANIMS:
		var b := _small_button(a[1], "Animation: " + a[1])
		b.add_theme_font_size_override("font_size", 15)
		b.toggle_mode = true
		var anim_id: String = a[0]
		b.pressed.connect(func() -> void: _set_anim(anim_id))
		_controls.add_child(b)
		_anim_buttons[anim_id] = b
	_auto_button = _small_button("Drehen", "Figur automatisch drehen")
	_auto_button.toggle_mode = true
	_auto_button.toggled.connect(func(on: bool) -> void: _auto_rotate = on)
	_controls.add_child(_auto_button)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(Color(0.07, 0.09, 0.12, 0.9)))
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	_tab_scroll = ScrollContainer.new()
	_tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_tab_scroll.custom_minimum_size = Vector2(0, 52)
	box.add_child(_tab_scroll)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	_tab_scroll.add_child(_tabs)
	for cat in CharacterCatalog.data.get("categories", []):
		var b := Button.new()
		b.text = cat["label"]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 16)
		var cat_id: String = cat["id"]
		b.pressed.connect(func() -> void: _select_category(cat_id))
		_tabs.add_child(b)
		_tab_buttons[cat_id] = b

	_content_scroll = ScrollContainer.new()
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_content_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_content_scroll.add_child(_content)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	var rnd := _small_button("Zufall", "Zufällige Figur")
	rnd.pressed.connect(_randomize)
	actions.add_child(rnd)
	_undo_button = _small_button("Rückgängig", "Letzte Änderung zurücknehmen")
	_set_icon(_undo_button, "ui.icon.undo", false)
	_undo_button.pressed.connect(_undo_last)
	actions.add_child(_undo_button)
	var reset := _small_button("Zurücksetzen", "Auf den Anfangszustand zurücksetzen")
	reset.pressed.connect(func() -> void: _change(_initial.duplicate(true)))
	actions.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_cancel_button = _small_button("Abbrechen", "Ohne Speichern schließen")
	_cancel_button.pressed.connect(func() -> void: cancelled.emit())
	actions.add_child(_cancel_button)
	_done_button = _small_button("Fertig", "Figur speichern")
	_done_button.add_theme_stylebox_override("normal", UiTheme.accent_style(false))
	_done_button.add_theme_stylebox_override("hover", UiTheme.accent_style(false))
	_done_button.add_theme_stylebox_override("pressed", UiTheme.accent_style(true))
	_done_button.add_theme_color_override("font_color", UiTheme.ACCENT_DARK)
	_done_button.add_theme_color_override("font_hover_color", UiTheme.ACCENT_DARK)
	_done_button.add_theme_constant_override("outline_size", 0)
	_done_button.custom_minimum_size = Vector2(120, 48)
	_done_button.pressed.connect(func() -> void: confirmed.emit(app.duplicate(true), _name_edit.text.strip_edges()))
	actions.add_child(_done_button)


func _icon_button(icon_key: String, mirrored: bool, fallback: String, tooltip: String) -> Button:
	var b := _small_button(fallback, tooltip)
	_set_icon(b, icon_key, mirrored)
	if b.icon:
		b.text = ""
	return b


func _set_icon(b: Button, icon_key: String, mirrored: bool) -> void:
	var tex := AssetRegistry.get_texture(icon_key)
	if tex == null:
		return
	if mirrored:
		var img := tex.get_image()
		if img:
			img.decompress()
			img.flip_x()
			tex = ImageTexture.create_from_image(img)
	b.icon = tex
	b.add_theme_constant_override("icon_max_width", 26)


func _small_button(text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(48, 46)
	b.add_theme_font_size_override("font_size", 16)
	return b


# --- layout ---------------------------------------------------------------

func _layout() -> void:
	var vp := get_viewport_rect().size
	var landscape := vp.x > vp.y * 1.05
	var stage_rect: Rect2
	var panel_rect: Rect2
	if landscape:
		var sw := floorf(vp.x * 0.44)
		stage_rect = Rect2(0, 0, sw, vp.y)
		panel_rect = Rect2(sw, 12, vp.x - sw - 12, vp.y - 24)
	else:
		var sh := floorf(vp.y * 0.44)
		stage_rect = Rect2(0, 0, vp.x, sh)
		panel_rect = Rect2(10, sh, vp.x - 20, vp.y - sh - 10)
	_stage.position = stage_rect.position
	_stage.size = stage_rect.size
	_panel.position = panel_rect.position
	_panel.size = panel_rect.size
	_controls.reset_size()
	_controls.position = Vector2((stage_rect.size.x - _controls.size.x) * 0.5, stage_rect.size.y - _controls.size.y - 14)
	# Character stands on the platform between header and controls.
	var header_h := 150.0 if landscape else 140.0
	var free_h := stage_rect.size.y - header_h - _controls.size.y - 30
	var char_h := clampf(free_h * 0.78, 90.0, 360.0)
	var k := char_h / (333.0 * _rig.world_per_src)
	var feet := Vector2(stage_rect.size.x * 0.5, header_h + free_h * 0.88)
	_stage_root.scale = Vector2(k, k)
	_stage_root.position = feet
	if _platform:
		var pw := char_h * 1.45
		var ps := pw / float(_platform.texture.get_width())
		_platform.scale = Vector2(ps, ps)
		# Diamond centre of the Penzilla tile (y = 217 of 512) under the feet.
		_platform.position = feet + Vector2(0, (0.5 - 217.0 / 512.0) * _platform.texture.get_height() * ps)
	var side := minf(char_h * 0.75, stage_rect.size.x * 0.5 - 40.0)
	_left_button.position = Vector2(maxf(10.0, feet.x - side - 56.0), feet.y - char_h * 0.55)
	_right_button.position = Vector2(minf(stage_rect.size.x - 66.0, feet.x + side), feet.y - char_h * 0.55)
	if absf(panel_rect.size.x - _last_width) > 8.0:
		_last_width = panel_rect.size.x
		_render_category()


# --- behaviour ------------------------------------------------------------

func _refresh_all() -> void:
	if _title == null:
		return
	if mode == "create":
		_title.text = "Erschaffe deine Figur"
		_subtitle.text = ("Aurel ist noch unbewohnt – du wirst der erste Mensch hier sein." if WorldState.is_planet_empty() else "So wirst du auf Aurel aussehen.")
	else:
		_title.text = "Figur bearbeiten"
		_subtitle.text = "Änderungen siehst du sofort. „Fertig“ speichert."
	_cancel_button.visible = mode == "edit"
	_rig.set_appearance(app)
	_set_anim(_anim)
	for id in _tab_buttons.keys():
		_tab_buttons[id].button_pressed = id == _category
		_style_selected(_tab_buttons[id], id == _category)
	_undo_button.disabled = _undo.is_empty()
	_render_category()


func _select_category(cat_id: String) -> void:
	_category = cat_id
	for id in _tab_buttons.keys():
		_tab_buttons[id].button_pressed = id == cat_id
		_style_selected(_tab_buttons[id], id == cat_id)
	_render_category()
	_content_scroll.scroll_vertical = 0


func _change(new_app: Dictionary) -> void:
	new_app = CharacterCatalog.normalize(new_app)
	if new_app == app:
		return
	_undo.append(app.duplicate(true))
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	app = new_app
	_rig.set_appearance(app)
	_undo_button.disabled = false
	_render_category()


func _undo_last() -> void:
	if _undo.is_empty():
		return
	app = _undo.pop_back()
	_rig.set_appearance(app)
	_undo_button.disabled = _undo.is_empty()
	_render_category()


func _randomize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var r := CharacterCatalog.random_appearance(rng)
	r["face"] = app.get("face", r["face"])
	_change(r)


func _rotate(dir: int) -> void:
	_rig.set_facing(posmod(_rig.facing + dir, 8))


func _set_anim(anim_id: String) -> void:
	_anim = anim_id
	_rig.play(anim_id, anim_id == "interact")
	for id in _anim_buttons.keys():
		_anim_buttons[id].button_pressed = id == anim_id
		_style_selected(_anim_buttons[id], id == anim_id)


func _on_stage_input(event: InputEvent) -> void:
	# Swipe sideways on the preview to turn the character.
	var rel := Vector2.ZERO
	if event is InputEventScreenDrag:
		rel = event.relative
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) and event.device != InputEvent.DEVICE_ID_EMULATION:
		rel = event.relative
	if rel != Vector2.ZERO:
		_drag += rel.x
		while absf(_drag) > 42.0:
			_rotate(1 if _drag > 0 else -1)
			_drag -= signf(_drag) * 42.0


# --- category content -------------------------------------------------------

func _render_category() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		c.queue_free()
	var cat := _category_def(_category)
	if cat.get("presets", false):
		_render_presets()
		return
	for slot in cat.get("slots", []):
		_render_slot(slot)


func _category_def(cat_id: String) -> Dictionary:
	for c in CharacterCatalog.data.get("categories", []):
		if c["id"] == cat_id:
			return c
	return {}


func _render_slot(slot: String) -> void:
	var slot_def: Dictionary = CharacterCatalog.data["slots"][slot]
	var sel: Dictionary = app.get(slot, {})
	var cur_opt: String = str(sel.get("option", "none"))
	var opt_def := CharacterCatalog.option(slot, cur_opt)

	var header := HBoxContainer.new()
	_content.add_child(header)
	var title := Label.new()
	title.text = slot_def.get("label", slot)
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var current := Label.new()
	current.name = "Current"
	current.add_theme_color_override("font_color", UiTheme.ACCENT)
	current.add_theme_font_size_override("font_size", 14)
	var text: String = opt_def.get("label", cur_opt)
	if opt_def.has("palette"):
		var color_label := str(CharacterCatalog.palette(opt_def["palette"]).get(sel.get("color", ""), {}).get("label", ""))
		text = color_label if (slot_def.get("options", {}) as Dictionary).size() == 1 else text + " · " + color_label
	current.text = text
	header.add_child(current)
	if slot == "head":
		var hint := Label.new()
		hint.text = "Mütze und Strohhut ersetzen die Frisur."
		hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		hint.add_theme_font_size_override("font_size", 12)
		_content.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = _columns()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	var region: Rect2 = CATEGORY_REGIONS.get(_category, Rect2(0, 0, 1, 1))
	# A slot with a single option (skin) only needs its colour swatches.
	grid.visible = (slot_def.get("options", {}) as Dictionary).size() > 1
	for opt_id in (slot_def.get("options", {}) as Dictionary).keys():
		var candidate := app.duplicate(true)
		var new_sel := {"option": opt_id}
		var o := CharacterCatalog.option(slot, opt_id)
		if o.has("palette"):
			var pal := CharacterCatalog.palette(o["palette"])
			var keep: String = str(sel.get("color", ""))
			new_sel["color"] = keep if pal.has(keep) else str(pal.keys()[0])
		candidate[slot] = new_sel
		var card := _card(o.get("label", opt_id), candidate, region, opt_id == cur_opt, o.get("swatch", ""))
		card.pressed.connect(func() -> void: _change(candidate))
		grid.add_child(card)

	if opt_def.has("palette"):
		var colors := HFlowContainer.new()
		colors.add_theme_constant_override("h_separation", 8)
		colors.add_theme_constant_override("v_separation", 8)
		_content.add_child(colors)
		var pal := CharacterCatalog.palette(opt_def["palette"])
		for color_id in pal.keys():
			var sw := _swatch(CharacterCatalog.tint_color(opt_def["palette"], color_id), color_id == str(sel.get("color", "")), str(pal[color_id].get("label", color_id)))
			var cid: String = color_id
			sw.pressed.connect(func() -> void:
				var c := app.duplicate(true)
				c[slot] = {"option": cur_opt, "color": cid}
				_change(c))
			colors.add_child(sw)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 10)
	_content.add_child(sep)


func _render_presets() -> void:
	var info := Label.new()
	info.text = "Komplette Outfits – Körper, Gesicht und Frisur bleiben erhalten."
	info.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	info.add_theme_font_size_override("font_size", 13)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(info)
	var grid := GridContainer.new()
	grid.columns = _columns()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)
	for preset_id in (CharacterCatalog.data.get("presets", {}) as Dictionary).keys():
		var candidate := CharacterCatalog.apply_preset(app, preset_id)
		var label: String = CharacterCatalog.data["presets"][preset_id].get("label", preset_id)
		var card := _card(label, candidate, CATEGORY_REGIONS["outfits"], candidate == app, "")
		card.pressed.connect(func() -> void: _change(candidate))
		grid.add_child(card)


func _columns() -> int:
	var w := _panel.size.x - 40.0 if _panel else 400.0
	return maxi(3, int(w / (CARD_SIZE.x + 8.0)))


func _card(label: String, candidate: Dictionary, region: Rect2, selected: bool, swatch: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = CARD_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = label
	_style_selected(b, selected)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	box.add_theme_constant_override("separation", 2)
	b.add_child(box)
	var thumb := CharacterThumb.new()
	thumb.region = region
	thumb.custom_minimum_size = Vector2(CARD_SIZE.x - 12, CARD_SIZE.y - 34)
	thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumb.appearance = candidate
	box.add_child(thumb)
	var l := Label.new()
	l.text = label
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if swatch != "":
		l.add_theme_color_override("font_color", Color(swatch).lightened(0.35))
	box.add_child(l)
	if selected:
		var icon := AssetRegistry.get_texture("ui.icon.check")
		if icon:
			var check := TextureRect.new()
			check.texture = icon
			check.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			check.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			check.size = Vector2(22, 22)
			check.position = Vector2(CARD_SIZE.x - 26, 4)
			check.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(check)
	return b


func _swatch(color: Color, selected: bool, label: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(46, 46)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = label
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(23)
	s.set_border_width_all(4 if selected else 2)
	s.border_color = UiTheme.ACCENT if selected else Color(0, 0, 0, 0.55)
	s.anti_aliasing = true
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, s)
	return b


func _style_selected(b: Button, selected: bool) -> void:
	if selected:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(UiTheme.ACCENT, 0.18)
		s.border_color = UiTheme.ACCENT
		s.set_border_width_all(3)
		s.set_corner_radius_all(12)
		s.content_margin_left = 10
		s.content_margin_right = 10
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, s)
	else:
		for state in ["normal", "hover", "pressed", "focus"]:
			b.remove_theme_stylebox_override(state)
