class_name ChatBubble
extends Node2D
## Small speech bubble (three dots) above NPCs who are chatting – drawn, no
## texture. Penzilla-like: white fill, #330022 outline.

const OUTLINE := Color("330022")
var _t := 0.0


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2(-13, -10), Vector2(26, 16))
	draw_rect(r.grow(1.5), OUTLINE, true)
	draw_rect(r, Color.WHITE, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-6, 6), Vector2(-1, 6), Vector2(-9, 12)]), OUTLINE)
	draw_colored_polygon(PackedVector2Array([Vector2(-5, 5), Vector2(-2, 5), Vector2(-7, 9)]), Color.WHITE)
	for i in 3:
		var on := int(_t * 3.0) % 4 > i
		draw_circle(Vector2(-6 + i * 6, -2), 2.0, OUTLINE if on else Color(OUTLINE, 0.3))
