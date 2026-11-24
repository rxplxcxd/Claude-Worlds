class_name AnimGallery
extends Node2D
## QA gallery of the character animation library ("?gallery=anim", web):
## every animation for four role appearances, all five Penzilla direction
## rows (west mirrored), at game size and 2× – to check readability,
## alignment of the feet and tool layers. Presentation only.

const ANIMS := ["idle", "walk", "run", "interact", "sit", "get_up", "dig", "swing"]
const ROLES := ["farmer", "builder", "medic", "resident"]
const CELL := Vector2(70, 96)

var sprites := 0


func _ready() -> void:
	add_to_group("perf_view")
	var bg := ColorRect.new()
	bg.color = Color("8fb86a")
	bg.size = Vector2(4000, 3000)
	bg.position = Vector2(-200, -200)
	bg.show_behind_parent = true
	add_child(bg)
	if not CharacterCatalog.is_available():
		_label(Vector2(20, 40), "Penzilla-Figuren nicht importiert (privat) – tools/assets/import_character.py", 18)
		return
	var font_y := 22.0
	for a in ANIMS.size():
		_label(Vector2(150 + a * CELL.x * 1.0, font_y), "%s\n%s" % [ANIMS[a], CharacterCatalog.anim_info(ANIMS[a]).get("label", "")], 11)
	for r in ROLES.size():
		var app := CharacterCatalog.role_appearance(ROLES[r], 1234 + r)
		var y := 90.0 + r * CELL.y * 1.15
		_label(Vector2(10, y - 30), CharacterCatalog.role_label(ROLES[r]) + "\n(" + str(app.get("tool", {}).get("option", "none")) + ")", 12)
		for a in ANIMS.size():
			var rig := CharacterRig.new()
			rig.appearance = app
			rig.position = Vector2(150 + a * CELL.x + 30, y + 30)
			add_child(rig)
			rig.play(ANIMS[a], true)
			rig.animation_finished.connect(func(_n): rig.play(ANIMS[a], true))
			rig.set_facing([6, 7, 0, 1, 2, 3, 4, 5][(a + r) % 8])
			sprites += 1
	# all directions of one walk + one sit, 2×
	for f in 8:
		for k in 2:
			var rig := CharacterRig.new()
			rig.appearance = CharacterCatalog.role_appearance("builder", 77)
			rig.scale = Vector2(2, 2)
			rig.position = Vector2(150 + f * 90, 640 + k * 190)
			add_child(rig)
			rig.play(["walk", "sit"][k], true)
			rig.animation_finished.connect(func(_n): rig.play(["walk", "sit"][k], true))
			rig.set_facing(f)
			sprites += 1
	_label(Vector2(10, 600), "8 Richtungen (West gespiegelt), 2×: Gehen / Sitzen", 13)


func _label(p: Vector2, text: String, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.position = p
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("2b1a2e"))
	add_child(l)
