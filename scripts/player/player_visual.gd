class_name PlayerVisual
extends Node2D
## Player appearance.
##
## Preferred: the player's own modular character (CharacterRig with the
## appearance from the character editor, Penzilla Ultimate Protagonist layers).
## Fallback 1: the premade Penzilla Character1 sheets ("character.player").
## Fallback 2: a procedurally drawn PLACEHOLDER figure.

const BODY := Color("2f7f8f")
const PANTS := Color("3b3f4a")
const SKIN := Color("e7c09a")
const HAIR := Color("4a3426")

var _speed01 := 0.0
var _facing := 6
var _phase := 0.0
var _sprite: AnimatedSprite2D


## facing index (Iso.facing_index) -> [sheet row, mirrored] – one mapping for everybody
const FACING_ROWS := CharacterRig.FACING_ROWS

var _interacting := false


var rig: CharacterRig


func _ready() -> void:
	if CharacterCatalog.is_available():
		rig = CharacterRig.new()
		rig.name = "Rig"
		rig.appearance = CharacterCatalog.normalize(LocalProfile.character) if LocalProfile.has_character() else CharacterCatalog.default_appearance()
		add_child(rig)
		return
	var frames := _build_sheet_frames()
	if frames:
		_sprite = AnimatedSprite2D.new()
		_sprite.name = "Sprite"
		_sprite.sprite_frames = frames
		_sprite.centered = false
		var entry := AssetRegistry.get_entry("character.player")
		var world_per_src: float = Iso.WORLD_PER_SRC_PX * float(entry.get("world_scale", 1.0))
		var frame_file: float = frames.get_frame_texture("idle_s", 0).get_width()
		_sprite.scale = Vector2.ONE * world_per_src * float(entry.get("frame_src_px", 460)) / frame_file
		var feet: Array = entry.get("feet_src_px", [230, 426])
		_sprite.position = -Vector2(float(feet[0]), float(feet[1])) * world_per_src
		_sprite.animation_finished.connect(func() -> void: _interacting = false)
		add_child(_sprite)
		_sprite.play("idle_s")


## Builds SpriteFrames from the Penzilla sheets, or returns null.
func _build_sheet_frames() -> SpriteFrames:
	var entry := AssetRegistry.get_entry("character.player")
	if entry.get("kind", "") != "sheet8" or not AssetRegistry.is_allowed("character.player"):
		return null
	var rows: Array = entry.get("rows", ["s", "sw", "w", "nw", "n"])
	var fps: Dictionary = entry.get("fps", {})
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim in (entry.get("sheets", {}) as Dictionary).keys():
		var path: String = entry["sheets"][anim]
		if not ResourceLoader.exists(path):
			return null if anim in ["idle", "walk"] else frames
		var tex := load(path) as Texture2D
		var cell := float(tex.get_height()) / rows.size()
		var cols := int(round(tex.get_width() / cell))
		for r in rows.size():
			var anim_name: String = "%s_%s" % [anim, rows[r]]
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, float(fps.get(anim, 10)))
			frames.set_animation_loop(anim_name, anim != "interact")
			for c in cols:
				var atlas := AtlasTexture.new()
				atlas.atlas = tex
				atlas.region = Rect2(c * cell, r * cell, cell, cell)
				frames.add_frame(anim_name, atlas)
	return frames


## Plays the one-shot interact animation (if available).
func play_interact() -> void:
	if rig:
		rig.play("interact", true)
		return
	if _sprite and _sprite.sprite_frames.has_animation("interact_s"):
		_interacting = true
		_play_dir("interact", _facing)


func _play_dir(anim: String, facing: int) -> void:
	var rule: Array = FACING_ROWS[clampi(facing, 0, 7)]
	var rows: Array = AssetRegistry.get_entry("character.player").get("rows", ["s", "sw", "w", "nw", "n"])
	var anim_name: String = "%s_%s" % [anim, rows[rule[0]]]
	_sprite.flip_h = rule[1]
	if _sprite.sprite_frames.has_animation(anim_name) and _sprite.animation != anim_name:
		_sprite.play(anim_name)


func is_placeholder() -> bool:
	return _sprite == null and rig == null


## Re-reads the saved character (after the editor was closed).
func refresh_appearance() -> void:
	if rig:
		rig.set_appearance(LocalProfile.character)


func set_motion(speed01: float, facing: int) -> void:
	_speed01 = speed01
	_facing = facing
	if rig:
		rig.set_motion(speed01, facing)
		return
	if _sprite:
		if _interacting and speed01 < 0.05:
			return
		_interacting = false
		_play_dir("walk" if speed01 > 0.05 else "idle", facing)
		return
	queue_redraw()


func _process(delta: float) -> void:
	if _sprite or rig:
		return
	if _speed01 > 0.05:
		_phase += delta * 11.0 * _speed01
		queue_redraw()
	elif _phase != 0.0:
		_phase = 0.0
		queue_redraw()


func _draw() -> void:
	if _sprite or rig:
		return
	var bob := absf(sin(_phase)) * 3.0
	var dir := Vector2.from_angle(-_facing * PI / 4.0) # screen-space facing
	var side := dir.x
	# Shadow
	IsoPainter.ellipse(self, Vector2.ZERO, Vector2(14, 6), Color(0, 0, 0, 0.25))
	# Legs (alternate while walking)
	var swing := sin(_phase) * 4.0 * _speed01
	draw_line(Vector2(-4, -16), Vector2(-4 + swing, -1), PANTS, 5.0, true)
	draw_line(Vector2(4, -16), Vector2(4 - swing, -1), PANTS, 5.0, true)
	# Body
	var body_top := -42.0 - bob
	draw_colored_polygon(PackedVector2Array([
		Vector2(-9, body_top + 4), Vector2(9, body_top + 4), Vector2(8, -15 - bob * 0.5), Vector2(-8, -15 - bob * 0.5)]), BODY)
	# Arms
	draw_line(Vector2(-9, body_top + 6), Vector2(-11 - swing * 0.5, -20 - bob), BODY.darkened(0.2), 4.0, true)
	draw_line(Vector2(9, body_top + 6), Vector2(11 + swing * 0.5, -20 - bob), BODY.darkened(0.2), 4.0, true)
	# Head
	var head := Vector2(0, body_top - 7)
	IsoPainter.ellipse(self, head, Vector2(8, 8.5), SKIN, 16)
	# Hair: shows more when facing away (north)
	var away := dir.y < -0.3
	IsoPainter.ellipse(self, head + Vector2(0, -3 if not away else 0), Vector2(8.5, 6 if not away else 8.5), HAIR, 16)
	if not away:
		# Eyes indicate facing direction.
		var eye := head + Vector2(side * 3.0, 1)
		draw_circle(eye + Vector2(-2.5, 0), 1.2, Color("222222"))
		draw_circle(eye + Vector2(2.5, 0), 1.2, Color("222222"))
	# Small marker so the local player is easy to find.
	draw_colored_polygon(PackedVector2Array([head + Vector2(-5, -18), head + Vector2(5, -18), head + Vector2(0, -12)]), Color("f2c230"))
