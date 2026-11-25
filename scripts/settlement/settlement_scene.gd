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
	_build_surroundings()
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
	if WorldState.authority:
		WorldState.authority.ensure_population(record)
	var roster: Array = record.get("npcs", [])
	if roster.is_empty():
		roster = NpcRoster.generate(record.get("settlement_id", ""), data.buildings, SettlementSim.load_config().get("founding_population", {}).get("composition", []))
		record["npcs"] = roster
	for b in data.buildings:
		_names[b.get("id", "")] = b.get("name", "")
	# Phase 3: bring the living world to NOW before anything is shown
	# (catch-up after absence is event-driven and invisible), then persist.
	sim = SettlementSim.create(record, data, int(GameClock.get_utc_unix()))
	if WorldState.authority:
		WorldState.authority.attach_hot(sim)   # tier S0/S1 while the scene is open
	sim.store()
	WorldState.save_world()
	_sync_npc_nodes()
	_sync_building_visuals()
	_update_lod(true)


## Building visuals follow the persistent Living-Assets states of the record.
func _sync_building_visuals() -> void:
	var profile := GraphicsProfile.current()
	for bid in building_nodes:
		(building_nodes[bid] as Building).apply_visual_state(VisualEventRouter.visual_state_of(record, bid), profile)


## One node per LIVING inhabitant: newcomers appear, the deceased leave.
func _sync_npc_nodes() -> void:
	var alive := {}
	for r in sim.roster:
		alive[r["npc_id"]] = true
		if not _npc_by_id.has(r["npc_id"]):
			var n := Npc.new()
			n.setup(r, _names, _building_type(str(r.get("employment", {}).get("workplace_id", r.get("workplace_id", "")))))
			objects.add_child(n)
			npcs.append(n)
			_npc_by_id[r["npc_id"]] = n
	for id in _npc_by_id.keys():
		if not alive.has(id):
			var n: Npc = _npc_by_id[id]
			npcs.erase(n)
			_npc_by_id.erase(id)
			_detail.erase(id)
			n.queue_free()


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


var surroundings: Surroundings


## The land around the settlement from the planet data (coast, mountains,
## forest, desert, snow …) – no black void at the edge. The climate summary
## is stored with the settlement for later weather and seasons.
func _build_surroundings() -> void:
	var terr := LocalTerrain.generate(record, data.size, 12)
	record["climate"] = terr.get("climate", {})
	record["surroundings_features"] = terr.get("features", [])
	surroundings = Surroundings.new()
	surroundings.name = "Surroundings"
	add_child(surroundings)
	move_child(surroundings, ground.get_index())
	surroundings.setup(terr, data.size)


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
	day_night.color = _interior_light() if interior else GameClock.get_ambient_color()


## Inside: daylight through the windows by day, warm lamp light at night.
func _interior_light() -> Color:
	var out := GameClock.get_ambient_color()
	var lum := (out.r + out.g + out.b) / 3.0
	var lamp := Color(0.9, 0.8, 0.68)
	return lamp.lerp(Color(1.0, 0.98, 0.94), clampf((lum - 0.45) / 0.4, 0.0, 1.0))


func _process(delta: float) -> void:
	# Cheap; keeps the time-of-day preview and dawn/dusk transitions fluid.
	day_night.color = _interior_light() if interior else GameClock.get_ambient_color()
	_update_occlusion(delta)
	if sim == null:
		return
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.25
		var n_before := sim.roster.size()
		sim.advance_to(int(GameClock.get_utc_unix()))
		if sim.roster.size() != n_before or sim.last_events.any(func(e): return e.get("kind", "") in ["died", "arrived", "born", "moved_in", "grown_up"]):
			_sync_npc_nodes()
		if sim.last_events.any(func(e): return e.get("kind", "") in ["building_condition", "fire"]):
			_sync_building_visuals()
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


func _exit_tree() -> void:
	persist()
	if sim and WorldState.authority:
		WorldState.authority.detach_hot(record.get("settlement_id", ""))


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
	for id in _detail:
		if _npc_by_id.has(id):
			var nd := s.needs_now(id, int(t))
			(_npc_by_id[id] as Npc).mood = NpcBrain.mood(nd)
			(_npc_by_id[id] as Npc).energy = float(nd.get("energy", 0.6))
	_render_npcs(true)
	_update_effects(s, t)


func _building_type(bid: String) -> String:
	for b in data.buildings:
		if b.get("id", "") == bid:
			return str(b.get("type", ""))
	return ""


func _view_rect() -> Rect2:
	if camera == null:
		return _world_bounds()
	var vp := get_viewport_rect().size / camera.zoom
	return Rect2(camera.get_screen_center_position() - vp * 0.5, vp)


func _render_npcs(all: bool) -> void:
	var s := render_sim()
	var t := render_time()
	var bubbles: bool = GraphicsProfile.params()["chat_bubbles"]
	var infos := {}
	for n in npcs:
		var id := n.npc_id
		if not _detail.has(id):
			if all and n.is_present():
				n.apply_render({"visible": false}, Vector2.ZERO, Vector2.ZERO, Vector2.INF, false)
			n.set_process(false)
			continue
		n.set_process(true)
		infos[id] = s.render_info(id, t)
	_assign_seats(infos)
	_avoid(infos)
	_update_doors(s, t)
	for n in npcs:
		var id := n.npc_id
		if not infos.has(id):
			continue
		var info: Dictionary = infos[id]
		var w := Iso.grid_to_world(info.get("grid", Vector2.ZERO))
		var wd := Iso.grid_to_world(info.get("grid", Vector2.ZERO) + info.get("dir", Vector2.ZERO)) - w
		var partner := Vector2.INF
		var talking := false
		var grp: Array = _groups.get(info.get("place", ""), [])
		if grp.size() > 1 and grp.has(id) and not info.get("walking", false):
			var i := grp.find(id)
			var other: String = grp[(i + 1) % grp.size()]
			partner = Iso.grid_to_world(infos[other].get("grid", Vector2.ZERO) if infos.has(other) else s.render_info(other, t).get("grid", Vector2.ZERO))
			talking = bubbles and grp[int(t / 4.0) % grp.size()] == id
		n.apply_render(info, w, wd, partner, talking)


## Doors open and close with the people passing through them: the opening
## follows the same door phase the NPC animation uses (open_door clip at
## 0.3–0.55 of the passage), the player's door sequence sets its own value.
var player_door := {}   # building id -> open 0..1 (player entering/leaving)


static func door_open_amount(door: String, f: float) -> float:
	if door == "enter":
		# opens while the hand reaches the door, stays open while passing,
		# closes once the person is inside
		if f < 0.3:
			return 0.0
		if f < 0.5:
			return (f - 0.3) / 0.2
		if f < 0.85:
			return 1.0
		return clampf(1.0 - (f - 0.85) / 0.15, 0.0, 1.0)
	if door == "exit":
		if f < 0.6:
			return clampf(f / 0.15, 0.0, 1.0)
		return clampf(1.0 - (f - 0.6) / 0.35, 0.0, 1.0)
	return 0.0


func _update_doors(s: SettlementSim, t: float) -> void:
	var want := {}
	for id in player_door:
		want[id] = float(player_door[id])
	for r in s.roster:
		var st: Dictionary = s.states.get(r["npc_id"], {})
		var tr: Dictionary = st.get("travel", {})
		if tr.is_empty():
			continue
		var info := s.render_info(r["npc_id"], t)
		var door := str(info.get("door", ""))
		if door == "":
			continue
		var place := str(tr["to"] if door == "enter" else tr["from"])
		var bid := str(s.nav.places.get(place, {}).get("building_id", ""))
		if bid != "":
			want[bid] = maxf(float(want.get(bid, 0.0)), door_open_amount(door, float(info.get("door_f", 0.0))))
	for bid in building_nodes:
		(building_nodes[bid] as Building).set_door_open("main", float(want.get(bid, 0.0)))


## Benches are used: people relaxing, chatting or on a break near a free
## bench sit down on it (one person per seat; presentation only).
const SEAT_ACTS := ["leisure", "socialize", "pause", "eat_out"]
var _seats: Array = []


func _seat_positions() -> Array:
	if _seats.is_empty() and data:
		for p in data.props:
			if p.get("kind", "") == "bench":
				var g: Vector2 = p.get("grid_v", Vector2.ZERO)
				_seats.append(g + Vector2(-0.18, 0.12))
				_seats.append(g + Vector2(0.18, 0.12))
	return _seats


func _assign_seats(infos: Dictionary) -> void:
	var free := {}
	for i in _seat_positions().size():
		free[i] = true
	var ids: Array = infos.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = infos[id]
		if not info.get("visible", false) or info.get("walking", false) or not info.get("act", "") in SEAT_ACTS:
			continue
		var best := -1
		var best_d := 2.2
		for i in free:
			var d: float = (_seats[i] as Vector2).distance_to(info["grid"])
			if d < best_d:
				best_d = d
				best = i
		if best >= 0:
			free.erase(best)
			info["grid"] = _seats[best]
			info["seat"] = true


## Local avoidance (presentation only – never changes the simulation):
## walkers keep to the right of their direction, so oncoming people pass
## each other, and anybody closer than a body width is pushed apart.
static func _avoid(infos: Dictionary) -> void:
	const LANE := 0.2
	const MIN_DIST := 0.42
	var ids: Array = infos.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = infos[id]
		if info.get("visible", false) and info.get("walking", false):
			var d: Vector2 = info.get("dir", Vector2.ZERO)
			if d.length_squared() > 0.000001:
				info["grid"] = info["grid"] + Vector2(-d.y, d.x).normalized() * LANE
	for iter in 2:
		for i in ids.size():
			var a: Dictionary = infos[ids[i]]
			if not a.get("visible", false):
				continue
			for j in range(i + 1, ids.size()):
				var b: Dictionary = infos[ids[j]]
				if not b.get("visible", false) or (a.get("seat", false) and b.get("seat", false)):
					continue
				var delta: Vector2 = b["grid"] - a["grid"]
				var dist := delta.length()
				if dist < MIN_DIST:
					var push := (delta.normalized() if dist > 0.0001 else Vector2(1, 0).rotated(float(i))) * (MIN_DIST - dist) * 0.5
					# standing people hold their spot, walkers step aside
					var a_moves: bool = a.get("walking", false) or not b.get("walking", false)
					var b_moves: bool = b.get("walking", false) or not a.get("walking", false)
					if a_moves:
						a["grid"] = a["grid"] - push * (1.0 if b_moves else 2.0)
					if b_moves:
						b["grid"] = b["grid"] + push * (1.0 if a_moves else 2.0)


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
	_last_interactable = it
	if it and it.kind == "npc" and _npc_by_id.has(it.interaction_id) and sim:
		(_npc_by_id[it.interaction_id] as Npc).refresh_card(render_sim(), int(render_time()), _names)
	elif it and sim and building_nodes.has(it.interaction_id.trim_suffix(":door")):
		_refresh_building_card(it)


var _last_interactable: Interactable


var _base_cards: Dictionary = {}   # building id -> [text, actions] from the template


## Phase 4: live building cards; the town hall is the administration.
func _refresh_building_card(it: Interactable) -> void:
	var bid := it.interaction_id.trim_suffix(":door")
	if not _base_cards.has(bid):
		_base_cards[bid] = [it.text, it.actions.duplicate()]
	var t := int(GameClock.get_utc_unix())
	var ty := ""
	for b in data.buildings:
		if b.get("id", "") == bid:
			ty = str(b.get("type", ""))
	if ty == "town_hall":
		it.text = SettlementReport.town_hall_text(record, data, sim.config, t, sim.offset_min())
		it.actions = _base_cards[bid][1] + SettlementReport.admin_actions(record, LocalProfile.player_id)
	else:
		it.text = SettlementReport.building_text(record, data, sim.config, bid, _base_cards[bid][0], t, sim.offset_min())


func _on_interaction_action(interaction_id: String, action_id: String) -> void:
	if action_id.begins_with("admin_") and sim and WorldState.client:
		var cmd := SettlementReport.admin_command(record, action_id)
		if not cmd.is_empty():
			var res := WorldState.client.submit(cmd)
			EventBus.toast_requested.emit("Die Verwaltung hat entschieden." if res.get("ok", false) else "Abgelehnt: " + str(res.get("reason", "")))
			persist()
		return
	if action_id == "enter":
		enter_building(interaction_id.trim_suffix(":door"))
		return
	if action_id == "leave":
		leave_building()
		return
	if action_id != "talk" and not action_id.begins_with("talk:"):
		# object interaction: the player plays the action's clip (shared
		# library with the NPCs); sit/lie take the position first
		var a := ActionLibrary.get_action(action_id)
		if a.has("opens") and a["opens"] == "town_hall" and building_nodes.has("bld_town_hall"):
			var b: Building = building_nodes["bld_town_hall"]
			_refresh_building_card(b._interactable)
			EventBus.interaction_opened.emit(b._interactable.to_info())
		var it := _last_interactable
		if not a.is_empty() and it and is_instance_valid(it):
			var point = it.get_meta("pose_point", null)
			if point is Vector2:
				point = it.get_parent().to_global(point) if it.get_parent() is Node2D and it.get_meta("pose_local", true) else point
			if a.has("pose") and not point is Vector2:
				point = it.global_position
			player.perform(a, it.global_position, point)
		return
	if not _npc_by_id.has(interaction_id) or sim == null:
		player.perform({"clip": "greet"}, player.global_position + Vector2(0, -10))
		return
	var t := int(GameClock.get_utc_unix())
	var n: Npc = _npc_by_id[interaction_id]
	player.perform({"clip": "greet"}, n.global_position)
	n.rig.play("talk" if action_id != "talk" else "greet", true)
	var topic := action_id.get_slice(":", 1) if action_id.begins_with("talk:") else "chat"
	# conversations are commands to the world authority (Phase 5; server-capable)
	var res := {}
	if WorldState.client:
		res = WorldState.client.submit({"kind": "talk", "settlement_id": record.get("settlement_id", ""),
			"payload": {"npc_id": interaction_id, "topic": topic, "name": LocalProfile.display_name}})
	if res.get("ok", false) and res.has("result"):
		EventBus.toast_requested.emit(str(res["result"]["line"]))
	else:
		sim.player_talk(interaction_id, t)
		var mood := NpcBrain.mood(sim.needs_now(interaction_id, t))
		var first := str(n.record.get("name", "")).get_slice(" ", 0)
		var lines := ["%s nickt dir müde zu." % first, "%s grüßt kurz zurück." % first, "„Hallo! Schön, dich zu sehen“, sagt %s." % first, "%s lächelt: „Was für ein Tag!“" % first]
		EventBus.toast_requested.emit(lines[clampi(int(mood * 4.0), 0, 3)])
	n.refresh_card(sim, t, _names)
	EventBus.interaction_opened.emit(n._interactable.to_info())     # card with the new state and topics
	persist()


# --- interiors: entering and leaving buildings ----------------------------------

var interior: InteriorScene
var _inside_bid := ""
var _outside_bounds := Rect2()
var _outside_zoom := Vector2.ONE
var _door_busy := false
const INTERIOR_OFFSET := Vector2(0, 60000)   # interiors live far below the town


## The player opens the door (clip event), the door swings open, the player
## steps through and fades; the interior is loaded and the player stands
## inside the entrance; the outside door closes behind.
func enter_building(bid: String) -> void:
	if _door_busy or interior != null or not building_nodes.has(bid):
		return
	var b: Building = building_nodes[bid]
	if not InteriorScene.has_layout(b.sprite_key) or not InteriorScene.assets_available():
		EventBus.toast_requested.emit("Dieser Innenraum folgt später.")
		return
	_door_busy = true
	player.input_enabled = false
	var door := b.door_world_point("main")
	player._face_towards(door)
	var rig: CharacterRig = player._visual.rig
	if rig:
		rig.play("open_door", true)
	await get_tree().create_timer(0.3).timeout          # hand reaches the door (clip event frame)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: player_door[bid] = v, 0.0, 1.0, 0.25)
	await tw.finished
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(player, "global_position", door + Vector2(0, -4), 0.45)
	tw2.tween_property(player, "modulate:a", 0.0, 0.45)
	if rig:
		rig.play("walk")
	await tw2.finished
	# the room
	interior = InteriorScene.create(b.sprite_key, _staff_on_duty(bid), SettlementCore.mix(str(record.get("settlement_id", "")) + "#" + bid), _interior_wealth())
	interior.position = INTERIOR_OFFSET
	add_child(interior)
	_inside_bid = bid
	_outside_return = b.door_world_point("main") + Vector2(0, 26)
	player.reparent(interior.objects)
	player.position = interior.spawn_point
	player.move_y_scale = InteriorScene.MOVE_Y_SCALE
	player._visual.scale = Vector2.ONE * InteriorScene.PERSON_SCALE
	player.facing = Iso.facing_index(Vector2(0, -1))     # looking into the room
	_outside_bounds = camera.bounds
	_outside_zoom = camera.zoom
	camera.bounds = interior.bounds()
	camera.fit_view = true
	camera.snap_to_target()
	objects.visible = false
	ground.visible = false
	surroundings.visible = false
	ground_lights.visible = false
	var tw3 := create_tween().set_parallel(true)
	tw3.tween_property(player, "modulate:a", 1.0, 0.35)
	tw3.tween_method(func(v: float) -> void: player_door[bid] = v, 1.0, 0.0, 0.4)
	await tw3.finished
	player_door.erase(bid)
	player.input_enabled = true
	_door_busy = false


var _outside_return := Vector2.ZERO


## Prosperity 0..1 for the furnishing variant (until the economy exists,
## Phase 6: from the population and the stock of food).
func _interior_wealth() -> float:
	var pop := SettlementCore.alive_npcs(record).size() if record.has("npcs") else 10
	var stocks: Dictionary = record.get("core", {}).get("stocks", {})
	var food_days := float(stocks.get("food", 0.0)) / maxf(1.0, float(pop))
	return clampf(0.25 + 0.4 * minf(1.0, pop / 40.0) + 0.3 * clampf(food_days / 20.0, 0.0, 1.0), 0.0, 1.0)


func leave_building() -> void:
	if _door_busy or interior == null:
		return
	_door_busy = true
	player.input_enabled = false
	var rig: CharacterRig = player._visual.rig
	player._face_towards(interior.to_global(interior.exit_point))
	if rig:
		rig.play("open_door", true)
	await get_tree().create_timer(0.3).timeout
	var tw := create_tween().set_parallel(true)
	tw.tween_property(player, "position", interior.exit_point, 0.4)
	tw.tween_property(player, "modulate:a", 0.0, 0.4)
	await tw.finished
	var bid := _inside_bid
	var b: Building = building_nodes.get(bid)
	objects.visible = true
	ground.visible = true
	surroundings.visible = true
	ground_lights.visible = true
	player.reparent(objects)
	player.move_y_scale = Iso.MOVE_Y_SCALE
	player._visual.scale = Vector2.ONE
	var door := b.door_world_point("main") if b else _outside_return
	player.global_position = door + Vector2(0, -2)
	camera.bounds = _outside_bounds
	camera.fit_view = false
	camera.snap_to_target()
	interior.queue_free()
	interior = null
	_inside_bid = ""
	player_door[bid] = 1.0
	player.facing = 6
	if rig:
		rig.play("walk")
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(player, "modulate:a", 1.0, 0.3)
	tw2.tween_property(player, "global_position", _outside_return, 0.45)
	await tw2.finished
	if rig:
		rig.play("idle")
	var tw3 := create_tween()
	tw3.tween_method(func(v: float) -> void: player_door[bid] = v, 1.0, 0.0, 0.35)
	await tw3.finished
	player_door.erase(bid)
	player.input_enabled = true
	_door_busy = false


func is_inside() -> bool:
	return interior != null


## People whose shift at this building is running right now (duty roster).
func _staff_on_duty(bid: String) -> Array:
	var out := []
	if sim == null:
		return out
	var t := int(GameClock.get_utc_unix())
	for r in sim.roster:
		var sh: Array = NpcBrain.next_shift(r, t, sim._ctx.get(r["npc_id"], {}))
		if sh.is_empty() or str(sh[2]) != bid or int(sh[0]) > t:
			continue
		var info := sim.render_info(r["npc_id"], float(t))
		if info.get("walking", false):
			continue
		out.append({"npc_id": r["npc_id"], "name": r.get("name", ""), "appearance": r.get("appearance", {}),
			"role_label": str(r.get("profession", {}).get("title", "")), "text": "Im Dienst: " + sim.schedule_text(r, t)})
		if out.size() >= 2:
			break
	return out


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
			if n is Building:
				for d in (n as Building)._doors.values():
					(d["sprite"] as Sprite2D).material = _occluder_material   # doors fade with the building
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
