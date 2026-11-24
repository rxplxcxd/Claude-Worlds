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
var player: Player
var camera: CameraRig
var interactions: InteractionService

@onready var ground: GroundLayer = $Ground
@onready var objects: Node2D = $Objects
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
	data = SettlementData.load_from_file(record.get("template_path", founding_template))
	if data == null:
		push_error("SettlementScene: could not load template")
		return
	data.apply_record(record)
	var problems := data.validate()
	for p in problems:
		push_warning("Settlement layout: " + p)

	ground.setup(data)
	_build_bounds()
	_build_buildings()
	_build_props()
	_build_player()

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

	GameClock.minute_changed.connect(_on_minute)
	_on_minute(0)
	# Deferred: sibling nodes (HUD) are ready by then.
	var summary := data.summary()
	summary["just_founded"] = just_founded
	summary["planet_name"] = WorldState.planet_name
	summary["settlements_on_planet"] = WorldState.get_settlements().size()
	EventBus.settlement_ready.emit.call_deferred(summary)


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
	_plant_crops()
	_scatter_vegetation()


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


func _build_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.player_id = LocalProfile.player_id
	player.position = Iso.grid_to_world(data.spawn)
	objects.add_child(player)


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
	var night := GameClock.get_night_factor()
	day_night.color = Color(1, 1, 1).lerp(Color(0.48, 0.55, 0.82), night)
