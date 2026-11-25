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
var actors: Node2D
var effects: Array[CPUParticles2D] = []
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
	var water_shader: Shader = load("res://shaders/landmark_water.gdshader")
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
		var wmat := ShaderMaterial.new()      # living water (ripples, falling streaks)
		wmat.shader = water_shader
		wmat.set_shader_parameter("depth_tex", dtex)
		wmat.set_shader_parameter("tile_origin", at)
		wmat.set_shader_parameter("tile_size", Vector2(tex.get_width(), tex.get_height()) * k)
		s.material = wmat
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
	# figure and water effects share one y-sorted layer: every node sits on its
	# ground point (sort key), the visual is lifted by its height
	actors = Node2D.new()
	actors.name = "Actors"
	actors.z_index = 1
	actors.y_sort_enabled = true
	add_child(actors)
	figure = Node2D.new()
	figure.name = "Figure"
	actors.add_child(figure)
	rig = CharacterRig.new()
	rig.appearance = CharacterCatalog.normalize(LocalProfile.character) if LocalProfile.has_character() else CharacterCatalog.default_appearance()
	figure.add_child(rig)
	camera = Camera2D.new()
	camera.zoom = Vector2(0.55, 0.55)
	camera.position_smoothing_enabled = true
	figure.add_child(camera)
	_build_effects()
	camera.make_current()
	_place_figure()


## Animated water from site.json "fx": fountain jet, falling water veils,
## spray at the foot of every cascade. CPU particles (GL Compatibility, iOS).
func _build_effects() -> void:
	var px_m := _cos_phi * M_PX          # screen px per vertical metre
	var grav := 9.0 * px_m               # ~9 m/s² in screen units
	var drop_tex := _drop_texture()
	for fx in site.get("fx", []):
		var at := Vector2(float(fx["at"][0]), float(fx["at"][1]))
		var z := float(fx["at"][2])
		var holder := Node2D.new()           # sits on the ground point (y-sort key)
		holder.position = ground_to_world(at, 0.0)
		var p := CPUParticles2D.new()
		p.local_coords = true
		p.gravity = Vector2(0, grav)
		p.color_ramp = _water_ramp()
		p.texture = drop_tex
		p.scale_amount_min = 0.35
		p.scale_amount_max = 0.7
		var src := Vector2(0, -z * px_m)
		match str(fx["type"]):
			"jet":
				var v0 := sqrt(2.0 * grav * float(fx["height"]) * px_m)
				p.amount = 160
				p.lifetime = 2.0 * v0 / grav
				p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
				p.emission_sphere_radius = 2.0
				p.position = src
				p.direction = Vector2(0, -1)
				p.spread = rad_to_deg(float(fx.get("spread", 0.15)))
				p.initial_velocity_min = v0 * 0.92
				p.initial_velocity_max = v0
			"veil":
				var r := float(fx["radius"])
				var pts := PackedVector2Array()
				for k in 24:
					var a := TAU * k / 24.0
					pts.append(ground_to_world(at + Vector2(cos(a), sin(a)) * r, z) - ground_to_world(at, 0.0))
				p.amount = 130
				p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
				p.emission_points = pts
				p.direction = Vector2(0, 1)
				p.spread = 12.0
				p.initial_velocity_min = 8.0
				p.initial_velocity_max = 22.0
				p.lifetime = sqrt(2.0 * float(fx["drop"]) * px_m / grav)
			"splash":
				var half := float(fx.get("width", 4.0)) * 0.5
				var axis := Vector2(1, 0) if str(fx.get("axis", "x")) == "x" else Vector2(0, 1)
				var e := ground_to_world(at + axis * half, 0.0) - ground_to_world(at - axis * half, 0.0)
				p.amount = 22
				p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
				p.emission_rect_extents = Vector2(absf(e.x) * 0.5, maxf(absf(e.y) * 0.5, 2.0))
				p.position = src
				p.direction = Vector2(0, -1)
				p.spread = 50.0
				p.initial_velocity_min = 12.0
				p.initial_velocity_max = 34.0
				p.lifetime = 0.6
				p.scale_amount_max = 0.55
			_:
				p.free()
				holder.free()
				continue
		p.preprocess = p.lifetime
		holder.add_child(p)
		actors.add_child(holder)
		effects.append(p)


## Soft round droplet (16 px radial gradient).
static func _drop_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.9))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 16
	t.height = 16
	return t


static func _water_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(0.93, 0.98, 1.0, 0.95))
	g.set_color(1, Color(0.62, 0.86, 0.95, 0.0))
	g.add_point(0.6, Color(0.78, 0.93, 0.99, 0.8))
	return g


func _place_figure() -> void:
	if figure == null:
		return
	figure.position = ground_to_world(pos_m, 0.0)
	var lift := Vector2(0, -height_m * _cos_phi * M_PX)
	rig.position = lift
	camera.position = lift
	var key := depth_key(pos_m)
	var fr := Rect2(figure.position + lift + Vector2(-40, -90), Vector2(80, 100))
	for t in _tiles:
		var ov: Sprite2D = t["overlay"]
		var on := (t["rect"] as Rect2).intersects(fr)
		ov.visible = on
		if on:
			(ov.material as ShaderMaterial).set_shader_parameter("figure_key", key)


## Doors of the Concordium buildings (site metres, +x east, +y south): the
## interiors of docs/WORLD_COUNCIL_INTERIORS.md in the interior standard.
## The tholos is reached over the footbridge across the pool, the
## Wasserschloss by its arched door beside the north pavilion. `kind` is the
## kind of opening (door, double door, gate, arcade) for the opening animation.
const DOORS := [
	{"key": "concordium_chamber", "label": "Großer Ratssaal", "at": Vector2(-16.0, 8.5), "kind": "gate"},
	{"key": "concordium_exhibition", "label": "Ausstellungshalle (Westflügel)", "at": Vector2(-62.5, -20.0), "kind": "arcade"},
	{"key": "concordium_diplomacy", "label": "Diplomatieflügel (Nordflügel)", "at": Vector2(-30.0, -62.5), "kind": "arcade"},
	{"key": "concordium_archive", "label": "Archiv der Welt (Zugang im Innenhof)", "at": Vector2(-62.5, -63.0), "kind": "double"},
	{"key": "concordium_refuge", "label": "Zufluchtsort (Westpavillon)", "at": Vector2(-63.0, 22.0), "kind": "double"},
	{"key": "concordium_guest", "label": "Gästehaus (Nordpavillon)", "at": Vector2(10.0, -63.0), "kind": "double"},
	{"key": "concordium_tholos", "label": "Rundtempel (Tholos)", "at": Vector2(65.0, -11.0), "kind": "arcade"},
	{"key": "concordium_castellum", "label": "Wasserschloss", "at": Vector2(25.0, -70.5), "kind": "door"},
]
const DOOR_RADIUS := 3.0
const INSIDE_SPEED := 150.0

var interior: InteriorScene
var walker: CharacterBody2D
var walker_rig: CharacterRig
var _act_button: Button
var _toast: Label
var _toast_left := 0.0
var _context := {}
var _interactables: Array = []


## The door zone the figure stands in (outside), or {}.
func door_at(p: Vector2) -> Dictionary:
	for d in DOORS:
		if p.distance_to(d["at"]) <= DOOR_RADIUS and InteriorScene.layout_available(d["key"]):
			return d
	return {}


func _process(delta: float) -> void:
	_toast_left -= delta
	if _toast:
		_toast.visible = _toast_left > 0.0
	if interior:
		_update_light()
		# inside: daylight through the openings by day, warm lamp light at night
		var lum := (_modulate.color.r + _modulate.color.g + _modulate.color.b) / 3.0
		_modulate.color = Color(0.93, 0.84, 0.72).lerp(Color(1.0, 0.98, 0.95), clampf((lum - 0.5) / 0.4, 0.0, 1.0))
		_process_inside(delta)
		return
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down") if InputMap.has_action("move_left") else Vector2.ZERO
	if _joystick.length_squared() > input.length_squared():
		input = _joystick
	var dz := door_at(pos_m)
	_set_context({"kind": "door", "door": dz, "label": "Betreten: " + str(dz["label"])} if not dz.is_empty() else {})
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


func _set_context(c: Dictionary) -> void:
	_context = c
	if _act_button:
		_act_button.visible = not c.is_empty()
		_act_button.text = str(c.get("label", ""))


func _show_toast(t: String) -> void:
	if _toast:
		_toast.text = t
		_toast_left = 3.5


func _on_act() -> void:
	match str(_context.get("kind", "")):
		"door":
			_enter_with_transition(_context["door"])
		"exit":
			leave_interior()
		"seat":
			var sd: Dictionary = interior.seats.get(_context["seat"], {})
			if walker_rig:
				walker_rig.play("sit", true)
			_show_toast("Delegiertenplatz %s – Reihe %d, Sektor %d\nSitzordnung und Abstimmungen folgen mit dem Ratssystem (Phase 10)." % [_context["seat"], int(sd.get("row", 0)), int(sd.get("sector", 0))])
		"item":
			var act: String = _context["action"]
			var adef: Dictionary = ActionLibrary.actions().get(act, {})
			if walker_rig and adef.has("clip"):
				walker_rig.play(str(adef["clip"]), true)
			var txt := str(adef.get("toast", _context.get("label", "")))
			if str(_context.get("text", "")) != "":
				txt += "\n" + str(_context["text"]).replace("[i]", "").replace("[/i]", "")
			_show_toast(txt)


var _entering := false


## Door opening, then a loading view (no black screen), then the interior.
func _enter_with_transition(d: Dictionary) -> void:
	if _entering or interior:
		return
	_entering = true
	_set_context({})
	var dur := 0.9 if str(d.get("kind", "door")) == "gate" else 0.5
	if str(d.get("kind", "door")) != "arcade":
		_door_animation(d, dur)
		await get_tree().create_timer(dur).timeout
	var ov := _loading_view(str(d["label"]))
	await get_tree().process_frame
	await get_tree().process_frame
	enter_interior(str(d["key"]))
	var tw := create_tween()
	tw.tween_property(ov.get_child(0), "modulate:a", 0.0, 0.35)
	tw.tween_callback(ov.queue_free)
	_entering = false


## Two leaves (one for a plain door) swing open in the doorway of the asset.
func _door_animation(d: Dictionary, dur: float) -> void:
	var at: Vector2 = d["at"]
	var node := Node2D.new()
	node.position = ground_to_world(at, surface_height(at))
	node.z_index = 5
	actors.add_child(node)
	var kind := str(d.get("kind", "door"))
	var w := (3.4 if kind == "gate" else 2.2) * M_PX * 0.5
	var h := (5.0 if kind == "gate" else 2.6) * M_PX * 0.5
	var col := Color("8a5a2e") if kind == "gate" else Color("6b4426")
	var leaves := 1 if kind == "door" else 2
	var back := Polygon2D.new()
	back.polygon = PackedVector2Array([Vector2(-w, -h), Vector2(w, -h), Vector2(w, 0), Vector2(-w, 0)])
	back.color = Color(0.08, 0.06, 0.05, 0.9)
	node.add_child(back)
	for k in leaves:
		var leaf := Polygon2D.new()
		var lw := w * 2.0 / leaves
		var x0 := -w + lw * k
		leaf.position = Vector2(x0 if k == 0 else x0 + lw, 0)
		var sgn := 1.0 if k == 0 else -1.0
		leaf.polygon = PackedVector2Array([Vector2(0, -h), Vector2(lw * sgn, -h), Vector2(lw * sgn, 0), Vector2(0, 0)])
		leaf.color = col
		var stud := Polygon2D.new()
		stud.polygon = PackedVector2Array([Vector2(lw * sgn * 0.2, -h * 0.55), Vector2(lw * sgn * 0.8, -h * 0.55), Vector2(lw * sgn * 0.8, -h * 0.5), Vector2(lw * sgn * 0.2, -h * 0.5)])
		stud.color = Color("d4a64a") if kind == "gate" else col.darkened(0.3)
		leaf.add_child(stud)
		node.add_child(leaf)
		create_tween().tween_property(leaf, "scale:x", 0.12, dur).set_trans(Tween.TRANS_SINE)
	var tw := create_tween()
	tw.tween_interval(dur + 0.6)
	tw.tween_callback(node.queue_free)


## A loading view over everything while a (large) interior is built.
func _loading_view(label: String) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 50
	var bg := ColorRect.new()
	bg.color = Color("1c1712")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var l := Label.new()
	l.text = "%s\nwird betreten …" % label
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.add_theme_color_override("font_color", Color("efe3c8"))
	l.add_theme_font_size_override("font_size", 22)
	bg.add_child(l)
	layer.add_child(bg)
	add_child(layer)
	return layer


## Enters a Concordium building: the interior (interior standard) replaces
## the site view; a walker with collisions moves inside.
func enter_interior(key: String) -> void:
	if interior or not InteriorScene.layout_available(key):
		return
	interior = InteriorScene.create(key, [], 1, 1.0)
	interior.position = Vector2(0, 200000)
	add_child(interior)
	for n in [get_node_or_null("Tiles"), get_node_or_null("Occluders"), actors]:
		if n:
			n.visible = false
	walker = CharacterBody2D.new()
	walker.name = "Walker"
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 9.0
	shape.shape = circle
	walker.add_child(shape)
	walker_rig = CharacterRig.new()
	walker_rig.appearance = rig.appearance
	walker_rig.world_per_src = Iso.WORLD_PER_SRC_PX * 0.62 * InteriorScene.PERSON_SCALE
	walker.add_child(walker_rig)
	interior.objects.add_child(walker)
	walker.collision_mask = InteriorScene.LAYER_SOLID | InteriorScene.LAYER_LEVEL_BASE
	walker.position = interior.spawn_point
	camera.reparent(walker)
	camera.position = Vector2(0, -40)
	var b := interior.bounds()
	camera.limit_left = int(b.position.x)
	camera.limit_top = int(b.position.y)
	camera.limit_right = int(b.end.x)
	camera.limit_bottom = int(b.end.y)
	camera.zoom = Vector2(0.75, 0.75)
	camera.reset_smoothing()
	_info.text = "%s – %s\n%s" % [Landmarks.site_name(landmark_id).to_upper(), str(interior.layout.get("label", "")), "Innenraum (Entwicklungsvorschau)"]
	_show_toast("Du betrittst: " + str(interior.layout.get("label", "")))


func leave_interior() -> void:
	if interior == null:
		return
	camera.reparent(figure)
	camera.position = rig.position
	camera.limit_left = -10000000
	camera.limit_top = -10000000
	camera.limit_right = 10000000
	camera.limit_bottom = 10000000
	camera.zoom = Vector2(0.55, 0.55)
	camera.reset_smoothing()
	interior.queue_free()
	interior = null
	_interactables = []
	walker = null
	walker_rig = null
	for n in [get_node_or_null("Tiles"), get_node_or_null("Occluders"), actors]:
		if n:
			n.visible = true
	var d := Landmarks.get_def(landmark_id)
	_info.text = "%s – %s\nEntwicklungsvorschau (Anreise folgt mit dem Verkehrssystem, Phase 8)" % [d.get("name", ""), d.get("subtitle", "")]
	_set_context({})


func _process_inside(_delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down") if InputMap.has_action("move_left") else Vector2.ZERO
	if _joystick.length_squared() > input.length_squared():
		input = _joystick
	walker.velocity = input.limit_length(1.0) * INSIDE_SPEED
	walker.move_and_slide()
	interior.carry(walker, walker_rig)
	if input.length() > 0.05:
		_facing = Iso.facing_with_hysteresis(input, _facing)
	walker_rig.set_motion(clampf(walker.velocity.length() / INSIDE_SPEED, 0.0, 1.0), _facing)
	# context: exit at the doormat, else the object under the figure
	var lp := walker.position
	if _interactables.is_empty():
		_interactables = interior.find_children("*", "Interactable", true, false)
	for it in _interactables:
		var cp := it.get_child(0) as CollisionPolygon2D
		if cp == null or not Geometry2D.is_point_in_polygon(lp - it.position, cp.polygon):
			continue
		if it.kind == "interior_exit":
			_set_context({"kind": "exit", "label": "Verlassen"})
			return
		if it.kind == "interior":
			var act := str(it.get_meta("action", ""))
			_set_context({"kind": "item", "action": act, "label": "%s: %s" % [it.verb, it.title], "text": it.text})
			return
	var seat := interior.nearest_seat(lp)
	if seat != "":
		_set_context({"kind": "seat", "seat": seat, "label": "Platz nehmen (%s)" % seat})
		return
	_set_context({})


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
	_act_button = Button.new()
	_act_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_act_button.custom_minimum_size = Vector2(220, 64)
	_act_button.position = Vector2(-250, -110)
	_act_button.visible = false
	_act_button.pressed.connect(_on_act)
	root.add_child(_act_button)
	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-260, 96)
	_toast.custom_minimum_size = Vector2(520, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_font_size_override("font_size", 15)
	_toast.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.visible = false
	root.add_child(_toast)
	var stick := TouchJoystick.new()
	stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stick.position = Vector2(20, -200)
	root.add_child(stick)


func perf_stats() -> Dictionary:
	var vis := 0
	for t in _tiles:
		vis += 1 if (t["overlay"] as Sprite2D).visible else 0
	var parts := 0
	for e in effects:
		parts += e.amount
	return {"view": "council", "tiles": _tiles.size(), "overlays": vis, "effects": effects.size(), "particles": parts}
