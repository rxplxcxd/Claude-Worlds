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
## Fixed world landmarks [{landmark_id, lat, lon, name, subtitle, reserve_km}]
## (reserve_km: radius of a circle with the property's area – drawn at least 9 px)
## (World Council). Drawn flat on the surface + a small monument emblem
## standing on the exact point – never floating above the globe.
var landmarks: Array = []
## Screen hit areas of the drawn landmarks {landmark_id: Rect2}.
var landmark_rects: Dictionary = {}

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
	landmark_rects.clear()
	for lm in landmarks:
		_landmark(lm, taken)
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


const LM_GOLD := Color("e0b64a")
const LM_MARBLE := Color("f3ede0")
const LM_INK := Color("2b0f2a")


## Landmark: a ring lying ON the sphere (projected surface circle, so it
## tilts and foreshortens with the globe) around the reserved ground, and a
## tiny temple emblem whose base sits exactly on the surface point.
func _landmark(lm: Dictionary, taken: Array[Rect2]) -> void:
	var pr := view.project(lm["lat"], lm["lon"])
	if not pr["visible"]:
		return
	var pos: Vector2 = pr["pos"]
	var r_km := maxf(float(lm.get("reserve_km", 18.0)), 9.0 / maxf(view.pixels_per_km(), 0.0001))
	var ring := PackedVector2Array()
	for k in 33:
		var a := TAU * k / 32.0
		var ll := Geo.offset(lm["lat"], lm["lon"], cos(a) * r_km, sin(a) * r_km, view.planet.radius_km)
		var q := view.project(ll.x, ll.y)
		ring.append(q["pos"])
	if ring.size() >= 3:
		draw_colored_polygon(ring, Color(LM_GOLD, 0.22))
		draw_polyline(ring, Color(LM_GOLD, 0.95), 2.0, true)
	# emblem: steps, columns, pediment (scaled down near the limb)
	var k := clampf(float(pr["facing"]) * 1.3, 0.55, 1.0)
	var w := 20.0 * k
	var h := 22.0 * k
	var base := pos
	var steps := PackedVector2Array([base + Vector2(-w * 0.62, 0), base + Vector2(w * 0.62, 0), base + Vector2(w * 0.55, -h * 0.14), base + Vector2(-w * 0.55, -h * 0.14)])
	draw_colored_polygon(steps, LM_MARBLE)
	draw_polyline(steps + PackedVector2Array([steps[0]]), LM_INK, 1.5, true)
	var top_y := -h * 0.68
	for c in 4:
		var x := -w * 0.42 + c * w * 0.28
		draw_rect(Rect2(base + Vector2(x - w * 0.06, top_y), Vector2(w * 0.12, -top_y - h * 0.14)), LM_MARBLE)
		draw_rect(Rect2(base + Vector2(x - w * 0.06, top_y), Vector2(w * 0.12, -top_y - h * 0.14)), LM_INK, false, 1.0)
	var ped := PackedVector2Array([base + Vector2(-w * 0.6, top_y), base + Vector2(w * 0.6, top_y), base + Vector2(0, -h)])
	draw_colored_polygon(ped, LM_GOLD)
	draw_polyline(ped + PackedVector2Array([ped[0]]), LM_INK, 1.5, true)
	draw_circle(pos, 2.0, LM_INK)
	var hit := Rect2(base + Vector2(-w * 0.8, -h - 4), Vector2(w * 1.6, h + 8))
	taken.append(hit)
	var r1 := _text(base + Vector2(0, -h - 14), str(lm["name"]), 15, LM_GOLD, taken, true)
	var r2 := _text(base + Vector2(0, 14), str(lm["subtitle"]), 11, Color(1, 1, 1, 0.9), taken, true)
	landmark_rects[lm["landmark_id"]] = hit.merge(r1).merge(r2).grow(6)


## The landmark drawn at a screen point, or "".
func landmark_at(pos: Vector2) -> String:
	for id in landmark_rects.keys():
		if (landmark_rects[id] as Rect2).has_point(pos):
			return id
	return ""


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
