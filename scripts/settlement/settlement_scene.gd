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
## Inhabitants (Npc nodes) – presentation of the simulation.
var npcs: Array[Npc] = []
## Phase 3: the living world of this settlement (pure data, see docs/LIVING_WORLD.md).
var sim: SettlementSim
var building_nodes: Dictionary = {}   # building_id -> Building
var _names: Dictionary = {}
var _npc_by_id: Dictionary = {}
var _lod_timer := 0.0
var _save_timer := 60.0
var _detail: Dictionary = {}           # npc_id -> true for LOD S0 (visible + detailed)
var _groups: Dictionary = {}
var _preview_sim: SettlementSim
var _preview_key := -1
var _fx_nodes: Dictionary = {}          # effect key -> node
var _vfx_atlas: Texture2D
var _vfx_meta: Dictionary = {}

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
	player.interaction_requested.connect(_on_interaction_requested)   # refresh NPC card first
	player.interaction_requested.connect(interactions.open)
	EventBus.interaction_action.connect(_on_interaction_action)

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
		building_nodes[entry.get("id", "")] = b


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
	for b in data.buildings:
		_names[b.get("id", "")] = b.get("name", "")
	# Phase 3: bring the living world to NOW before anything is shown
	# (catch-up after absence is event-driven and invisible), then persist.
	sim = SettlementSim.create(record, data, int(GameClock.get_utc_unix()))
	sim.store()
	WorldState.save_world()
	for r in roster:
		var n := Npc.new()
		n.setup(r, _names)
		objects.add_child(n)
		npcs.append(n)
		_npc_by_id[r["npc_id"]] = n
	_update_lod(true)


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
	if sim == null:
		return
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.25
		sim.advance_to(int(GameClock.get_utc_unix()))
		_update_lod(false)
	_render_npcs(false)
	_save_timer -= delta
	if _save_timer <= 0.0:
		_save_timer = 60.0
		persist()


## Writes the simulation into the settlement record and saves the world.
func persist() -> void:
	if sim:
		sim.store()
		WorldState.save_world()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		persist()


# --- Phase 3: presentation of the simulation (LOD) ---------------------------------

## Time shown: real time, or the time-of-day preview (menu / QA) – the
## preview uses a throw-away simulation and never changes the real one.
func render_time() -> float:
	if GameClock.preview_minute_of_day < 0.0:
		return GameClock.get_utc_unix()
	var now := int(GameClock.get_utc_unix())
	return float(NpcBrain.day_start(now, sim.offset_min()) + int(GameClock.preview_minute_of_day * 60.0))


func render_sim() -> SettlementSim:
	if GameClock.preview_minute_of_day < 0.0:
		_preview_sim = null
		return sim
	var t := int(render_time())
	var key := int(t / 300)
	if _preview_sim == null or _preview_key != key:
		_preview_key = key
		_preview_sim = SettlementSim.preview(record, data, t, sim.config)
	return _preview_sim


## LOD classification (4×/s): NPCs whose position lies in the camera view
## are rendered in detail (S0, capped by the graphics profile, nearest to the
## view centre first); all others are data-only (S1): hidden, not processed.
func _update_lod(force: bool) -> void:
	var s := render_sim()
	var t := render_time()
	var rect := _view_rect().grow(220)
	var cap := int(GraphicsProfile.params()["npc_detail_cap"])
	var centre := rect.get_center()
	var cand := []
	for r in s.roster:
		var id: String = r["npc_id"]
		var info := s.render_info(id, t)
		var w := Iso.grid_to_world(info.get("grid", Vector2.ZERO))
		if info.get("visible", false) and rect.has_point(w):
			cand.append([w.distance_squared_to(centre), id])
	cand.sort()
	_detail.clear()
	for i in mini(cap, cand.size()):
		_detail[cand[i][1]] = true
	_groups = s.groups_at(t)
	_render_npcs(true)
	_update_effects(s, t)


func _view_rect() -> Rect2:
	if camera == null:
		return _world_bounds()
	var vp := get_viewport_rect().size / camera.zoom
	return Rect2(camera.get_screen_center_position() - vp * 0.5, vp)


func _render_npcs(all: bool) -> void:
	var s := render_sim()
	var t := render_time()
	var bubbles: bool = GraphicsProfile.params()["chat_bubbles"]
	for n in npcs:
		var id := n.npc_id
		if not _detail.has(id):
			if all and n.is_present():
				n.apply_render({"visible": false}, Vector2.ZERO, Vector2.ZERO, Vector2.INF, false)
			n.set_process(false)
			continue
		n.set_process(true)
		var info := s.render_info(id, t)
		var w := Iso.grid_to_world(info.get("grid", Vector2.ZERO))
		var wd := Iso.grid_to_world(info.get("grid", Vector2.ZERO) + info.get("dir", Vector2.ZERO)) - w
		var partner := Vector2.INF
		var talking := false
		var grp: Array = _groups.get(info.get("place", ""), [])
		if grp.size() > 1 and grp.has(id) and not info.get("walking", false):
			var i := grp.find(id)
			var other: String = grp[(i + 1) % grp.size()]
			partner = Iso.grid_to_world(s.render_info(other, t).get("grid", Vector2.ZERO))
			talking = bubbles and grp[int(t / 4.0) % grp.size()] == id
		n.apply_render(info, w, wd, partner, talking)


## Effects derived from the simulation state (VisualEventRouter): appear and
## disappear with what the inhabitants actually do right now.
func _update_effects(s: SettlementSim, t: float) -> void:
	var want := {}
	for e in VisualEventRouter.active_effects(s, t):
		if building_nodes.has(e["building_id"]):
			want[e["vfx"] + "|" + e["building_id"]] = e
	for key in _fx_nodes.keys():
		if not want.has(key):
			_fx_nodes[key].queue_free()
			_fx_nodes.erase(key)
	for key in want:
		if not _fx_nodes.has(key):
			var node := _make_effect(want[key])
			if node:
				_fx_nodes[key] = node


func _make_effect(e: Dictionary) -> Node2D:
	if _vfx_atlas == null:
		if not ResourceLoader.exists("res://assets/vfx/vfx_atlas.png"):
			return null
		_vfx_atlas = load("res://assets/vfx/vfx_atlas.png")
		_vfx_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/vfx/vfx_atlas.json"))
	var b: Building = building_nodes[e["building_id"]]
	var p := CPUParticles2D.new()
	var k := float(GraphicsProfile.params()["particles"])
	var frame_name := "smoke_light" if e["vfx"] == "chimney_smoke" else "spark"
	var r: Array = _vfx_meta["animations"][frame_name]["frames"][1]
	var at := AtlasTexture.new()
	at.atlas = _vfx_atlas
	at.region = Rect2(r[0], r[1], r[2], r[3])
	p.texture = at
	if e["vfx"] == "chimney_smoke":
		p.position = b.position + Vector2(10, -b.height * 0.95)
		p.amount = maxi(2, int(6 * k))
		p.lifetime = 3.0
		p.direction = Vector2(0.25, -1)
		p.spread = 10
		p.gravity = Vector2(4, -6)
		p.initial_velocity_min = 8
		p.initial_velocity_max = 14
		p.scale_amount_min = 0.12
		p.scale_amount_max = 0.22
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 0.85))
		ramp.set_color(1, Color(1, 1, 1, 0))
		p.color_ramp = ramp
	else:
		p.position = b.position + Vector2(18, -18)
		p.amount = maxi(2, int(5 * k))
		p.lifetime = 0.6
		p.explosiveness = 0.5
		p.direction = Vector2(0, -1)
		p.spread = 70
		p.gravity = Vector2(0, 200)
		p.initial_velocity_min = 40
		p.initial_velocity_max = 70
		p.scale_amount_min = 0.1
		p.scale_amount_max = 0.16
	p.z_index = 50
	p.name = "Fx_%s_%s" % [e["vfx"], e["building_id"]]
	objects.add_child(p)
	return p


## Opens an NPC's card with live information (connected before the
## InteractionService so the text is current).
func _on_interaction_requested(it: Interactable) -> void:
	if it and it.kind == "npc" and _npc_by_id.has(it.interaction_id) and sim:
		(_npc_by_id[it.interaction_id] as Npc).refresh_card(render_sim(), int(render_time()), _names)


func _on_interaction_action(interaction_id: String, action_id: String) -> void:
	if action_id != "talk" or not _npc_by_id.has(interaction_id) or sim == null:
		return
	var t := int(GameClock.get_utc_unix())
	sim.player_talk(interaction_id, t)
	var n: Npc = _npc_by_id[interaction_id]
	var mood := NpcBrain.mood(sim.needs_now(interaction_id, t))
	var first := str(n.record.get("name", "")).get_slice(" ", 0)
	var lines := ["%s nickt dir müde zu." % first, "%s grüßt kurz zurück." % first, "„Hallo! Schön, dich zu sehen“, sagt %s." % first, "%s lächelt: „Was für ein Tag!“" % first]
	EventBus.toast_requested.emit(lines[clampi(int(mood * 4.0), 0, 3)])
	n.refresh_card(sim, t, _names)
	persist()


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
