class_name LivingGallery
extends Node2D
## Living Assets – step E: technical check in Godot (QA only, not in the game).
## Opened with "?gallery=living" (web) – see Main._qa_gallery().
##
## Every object is composed by LivingComposer from a VisualState – the same
## code path the game will use: structural base (tier 3) + overlays (tier 2)
## + shared wear shader (tier 1), plus own VFX. "&profile=ultra|hoch|leistung"
## switches the quality profile. Files: assets/penzilla/states (generated, private).

const WORLD_PER_SRC := 0.25
const CELL := Vector2(150, 190)
const COLS := 12

var sprites := 0
var profile := "hoch"
var _vfx: Texture2D
var _vfx_meta: Dictionary = {}
var _font: Font
var _labels: Array = []


func _ready() -> void:
	add_to_group("perf_view")
	_font = ThemeDB.fallback_font
	profile = _url_profile()
	var bg := ColorRect.new()
	bg.color = Color("7ea85c")
	bg.size = Vector2(6000, 4000)
	bg.position = Vector2(-200, -200)
	bg.show_behind_parent = true # captions (_draw of this node) stay on top
	add_child(bg)
	if LivingComposer.manifest().is_empty():
		_label(Vector2(20, 40), "Keine Zustandsdateien – tools/assets/make_living_states.py ausführen.", 24)
		return
	_vfx = load("res://assets/vfx/vfx_atlas.png")
	_vfx_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vfx/vfx_atlas.json"))
	var y := 0
	_row_title(y, "Gebäude – 12 Zustände als Merkmal-Kombination (Profil: %s)" % LivingComposer.PROFILES[profile]["label"])
	var x := 0
	for k in ["01_neu", "02_gepflegt", "03_benutzt", "04_leicht_verschmutzt", "05_vernachlaessigt", "06_heruntergekommen",
			"07_beschaedigt", "08_schwer_beschaedigt", "09_ausgebrannt", "10_zerstoert", "11_ruine", "12_restauriert"]:
		_visual("buildings/house_1", VisualState.preset(k), x, y, k.substr(3).replace("_", " "))
		x += 1
	y += 1
	_row_title(y, "Kombinationen, Reparaturspuren, Wetter, weitere Gebäude")
	x = 0
	_visual("buildings/house_1", VisualState.create("intact", 2, 1, 2), x, y, "schmutzig+beschädigt+Brand"); x += 1
	_visual("buildings/house_1", VisualState.create("intact", 3, 0, 1), x, y, "verwahrlost+Rußspuren"); x += 1
	_visual("buildings/house_1", VisualState.create("intact", 0, 0, 0, 0, 2), x, y, "frisch repariert"); x += 1
	_visual("buildings/house_1", VisualState.create("partial", 1, 2), x, y, "schwer beschädigt+Schnee", {"snow": true}); x += 1
	_visual("buildings/house_1", VisualState.create("ruin"), x, y, "Ruine+Schnee", {"snow": true}); x += 1
	_visual("buildings/town_hall", VisualState.preset("09_ausgebrannt"), x, y, "Rathaus ausgebrannt"); x += 1
	_visual("buildings/town_hall", VisualState.preset("07_beschaedigt"), x, y, "Rathaus beschädigt"); x += 1
	_visual("buildings/shop_smith", VisualState.preset("06_heruntergekommen"), x, y, "Schmiede verwahrlost"); x += 1
	_visual("buildings/shop_smith", VisualState.preset("08_schwer_beschaedigt"), x, y, "Schmiede schwer beschädigt"); x += 1
	_visual("buildings/emergency_post", VisualState.preset("11_ruine"), x, y, "Feuerwache Ruine"); x += 1
	_visual("props/tent", VisualState.create("collapsed"), x, y, "Zelt eingestürzt"); x += 1
	_visual("props/tent", VisualState.create("intact", 0, 0, 0, 0, 1), x, y, "Zelt geflickt")
	y += 1
	_row_title(y, "Stadtmöbel, Beleuchtung, Fahrzeuge, Vegetation, Brunnen")
	x = 0
	_visual("props/bench", VisualState.create("intact", 3), x, y, "Bank verwittert"); x += 1
	_visual("props/bench", VisualState.create("broken"), x, y, "Bank zerstört"); x += 1
	_visual("props/hydrant", VisualState.create("intact", 1, 1), x, y, "Hydrant beschädigt"); x += 1
	_visual("props/lamp_off", VisualState.create("broken"), x, y, "Laterne umgestürzt"); x += 1
	_visual("props/crates", VisualState.create("burnt"), x, y, "Kisten verbrannt"); x += 1
	_visual("vehicles/car_red", VisualState.create("intact", 3), x, y, "Auto verlassen"); x += 1
	_visual("vehicles/car_red", VisualState.create("wreck"), x, y, "Autowrack"); x += 1
	_visual("props/tree_1", VisualState.create("dead"), x, y, "Baum abgestorben"); x += 1
	_visual("props/tree_1", VisualState.create("burnt"), x, y, "Baum verbrannt"); x += 1
	_visual("props/pine_1", VisualState.create(), x, y, "Tanne Schnee", {"snow": true}); x += 1
	_visual("props/fountain", VisualState.create("drained", 2), x, y, "Brunnen trocken"); x += 1
	_visual("props/fountain", VisualState.create("frozen"), x, y, "Brunnen gefroren")
	y += 1
	_row_title(y, "Böden – Overlays je Bodenfamilie (alle 9 Straßenkacheln teilen sie)")
	x = 0
	for st in ["verschmutzt", "rissig", "schlagloecher", "pfuetzen", "schnee", "frost", "laub", "muell"]:
		_surface("tiles/road_5", st, x, y, "Straße " + st)
		x += 1
	_surface("tiles/path_5", "schlamm", x, y, "Weg Schlamm"); x += 1
	_surface("tiles/grass", "trocken", x, y, "Gras trocken"); x += 1
	_surface("tiles/sidewalk", "laub", x, y, "Gehweg Laub"); x += 1
	_surface("tiles/water", "gefroren", x, y, "Wasser gefroren")
	y += 1
	_row_title(y, "Effekte (eigene VFX im Penzilla-Stil, Menge je Profil)")
	x = 0
	var burning := _visual("buildings/house_1", VisualState.create("intact", 1, 0, 2), x, y, "brennt (Flammen + Rauch)")
	for off in [Vector2(-20, -60), Vector2(16, -78), Vector2(2, -40)]:
		_flame(burning, off)
	_smoke(burning, Vector2(0, -95))
	x += 1
	var road := _surface("tiles/road_5", "pfuetzen", x, y, "Regen + Pfützen")
	_weather(road, "raindrop", Vector2(0, 260), 40)
	x += 1
	var snow := _visual("props/tree_1", VisualState.create("dead"), x, y, "Schneefall", {"snow": true})
	_weather(snow, "snowflake", Vector2(0, 40), 30)
	x += 1
	var lamp := _visual("props/lamp_off", VisualState.create("intact", 1, 1), x, y, "Funken (defekt)")
	_sparks(lamp, Vector2(0, -52))
	x += 1
	var star := _anim(Vector2(x * CELL.x + CELL.x * 0.5, y * CELL.y + CELL.y * 0.55), "reward_star", 6.0)
	star.scale = Vector2.ONE * 0.6
	_label(Vector2(x * CELL.x + 6, y * CELL.y + 28), "Belohnung", 13)
	x += 1
	var rep := _anim(Vector2(x * CELL.x + CELL.x * 0.5, y * CELL.y + CELL.y * 0.55), "repair", 8.0)
	rep.scale = Vector2.ONE * 0.6
	_label(Vector2(x * CELL.x + 6, y * CELL.y + 28), "Reparatur", 13)
	var cam := Camera2D.new()
	add_child(cam)
	cam.position = Vector2(COLS * CELL.x, 5.0 * CELL.y) * 0.5
	var vp := get_viewport_rect().size
	var z := minf(vp.x / ((COLS + 0.2) * CELL.x), vp.y / (5.2 * CELL.y))
	cam.zoom = Vector2(z, z)
	cam.make_current()
	var captions := Node2D.new()
	captions.z_index = 100
	captions.draw.connect(func() -> void: _draw_labels(captions))
	add_child(captions)
	captions.queue_redraw()


func perf_stats() -> Dictionary:
	# context separates gallery measurements from real game measurements
	return {"view": "Living-Assets-Galerie (%s)" % profile, "context": "testgalerie", "visible_objects": sprites, "total_objects": sprites}


func _url_profile() -> String:
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("location.search", true))
		for p in ["ultra", "hoch", "leistung"]:
			if q.contains("profile=" + p):
				return p
	return "hoch"


## Composes an object from its VisualState (same code path the game will use).
func _visual(key: String, state: VisualState, col: int, row: float, caption: String, weather := {}) -> Node2D:
	var holder := Node2D.new()
	holder.position = Vector2(col * CELL.x + CELL.x * 0.5, row * CELL.y + CELL.y - 18)
	add_child(holder)
	var entry: Dictionary = LivingComposer.manifest().get("assets", {}).get(key, {})
	var orig_path := "res://assets/penzilla/%s.png" % key
	var original: Texture2D = load(orig_path) if ResourceLoader.exists(orig_path) else null
	var node := LivingComposer.build(key, state, original, profile, weather)
	var canvas: Array = entry.get("canvas_src", [512, 512])
	var k := _fit(canvas)
	node.scale = Vector2(k, k)
	node.position = Vector2(-canvas[0] * k * 0.5, -canvas[1] * k)
	holder.add_child(node)
	sprites += node.get_child_count()
	holder.set_meta("visual", node)
	_label(Vector2(col * CELL.x + 6, row * CELL.y + 28), caption, 13)
	return holder


func _surface(key: String, state: String, col: int, row: float, caption: String) -> Node2D:
	var holder := Node2D.new()
	holder.position = Vector2(col * CELL.x + CELL.x * 0.5, row * CELL.y + CELL.y - 18)
	add_child(holder)
	var path := "res://assets/penzilla/%s.png" % key
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		var k := _fit([tex.get_width() * 2, tex.get_height() * 2])
		var root := Node2D.new()
		root.scale = Vector2(k, k)
		root.position = Vector2(-tex.get_width() * k, -tex.get_height() * 2 * k)
		var s := Sprite2D.new()
		s.centered = false
		s.texture = tex
		s.scale = Vector2(2, 2)
		root.add_child(s)
		var ov := LivingComposer.surface_overlay(key, state)
		if not ov.is_empty() and ResourceLoader.exists(LivingComposer.STATES_DIR + ov["file"]):
			var o := Sprite2D.new()
			o.centered = false
			o.texture = load(LivingComposer.STATES_DIR + ov["file"])
			o.scale = Vector2(2, 2)
			o.position = Vector2(ov["offset_src"][0], ov["offset_src"][1])
			root.add_child(o)
		holder.add_child(root)
		sprites += root.get_child_count()
	_label(Vector2(col * CELL.x + 6, row * CELL.y + 28), caption, 13)
	return holder


func _fit(canvas: Array) -> float:
	# Gallery only: every object fits its cell (source px -> gallery px).
	return minf((CELL.x - 12) / float(canvas[0]), (CELL.y - 40) / float(canvas[1]))


func _frames(name: String) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.add_animation("a")
	var anim: Dictionary = _vfx_meta["animations"][name]
	for r in anim["frames"]:
		var at := AtlasTexture.new()
		at.atlas = _vfx
		at.region = Rect2(r[0], r[1], r[2], r[3])
		sf.add_frame("a", at)
	sf.set_animation_speed("a", float(anim["fps"]))
	return sf


func _anim(pos: Vector2, name: String, fps: float) -> AnimatedSprite2D:
	var a := AnimatedSprite2D.new()
	a.sprite_frames = _frames(name)
	a.sprite_frames.set_animation_speed("a", fps)
	a.position = pos
	a.play("a")
	add_child(a)
	sprites += 1
	return a


func _flame(holder: Node2D, off: Vector2) -> void:
	var a := AnimatedSprite2D.new()
	a.sprite_frames = _frames("flame")
	a.position = off
	a.scale = Vector2.ONE * 0.45
	a.offset = Vector2(0, -30)
	if LivingComposer.PROFILES[profile]["animated_fire"]:
		a.play("a")
	a.frame = randi() % 8
	holder.add_child(a)
	sprites += 1


func _atlas_frame(name: String, i: int) -> AtlasTexture:
	var r: Array = _vfx_meta["animations"][name]["frames"][i]
	var at := AtlasTexture.new()
	at.atlas = _vfx
	at.region = Rect2(r[0], r[1], r[2], r[3])
	return at


func _smoke(holder: Node2D, off: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.texture = _atlas_frame("smoke_dark", 2)
	p.position = off
	p.amount = maxi(2, int(10 * LivingComposer.PROFILES[profile]["particles"]))
	p.lifetime = 2.6
	p.direction = Vector2(0.15, -1)
	p.spread = 12
	p.gravity = Vector2(0, -12)
	p.initial_velocity_min = 18
	p.initial_velocity_max = 28
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.95))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	holder.add_child(p)
	sprites += 1


func _weather(holder: Node2D, name: String, extents: Vector2, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.texture = _atlas_frame(name, 0)
	p.position = Vector2(0, -150)
	p.amount = maxi(4, int(amount * LivingComposer.PROFILES[profile]["particles"]))
	p.lifetime = 1.4 if name == "raindrop" else 4.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(60, 4)
	p.direction = Vector2(0.15, 1)
	p.spread = 4 if name == "raindrop" else 25
	p.gravity = Vector2(0, 160 if name == "raindrop" else 8)
	p.initial_velocity_min = 90 if name == "raindrop" else 12
	p.initial_velocity_max = 120 if name == "raindrop" else 22
	p.scale_amount_min = 0.22
	p.scale_amount_max = 0.3
	holder.add_child(p)
	sprites += 1


func _sparks(holder: Node2D, off: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.texture = _atlas_frame("spark", 1)
	p.position = off
	p.amount = 8
	p.lifetime = 0.7
	p.explosiveness = 0.6
	p.direction = Vector2(0, -1)
	p.spread = 70
	p.gravity = Vector2(0, 220)
	p.initial_velocity_min = 50
	p.initial_velocity_max = 90
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.25
	holder.add_child(p)
	sprites += 1


func _row_title(row: float, text: String) -> void:
	_label(Vector2(6, row * CELL.y + 8), text, 16)


func _label(pos: Vector2, text: String, size: int) -> void:
	_labels.append([pos, text, size])
	queue_redraw()


func _draw() -> void:
	# Captions are drawn by a top-most child (children draw above the parent).
	pass


func _draw_labels(ci: Node2D) -> void:
	for l in _labels:
		ci.draw_string_outline(_font, l[0], l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, l[2], 4, Color(0.1, 0.1, 0.12, 0.8))
		ci.draw_string(_font, l[0], l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, l[2], Color.WHITE)
