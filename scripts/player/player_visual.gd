class_name PlayerVisual
extends Node2D
## Player appearance.
##
## If "character.player" (Penzilla Ultimate Protagonist, SpriteFrames) is
## registered, an AnimatedSprite2D plays "idle_<dir>" / "walk_<dir>".
## Otherwise a PLACEHOLDER figure is drawn: body, head, facing and a walk bob,
## so movement, scale and facing can be tested before the real sprites exist.

const BODY := Color("2f7f8f")
const PANTS := Color("3b3f4a")
const SKIN := Color("e7c09a")
const HAIR := Color("4a3426")

var _speed01 := 0.0
var _facing := 6
var _phase := 0.0
var _sprite: AnimatedSprite2D


func _ready() -> void:
	var frames := AssetRegistry.get_resource("character.player") as SpriteFrames
	if frames:
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = frames
		var e := AssetRegistry.get_entry("character.player")
		var anchor: Array = e.get("anchor", [0, 0])
		_sprite.offset = Vector2(float(anchor[0]), float(anchor[1]))
		_sprite.scale = Vector2.ONE * float(e.get("scale", 1.0))
		add_child(_sprite)


func is_placeholder() -> bool:
	return _sprite == null


func set_motion(speed01: float, facing: int) -> void:
	_speed01 = speed01
	_facing = facing
	if _sprite:
		var anim := ("walk_" if speed01 > 0.05 else "idle_") + Iso.facing_name(facing)
		if _sprite.sprite_frames.has_animation(anim) and _sprite.animation != anim:
			_sprite.play(anim)
		return
	queue_redraw()


func _process(delta: float) -> void:
	if _sprite:
		return
	if _speed01 > 0.05:
		_phase += delta * 11.0 * _speed01
		queue_redraw()
	elif _phase != 0.0:
		_phase = 0.0
		queue_redraw()


func _draw() -> void:
	if _sprite:
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
