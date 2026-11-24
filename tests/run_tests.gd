extends Node
## Headless test suite for Phase 1.
##
## Run:  godot --headless --path . res://tests/test_runner.tscn
## (a scene, not "-s", so autoloads exist exactly as in the game)
## Exit code 0 = all passed, 1 = failures. Used locally and in CI.

var _passed := 0
var _failed: PackedStringArray = []
var _main: Node


func _ready() -> void:
	_run.call_deferred()


func check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed.append(label)
		print("  FAIL ", label)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	# Headless windows default to 64x64; use the real logical size.
	get_window().size = Vector2i(960, 540)
	await get_tree().process_frame
	var registry: Node = get_tree().root.get_node("AssetRegistry")
	var clock: Node = get_tree().root.get_node("GameClock")
	var bus: Node = get_tree().root.get_node("EventBus")

	print("[assets]")
	check(registry.get_violations().is_empty(), "manifest has no art-direction violations")
	var summary: Dictionary = registry.get_status_summary()
	check(summary["total"] > 10, "manifest lists asset entries (%d)" % summary["total"])
	# Art-direction guard: foreign vendor must be rejected outdoors, allowed indoors.
	registry._manifest["sources"]["test_foreign"] = {"vendor": "someone_else"}
	registry._manifest["entries"]["exterior.building.test"] = {"source": "test_foreign", "path": "res://icon.svg"}
	registry._manifest["entries"]["interior.test"] = {"source": "test_foreign", "path": "res://icon.svg"}
	check(not registry.is_allowed("exterior.building.test"), "guard blocks non-Penzilla exterior asset")
	check(registry.get_texture("exterior.building.test") == null, "blocked exterior asset is not loaded")
	check(registry.is_allowed("interior.test"), "guard allows other vendors for interiors")
	registry.reload()

	print("[empty planet]")
	var world: Node = get_tree().root.get_node("WorldState")
	var profile: Node = get_tree().root.get_node("LocalProfile")
	# Isolated storage: the real local world is never touched by tests.
	world.use_storage("user://test_world_state.json", true)
	var genesis: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/genesis.json"))
	check((genesis["settlements"] as Array).is_empty(), "genesis: planet starts with zero settlements")
	check(genesis["rules"]["npc_only_settlements_allowed"] == false, "genesis: NPC-only settlements disallowed")
	check(world.is_planet_empty(), "world state starts empty")
	var tpl := "res://data/settlement_templates/founding_basic.json"
	check(world.found_settlement(tpl, "").is_empty(), "founding without a founder is rejected")
	check(world.found_settlement(tpl, "npc_abc123").is_empty(), "an NPC cannot found a settlement")
	check(world.is_planet_empty(), "rejected foundings leave the planet empty")

	print("[data]")
	var data := SettlementData.load_from_file(tpl)
	check(data != null, "founding template loads")
	check(data.ids.get("settlement_id", "") == "" and not data.is_founded(), "a template is not a settlement (no ID, no founder)")
	var problems := data.validate()
	for p in problems:
		print("       ", p)
	check(problems.is_empty(), "template layout is valid")
	check(Iso.world_to_grid(Iso.grid_to_world(Vector2(3.5, 7.25))).distance_to(Vector2(3.5, 7.25)) < 0.001, "iso projection round trip")
	check(Iso.facing_index(Vector2(1, 0)) == 0 and Iso.facing_index(Vector2(0, -1)) == 2 and Iso.facing_index(Vector2(-1, 1)) == 5, "8-way facing")

	print("[clock]")
	# 2026-06-21 12:00 UTC, offset +120 min (Berlin summer time).
	clock.fixed_utc_unix = float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 6, "day": 21, "hour": 12, "minute": 0, "second": 0}))
	clock.utc_offset_minutes = 120
	clock.is_dst = true
	check(clock.format_time() == "14:00", "local time = UTC + zone offset (14:00 CEST)")
	check(clock.get_night_factor() < 0.05, "midsummer afternoon is daylight")
	var times: Vector2 = clock.get_sun_times()
	check(times.x > 4.5 and times.x < 5.6 and times.y > 21.0 and times.y < 22.0, "midsummer sunrise/sunset plausible (%.2f / %.2f)" % [times.x, times.y])
	clock.fixed_utc_unix = float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 12, "day": 21, "hour": 22, "minute": 0, "second": 0}))
	clock.utc_offset_minutes = 60
	clock.is_dst = false
	check(clock.format_time() == "23:00" and clock.get_night_factor() > 0.95, "winter night 23:00 CET is dark")
	var wt: Vector2 = clock.get_sun_times()
	check(wt.x > 7.8 and wt.x < 8.9, "winter sunrise around 08:20 (%.2f)" % wt.x)
	clock.utc_offset_minutes = -300
	check(clock.format_time() == "17:00", "other time zone (UTC-5) shows its own local time")
	clock.preview_minute_of_day = 2 * 60.0
	check(clock.get_hour() == 2 and clock.get_night_factor() > 0.9, "time-of-day preview overrides visuals")
	clock.preview_minute_of_day = -1.0
	clock.fixed_utc_unix = -1.0
	clock.detect_timezone()
	check(absf(clock.get_utc_unix() - Time.get_unix_time_from_system()) < 2.0, "real clock follows system UTC")

	print("[scene]")
	# Tests use a ready-made character so the game starts in the world.
	profile.character = {}
	if root_has_character_assets():
		profile.set_character(get_tree().root.get_node("CharacterCatalog").default_appearance(), "Test")
	_main = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await frames(5)
	var settlement: SettlementScene = _main.get_node("Settlement")
	var hud: Hud = _main.get_node("HUD")
	var player: Player = settlement.player
	check(player != null, "player spawned")
	var building_count := 0
	for c in settlement.objects.get_children():
		if c is Building:
			building_count += 1
	check(building_count == data.buildings.size(), "all %d buildings instantiated" % data.buildings.size())
	check(settlement.camera.is_current(), "camera is current")
	check(hud.get_settlement_label() == "Lichtfeld", "HUD shows settlement name")
	var founded: Array = world.get_settlements()
	check(founded.size() == 1, "first launch founds exactly one settlement")
	check(founded[0]["founder_player_id"] == profile.player_id and settlement.just_founded, "local player is the founder")
	check(founded[0]["order_on_planet"] == 1, "it is the first settlement on the planet")
	check(Ids.has_prefix(settlement.data.ids.get("settlement_id", ""), "stl") and settlement.data.is_founded(), "founded settlement has generated ID")
	check(not settlement.data.notice_board.get("text", "").contains("{settlement}"), "template tokens are filled in")
	check(world.validate().is_empty(), "no NPC-only settlements exist")

	print("[street planning]")
	var planner := StreetPlanner.new(settlement.data)
	var items: Array = settlement.street_items
	var kinds := {}
	for it in items:
		kinds[it["kind"]] = int(kinds.get(it["kind"], 0)) + 1
	print("       ", kinds)
	var plan_problems := planner.validate(items)
	for p in plan_problems:
		print("       ", p)
	check(plan_problems.is_empty(), "street furniture follows placement rules")
	check(int(kinds.get("street_lamp", 0)) >= 8 and int(kinds.get("hydrant", 0)) >= 3, "town has lamps and hydrants")
	check(kinds.has("bus_stop") and kinds.has("street_sign"), "bus stop and street sign placed")
	var bad := [{"kind": "hydrant", "grid_v": Vector2(12.5, 5.5)}, {"kind": "street_lamp", "grid_v": Vector2(11.8, 5.5), "road_dir": Vector2i(-1, 0)}]
	check(planner.validate(bad).size() >= 2, "validator rejects a hydrant on the road and a lamp facing away")

	print("[movement]")
	var start := player.global_position
	Input.action_press("move_right")
	await frames(30)
	Input.action_release("move_right")
	check(player.global_position.x > start.x + 40.0, "keyboard moves player right (%.0f px)" % (player.global_position.x - start.x))
	start = player.global_position
	bus.move_vector_changed.emit(Vector2(0, 1))
	await frames(30)
	bus.move_vector_changed.emit(Vector2.ZERO)
	check(player.global_position.y > start.y + 20.0, "joystick vector moves player down")
	await frames(2)
	start = player.global_position
	await frames(10)
	check(player.global_position.distance_to(start) < 0.5, "player stops without input")

	print("[tap to move]")
	player.global_position = Iso.grid_to_world(Vector2(12.5, 19.5))
	await frames(2)
	settlement.camera.snap_to_target()
	await frames(1)
	var goal := Iso.grid_to_world(Vector2(12.5, 22.5))
	var screen := _world_to_screen(settlement.camera, goal)
	settlement.handle_tap(screen)
	var d0 := player.global_position.distance_to(goal)
	await frames(90)
	check(player.global_position.distance_to(goal) < d0 * 0.3, "tap-to-move walks towards target")

	print("[collision]")
	# Walk into the town hall from the south; must not end inside it.
	player.global_position = Iso.grid_to_world(Vector2(10.5, 8.8))
	await frames(2)
	Input.action_press("move_up")
	await frames(60)
	Input.action_release("move_up")
	var g := Iso.world_to_grid(player.global_position)
	check(not (g.x > 9.1 and g.x < 10.9 and g.y > 6.1 and g.y < 7.9), "building blocks the player")

	print("[occlusion]")
	var town_hall: Node2D = settlement.objects.get_node("bld_town_hall")
	player.global_position = Iso.grid_to_world(Vector2(9.6, 5.5))
	await frames(40)
	check(settlement.is_occluding(town_hall) and settlement.occlusion_strength(town_hall) > 0.95, "building in front of the player fades (x-ray hole)")
	player.global_position = Iso.grid_to_world(Vector2(10.5, 8.7))
	await frames(40)
	check(not settlement.is_occluding(town_hall) and settlement.occlusion_strength(town_hall) < 0.05, "building behind the player stays opaque")

	print("[interaction]")
	var opened: Array = []
	bus.interaction_opened.connect(func(info: Dictionary) -> void: opened.append(info))
	player.global_position = Iso.grid_to_world(Vector2(10.95, 11.05))
	await frames(4)
	var focused := player.get_focused_interactable()
	check(focused != null and focused.kind == "notice_board", "notice board gets focus when near")
	check(hud.interact_button.visible, "interact button visible")
	bus.interact_pressed.emit()
	await frames(3)
	check(opened.size() == 1 and opened[0].get("title", "") == "Lichtfeld" and String(opened[0].get("text", "")).contains("von dir gegründet"), "notice board names you as founder")
	check(hud.is_panel_open(), "HUD panel is open")
	player.global_position = Iso.grid_to_world(Vector2(18.5, 14.5))
	await frames(4)
	check(not hud.is_panel_open(), "panel closes when walking away")

	# Tap on a building -> walk there and open it.
	opened.clear()
	player.global_position = Iso.grid_to_world(Vector2(9.5, 17.5))
	await frames(2)
	settlement.camera.snap_to_target()
	await frames(1)
	var home_pos := Iso.grid_to_world(Vector2(10.5, 15.5)) + Vector2(0, -20)
	settlement.handle_tap(_world_to_screen(settlement.camera, home_pos))
	await frames(150)
	check(opened.size() == 1 and opened[0].get("id", "") == "bld_player_home", "tapping a building walks there and opens it")
	var toasts: Array = []
	bus.toast_requested.connect(func(t: String) -> void: toasts.append(t))
	bus.interaction_action.emit("bld_player_home", "rest")
	check(toasts.size() > 0, "rest action responds without skipping real time")
	hud.close_panel()

	print("[camera]")
	var cam := settlement.camera
	var z := cam.zoom.x
	cam.zoom_at(1.5, Vector2(480, 270))
	check(cam.zoom.x > z, "pinch/wheel zoom increases zoom")
	cam.zoom_at(100.0, Vector2(480, 270))
	check(is_equal_approx(cam.zoom.x, CameraRig.MAX_ZOOM), "zoom is clamped")
	cam.set_target_zoom(CameraRig.DEFAULT_ZOOM)
	var cp := cam.position
	cam.pan_screen(Vector2(-200, 0))
	check(cam.free_pan and cam.position.x > cp.x, "drag pans camera")
	cam.recenter()
	check(not cam.free_pan, "recenter returns to follow mode")

	print("[touch gestures]")
	var taps: Array = []
	var pinches: Array = []
	hud.gesture.tapped.connect(func(p: Vector2) -> void: taps.append(p))
	hud.gesture.pinched.connect(func(f: float, _c: Vector2) -> void: pinches.append(f))
	var vp_size := hud.root.get_viewport_rect().size
	var world_pt := Vector2(vp_size.x * 0.5, vp_size.y * 0.6)
	var probe := InputEventMouseMotion.new()
	probe.position = world_pt
	get_tree().root.push_input(probe)
	await get_tree().process_frame
	var hovered := get_viewport().gui_get_hovered_control()
	check(hovered == hud.gesture, "world area is covered only by gesture surface (got %s)" % (hovered.get_path() if hovered else "null"))
	_touch(0, world_pt, true)
	await get_tree().process_frame
	_touch(0, world_pt, false)
	await get_tree().process_frame
	check(taps.size() == 1, "touch tap on world reaches gesture surface")
	# The tap may have started a walk to an object; stop it and close panels.
	settlement.player.cancel_move_target()
	hud.close_panel()
	await get_tree().process_frame
	_touch(0, world_pt + Vector2(-40, 0), true)
	_touch(1, world_pt + Vector2(40, 0), true)
	await get_tree().process_frame
	_drag(0, world_pt + Vector2(-80, 0), Vector2(-40, 0))
	_drag(1, world_pt + Vector2(80, 0), Vector2(40, 0))
	await get_tree().process_frame
	_touch(0, world_pt + Vector2(-80, 0), false)
	_touch(1, world_pt + Vector2(80, 0), false)
	await get_tree().process_frame
	check(pinches.size() > 0 and pinches.back() > 1.0, "two-finger spread produces zoom-in pinch")
	check(taps.size() == 1, "pinch is not mistaken for a tap")
	# A touch on a HUD button must not reach the world.
	var menu_btn: Control = hud.root.get_node("TopRight").get_child(1).get_child(0)
	var btn_center := menu_btn.get_global_rect().get_center()
	_touch(0, btn_center, true)
	await get_tree().process_frame
	_touch(0, btn_center, false)
	await get_tree().process_frame
	check(taps.size() == 1, "touch on HUD button does not tap the world")
	# Joystick multi-touch: finger 0 on stick, finger 1 on interact button.
	hud.joystick.visible = true
	await get_tree().process_frame
	var stick_vectors: Array = []
	bus.move_vector_changed.connect(func(v: Vector2) -> void: stick_vectors.append(v))
	var jr := hud.joystick.get_global_rect()
	_touch(0, jr.get_center(), true)
	_drag(0, jr.get_center() + Vector2(50, 0), Vector2(50, 0))
	await get_tree().process_frame
	check(stick_vectors.size() > 0 and stick_vectors.back().x > 0.5, "joystick reports drag direction")
	player.global_position = Iso.grid_to_world(Vector2(10.95, 11.05))
	await frames(4)
	var interacts := [0]
	bus.interact_pressed.connect(func() -> void: interacts[0] += 1)
	var ib := hud.interact_button.get_global_rect().get_center()
	_touch(1, ib, true)
	await get_tree().process_frame
	_touch(1, ib, false)
	_touch(0, jr.get_center() + Vector2(50, 0), false)
	await get_tree().process_frame
	check(interacts[0] == 1, "interact button works while joystick is held (multi-touch)")
	check(stick_vectors.back() == Vector2.ZERO, "joystick resets on release")

	print("[relaunch]")
	_main.queue_free()
	await get_tree().process_frame
	world.load_world()
	_main = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await frames(3)
	var again: SettlementScene = _main.get_node("Settlement")
	check(not again.just_founded and world.get_settlements().size() == 1, "relaunch reuses the founded settlement")
	check(again.data.ids.get("settlement_id") == founded[0]["settlement_id"], "settlement ID is persistent")

	print("")
	print("Passed: %d  Failed: %d" % [_passed, _failed.size()])
	for f in _failed:
		print("  - ", f)
	get_tree().quit(1 if _failed.size() > 0 else 0)


func root_has_character_assets() -> bool:
	return get_tree().root.get_node("CharacterCatalog").is_available()


func _world_to_screen(cam: CameraRig, world: Vector2) -> Vector2:
	return (world - cam.global_position) * cam.zoom.x + cam.get_viewport_rect().size * 0.5


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	get_tree().root.push_input(e)


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = rel
	get_tree().root.push_input(e)
