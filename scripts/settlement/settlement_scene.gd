class_name SettlementScene
extends Node2D
## Local, detailed view of ONE settlement (simulation LOD "active").
##
## Builds ground, buildings, props and the player from SettlementData.
## The settlement must have been FOUNDED by a human player (WorldState); on
## the very first launch the local player founds it from the template. The
## global world map / globe (Phase 2) is a separate scene; only the settlement
## the player is in is ever instantiated as nodes (docs/PERFORMANCE.md).

const DEFAULT_TEMPLATE := "res://data/settlement_templates/founding_basic.json"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

@export_file("*.json") var founding_template: String = DEFAULT_TEMPLATE

var data: SettlementData
var record: Dictionary = {}
## True when this launch created the settlement (first start).
var just_founded := false
## Set by Main when the player just founded it on the globe.
var founded_now := false
var player: Player
var camera: CameraRig
var interactions: InteractionService
## Generated street furniture (for tests / validation).
var street_items: Array = []
## Founding community (Npc nodes).
var npcs: Array[Npc] = []
var _presence_timer := 0.0

@onready var ground: GroundLayer = $Ground
@onready var objects: Node2D = $Objects
@onready var ground_lights: Node2D = $GroundLights
@onready var day_night: CanvasModulate = $DayNight


func _ready() -> void:
	record = WorldState.get_settlement_of(LocalProfile.player_id)
	if record.is_empty():
		# The planet has no settlement for this player yet: they found one.
		# Phase 1 founds automatically from the template; choosing location
		# and name on the planet follows with the globe (Phase 2/4).
		record = WorldState.found_settlement(founding_template, LocalProfile.player_id)
		just_founded = true
	if record.is_empty():
		push_error("SettlementScene: founding failed")
		return
	just_founded = just_founded or founded_now
	data = SettlementData.load_from_file(record.get("template_path", founding_template))
	if data == null:
		push_error("SettlementScene: could not load template")
		return
	data.apply_record(record)
	# The sun follows the settlement's latitude on the planet (day length).
	if record.has("position"):
		GameClock.latitude = float(record["position"]["lat"])
	var problems := data.validate()
	for p in problems:
		push_warning("Settlement layout: " + p)

	ground.setup(data)
	_build_bounds()
	_build_buildings()
	_build_props()
	_build_player()
	_build_npcs()

	interactions = InteractionService.new()
	interactions.name = "InteractionService"
	interactions.settlement = data
	add_child(interactions)
	player.interaction_requested.connect(interactions.open)

	camera = CameraRig.new()
	camera.name = "Camera"
	camera.target = player
	camera.bounds = _world_bounds().grow(-120)
	add_child(camera)
	camera.make_current()
	camera.snap_to_target()
	player.moved_by_input.connect(camera.recenter)

	_setup_occlusion()
	add_to_group("perf_view")
	GameClock.minute_changed.connect(_on_minute)
	_on_minute(0)
	# Deferred: sibling nodes (HUD) are ready by then.
	var summary := data.summary()
	summary["just_founded"] = just_founded
	summary["planet_name"] = WorldState.planet_name
	summary["settlements_on_planet"] = WorldState.get_settlements().size()
	summary["continent_name"] = record.get("continent_name", "")
	summary["migrated"] = WorldState.migrated_settlement_ids.has(record.get("settlement_id", ""))
	EventBus.settlement_ready.emit.call_deferred(summary)


## Blocks/unblocks direct control (e.g. while the character editor is open).
## Diagnostics for PerfMonitor: world objects whose position lies in (or
## close to) the camera view. The ground is one drawing with all tiles.
func perf_stats() -> Dictionary:
	var vis := 0
	var total := 0
	if camera:
		var rect := Rect2(camera.get_screen_center_position() - get_viewport_rect().size * 0.5 / camera.zoom, get_viewport_rect().size / camera.zoom).grow(160)
		for c in objects.get_children():
			total += 1
			if c is Node2D and rect.has_point((c as Node2D).global_position):
				vis += 1
	return {"view": "Siedlung", "visible_objects": vis, "total_objects": total,
		"ground_tiles_drawn": data.size.x * data.size.y if data else 0, "npcs": npcs.size()}


func set_input_enabled(on: bool) -> void:
	if player:
		player.input_enabled = on
		if not on:
			player.cancel_move_target()


## Converts a screen position into a world position and handles a tap:
## tap an object -> walk there and use it, tap ground -> walk there.
func handle_tap(screen_pos: Vector2) -> void:
	var world := camera.screen_to_world(screen_pos)
	var it := _interactable_at(world)
	if it:
		player.move_to(it.get_approach_point(), it)
	else:
		player.move_to(world)


func _interactable_at(world: Vector2) -> Interactable:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = world
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = 1 << 2
	var best: Interactable = null
	var best_y := -INF
	for hit in get_world_2d().direct_space_state.intersect_point(q, 8):
		var c: Object = hit.get("collider")
		# Frontmost (largest y) object wins when shapes overlap.
		if c is Interactable and c.global_position.y > best_y:
			best = c
			best_y = c.global_position.y
	return best


func _build_buildings() -> void:
	for entry in data.buildings:
		var b := Building.new()
		b.setup(entry)
		objects.add_child(b)


func _build_props() -> void:
	for i in data.props.size():
		var p := Prop.new()
		p.setup(data.props[i], GroundLayer._hash(i, 99))
		objects.add_child(p)
	_build_street_furniture()
	_plant_crops()
	_scatter_vegetation()


## Lamps, hydrants, signs, bus stop, mailboxes: derived from the road network
## by placement rules (StreetPlanner), not hand-placed.
func _build_street_furniture() -> void:
	var planner := StreetPlanner.new(data)
	street_items = planner.plan()
	for it in street_items:
		if it["kind"] == "street_lamp":
			var lamp := StreetLamp.new()
			lamp.setup(it["grid_v"], it["road_dir"])
			objects.add_child(lamp)
			ground_lights.add_child(lamp.make_ground_light())
		else:
			var entry: Dictionary = it.duplicate()
			if entry.has("text"):
				entry["text"] = str(entry["text"]).replace("{settlement}", data.settlement_name)
			var p := Prop.new()
			p.setup(entry, 0.0)
			objects.add_child(p)
		data.props.append({"kind": it["kind"], "grid_v": it["grid_v"]})


## One crop plant per field tile (only with the real Penzilla plants; the
## placeholder ground already draws crop rows).
func _plant_crops() -> void:
	if AssetRegistry.get_texture("exterior.prop.crop") == null:
		return
	for y in data.size.y:
		for x in data.size.x:
			if data.get_tile(x, y) == "field":
				var p := Prop.new()
				p.setup({"kind": "crop", "grid_v": Vector2(x + 0.5, y + 0.55)}, GroundLayer._hash(x, y))
				objects.add_child(p)


## Deterministic vegetation on free grass cells (seeded, reproducible).
func _scatter_vegetation() -> void:
	var blocked := {}
	for b in data.buildings:
		for c in data.get_building_cells(b):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					blocked[c + Vector2i(dx, dy)] = true
	for p in data.props:
		var g: Vector2 = p["grid_v"]
		blocked[Vector2i(int(g.x), int(g.y))] = true
	var sp := Vector2i(int(data.spawn.x), int(data.spawn.y))
	blocked[sp] = true

	for spec in data.scatter:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(spec.get("seed", 1))
		var placed := 0
		var attempts := 0
		var margin := int(spec.get("margin", 0))
		while placed < int(spec.get("count", 0)) and attempts < 4000:
			attempts += 1
			var x := rng.randi_range(margin, data.size.x - 1 - margin)
			var y := rng.randi_range(margin, data.size.y - 1 - margin)
			var cell := Vector2i(x, y)
			if blocked.has(cell) or data.get_tile(x, y) != "grass":
				continue
			# Trees prefer the outskirts so the centre stays readable.
			var center_dist := Vector2(x, y).distance_to(Vector2(data.size) * 0.5)
			if spec.get("kind") == "tree" and center_dist < 7.0 and rng.randf() < 0.85:
				continue
			blocked[cell] = true
			var p := Prop.new()
			var g := Vector2(x + rng.randf_range(0.25, 0.75), y + rng.randf_range(0.25, 0.75))
			p.setup({"kind": spec.get("kind", "tree"), "grid_v": g}, rng.randf())
			objects.add_child(p)
			placed += 1


## The founding community: stored in the settlement record (persistent
## identities and appearances), generated once at founding. Older saves
## without NPCs get them on first load.
func _build_npcs() -> void:
	if not CharacterCatalog.is_available():
		return # NPCs need the character art; no placeholder crowd.
	var roster: Array = record.get("npcs", [])
	if roster.is_empty():
		roster = NpcRoster.generate(record.get("settlement_id", ""), data.buildings)
		record["npcs"] = roster
		WorldState.save_world()
	var spawn_cell := Vector2i(int(floor(data.spawn.x)), int(floor(data.spawn.y)))
	var reserved: Array = [spawn_cell]
	for it in street_items:
		var g: Vector2 = it["grid_v"]
		reserved.append(Vector2i(int(floor(g.x)), int(floor(g.y))))
	var spots := NpcRoster.plan_spots(data, roster, reserved)
	var names := {}
	for b in data.buildings:
		names[b.get("id", "")] = b.get("name", "")
	for r in roster:
		var n := Npc.new()
		n.setup(r, spots.get(r.get("npc_id", ""), {}), names)
		objects.add_child(n)
		npcs.append(n)


func _build_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.player_id = LocalProfile.player_id
	player.position = Iso.grid_to_world(_qa_spawn(data.spawn))
	objects.add_child(player)


## QA helper: "?spawn=9.6,5.5" in the page URL overrides the start position.
func _qa_spawn(default_pos: Vector2) -> Vector2:
	if not OS.has_feature("web"):
		return default_pos
	var v := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('spawn')||''", true)).split(",")
	if v.size() == 2 and v[0].is_valid_float() and v[1].is_valid_float():
		return Vector2(float(v[0]), float(v[1]))
	return default_pos


## Invisible walls along the settlement edge and around water.
func _build_bounds() -> void:
	var walls := StaticBody2D.new()
	walls.name = "Bounds"
	walls.collision_layer = 1
	walls.collision_mask = 0
	var c := Iso.rect_corners(Vector2.ZERO, Vector2(data.size))
	for i in 4:
		var seg := CollisionShape2D.new()
		var s := SegmentShape2D.new()
		s.a = c[i]
		s.b = c[(i + 1) % 4]
		seg.shape = s
		walls.add_child(seg)
	for y in data.size.y:
		for x in data.size.x:
			if SettlementData.BLOCKING_TILES.has(data.get_tile(x, y)):
				var poly := CollisionPolygon2D.new()
				poly.polygon = Iso.rect_corners(Vector2(x, y), Vector2.ONE)
				walls.add_child(poly)
	add_child(walls)


func _world_bounds() -> Rect2:
	var c := Iso.rect_corners(Vector2.ZERO, Vector2(data.size))
	var r := Rect2(c[0], Vector2.ZERO)
	for p in c:
		r = r.expand(p)
	return r


func _on_minute(_m: int) -> void:
	day_night.color = GameClock.get_ambient_color()


func _process(delta: float) -> void:
	# Cheap; keeps the time-of-day preview and dawn/dusk transitions fluid.
	day_night.color = GameClock.get_ambient_color()
	_update_occlusion(delta)
	_presence_timer -= delta
	if _presence_timer <= 0.0:
		_presence_timer = 0.5 # also follows the time-of-day preview
		for n in npcs:
			n.update_presence()


# --- occlusion: keep the player visible behind buildings and trees ---------

const OCCLUDER_SHADER := preload("res://shaders/occluder.gdshader")
const OCCLUSION_FADE_SPEED := 6.0
var _occluder_material: ShaderMaterial
## [node, current strength]
var _occluders: Array = []


func _setup_occlusion() -> void:
	_occluder_material = ShaderMaterial.new()
	_occluder_material.shader = OCCLUDER_SHADER
	for n in objects.get_children():
		if n is Building or (n is Prop and (n as Prop).is_occluder()):
			n.occluder_item().material = _occluder_material
			_occluders.append([n, 0.0])


## An object hides the player when it is drawn after the player (its sort
## position is further front) and its picture overlaps the player's body.
func is_occluding(n: Node2D) -> bool:
	if player == null:
		return false
	if n.global_position.y <= player.global_position.y:
		return false
	var body := Rect2(player.global_position + Vector2(-12, -58), Vector2(24, 58))
	return n.occluder_rect().grow(-4.0).intersects(body)


func _update_occlusion(delta: float) -> void:
	if player == null or _occluder_material == null:
		return
	_occluder_material.set_shader_parameter("player_pos", player.global_position + Vector2(0, -26))
	for entry in _occluders:
		var n: Node2D = entry[0]
		var target := 1.0 if is_occluding(n) else 0.0
		var s: float = entry[1]
		if is_equal_approx(s, target):
			continue
		s = move_toward(s, target, delta * OCCLUSION_FADE_SPEED)
		entry[1] = s
		var item: CanvasItem = n.occluder_item()
		item.modulate.a = 1.0 - 0.5 * s


func occlusion_strength(n: Node2D) -> float:
	for entry in _occluders:
		if entry[0] == n:
			return entry[1]
	return 0.0
