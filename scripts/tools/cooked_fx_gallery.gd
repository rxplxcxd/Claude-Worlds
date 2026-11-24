class_name CookedFxGallery
extends Node2D
## Evaluation gallery for the Cooked FX "Cozy Chunky" effects (QA only, not
## in the game). Opened with "?gallery=cookedfx" (web). Shows each effect
## animated next to representative Penzilla assets: column 1 original,
## column 2 WORLDS adaptation (contour #330022, no glow, top-down squashed 2:1),
## column 3 our own VFX for comparison. Files: assets/thirdparty/cooked_fx
## (private import, tools/assets/import_cooked_fx.py – never committed).

const DIR := "res://assets/thirdparty/cooked_fx/"
const CELL := Vector2(420, 230)
const FX_SCALE := 0.5   # 1x cell -> world px (game scale, like the Penzilla files)

var sprites := 0
var _meta: Dictionary = {}
var _labels: Array = []
var _font: Font


func _ready() -> void:
	add_to_group("perf_view")
	_font = ThemeDB.fallback_font
	var bg := ColorRect.new()
	bg.color = Color("7ea85c")
	bg.size = Vector2(4000, 3000)
	bg.position = Vector2(-200, -200)
	bg.show_behind_parent = true
	add_child(bg)
	if not FileAccess.file_exists(DIR + "fx.json"):
		_label(Vector2(20, 40), "Cooked FX nicht importiert – tools/assets/import_cooked_fx.py ausführen (privat).", 22)
		return
	_meta = JSON.parse_string(FileAccess.get_file_as_string(DIR + "fx.json"))
	for c in 3:
		_label(Vector2(c * CELL.x + 10, 18), ["Original Cozy Chunky", "angepasst für WORLDS", "eigene WORLDS-VFX"][c], 18)
	var rows := [
		["Feuer + Rauch am Gebäude", "buildings/house_1", [["nature_fire_side", Vector2(-18, -70)], ["nature_fire_side", Vector2(14, -85)], ["nature_smoke_side", Vector2(-4, -150)]], [["flame", Vector2(-18, -70)], ["smoke_dark", Vector2(-4, -150)]]],
		["Wasser: Fontäne + Kräuselring (Top-down)", "props/fountain", [["nature_water_side", Vector2(0, -40)], ["nature_water_top", Vector2(-70, -5)]], [["splash", Vector2(0, -40)]]],
		["Explosion + Trümmer am Boden", "buildings/trade_post", [["combat_explosion_side", Vector2(40, -60)], ["nature_rocks_top", Vector2(-50, -10)], ["movement_dust_top", Vector2(0, 0)]], [["debris", Vector2(40, -40)]]],
		["Belohnungen", "props/tree_1", [["pickup_ui_coins_top", Vector2(-90, -10)], ["pickup_ui_star", Vector2(80, -60)], ["pickup_ui_confetti_side", Vector2(-80, -90)], ["pickup_ui_heart", Vector2(90, -120)]], [["reward_star", Vector2(80, -60)], ["repair", Vector2(-80, -60)]]],
		["Alltag: Schlafen, Staub, Blätter", "buildings/house_2", [["status_sleep", Vector2(30, -120)], ["movement_poof_side", Vector2(-80, -10)], ["nature_leaves_side", Vector2(80, -30)]], [["leaf", Vector2(80, -30)], ["dust", Vector2(-80, -10)]]],
	]
	var y := 1
	for r in rows:
		_label(Vector2(10, y * CELL.y - 160), r[0], 15)
		for c in 3:
			var anchor := Vector2(c * CELL.x + CELL.x * 0.5, y * CELL.y + 30)
			_penzilla(r[1], anchor)
			var fx: Array = r[2] if c < 2 else r[3]
			for e in fx:
				if c < 2:
					_cooked(e[0], anchor + e[1], c == 1)
				else:
					_own(e[0], anchor + e[1])
		y += 1
	var cam := Camera2D.new()
	add_child(cam)
	cam.position = Vector2(3 * CELL.x, (y - 0.4) * CELL.y) * 0.5
	var vp := get_viewport_rect().size
	var z := minf(vp.x / (3.1 * CELL.x), vp.y / ((y - 0.2) * CELL.y))
	cam.zoom = Vector2(z, z)
	cam.make_current()
	var captions := Node2D.new()
	captions.z_index = 100
	captions.draw.connect(func() -> void:
		for l in _labels:
			captions.draw_string_outline(_font, l[0], l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, l[2], 4, Color(0.1, 0.1, 0.12, 0.8))
			captions.draw_string(_font, l[0], l[1], HORIZONTAL_ALIGNMENT_LEFT, -1, l[2], Color.WHITE))
	add_child(captions)


func perf_stats() -> Dictionary:
	return {"view": "Cooked-FX-Galerie", "context": "testgalerie", "visible_objects": sprites, "total_objects": sprites}


func _penzilla(key: String, anchor: Vector2) -> void:
	var path := "res://assets/penzilla/%s.png" % key
	if not ResourceLoader.exists(path):
		return
	var s := Sprite2D.new()
	s.texture = load(path)
	s.scale = Vector2(0.5, 0.5)   # file scale 0.5 -> world 0.25 of source
	s.offset = Vector2(0, -s.texture.get_height() * 0.5)
	s.position = anchor
	add_child(s)
	sprites += 1


func _cooked(name: String, pos: Vector2, adapted: bool) -> void:
	var m: Dictionary = _meta["effects"].get(name, {})
	var path := DIR + ("adapted/" if adapted else "raw/") + name + ".png"
	if m.is_empty() or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	var n := int(m["frames"])
	var fw := tex.get_width() / n
	var fh := tex.get_height()
	var sf := SpriteFrames.new()
	sf.add_animation("a")
	sf.set_animation_loop("a", true)   # gallery loops one-shots too
	sf.set_animation_speed("a", float(m["fps"]))
	for i in n:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, fh)
		sf.add_frame("a", at)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = sf
	a.scale = Vector2.ONE * FX_SCALE
	a.position = pos
	a.play("a")
	a.frame = randi() % n
	add_child(a)
	sprites += 1


func _own(name: String, pos: Vector2) -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vfx/vfx_atlas.json"))
	var atlas: Texture2D = load("res://assets/vfx/vfx_atlas.png")
	var anim: Dictionary = meta["animations"].get(name, {})
	if anim.is_empty():
		return
	var sf := SpriteFrames.new()
	sf.add_animation("a")
	sf.set_animation_speed("a", float(anim["fps"]))
	for r in anim["frames"]:
		var at := AtlasTexture.new()
		at.atlas = atlas
		at.region = Rect2(r[0], r[1], r[2], r[3])
		sf.add_frame("a", at)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = sf
	a.scale = Vector2.ONE * 0.6
	a.position = pos
	a.play("a")
	add_child(a)
	sprites += 1


func _label(pos: Vector2, text: String, size: int) -> void:
	_labels.append([pos, text, size])
