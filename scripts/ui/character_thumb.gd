class_name CharacterThumb
extends Control
## Small static picture of a whole character appearance (one idle frame,
## facing the viewer), optionally zoomed to a region of the body. Used for the
## option cards in the character editor, so every card shows the player's OWN
## character wearing that option.

## Normalised region of the frame to show (0..1), e.g. the head.
var region := Rect2(0, 0, 1, 1)
var appearance: Dictionary = {}:
	set(value):
		appearance = value
		_layers = CharacterCatalog.layers_for(appearance, CharacterCatalog.resolve_anim(appearance, "idle"))
		queue_redraw()

var _layers: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _draw() -> void:
	if _layers.is_empty():
		return
	var fs := CharacterCatalog.frame_size()
	var src := Rect2(region.position * fs, region.size * fs)
	# Fit the region into our rect, keep aspect, centre horizontally.
	var k := minf(size.x / src.size.x, size.y / src.size.y)
	var dst_size := src.size * k
	var dst := Rect2(Vector2((size.x - dst_size.x) * 0.5, size.y - dst_size.y), dst_size)
	for l in _layers:
		draw_texture_rect_region(l["texture"], dst, src, l["modulate"])
