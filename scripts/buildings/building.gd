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
var _doors: Dictionary = {}       # door id -> {sprite, rect, frames}
var _interactable: Interactable
static var _door_meta: Dictionary = {}
const DOOR_META := "res://assets/penzilla/doors/doors.json"


## Builds the node from a settlement data entry.
var _entry: Dictionary = {}


func setup(entry: Dictionary) -> void:
	_entry = entry
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
	# Collision follows the real building, not the whole footprint: complex
	# footprints (parking, aprons, open markets) list their solid parts.
	var fp_spec := footprint_spec(building_type, entry)
	if fp_spec.is_empty():
		var body := CollisionPolygon2D.new()
		body.polygon = _scaled(_corners, 0.94)
		add_child(body)
	else:
		for poly in fp_spec.get("solid", []):
			var pts := PackedVector2Array()
			for q in poly:
				pts.append(Iso.grid_to_world(origin + Vector2(float(q[0]), float(q[1]))) - position)
			var cp := CollisionPolygon2D.new()
			cp.polygon = pts
			add_child(cp)
		surfaces = fp_spec.get("surfaces", [])

	var it := Interactable.create(building_id, display_name, _scaled(_corners, 1.0 + 1.2 / maxf(footprint.x, footprint.y)))
	it.subtitle = entry.get("function", "")
	it.text = entry.get("text", "")
	it.actions = entry.get("actions", [])
	it.verb = "Ansehen"
	# The body is only reachable by tapping; the button by proximity belongs
	# to the door (see _add_door_interactable).
	it.proximity = false
	# Stand in front of the door (middle of the front-left face).
	it.approach_offset = (_corners[3] + _corners[2]) * 0.5 + Iso.grid_to_world(Vector2(0, 0.6))
	add_child(it)
	_interactable = it

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
		_setup_doors()
		if _doors.has("main"):
			# stand in front of the door that is painted on the sprite
			_interactable.approach_offset = door_local_point("main") + Vector2(0, 16)
	_add_door_interactable()
	queue_redraw()


## Door overlays (tools/assets/make_doors.py): frames of the opening door,
## drawn over the sprite exactly where the door is painted.
func _setup_doors() -> void:
	if _door_meta.is_empty() and FileAccess.file_exists(DOOR_META):
		var d = JSON.parse_string(FileAccess.get_file_as_string(DOOR_META))
		_door_meta = d if d is Dictionary else {"doors": {}}
	var key := _sprite.texture.resource_path.get_file().get_basename()
	for d in _door_meta.get("doors", {}).get(key, []):
		if d.get("type", "none") == "none" or not ResourceLoader.exists("res://assets/penzilla/doors/" + str(d["file"])):
			continue
		var tex: Texture2D = load("res://assets/penzilla/doors/" + str(d["file"]))
		var rect: Array = d["rect"]
		var spr := Sprite2D.new()
		spr.name = "Door_" + str(d["id"])
		spr.texture = tex
		spr.centered = false
		spr.region_enabled = true
		spr.region_rect = Rect2(0, 0, rect[2], rect[3])
		# the door files are cut from the sprite file: same scale and origin
		var k := float(tex.get_height()) / float(rect[3])
		spr.scale = _sprite.scale / k
		spr.position = _sprite.position + Vector2(rect[0], rect[1]) * _sprite.scale
		spr.visible = false
		add_child(spr)
		_doors[str(d["id"])] = {"sprite": spr, "rect": rect, "frames": int(_door_meta.get("frames", 6)), "type": d["type"]}


var door_interactable: Interactable
## Walkable surfaces inside the footprint (parking, apron, market) – data for
## later systems (vehicles park on "parking" surfaces).
var surfaces: Array = []
static var _footprints: Dictionary = {}


static func footprint_spec(p_type: String, entry: Dictionary) -> Dictionary:
	if _footprints.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings/footprints.json"))
		_footprints = d if d is Dictionary else {"_": {}}
	return _footprints.get(str(entry.get("sprite_key", p_type)), {})
var sprite_key := ""


## A small interaction area right at the door: only there the button
## "Betreten" (or "Ansehen" for buildings without an interior yet) appears.
func _add_door_interactable() -> void:
	sprite_key = _sprite.texture.resource_path.get_file().get_basename() if _sprite else building_type
	var p := door_local_point("main")
	var poly := PackedVector2Array([Vector2(-30, -14), Vector2(30, -14), Vector2(30, 20), Vector2(-30, 20)])
	var it := Interactable.create(building_id + ":door", display_name, poly)
	# every regular settlement building has a generated interior (InteriorGenerator)
	var enterable := InteriorGenerator.type_for_building(building_type, _entry) != ""
	it.kind = "door_enter" if enterable else "door_info"
	it.verb = "Betreten" if enterable else "Ansehen"
	it.subtitle = _interactable.subtitle
	it.text = _interactable.text
	it.actions = _interactable.actions
	it.position = p
	it.approach_offset = Vector2(0, 16)
	it.set_meta("building_id", building_id)
	add_child(it)
	door_interactable = it


func has_door(id: String = "main") -> bool:
	return _doors.has(id)


## 0 = closed (the painted door), 1 = fully open.
func set_door_open(id: String, amount: float) -> void:
	if not _doors.has(id):
		return
	var d: Dictionary = _doors[id]
	var n: int = d["frames"]
	var fr := clampi(int(round(clampf(amount, 0.0, 1.0) * (n - 1))), 0, n - 1)
	var spr: Sprite2D = d["sprite"]
	spr.visible = fr > 0
	var rect: Array = d["rect"]
	spr.region_rect = Rect2(fr * int(rect[2]), 0, rect[2], rect[3])


## World position at the bottom centre of a door (where people pass).
func door_world_point(id: String = "main") -> Vector2:
	return global_position + door_local_point(id)


func door_local_point(id: String = "main") -> Vector2:
	if not _doors.has(id):
		return (_corners[3] + _corners[2]) * 0.5
	var rect: Array = _doors[id]["rect"]
	return _sprite.position + Vector2(float(rect[0]) + float(rect[2]) * 0.5, float(rect[1]) + float(rect[3])) * _sprite.scale


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
