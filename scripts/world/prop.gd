class_name Prop
extends StaticBody2D
## Small world object (tree, lamp, bench, well, ...).
##
## PLACEHOLDER RENDERING unless "exterior.prop.<kind>" is registered.
## Node origin = ground contact point (y-sort origin).

## Collision radius per kind in world pixels (0 = walk-through).
const SOLID_RADIUS := {
	"tree": 12.0, "lamp": 5.0, "bench": 14.0, "well": 30.0, "notice_board": 12.0,
	"market_stall": 16.0, "crates": 16.0, "solar_panel": 26.0, "bush": 0.0,
	"fountain": 70.0, "cart": 16.0, "wheelbarrow": 12.0, "electrical_box": 16.0,
	"electrical_tower": 14.0, "mailbox": 8.0, "trash_can": 8.0, "hydrant": 6.0,
	"water_tower": 22.0, "garden": 0.0, "crop": 0.0,
	"street_sign": 5.0, "traffic_sign": 5.0, "trash_small": 6.0, "bus_stop": 22.0,
	"tent": 30.0,
}

var kind: String = "tree"
var variant: float = 0.0
var _sprite: Sprite2D
var _glow: Sprite2D
var _halo: Sprite2D
var _lamp_off_info: Dictionary = {}
var _lamp_on_info: Dictionary = {}
var _lit := false
## Sprite anchor relative to the node origin (footprint bottom vertex).
var _anchor_shift := Vector2.ZERO


func setup(entry: Dictionary, p_variant: float = 0.0) -> void:
	kind = entry.get("kind", "tree")
	variant = p_variant
	position = Iso.grid_to_world(entry["grid_v"])
	name = "%s_%d" % [kind, get_instance_id()]
	collision_layer = 1
	collision_mask = 0
	var r: float = SOLID_RADIUS.get(kind, 0.0)
	# Props with a footprint (fountain, garden): node origin = footprint centre,
	# collision = footprint diamond; the sprite anchor is its bottom vertex.
	var footprint: Vector2 = entry.get("footprint_v", Vector2.ZERO)
	var diamond := PackedVector2Array()
	if footprint != Vector2.ZERO:
		for c in Iso.rect_corners(-footprint * 0.5, footprint):
			diamond.append(c)
		if r > 0.0:
			var body := CollisionPolygon2D.new()
			body.polygon = _scaled(diamond, 0.8)
			add_child(body)
	elif r > 0.0:
		# Ellipse flattened to the ground plane.
		var shape := CollisionPolygon2D.new()
		var pts := PackedVector2Array()
		for i in 10:
			var a := TAU * i / 10
			pts.append(Vector2(cos(a) * r, sin(a) * r * 0.55))
		shape.polygon = pts
		add_child(shape)

	if entry.has("name"):
		var poly := PackedVector2Array()
		var rr := maxf(r, 16.0) + 26.0
		var approach := Vector2(0, rr * 0.6)
		if diamond.size() > 0:
			poly = _scaled(diamond, 1.3)
			approach = diamond[2] + Vector2(0, 12)
		else:
			for i in 12:
				var a := TAU * i / 12
				poly.append(Vector2(cos(a) * rr, sin(a) * rr * 0.6))
		var it := Interactable.create(entry.get("id", "prp_" + kind), entry.get("name", kind), poly)
		it.kind = entry.get("interaction", "info")
		it.text = entry.get("text", "")
		it.actions = entry.get("actions", [])
		it.approach_offset = approach
		add_child(it)

	if diamond.size() > 0:
		_anchor_shift = diamond[2]
	var sprite_variant := int(entry.get("variant", int(p_variant * 1000.0)))
	_lamp_off_info = AssetRegistry.get_sprite("exterior.prop." + kind, sprite_variant)
	if not _lamp_off_info.is_empty():
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		_sprite.centered = false
		_apply_sprite(_lamp_off_info)
		add_child(_sprite)
		if kind == "lamp":
			_lamp_on_info = AssetRegistry.get_sprite("exterior.prop.lamp_on")
	if kind == "lamp":
		_add_glow()
	queue_redraw()


func _process(_delta: float) -> void:
	var night := GameClock.get_night_factor()
	if _glow:
		_glow.modulate.a = night * 0.85
	if _halo:
		_halo.modulate.a = night
	var lit := night > 0.35
	if _sprite and lit != _lit and not _lamp_on_info.is_empty():
		_lit = lit
		_apply_sprite(_lamp_on_info if lit else _lamp_off_info)


func _apply_sprite(info: Dictionary) -> void:
	_sprite.texture = info["texture"]
	_sprite.scale = Vector2.ONE * float(info["scale"])
	_sprite.position = info["offset"] + _anchor_shift


static func _scaled(poly: PackedVector2Array, f: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p * f)
	return out


func _add_glow() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.85, 0.55, 0.9))
	g.set_color(1, Color(1.0, 0.8, 0.5, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 128
	t.height = 128
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# Light pool on the ground.
	_glow = Sprite2D.new()
	_glow.texture = t
	_glow.scale = Vector2(2.2, 1.3)
	_glow.position = Vector2(0, -6)
	_glow.material = mat
	_glow.show_behind_parent = true
	_glow.modulate.a = 0.0
	add_child(_glow)
	# Halo around the lamp head (only with the real lamp sprite).
	if _sprite:
		_halo = Sprite2D.new()
		_halo.texture = t
		_halo.scale = Vector2(0.45, 0.45)
		var top := _sprite.position.y + _sprite.texture.get_height() * _sprite.scale.y * 0.08
		_halo.position = Vector2(0, top + 6.0)
		_halo.material = mat
		_halo.modulate.a = 0.0
		add_child(_halo)
	set_process(true)


func _ready() -> void:
	set_process(kind == "lamp")


## Only tall props hide the player.
func is_occluder() -> bool:
	return kind in ["tree", "electrical_tower", "water_tower", "bus_stop", "tent"]


func occluder_item() -> CanvasItem:
	return _sprite if _sprite else self


func occluder_rect() -> Rect2:
	if _sprite:
		return Rect2(_sprite.global_position, _sprite.texture.get_size() * _sprite.scale)
	return Rect2(global_position + Vector2(-30, -90), Vector2(60, 92))


func _draw() -> void:
	if _sprite:
		return
	match kind:
		"tree": _draw_tree()
		"bush": _draw_bush()
		"lamp": _draw_lamp()
		"bench": _draw_bench()
		"well": _draw_well()
		"notice_board": _draw_notice_board()
		"market_stall": _draw_market_stall()
		"crates": _draw_crates()
		"solar_panel": _draw_solar_panel()
		"fountain": _draw_well()
		"crop": _draw_bush()
		"electrical_tower", "water_tower": _draw_lamp()
		"cart", "wheelbarrow", "electrical_box", "mailbox", "trash_can", "hydrant", "trash_small", "bus_stop": _draw_crates()
		"street_sign", "traffic_sign": _draw_lamp()


func _shadow(rx: float) -> void:
	IsoPainter.ellipse(self, Vector2.ZERO, Vector2(rx, rx * 0.45), Color(0, 0, 0, 0.2))


func _draw_tree() -> void:
	var s := 0.85 + variant * 0.4
	_shadow(26.0 * s)
	draw_line(Vector2.ZERO, Vector2(0, -34 * s), Color("6b4a32"), 6.0 * s, true)
	var g1 := Color("4f7f3a").lerp(Color("5f8f3f"), variant)
	IsoPainter.ellipse(self, Vector2(0, -52 * s), Vector2(28, 24) * s, g1.darkened(0.15))
	IsoPainter.ellipse(self, Vector2(-9, -62 * s), Vector2(20, 18) * s, g1)
	IsoPainter.ellipse(self, Vector2(8, -70 * s), Vector2(15, 13) * s, g1.lightened(0.12))


func _draw_bush() -> void:
	var s := 0.7 + variant * 0.5
	_shadow(16.0 * s)
	var g := Color("5d8f42").lerp(Color("6e9b46"), variant)
	IsoPainter.ellipse(self, Vector2(-6, -8) * s, Vector2(12, 9) * s, g.darkened(0.1))
	IsoPainter.ellipse(self, Vector2(6, -10) * s, Vector2(11, 9) * s, g)
	IsoPainter.ellipse(self, Vector2(0, -15) * s, Vector2(9, 7) * s, g.lightened(0.1))


func _draw_lamp() -> void:
	_shadow(8.0)
	draw_line(Vector2.ZERO, Vector2(0, -78), Color("3c4248"), 3.0, true)
	draw_line(Vector2(0, -78), Vector2(10, -82), Color("3c4248"), 2.0, true)
	IsoPainter.ellipse(self, Vector2(11, -80), Vector2(6, 4), Color("f6e3a1"))


func _draw_bench() -> void:
	_shadow(18.0)
	var c := PackedVector2Array([Vector2(-6, -10), Vector2(20, 3), Vector2(6, 10), Vector2(-20, -3)])
	var top := IsoPainter.box(self, c, 10.0, Color("8a5a3b"), Color("a8714a"))
	draw_line((top[0] + top[3]) * 0.5, (top[0] + top[3]) * 0.5 + Vector2(0, -14), Color("6e4630"), 2.0, true)
	draw_line((top[1] + top[2]) * 0.5 + Vector2(-26, -16), (top[1] + top[2]) * 0.5 + Vector2(0, -14), Color("6e4630"), 2.0, true)


func _draw_well() -> void:
	_shadow(40.0)
	IsoPainter.cylinder(self, Vector2.ZERO, 32.0, 22.0, Color("a19a8f"), Color("4f8fb5"))
	IsoPainter.ellipse(self, Vector2(0, -22), Vector2(24, 11), Color("3f7aa0"))
	draw_line(Vector2(-28, -18), Vector2(-28, -66), Color("6b4a32"), 4.0, true)
	draw_line(Vector2(28, -18), Vector2(28, -66), Color("6b4a32"), 4.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-38, -62), Vector2(0, -86), Vector2(38, -62), Vector2(0, -50)]), Color("8d3b2f"))
	draw_line(Vector2(0, -60), Vector2(0, -34), Color("3c3c3c"), 1.0, true)


func _draw_notice_board() -> void:
	_shadow(18.0)
	draw_line(Vector2(-14, 0), Vector2(-14, -50), Color("5b3f2b"), 4.0, true)
	draw_line(Vector2(14, 6), Vector2(14, -44), Color("5b3f2b"), 4.0, true)
	var board := PackedVector2Array([Vector2(-20, -60), Vector2(20, -52), Vector2(20, -28), Vector2(-20, -36)])
	draw_colored_polygon(board, Color("8a5a3b"))
	draw_colored_polygon(PackedVector2Array([Vector2(-16, -56), Vector2(-2, -53), Vector2(-2, -40), Vector2(-16, -43)]), Color("f3eee2"))
	draw_colored_polygon(PackedVector2Array([Vector2(1, -52), Vector2(16, -49), Vector2(16, -38), Vector2(1, -41)]), Color("f2d37a"))


func _draw_market_stall() -> void:
	_shadow(30.0)
	var c := PackedVector2Array([Vector2(0, -16), Vector2(30, -1), Vector2(0, 14), Vector2(-30, -1)])
	IsoPainter.box(self, c, 22.0, Color("8a5a3b"), Color("c79a5b"))
	for i in 4:
		IsoPainter.ellipse(self, Vector2(-14 + i * 8, -26 + i * 2), Vector2(4, 3), Color("c0392b") if i % 2 == 0 else Color("e0b04a"))
	draw_line(Vector2(-30, -1), Vector2(-30, -52), Color("5b3f2b"), 2.0, true)
	draw_line(Vector2(30, -1), Vector2(30, -52), Color("5b3f2b"), 2.0, true)
	for i in 6:
		var x0 := -34 + i * 11.3
		draw_colored_polygon(PackedVector2Array([Vector2(x0, -54), Vector2(x0 + 11.3, -54), Vector2(x0 + 11.3, -44), Vector2(x0, -44)]),
			Color("2f7f6f") if i % 2 == 0 else Color("f3eee2"))


func _draw_crates() -> void:
	_shadow(20.0)
	var c := PackedVector2Array([Vector2(-6, -9), Vector2(10, -1), Vector2(-6, 7), Vector2(-22, -1)])
	IsoPainter.box(self, c, 16.0, Color("a0763f"), Color("c49455"))
	var c2 := PackedVector2Array([Vector2(12, -3), Vector2(24, 3), Vector2(12, 9), Vector2(0, 3)])
	IsoPainter.box(self, c2, 12.0, Color("8f6a3a"), Color("b88a4f"))


func _draw_solar_panel() -> void:
	_shadow(28.0)
	draw_line(Vector2(-14, 4), Vector2(-14, -14), Color("6b737a"), 2.0, true)
	draw_line(Vector2(14, 4), Vector2(14, -22), Color("6b737a"), 2.0, true)
	var p := PackedVector2Array([Vector2(-30, -10), Vector2(2, -36), Vector2(30, -22), Vector2(-2, 4)])
	draw_colored_polygon(p, Color("23405e"))
	for i in range(1, 4):
		var t := i / 4.0
		draw_line(p[0].lerp(p[1], t), p[3].lerp(p[2], t), Color("5d86ad"), 1.0, true)
	draw_polyline(PackedVector2Array([p[0], p[1], p[2], p[3], p[0]]), Color("c9d1d8"), 1.5, true)
