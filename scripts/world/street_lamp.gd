class_name StreetLamp
extends StaticBody2D
## Street lamp with an arm reaching over the road.
##
## Penzilla has no arm lamp, so it is assembled from Penzilla parts:
##   pole  – StreetLamp sprite below its head (source rows 66..232)
##   arm   – WallPole, mirrored/rotated onto the isometric axis towards the road
##   head  – StreetLamp head (source rows 0..70), hanging at the arm's end
## Node origin = foot of the pole (y-sort origin), so characters pass in front
## of / behind the lamp correctly. Light at night: halo at the head, a soft
## cone down to the road and a light pool on the road surface (the pool lives
## in the settlement's ground-light layer, below all objects).

const POLE_SRC := Rect2(0, 66, 58, 166)
const HEAD_SRC := Rect2(0, 0, 58, 70)
const ARM_JOINT_SRC := Vector2(103, 84)
const ARM_FREE_SRC := Vector2(9, 8)
## How far the arm reaches over the road, in tiles (ground projection).
const ARM_REACH_TILES := 0.42

## Grid direction from the lamp towards the road it lights.
var road_dir := Vector2i(0, 1)
var pool: Node2D

var _head: Sprite2D
var _halo: Sprite2D
var _cone: Polygon2D
var _pool_sprite: Sprite2D
var _off_tex: Texture2D
var _on_tex: Texture2D
var _lit := false
var _head_world := Vector2.ZERO
var _light_tex: GradientTexture2D


func setup(grid: Vector2, p_road_dir: Vector2i) -> void:
	road_dir = p_road_dir
	position = Iso.grid_to_world(grid)
	name = "lamp_%d" % get_instance_id()
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionPolygon2D.new()
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8
		pts.append(Vector2(cos(a) * 5.0, sin(a) * 3.0))
	shape.polygon = pts
	add_child(shape)
	_light_tex = _make_light_texture()
	_build_visual()
	set_process(true)


## Ground-plane vector of the arm (screen space), towards the road.
func arm_vector() -> Vector2:
	return Iso.grid_to_world(Vector2(road_dir) * ARM_REACH_TILES)


func _build_visual() -> void:
	_off_tex = AssetRegistry.get_texture("exterior.prop.lamp")
	_on_tex = AssetRegistry.get_texture("exterior.prop.lamp_on")
	var arm_tex := AssetRegistry.get_texture("exterior.prop.lamp_arm")
	var reach := arm_vector()
	if _off_tex == null or arm_tex == null:
		# Placeholder: simple pole + arm + head drawn in _draw().
		_head_world = Vector2(0, -62) + reach
		queue_redraw()
		return
	var k := Iso.WORLD_PER_SRC_PX
	var f_lamp := float(_off_tex.get_width()) / 58.0 # file pixels per source pixel
	var pole := Sprite2D.new()
	pole.texture = _off_tex
	pole.region_enabled = true
	pole.region_rect = Rect2(POLE_SRC.position * f_lamp, POLE_SRC.size * f_lamp)
	pole.centered = false
	pole.scale = Vector2.ONE * k / f_lamp
	pole.position = Vector2(-29.0 * k, -POLE_SRC.size.y * k)
	add_child(pole)
	var top := Vector2(0, -POLE_SRC.size.y * k + 3.0)

	# Arm: its source runs from the joint (bottom right) to the free end
	# (top left). Rotate it so it follows the ground direction towards the road.
	var arm := Sprite2D.new()
	arm.texture = arm_tex
	arm.centered = false
	var f_arm := float(arm_tex.get_width()) / 121.0
	var src_vec := (ARM_FREE_SRC - ARM_JOINT_SRC)
	var want := reach
	var scale_len := want.length() / (src_vec.length() * k)
	arm.scale = Vector2.ONE * k * scale_len / f_arm
	arm.rotation = src_vec.angle_to(want)
	arm.position = top - (ARM_JOINT_SRC * k * scale_len).rotated(arm.rotation)
	add_child(arm)
	var free_end := top + want

	_head = Sprite2D.new()
	_head.texture = _off_tex
	_head.region_enabled = true
	_head.region_rect = Rect2(HEAD_SRC.position * f_lamp, HEAD_SRC.size * f_lamp)
	_head.centered = false
	_head.scale = Vector2.ONE * k / f_lamp
	# Hangs below the arm's end.
	_head.position = free_end + Vector2(-29.0 * k, -4.0)
	add_child(_head)
	_head_world = free_end + Vector2(0, HEAD_SRC.size.y * k * 0.55)

	_halo = Sprite2D.new()
	_halo.texture = _light_tex
	_halo.scale = Vector2(0.32, 0.32)
	_halo.position = _head_world
	_halo.material = _additive()
	_halo.modulate.a = 0.0
	add_child(_halo)

	_cone = Polygon2D.new()
	var ground := reach
	var spread := Iso.grid_to_world(Vector2(road_dir.y, -road_dir.x) * 0.55)
	_cone.polygon = PackedVector2Array([_head_world + Vector2(-4, 0), _head_world + Vector2(4, 0), ground + spread, ground - spread])
	_cone.vertex_colors = PackedColorArray([Color(1, 0.86, 0.6, 0.55), Color(1, 0.86, 0.6, 0.55), Color(1, 0.8, 0.5, 0.0), Color(1, 0.8, 0.5, 0.0)])
	_cone.material = _additive()
	_cone.modulate.a = 0.0
	_cone.show_behind_parent = true
	add_child(_cone)


## Light pool on the road; added by the settlement to its ground-light layer.
func make_ground_light() -> Node2D:
	_pool_sprite = Sprite2D.new()
	_pool_sprite.texture = _light_tex
	_pool_sprite.position = position + arm_vector()
	_pool_sprite.scale = Vector2(2.3, 1.3)
	_pool_sprite.material = _additive()
	_pool_sprite.modulate.a = 0.0
	pool = _pool_sprite
	return _pool_sprite


func _process(_delta: float) -> void:
	var night := GameClock.get_night_factor()
	var lit := night > 0.35
	if lit != _lit:
		_lit = lit
		if _head and _on_tex:
			_head.texture = _on_tex if lit else _off_tex
		queue_redraw()
	# The ambient tint darkens everything incl. additive light; compensate so
	# the light keeps its intended brightness at night.
	var amb := GameClock.get_ambient_color()
	var boost := Color(1.0 / maxf(amb.r, 0.2), 1.0 / maxf(amb.g, 0.2), 1.0 / maxf(amb.b, 0.2))
	var light := Color(1.0, 0.86, 0.62) * boost
	if _pool_sprite:
		_pool_sprite.modulate = Color(light.r * 0.55, light.g * 0.55, light.b * 0.55, night * 0.9)
	if _halo:
		_halo.modulate = Color(light.r, light.g, light.b, night)
	if _cone:
		_cone.modulate = Color(light.r * 0.5, light.g * 0.5, light.b * 0.5, night * 0.8)


func _draw() -> void:
	if _head:
		return
	# PLACEHOLDER arm lamp.
	var reach := arm_vector()
	IsoPainter.ellipse(self, Vector2.ZERO, Vector2(7, 3), Color(0, 0, 0, 0.2))
	draw_line(Vector2.ZERO, Vector2(0, -62), Color("3c4248"), 3.0, true)
	draw_line(Vector2(0, -62), Vector2(0, -62) + reach, Color("3c4248"), 2.0, true)
	IsoPainter.ellipse(self, Vector2(0, -58) + reach, Vector2(6, 4), Color("f6e3a1") if _lit else Color("9aa0a6"))


static func _make_light_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.45))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 128
	t.height = 128
	return t


static func _additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m
