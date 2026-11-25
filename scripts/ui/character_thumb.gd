class_name CharacterThumb
extends Control
## Small static picture of a whole character appearance (one idle frame,
## facing the viewer), optionally zoomed to a region of the body. Used for the
## option cards in the character editor, so every card shows the player's OWN
## character wearing that option. Layers are sprites so clothing uses the same
## palette shader as the game (CharacterCatalog.apply_layer_color).

## Normalised region of the frame to show (0..1), e.g. the head.
var region := Rect2(0, 0, 1, 1)
var appearance: Dictionary = {}:
	set(value):
		appearance = value
		_layers = CharacterCatalog.layers_for(appearance, CharacterCatalog.resolve_anim(appearance, "idle"))
		_rebuild()

var _layers: Array = []
var _sprites: Array[Sprite2D] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(_layout)


func _rebuild() -> void:
	for s in _sprites:
		s.queue_free()
	_sprites.clear()
	var fs := CharacterCatalog.frame_size()
	for l in _layers:
		var s := Sprite2D.new()
		s.texture = l["texture"]
		s.centered = false
		s.region_enabled = true
		s.region_rect = Rect2(region.position * fs, region.size * fs)
		CharacterCatalog.apply_layer_color(s, l)
		add_child(s)
		_sprites.append(s)
	_layout()


func _layout() -> void:
	if _sprites.is_empty():
		return
	var fs := CharacterCatalog.frame_size()
	var src := Rect2(region.position * fs, region.size * fs)
	# Fit the region into our rect, keep aspect, centre horizontally.
	var k := minf(size.x / maxf(src.size.x, 1.0), size.y / maxf(src.size.y, 1.0))
	var dst_size := src.size * k
	for s in _sprites:
		s.scale = Vector2(k, k)
		s.position = Vector2((size.x - dst_size.x) * 0.5, size.y - dst_size.y)
