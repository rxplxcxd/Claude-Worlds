class_name Building
extends StaticBody2D
## A placed building in the local settlement scene.
##
## Node origin = centre of the footprint on the ground; this is also the
## y-sort origin, which works for the box-shaped footprints used here.
## Visual: Penzilla sprite from the AssetRegistry if integrated, otherwise a
## procedurally drawn placeholder volume (see IsoPainter).

var building_id: String = ""
var building_type: String = ""
var display_name: String = ""
var footprint: Vector2 = Vector2.ONE
var height: float = 64.0
var roof: String = "gable"
var wall_color := Color("e0d2b8")
var roof_color := Color("a2493a")
var accent_color := Color("6b4e3a")

var _corners: PackedVector2Array
var _sprite: Sprite2D
var _world_per_src := 1.0
var _living: Node2D
var _living_key := ""


## Builds the node from a settlement data entry.
func setup(entry: Dictionary) -> void:
	building_id = entry.get("id", "")
	building_type = entry.get("type", "house")
	display_name = entry.get("name", building_type)
	name = building_id
	footprint = entry["footprint_v"]
	height = float(entry.get("height", 64))
	roof = entry.get("roof", "gable")
	wall_color = Color(entry.get("color", "#e0d2b8"))
	roof_color = Color(entry.get("roof_color", "#a2493a"))
	accent_color = Color(entry.get("accent", "#6b4e3a"))

	var origin: Vector2 = entry["grid_v"]
	var center_grid := origin + footprint * 0.5
	position = Iso.grid_to_world(center_grid)
	var world_corners := Iso.rect_corners(origin, footprint)
	_corners = PackedVector2Array()
	for p in world_corners:
		_corners.append(p - position)

	collision_layer = 1 # "world"
	collision_mask = 0
	var body := CollisionPolygon2D.new()
	body.polygon = _scaled(_corners, 0.94)
	add_child(body)

	var it := Interactable.create(building_id, display_name, _scaled(_corners, 1.0 + 1.2 / maxf(footprint.x, footprint.y)))
	it.subtitle = entry.get("function", "")
	it.text = entry.get("text", "")
	it.actions = entry.get("actions", [])
	it.verb = "Betreten" if building_type == "player_home" else "Ansehen"
	# Stand in front of the door (middle of the front-left face).
	it.approach_offset = (_corners[3] + _corners[2]) * 0.5 + Iso.grid_to_world(Vector2(0, 0.6))
	add_child(it)

	# Penzilla sprite: its anchor (footprint bottom vertex) sits on the
	# bottom corner of the footprint diamond.
	var variant := int(entry.get("variant", absi(hash(building_id))))
	var info := AssetRegistry.get_sprite("exterior.building." + building_type, variant)
	if not info.is_empty():
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		_sprite.texture = info["texture"]
		_sprite.centered = false
		_sprite.scale = Vector2.ONE * float(info["scale"])
		_sprite.position = _corners[2] + info["offset"]
		add_child(_sprite)
		_world_per_src = float(info.get("world_per_src", 1.0))
	queue_redraw()


## Living Assets (Phase 4): shows the building's persistent visual state
## (wear, fire traces, overgrowth, damage) from the simulation. Pristine
## buildings keep the original sprite; missing state files fall back to it.
func apply_visual_state(vs: VisualState, profile: String) -> void:
	if _sprite == null:
		return
	var key := JSON.stringify([vs.structure, vs.wear, vs.damage, vs.fire, vs.overgrowth, vs.repair, profile])
	if key == _living_key:
		return
	_living_key = key
	if _living:
		_living.queue_free()
		_living = null
	_sprite.visible = true
	if vs.structure == "intact" and vs.wear == 0 and vs.damage == 0 and vs.fire == 0 and vs.overgrowth == 0 and vs.repair == 0:
		return
	var asset := _sprite.texture.resource_path.trim_prefix("res://assets/penzilla/").get_basename()
	if not LivingComposer.has_asset(asset):
		return
	_living = LivingComposer.build(asset, vs, _sprite.texture, profile)
	_living.scale = Vector2.ONE * _world_per_src
	_living.position = _sprite.position
	add_child(_living)
	_sprite.visible = false


func is_placeholder() -> bool:
	return _sprite == null


## Canvas item that fades when the player is behind this building.
func occluder_item() -> CanvasItem:
	return _sprite if _sprite else self


## Screen-space (canvas) rectangle covered by the building's visual.
func occluder_rect() -> Rect2:
	if _sprite:
		var size := _sprite.texture.get_size() * _sprite.scale
		return Rect2(_sprite.global_position, size)
	var r := Rect2(global_position + _corners[0], Vector2.ZERO)
	for c in _corners:
		r = r.expand(global_position + c)
	r = r.expand(global_position + _corners[0] + Vector2(0, -height - 40.0))
	return r


func _draw() -> void:
	if _sprite:
		return
	_draw_placeholder()


func _draw_placeholder() -> void:
	var c := _corners
	IsoPainter.contact_shadow(self, c)
	var top_color := roof_color if roof == "flat" else wall_color
	var top := IsoPainter.box(self, c, height, wall_color, top_color)

	# Windows and door on the two visible faces.
	var glass := Color("2f4858").lerp(Color("9cc3d5"), 0.35)
	var floors := maxi(1, int(height / 48.0))
	for f in floors:
		var v0 := (f + 0.45) / floors
		var v1 := (f + 0.78) / floors
		IsoPainter.windows(self, c[3], c[2], height, int(footprint.x) * 2, v0, v1, glass, f == 0)
		IsoPainter.windows(self, c[2], c[1], height, int(footprint.y) * 2, v0, v1, glass.darkened(0.15))
	# Door, centred on the front-left face.
	var door_h := minf(40.0 / height, 0.6)
	IsoPainter.face_quad(self, c[3], c[2], height, 0.43, 0.0, 0.57, door_h, accent_color.darkened(0.25))

	_draw_type_details(c, top)

	if roof == "flat":
		IsoPainter.flat_roof(self, top, roof_color)
	else:
		IsoPainter.gable_roof(self, top, footprint.x >= footprint.y, 22.0 + 6.0 * minf(footprint.x, footprint.y), roof_color, wall_color)

	_draw_roof_details(top)


func _draw_type_details(c: PackedVector2Array, _top: PackedVector2Array) -> void:
	match building_type:
		"clinic", "emergency_post":
			# Red cross / emergency stripe on the right face.
			var a := c[2]
			var b := c[1]
			IsoPainter.face_quad(self, a, b, height, 0.0, 0.82, 1.0, 0.92, accent_color)
			if building_type == "clinic":
				IsoPainter.face_quad(self, a, b, height, 0.44, 0.35, 0.56, 0.7, accent_color)
				IsoPainter.face_quad(self, a, b, height, 0.36, 0.47, 0.64, 0.58, accent_color)
			else:
				IsoPainter.face_quad(self, a, b, height, 0.15, 0.0, 0.85, 0.55, accent_color.darkened(0.1))
		"trade_post":
			# Striped awning on the front-left face.
			for i in 6:
				var col := accent_color if i % 2 == 0 else Color("f3eee2")
				IsoPainter.face_quad(self, c[3], c[2], height, i / 6.0, 0.62, (i + 1) / 6.0, 0.74, col)
		"energy_station":
			IsoPainter.face_quad(self, c[3], c[2], height, 0.0, 0.85, 1.0, 0.95, accent_color)
		"greenhouse":
			for i in range(1, 6):
				var u := i / 6.0
				draw_line(IsoPainter.face_point(c[3], c[2], height, u, 0.1), IsoPainter.face_point(c[3], c[2], height, u, 1.0), Color(1, 1, 1, 0.5), 1.0, true)


func _draw_roof_details(top: PackedVector2Array) -> void:
	var m := (top[0] + top[2]) * 0.5
	match building_type:
		"town_hall":
			# Flag pole and settlement banner.
			var base := m + Vector2(0, -2)
			draw_line(base, base + Vector2(0, -70), Color("4a4a4a"), 2.0, true)
			draw_colored_polygon(PackedVector2Array([base + Vector2(0, -70), base + Vector2(34, -62), base + Vector2(0, -52)]), accent_color)
			IsoPainter.ellipse(self, base + Vector2(0, -70), Vector2(2.5, 2.5), Color("e0b04a"))
		"water_works":
			IsoPainter.cylinder(self, m + Vector2(0, -2), 34.0, 44.0, Color("9fb4bb"), Color("c9d6da"))
			draw_line(m + Vector2(-34, -24), m + Vector2(34, -24), accent_color, 3.0, true)
		"energy_station":
			for i in 3:
				draw_line(m + Vector2(-20 + i * 20, 0), m + Vector2(-20 + i * 20, -30), Color("59626b"), 2.0, true)
			draw_line(m + Vector2(-26, -30), m + Vector2(26, -30), Color("59626b"), 2.0, true)
		"depot", "workshop":
			# Chimney / vent.
			var p := m + Vector2(18, -18)
			IsoPainter.box(self, PackedVector2Array([p + Vector2(0, -6), p + Vector2(10, -1), p + Vector2(0, 4), p + Vector2(-10, -1)]), 22.0, Color("7a6e66"), Color("4a423d"))


static func _scaled(poly: PackedVector2Array, f: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p * f)
	return out
