class_name GlobeLabels
extends Control
## 2D overlay above the globe: continent and region names, settlement pins
## and the founding candidate. Drawn in one _draw() call (no node per label);
## labels on the far side are hidden and overlapping labels are skipped.

var view: GlobeView
## [{lat, lon, name, own}] settlement markers.
var settlements: Array = []
## Candidate founding site {lat, lon} or empty.
var candidate: Dictionary = {}
var candidate_valid := true

var _font: Font
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if view == null or view.planet == null or view.camera == null:
		return
	var taken: Array[Rect2] = []
	# Markers first (they have priority over names).
	for s in settlements:
		var pr := view.project(s["lat"], s["lon"], 0.004)
		if not pr["visible"]:
			continue
		var pos: Vector2 = pr["pos"]
		_pin(pos, UiTheme.ACCENT if s.get("own", false) else Color("e8e4da"))
		var label: String = s["name"]
		if view.level != "planetar" or s.get("own", false):
			taken.append(_text(pos + Vector2(0, -30), label, 15, Color.WHITE, taken, true))
		taken.append(Rect2(pos - Vector2(10, 26), Vector2(20, 28)))
	if not candidate.is_empty():
		var pr := view.project(candidate["lat"], candidate["lon"], 0.004)
		if pr["visible"]:
			var pulse := 0.5 + 0.5 * sin(_time * 4.0)
			var c := Color("ff9b2f") if candidate_valid else Color("e5534b")
			draw_circle(pr["pos"], 9.0 + pulse * 5.0, Color(c, 0.25))
			_pin(pr["pos"], c)
			taken.append(Rect2(pr["pos"] - Vector2(12, 28), Vector2(24, 30)))
	# Continents (planetar + kontinental).
	if view.level != "regional":
		var size := 19 if view.level == "planetar" else 16
		for c in view.planet.continents:
			var center: Vector2 = c["center"]
			var pr := view.project(center.x, center.y)
			if pr["visible"]:
				_text(pr["pos"], str(c["name"]).to_upper(), size, Color(1, 1, 1, 0.92), taken, false)
	# Regions (kontinental + regional).
	if view.level != "planetar":
		var size := 12 if view.level == "kontinental" else 14
		for r in view.planet.regions:
			var center: Vector2 = r["center"]
			var pr := view.project(center.x, center.y)
			if pr["visible"] and pr["facing"] > 0.35:
				var col := Color(1, 0.93, 0.75, 0.95) if r["region_id"] == view.highlight_region else Color(1, 1, 1, 0.78)
				_text(pr["pos"], r["name"], size, col, taken, false)


func _pin(pos: Vector2, color: Color) -> void:
	var top := pos + Vector2(0, -20)
	draw_line(pos, top, Color(0.1, 0.1, 0.12), 3.0, true)
	draw_circle(top, 8.0, Color(0.1, 0.1, 0.12))
	draw_circle(top, 6.0, color)
	draw_circle(pos, 2.5, Color(0.1, 0.1, 0.12))


## Draws centred text with outline unless it overlaps an earlier label.
func _text(center: Vector2, text: String, size: int, color: Color, taken: Array[Rect2], force: bool) -> Rect2:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var rect := Rect2(center - Vector2(w * 0.5, size * 0.75), Vector2(w, size * 1.1)).grow(3)
	if not force:
		if not get_rect().has_point(center):
			return Rect2()
		for t in taken:
			if t.intersects(rect):
				return Rect2()
	taken.append(rect)
	var base := center + Vector2(-w * 0.5, size * 0.35)
	draw_string_outline(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0.05, 0.07, 0.1, 0.85))
	draw_string(_font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return rect
