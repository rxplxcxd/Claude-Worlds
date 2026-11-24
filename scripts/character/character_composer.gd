extends Node
## Merges tinted character layers into ONE texture on the GPU
## (autoload "CharacterComposer").
##
## Why: a character is built from up to ~12 layer sheets. Keeping them all as
## separate sprites costs memory and draw calls (every NPC would hold its own
## set). The composer renders the layers once into an off-screen SubViewport,
## reads the result back and returns a single ImageTexture. Identical requests
## share the same texture (cache by key).
##
## The result is PREMULTIPLIED alpha (2D blending into a transparent target);
## display it with CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA.
## Headless runs (tests, CI) have no renderer: compose() returns null and the
## rig simply keeps its stacked layers.

var _cache: Dictionary = {}
var _busy := false
var _queue: Array = []


func can_compose() -> bool:
	return DisplayServer.get_name() != "headless"


func cached(key: String) -> Texture2D:
	return _cache.get(key, null)


## layers: [{ "texture": Texture2D, "modulate": Color }], all the same size.
## Returns the merged texture, or null if composing is not possible.
func compose(key: String, layers: Array) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	if not can_compose() or layers.is_empty():
		return null
	# One composition at a time keeps memory peaks small.
	while _busy:
		await get_tree().process_frame
	if _cache.has(key):
		return _cache[key]
	_busy = true
	var size := Vector2i((layers[0]["texture"] as Texture2D).get_size())
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	for l in layers:
		var s := Sprite2D.new()
		s.centered = false
		s.texture = l["texture"]
		s.self_modulate = l["modulate"]
		vp.add_child(s)
	add_child(vp)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	_busy = false
	if img == null or img.is_empty():
		return null
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


func clear_cache() -> void:
	_cache.clear()


static func premult_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	return m
