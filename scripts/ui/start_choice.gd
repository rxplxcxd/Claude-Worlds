class_name StartChoice
extends Control
## "Wie möchtest du beginnen?" – shown to a new player after the character
## editor (DESIGN_DIRECTIVES.md §4, PLAYER_SYSTEM.md §3a):
##   A) join an existing settlement of another player
##   B) found an own settlement (globe)
## Joining needs a shared multiplayer world (Phase 12). Until then the option
## is visible but clearly marked as unavailable – nothing is faked: the local
## planet contains no settlements of other players.

signal found_chosen

var _join_button: Button
var _found_button: Button
var _card_found: PanelContainer
var _card_join: PanelContainer
var _box: BoxContainer


func _ready() -> void:
	theme = UiTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var outer := VBoxContainer.new()
	outer.name = "Outer"
	outer.add_theme_constant_override("separation", 14)
	add_child(outer)
	var title := Label.new()
	title.text = "Wie möchtest du beginnen?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	outer.add_child(title)
	_box = BoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	outer.add_child(_box)

	var others := _other_players_settlements()
	_card_found = _card("Eigene Siedlung gründen",
		"Wähle auf dem Globus einen freien Ort (mindestens 20 km Abstand zu fremden Gebieten). Deine Siedlung beginnt klein – mit 1 × 1 km Gebiet, ersten Gebäuden und viel Platz zum Ausbauen.",
		"Ort auf dem Globus wählen", true)
	_found_button = _card_found.get_meta("button")
	_found_button.pressed.connect(func() -> void: found_chosen.emit())
	_box.add_child(_card_found)

	var join_text := "Ziehe in eine Siedlung, die ein anderer Mensch gegründet hat.\n\n"
	join_text += "Noch nicht verfügbar: Diese Version läuft nur lokal auf deinem Gerät. Es gibt keine gemeinsame Welt und keine Siedlungen anderer Spieler (gefunden: %d). Beitreten wird mit der Mehrspieler-Grundlage freigeschaltet." % others
	_card_join = _card("Einer Siedlung beitreten", join_text, "Mehrspieler – noch nicht verfügbar", false)
	_join_button = _card_join.get_meta("button")
	_join_button.disabled = true
	_box.add_child(_card_join)
	get_viewport().size_changed.connect(_layout)
	_layout()


## Settlements founded by OTHER players on the local planet (always 0 until
## a shared world exists – the count is real, not decorative).
func _other_players_settlements() -> int:
	return WorldState.get_settlements().filter(func(s): return not (s.get("resident_player_ids", []) as Array).has(LocalProfile.player_id)).size()


func _card(head: String, body: String, button_text: String, primary: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.BG_SOLID if primary else Color(0.1, 0.12, 0.16, 0.9)))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var h := Label.new()
	h.text = head
	h.add_theme_font_size_override("font_size", 22)
	h.add_theme_color_override("font_color", UiTheme.TEXT if primary else UiTheme.TEXT_DIM)
	v.add_child(h)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(240, 0)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", UiTheme.TEXT if primary else UiTheme.TEXT_DIM)
	v.add_child(b)
	var btn := Button.new()
	btn.text = button_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 52)
	btn.add_theme_font_size_override("font_size", 17)
	if primary:
		btn.add_theme_stylebox_override("normal", UiTheme.accent_style(false))
		btn.add_theme_stylebox_override("hover", UiTheme.accent_style(false))
		btn.add_theme_stylebox_override("pressed", UiTheme.accent_style(true))
		btn.add_theme_color_override("font_color", UiTheme.ACCENT_DARK)
		btn.add_theme_color_override("font_hover_color", UiTheme.ACCENT_DARK)
	v.add_child(btn)
	card.set_meta("button", btn)
	return card


func _layout() -> void:
	var vp := get_viewport_rect().size
	var portrait := vp.y > vp.x
	_box.vertical = portrait
	var outer := get_node("Outer") as VBoxContainer
	var margin := 18.0
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.position = Vector2(margin, margin)
	outer.size = vp - Vector2(margin, margin) * 2.0
	outer.reset_size.call_deferred()
	(func() -> void:
		outer.size.x = vp.x - margin * 2.0
		outer.position.y = maxf(margin, (vp.y - outer.size.y) * 0.5)).call_deferred()
