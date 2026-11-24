class_name LivingGallery
extends Node2D
## Living Assets – step E: technical check in Godot (QA only, not in the game).
## Opened with "?gallery=living" (web) – see Main._qa_gallery().
##
## Shows the three integration tiers side by side with real rendering:
##   tier 1  shader shaders/living_wear.gdshader on the ORIGINAL sprite
##   tier 2  original + overlay (only changed pixels)
##   tier 3  separate variant sprite
## plus the own VFX (assets/vfx) as AnimatedSprite2D / CPUParticles2D.
## Samples: assets/penzilla/states (generated, private).

const STATES_DIR := "res://assets/penzilla/states"
const WORLD_PER_SRC := 0.25
const FILE_SCALE := 0.5
const CELL := Vector2(150, 190)

var manifest: Dictionary = {}
var sprites := 0
var _wear_materials := {}
var _grime: Texture2D
var _vfx: Texture2D
var _vfx_meta: Dictionary = {}
var _font: Font
var _labels: Array = []


func _ready() -> void:
	add_to_group("perf_view")
	_font = ThemeDB.fallback_font
	var bg := ColorRect.new()
	bg.color = Color("7ea85c")
	bg.size = Vector2(4000, 3000)
	bg.position = Vector2(-200, -200)
	bg.show_behind_parent = true # captions (_draw of this node) stay on top
	add_child(bg)
	if not FileAccess.file_exists(STATES_DIR + "/states.json"):
		_label(Vector2(20, 40), "Keine Beispieldateien – tools/assets/make_living_samples.py ausführen.", 24)
		return
	manifest = JSON.parse_string(FileAccess.get_file_as_string(STATES_DIR + "/states.json"))
	_grime = load("res://assets/vfx/grime_field.png")
	_vfx = load("res://assets/vfx/vfx_atlas.png")
	_vfx_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vfx/vfx_atlas.json"))
	var y := 0.0
	_row_title(y, "Stufe 1 – Shader auf dem Original (keine Zusatztextur)")
	var x := 0
	for lv in [[0.0, 0.0, "gepflegt"], [0.25, 0.0, "benutzt"], [0.45, 0.1, "verschmutzt"], [0.65, 0.3, "vernachlässigt"]]:
		_place("house_blue", "original", x, y, lv[2], _wear(lv[0], lv[1]))
		x += 1
	_place("bench", "original", x, y, "Bank verwittert", _wear(0.55, 0.3)); x += 1
	_place("car", "original", x, y, "Auto verschmutzt", _wear(0.55, 0.0)); x += 1
	_place("lamp", "original", x, y, "Laterne verwittert", _wear(0.4, 0.35))
	y += 1
	_row_title(y, "Stufe 2 – Original + Overlay (nur veränderte Pixel)")
	x = 0
	var n := _place("house_blue", "original", x, y, "beschädigt", _wear(0.35, 0.1))
	_overlay(n, "house_blue", "overlay_damage")
	x += 1
	for k in ["rissig", "schlagloecher", "pfuetzen", "schlamm", "schnee"]:
		var r := _place("road", "original", x, y, "Straße " + k, null)
		_overlay(r, "road", "overlay_" + k)
		x += 1
	y += 1
	_row_title(y, "Stufe 3 – eigene Variante (strukturelle Zustände)")
	x = 0
	for k in ["08_schwer_beschaedigt", "09_ausgebrannt", "10_zerstoert", "11_ruine"]:
		_place("house_blue", k, x, y, k.substr(3).replace("_", " "), null)
		x += 1
	_place("tree", "abgestorben", x, y, "Baum abgestorben", null); x += 1
	_place("bare_tree", "schnee", x, y, "BareTree Schnee", null); x += 1
	_place("lamp", "zerstoert", x, y, "Laterne umgestürzt", null); x += 1
	_place("car", "wrack", x, y, "Autowrack", null)
	y += 1
	_row_title(y, "Effekte (eigene VFX im Penzilla-Stil)")
	x = 0
	var burning := _place("house_blue", "09_ausgebrannt", x, y, "brennt (Flammen + Rauch)", null)
	for off in [Vector2(-20, -60), Vector2(16, -78), Vector2(2, -40)]:
		_flame(burning, off)
	_smoke(burning, Vector2(0, -95))
	x += 1
	var road := _place("road", "original", x, y, "Regen + Pfützen", null)
	_overlay(road, "road", "overlay_pfuetzen")
	_weather(road, "raindrop", Vector2(0, 260), 40)
	x += 1
	var snow := _place("bare_tree", "schnee", x, y, "Schneefall", null)
	_weather(snow, "snowflake", Vector2(0, 40), 30)
	x += 1
	var lamp := _place("lamp", "beschaedigt", x, y, "Funken (defekt)", null)
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
	cam.position = Vector2(8 * CELL.x, 4.2 * CELL.y) * 0.5
	var vp := get_viewport_rect().size
	var z := minf(vp.x / (8.2 * CELL.x), vp.y / (4.4 * CELL.y))
	cam.zoom = Vector2(z, z)
	cam.make_current()
	var captions := Node2D.new()
	captions.z_index = 100
	captions.draw.connect(func() -> void: _draw_labels(captions))
	add_child(captions)
	captions.queue_redraw()


func perf_stats() -> Dictionary:
	return {"view": "Living-Assets-Galerie", "visible_objects": sprites, "total_objects": sprites}


func _wear(dirt: float, fade: float) -> ShaderMaterial:
	# Shared per quantised level → sprites at the same level keep batching.
	var key := "%.2f_%.2f" % [dirt, fade]
	if not _wear_materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/living_wear.gdshader")
		m.set_shader_parameter("grime_tex", _grime)
		m.set_shader_parameter("dirt", dirt)
		m.set_shader_parameter("fade", fade)
		m.set_shader_parameter("grime_px", 90.0)
		_wear_materials[key] = m
	return _wear_materials[key]


func _place(asset: String, file: String, col: int, row: float, caption: String, mat: Material) -> Node2D:
	var holder := Node2D.new()
	holder.position = Vector2(col * CELL.x + CELL.x * 0.5, row * CELL.y + CELL.y - 18)
	add_child(holder)
	var path := "%s/%s/%s.png" % [STATES_DIR, asset, file]
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		var k := WORLD_PER_SRC / FILE_SCALE * _fit(asset)
		s.scale = Vector2(k, k)
		s.position = Vector2(-tex.get_width() * k * 0.5, -tex.get_height() * k)
		if mat:
			s.material = mat
		holder.add_child(s)
		holder.set_meta("sprite", s)
		sprites += 1
	_label(Vector2(col * CELL.x + 6, row * CELL.y + 28), caption, 13)
	return holder


func _fit(asset: String) -> float:
	# Gallery only: show everything at a readable size.
	return {"house_blue": 0.9, "road": 0.42, "tree": 1.6, "bare_tree": 1.6, "lamp": 1.6, "bench": 1.6, "car": 0.9}.get(asset, 1.0)


func _overlay(holder: Node2D, asset: String, file: String) -> void:
	var info: Dictionary = manifest["assets"][asset]["files"].get(file, {})
	var path := "%s/%s/%s.png" % [STATES_DIR, asset, file]
	if info.is_empty() or not ResourceLoader.exists(path) or not holder.has_meta("sprite"):
		return
	var base: Sprite2D = holder.get_meta("sprite")
	var s := Sprite2D.new()
	s.texture = load(path)
	s.centered = false
	s.scale = base.scale
	var off: Array = info["offset_src"]
	s.position = base.position + Vector2(off[0], off[1]) * FILE_SCALE * base.scale.x
	holder.add_child(s)
	sprites += 1


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
	p.amount = 10
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
	p.amount = amount
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
