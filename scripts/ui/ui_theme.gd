class_name UiTheme
extends RefCounted
## Fallback HUD theme built in code.
##
## PLACEHOLDER until the Penzilla "Basic GUI" package is integrated
## ("ui.theme" in data/asset_manifest.json). Colours/sizes are tokens here so
## the switch to the real theme touches only this file.

const BG := Color(0.07, 0.09, 0.125, 0.86)
const BG_SOLID := Color(0.09, 0.11, 0.15, 0.96)
const BORDER := Color(1, 1, 1, 0.08)
const TEXT := Color("f3eee2")
const TEXT_DIM := Color("b9b4a8")
const ACCENT := Color("f2c230")
const ACCENT_DARK := Color("1d1a12")
const RADIUS := 14
const FONT_SIZE := 17


static func build() -> Theme:
	var custom := AssetRegistry.get_resource("ui.theme") as Theme
	if custom:
		return custom
	var t := Theme.new()
	t.default_font_size = FONT_SIZE

	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())

	var normal := _box(BG, RADIUS - 4, 10, 8)
	normal.border_color = BORDER
	normal.set_border_width_all(1)
	var hover := _box(BG.lightened(0.12), RADIUS - 4, 10, 8)
	var pressed := _box(Color(ACCENT, 0.35), RADIUS - 4, 10, 8)
	for state in ["normal", "focus"]:
		t.set_stylebox(state, "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", _box(Color(1, 1, 1, 0.03), RADIUS - 4, 10, 8))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", FONT_SIZE)
	t.set_font_size("bold_font_size", "RichTextLabel", FONT_SIZE)
	t.set_font_size("italics_font_size", "RichTextLabel", FONT_SIZE - 1)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_stylebox("normal", "CheckButton", _box(Color(0, 0, 0, 0), 6, 4, 4))
	return t


static func panel_style(color: Color = BG) -> StyleBoxFlat:
	var s := _box(color, RADIUS, 16, 12)
	s.border_color = BORDER
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 6
	return s


static func _box(color: Color, radius: int, mx: int, my: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	s.anti_aliasing = true
	return s
