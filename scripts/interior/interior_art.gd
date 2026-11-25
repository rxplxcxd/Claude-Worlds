class_name InteriorArt
extends RefCounted
## Own pixel art for interior pieces the Penzilla retro pack does not have
## (WORLDS work, drawn at runtime in the pack's palette: dark-brown contour,
## warm mid-tones, one highlight row). A simple mattress on the floor (the
## starter home has no bed yet), a shower tray and a door mat.

const OUTLINE := Color("3b2416")
static var _cache: Dictionary = {}


static func texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var img: Image
	match id:
		"mattress":
			img = _mattress()
		"shower":
			img = _shower()
		"doormat":
			img = _doormat()
		_:
			return null
	var tex := ImageTexture.create_from_image(img)
	_cache[id] = tex
	return tex


static func _box(img: Image, r: Rect2i, fill: Color, outline := OUTLINE) -> void:
	img.fill_rect(r, outline)
	img.fill_rect(r.grow(-1), fill)


static func _mattress() -> Image:
	var img := Image.create(44, 24, false, Image.FORMAT_RGBA8)
	# slightly thick mattress lying on the floor, seen from above-front
	_box(img, Rect2i(0, 2, 44, 22), Color("cdbf9e"))
	img.fill_rect(Rect2i(1, 18, 42, 5), Color("a8946c"))          # front side (thickness)
	img.fill_rect(Rect2i(1, 17, 42, 1), OUTLINE)
	for x in range(4, 42, 6):                                      # quilting
		img.fill_rect(Rect2i(x, 4, 1, 12), Color("b9aa86"))
	img.fill_rect(Rect2i(1, 3, 42, 1), Color("e3d8bc"))            # highlight
	_box(img, Rect2i(2, 0, 13, 9), Color("efe7d4"))                # pillow
	img.fill_rect(Rect2i(3, 1, 11, 1), Color("fbf6ea"))
	_box(img, Rect2i(18, 6, 24, 12), Color("6e8fa8"))              # thin blanket
	img.fill_rect(Rect2i(19, 7, 22, 1), Color("8aa9c0"))
	img.fill_rect(Rect2i(19, 12, 22, 1), Color("5b7a92"))
	return img


static func _shower() -> Image:
	var img := Image.create(26, 30, false, Image.FORMAT_RGBA8)
	_box(img, Rect2i(0, 10, 26, 20), Color("c9d4da"))              # tray
	img.fill_rect(Rect2i(2, 12, 22, 16), Color("dfe8ec"))
	img.fill_rect(Rect2i(12, 19, 3, 3), Color("7d8a91"))           # drain
	img.fill_rect(Rect2i(1, 1, 24, 1), Color("7d8a91"))            # curtain rod
	for x in range(1, 9):                                          # curtain, pushed aside
		img.fill_rect(Rect2i(x, 2, 1, 16 - (x % 2) * 2), Color("e6a85c") if x % 2 else Color("cf8d43"))
	img.fill_rect(Rect2i(20, 0, 3, 6), Color("7d8a91"))            # shower head
	img.fill_rect(Rect2i(19, 5, 5, 2), Color("aab7be"))
	return img


static func _doormat() -> Image:
	var img := Image.create(26, 10, false, Image.FORMAT_RGBA8)
	_box(img, Rect2i(0, 0, 26, 10), Color("8a5a2b"))
	for x in range(2, 24, 3):
		img.fill_rect(Rect2i(x, 2, 1, 6), Color("6f4520"))
	return img
