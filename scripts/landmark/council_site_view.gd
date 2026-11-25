class_name CouncilSiteView
extends Node2D
## Walkable development preview of the World Council seat (stage art from
## tools/art/export_council.py). Reached from the globe ("Ansehen") – real
## travel there comes with the transport systems (Phase 8), see
## docs/WORLD_COUNCIL_ROADMAP.md.
##
## Rendering: colour tiles at the bottom, the figure above them, and an
## overlay copy of the tiles around the figure that keeps only the pixels in
## front of it (per-pixel footprint depth, shaders/landmark_occluder.gdshader).
## Walking: 0.5 m grid with surface heights (stairs, podium, terraces), blocked
## cells (walls, columns, statues, water, plants).

signal closed

const SITE_DIR := "res://assets/landmarks/world_council/stage%d/"
## Projection pixels per metre in world units: a Penzilla figure (~54 px) is 1.75 m.
const M_PX := 37.5
const R2 := 0.7071067811865476
const WALK_SPEED := 3.4
const STEP_MAX := 0.55
const RADIUS := 0.35

var site: Dictionary = {}
var landmark_id := Landmarks.WORLD_COUNCIL
var stage := 1
var camera: Camera2D
var figure: Node2D
var rig: CharacterRig
var pos_m := Vector2.ZERO          # grid position (metres)
var height_m := 0.0
var _tiles: Array = []             # [{sprite, overlay, rect}]
var _heights := PackedInt32Array()
var _kinds := PackedByteArray()
var _nx := 0
var _ny := 0
var _x0 := 0.0
var _y0 := 0.0
var _cell_m := 1.0
var _joystick := Vector2.ZERO
var _facing := 2
var _sin_phi := 292.0 / 512.0
var _cos_phi := 0.0
var _ui: CanvasLayer
var _info: Label
var _zone: Label
var _inside := true
var _modulate: CanvasModulate


func _ready() -> void:
	add_to_group("perf_view")
	_cos_phi = sqrt(1.0 - _sin_phi * _sin_phi)
	stage = int(WorldState.landmark_state(landmark_id).get("stage", 1))
	if not load_site(stage):
		push_warning("CouncilSiteView: site data missing")
	_build_world()
	_build_ui()
	EventBus.move_vector_changed.connect(func(v: Vector2) -> void: _joystick = v)


## Reads site.json (tiles, projection, walk grid). Returns false if missing.
func load_site(p_stage: int) -> bool:
	var path := (SITE_DIR % p_stage) + "site.json"
	if not FileAccess.file_exists(path):
		path = (SITE_DIR % 1) + "site.json"
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return false
	site = parsed
	_sin_phi = float(site["view"]["sin_phi"])
	_cos_phi = sqrt(1.0 - _sin_phi * _sin_phi)
	var g: Dictionary = site["grid"]
	_nx = int(g["nx"])
	_ny = int(g["ny"])
	_x0 = float(g["x0"])
	_y0 = float(g["y0"])
	_cell_m = float(g.get("cell_m", 1.0))
	var hb := Marshalls.base64_to_raw(g["height_dm"])
	_heights.resize(_nx * _ny)
	for i in _nx * _ny:
		_heights[i] = hb.decode_s16(i * 2)
	_kinds = Marshalls.base64_to_raw(g["kind"])
	var sp: Array = site.get("spawn", [0, 0])
	pos_m = Vector2(float(sp[0]), float(sp[1]))
	height_m = surface_height(pos_m)
	return true


# --- projection ----------------------------------------------------------------

func ground_to_world(p: Vector2, z: float = 0.0) -> Vector2:
	return Vector2((p.x - p.y) * R2, (p.x + p.y) * R2 * _sin_phi - z * _cos_phi) * M_PX


## Screen direction (x right, y down) -> grid direction on the ground.
func screen_dir_to_grid(v: Vector2) -> Vector2:
	var a := v.x / R2
	var b := v.y / (R2 * _sin_phi)
	var g := Vector2((a + b) * 0.5, (b - a) * 0.5)
	return g.normalized() * v.length() if g.length_squared() > 0.0 else Vector2.ZERO


func depth_key(p: Vector2) -> float:
	return (p.x + p.y + 200.0) * 100.0


# --- walk grid -------------------------------------------------------------------

func _cell(p: Vector2) -> int:
	var ix := int(floor((p.x - _x0) / _cell_m))
	var iy := int(floor((p.y - _y0) / _cell_m))
	if ix < 0 or iy < 0 or ix >= _nx or iy >= _ny:
		return -1
	return iy * _nx + ix


func surface_height(p: Vector2) -> float:
	var c := _cell(p)
	return float(_heights[c]) / 10.0 if c >= 0 else 0.0


func cell_kind(p: Vector2) -> int:
	var c := _cell(p)
	return int(_kinds[c]) if c >= 0 else 1


## Whether a figure can stand at p coming from height `from_h`.
func can_stand(p: Vector2, from_h: float) -> bool:
	for o in [Vector2.ZERO, Vector2(RADIUS, 0), Vector2(-RADIUS, 0), Vector2(0, RADIUS), Vector2(0, -RADIUS)]:
		var q: Vector2 = p + o
		if cell_kind(q) != 0:
			return false
		if absf(surface_height(q) - from_h) > STEP_MAX + (0.0 if o == Vector2.ZERO else 0.3):
			return false
	return true


# --- scene ---------------------------------------------------------------------------

func _build_world() -> void:
	_modulate = CanvasModulate.new()
	add_child(_modulate)
	if site.is_empty():
		return
	var dir := SITE_DIR % int(site.get("stage", 1))
	var k := M_PX / float(site["px_per_m"])
	var origin := Vector2(float(site["origin_m"][0]), -float(site["origin_m"][1])) * M_PX
	var shader: Shader = load("res://shaders/landmark_occluder.gdshader")
	var base := Node2D.new()
	base.name = "Tiles"
	base.z_index = 0
	add_child(base)
	var over := Node2D.new()
	over.name = "Occluders"
	over.z_index = 2
	add_child(over)
	for t in site["tiles"]:
		var tex: Texture2D = load(dir + "color_%s.png" % t["name"])
		var dtex: Texture2D = load(dir + "depth_%s.png" % t["name"])
		if tex == null:
			continue
		var at := origin + Vector2(float(t["x"]), float(t["y"])) * k
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.position = at
		s.scale = Vector2(k, k)
		base.add_child(s)
		var o := Sprite2D.new()
		o.texture = tex
		o.centered = false
		o.position = at
		o.scale = Vector2(k, k)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("depth_tex", dtex)
		o.material = mat
		o.visible = false
		over.add_child(o)
		_tiles.append({"sprite": s, "overlay": o, "rect": Rect2(at, Vector2(float(t["w"]), float(t["h"])) * k)})
	figure = Node2D.new()
	figure.name = "Figure"
	figure.z_index = 1
	add_child(figure)
	rig = CharacterRig.new()
	rig.appearance = CharacterCatalog.normalize(LocalProfile.character) if LocalProfile.has_character() else CharacterCatalog.default_appearance()
	figure.add_child(rig)
	camera = Camera2D.new()
	camera.zoom = Vector2(0.55, 0.55)
	camera.position_smoothing_enabled = true
	figure.add_child(camera)
	camera.make_current()
	_place_figure()


func _place_figure() -> void:
	if figure == null:
		return
	figure.position = ground_to_world(pos_m, height_m)
	var key := depth_key(pos_m)
	var fr := Rect2(figure.position + Vector2(-40, -90), Vector2(80, 100))
	for t in _tiles:
		var ov: Sprite2D = t["overlay"]
		var on := (t["rect"] as Rect2).intersects(fr)
		ov.visible = on
		if on:
			(ov.material as ShaderMaterial).set_shader_parameter("figure_key", key)


func _process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down") if InputMap.has_action("move_left") else Vector2.ZERO
	if _joystick.length_squared() > input.length_squared():
		input = _joystick
	var moving := input.length() > 0.05
	if moving:
		var g := screen_dir_to_grid(input) * WALK_SPEED * delta
		var moved := false
		for step in [g, Vector2(g.x, 0), Vector2(0, g.y)]:  # slide along walls
			var np: Vector2 = pos_m + step
			if step.length_squared() > 0.0 and can_stand(np, height_m):
				pos_m = np
				height_m = lerpf(height_m, surface_height(np), 0.6)
				moved = true
				break
		_facing = Iso.facing_with_hysteresis(Vector2(input.x, input.y), _facing)
		if rig:
			rig.set_motion(clampf(input.length(), 0.0, 1.0) if moved else 0.0, _facing)
	elif rig:
		rig.set_motion(0.0, _facing)
	height_m = lerpf(height_m, surface_height(pos_m), clampf(delta * 12.0, 0.0, 1.0))
	_place_figure()
	_update_light()
	_update_zone()


func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.15)
	elif event is InputEventMagnifyGesture:
		zoom_by(event.factor)


func zoom_by(f: float) -> void:
	var z := clampf(camera.zoom.x * f, 0.1, 0.8)
	camera.zoom = Vector2(z, z)


## Day and night from the site's solar time (UTC + longitude / 15).
func _update_light() -> void:
	var lon := Landmarks.position_of(landmark_id).y
	var utc := Time.get_unix_time_from_system()
	var h := fposmod(utc / 3600.0 + lon / 15.0, 24.0)
	var sun := clampf(sin((h - 6.0) / 12.0 * PI) * 1.6 + 0.2, 0.0, 1.0)
	var night := Color(0.42, 0.45, 0.68)
	var dusk := Color(1.0, 0.86, 0.74)
	var c := night.lerp(Color.WHITE, sun)
	if sun > 0.0 and sun < 0.6:
		c = c.lerp(dusk, 0.35 * (1.0 - absf(sun - 0.3) / 0.3))
	_modulate.color = c


## Neutral zone = exactly the property polygon (site metres: +x east, +y south).
func is_in_neutral_zone(p: Vector2) -> bool:
	return Landmarks.inside_property(landmark_id, p, WorldState.landmark_state(landmark_id))


func _update_zone() -> void:
	var inside := is_in_neutral_zone(pos_m)
	if _zone and (inside != _inside or _zone.text == ""):
		_zone.text = "Neutrales Gelände des Concordiums – Gewalt ist hier verboten." if inside else "Außerhalb des Concordiums – hier gelten die normalen Regeln."
	_inside = inside


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	var root := Control.new()
	root.theme = UiTheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	var d := Landmarks.get_def(landmark_id)
	_info = Label.new()
	_info.text = "%s – %s\nEntwicklungsvorschau (Anreise folgt mit dem Verkehrssystem, Phase 8)" % [d.get("name", ""), d.get("subtitle", "")]
	_info.position = Vector2(16, 12)
	_info.add_theme_font_size_override("font_size", 15)
	_info.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
	_info.add_theme_constant_override("outline_size", 5)
	root.add_child(_info)
	_zone = Label.new()
	_zone.position = Vector2(16, 62)
	_zone.add_theme_font_size_override("font_size", 13)
	_zone.add_theme_color_override("font_color", Color("f2d58a"))
	_zone.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
	_zone.add_theme_constant_override("outline_size", 5)
	root.add_child(_zone)
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	bar.position = Vector2(-230, 12)
	root.add_child(bar)
	for spec in [["−", func() -> void: zoom_by(1.0 / 1.3)], ["+", func() -> void: zoom_by(1.3)], ["Zurück", func() -> void: closed.emit()]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(56, 48)
		b.pressed.connect(spec[1])
		bar.add_child(b)
	var stick := TouchJoystick.new()
	stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stick.position = Vector2(20, -200)
	root.add_child(stick)


func perf_stats() -> Dictionary:
	var vis := 0
	for t in _tiles:
		vis += 1 if (t["overlay"] as Sprite2D).visible else 0
	return {"view": "council", "tiles": _tiles.size(), "overlays": vis}
