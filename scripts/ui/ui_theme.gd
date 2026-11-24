class_name UiTheme
extends RefCounted
## HUD theme.
##
## Uses the Penzilla "Basic GUI Bundle" (keys ui.panel / ui.button /
## ui.button_pressed / ui.button_accent) as 9-slice styles when imported;
## otherwise falls back to flat styles built in code. Colours and sizes are
## tokens here so the look is changed in one place.

const BG := Color(0.07, 0.09, 0.125, 0.86)
const BG_SOLID := Color(0.09, 0.11, 0.15, 0.96)
const BORDER := Color(1, 1, 1, 0.08)
const TEXT := Color("f3eee2")
const TEXT_DIM := Color("b9b4a8")
const ACCENT := Color("f2c230")
const ACCENT_DARK := Color("1d1a12")
const RADIUS := 14
const FONT_SIZE := 17


const SLICE_MARGIN := 22.0


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE

	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())

	var normal: StyleBox = _textured("ui.button", 12, 8)
	if normal == null:
		var flat := _box(BG, RADIUS - 4, 10, 8)
		flat.border_color = BORDER
		flat.set_border_width_all(1)
		normal = flat
	var hover: StyleBox = _textured("ui.button", 12, 8, Color(1.12, 1.12, 1.12))
	if hover == null:
		hover = _box(BG.lightened(0.12), RADIUS - 4, 10, 8)
	var pressed: StyleBox = _textured("ui.button_pressed", 12, 8)
	if pressed == null:
		pressed = _box(Color(ACCENT, 0.35), RADIUS - 4, 10, 8)
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
	t.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.6))
	t.set_constant("outline_size", "Button", 3)
	t.set_constant("icon_max_width", "Button", 30)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", FONT_SIZE)
	t.set_font_size("bold_font_size", "RichTextLabel", FONT_SIZE)
	t.set_font_size("italics_font_size", "RichTextLabel", FONT_SIZE - 1)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_stylebox("normal", "CheckButton", _box(Color(0, 0, 0, 0), 6, 4, 4))
	return t


static func panel_style(color: Color = BG) -> StyleBox:
	# Nearly opaque panels (dialogs) stay flat and solid for readability.
	var tex: StyleBox = null if color.a >= 0.95 else _textured("ui.panel", 18, 14, Color(1, 1, 1, clampf(color.a + 0.08, 0.0, 1.0)))
	if tex:
		return tex
	var s := _box(color, RADIUS, 16, 12)
	s.border_color = BORDER
	s.set_border_width_all(1)
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 6
	return s


## Orange accent style (interact button, action buttons).
static func accent_style(pressed: bool = false) -> StyleBox:
	var tex := _textured("ui.button_accent", 16, 10, Color(0.85, 0.85, 0.85) if pressed else Color.WHITE)
	if tex:
		return tex
	var s := _box(Color(ACCENT.darkened(0.25) if pressed else ACCENT, 0.94), RADIUS, 16, 12)
	return s


## 9-slice style from a Penzilla GUI texture, or null if unavailable.
static func _textured(key: String, mx: int, my: int, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var tex := AssetRegistry.get_texture(key)
	if tex == null:
		return null
	var s := StyleBoxTexture.new()
	s.texture = tex
	s.set_texture_margin_all(SLICE_MARGIN)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	s.modulate_color = modulate
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
