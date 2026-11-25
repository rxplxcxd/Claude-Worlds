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

	print("[geography]")
	var geo: Node = get_tree().root.get_node("Geography")
	var planet: PlanetData = geo.planet()
	check(planet != null, "baked planet loads (data/world/planet)")
	check(planet.continents.size() >= 4 and planet.continents.size() <= 7, "planet has 4-7 continents (%d)" % planet.continents.size())
	check(planet.regions.size() >= 100, "planet has many regions (%d)" % planet.regions.size())
	var land_without_region := 0
	var land_cells := 0
	for i in planet.biome.size():
		if planet.is_land(i):
			land_cells += 1
			if planet.region_of[i] == 0 or planet.continent_of[i] == 0:
				land_without_region += 1
	var land_share := float(land_cells) / planet.biome.size()
	check(land_without_region == 0, "every land cell belongs to a region and a continent")
	check(land_share > 0.2 and land_share < 0.5, "sensible land/sea ratio (%.0f%% of cells)" % (land_share * 100.0))
	var region_ids := {}
	var in_continents := 0
	var all_wild := true
	for r in planet.regions:
		region_ids[r["region_id"]] = true
		all_wild = all_wild and r["development"] == "wild" and r["territory_id"] == ""
	check(all_wild, "genesis: every region is wild and unclaimed (nature only)")
	for c in planet.continents:
		in_continents += (c["region_ids"] as Array).size()
	check(region_ids.size() == planet.regions.size() and in_continents == planet.regions.size(), "region IDs unique, every region on a continent")
	var terrain_kinds := {}
	for r in planet.regions:
		terrain_kinds[r["terrain"]] = true
	check(terrain_kinds.size() >= 6, "varied terrain (%s)" % ", ".join(terrain_kinds.keys()))
	# Determinism: regenerating from genesis gives byte-identical baked files.
	var spec: Dictionary = genesis["planet"].duplicate()
	spec["planet_id"] = genesis["planet_id"]
	spec["planet_name"] = genesis["planet_name"]
	var regen := PlanetGenerator.new().generate(spec)
	regen.save_to(ProjectSettings.globalize_path("user://planet_check"))
	var bake_same := FileAccess.get_file_as_bytes("user://planet_check/planet_cells.bin") == FileAccess.get_file_as_bytes("res://data/world/planet/planet_cells.bin") \
			and FileAccess.get_file_as_string("user://planet_check/planet.json") == FileAccess.get_file_as_string("res://data/world/planet/planet.json")
	check(bake_same, "baked planet matches the generator (seed %d, v%d)" % [planet.seed, planet.generator_version])
	# Coordinates.
	var ll := Geo.from_vec3(Geo.to_vec3(48.5, -120.25))
	check(absf(ll.x - 48.5) < 0.001 and absf(ll.y + 120.25) < 0.001, "lat/lon <-> 3D round trip")
	check(absf(Geo.distance_km(0, 0, 0, 90, 4000.0) - PI * 2000.0) < 0.5, "great-circle distance")
	check(planet.cell_of(89.9, 179.9) < planet.biome.size() and planet.cell_of(-89.9, -179.9) >= 0, "cell lookup clamps at the poles and date line")
	# Site rating (Paket 2.1: no geographic bans, difficulty instead).
	var ocean_cell := -1
	var ice_cell := -1
	var polar_land := -1
	for i in planet.biome.size():
		if ocean_cell < 0 and planet.biome[i] == PlanetData.Biome.OCEAN:
			ocean_cell = i
		if ice_cell < 0 and planet.biome[i] == PlanetData.Biome.ICE:
			var ill := planet.cell_lat_lon(i)
			if planet.is_land(planet.cell_of(ill.x + 0.3, ill.y)) and planet.is_land(planet.cell_of(ill.x - 0.3, ill.y)):
				ice_cell = i
		if polar_land < 0 and planet.is_land(i) and absf(planet.cell_lat_lon(i).x) > 66.0:
			polar_land = i
	var o_ll := planet.cell_lat_lon(ocean_cell)
	check(not geo.rate_site(o_ll.x, o_ll.y, [], [])["valid"], "founding on water is not possible (no land)")
	check(ice_cell >= 0 and polar_land >= 0, "planet has ice and polar land to test with")
	var i_ll := planet.cell_lat_lon(ice_cell)
	var ice_site: Dictionary = geo.rate_site(i_ll.x, i_ll.y, [], [])
	check(ice_site["valid"] and int(ice_site["difficulty"]["index"]) >= 2, "ice is settleable, rated %s" % ice_site["difficulty"].get("class", "?"))
	var p_ll := planet.cell_lat_lon(polar_land)
	var polar_site: Dictionary = geo.rate_site(p_ll.x, p_ll.y, [], [])
	check(polar_site["valid"], "no latitude limit: polar land at %.1f° is settleable (%s)" % [p_ll.x, polar_site["difficulty"].get("class", "?")])
	var best: Dictionary = geo.best_site([], [])
	check(best.get("valid", false) and int(best["score"]) >= 50, "best free site is valid and well rated (%d)" % best.get("score", 0))
	check(best["difficulty"]["class"] in ["leicht", "mittel"], "best site is an easy/medium start (%s)" % best["difficulty"]["class"])
	var bs: Dictionary = best["sample"]
	var R := planet.radius_km

	print("[territory geometry]")
	var sq := TerritoryGeometry.start_square(10.0, 20.0, R)
	var sv := Geo.ring_vectors(sq)
	check(absf(Geo.ring_area_km2(sq, R) - 1.0) < 0.01, "start territory is 1 km² (%.4f)" % Geo.ring_area_km2(sq, R))
	check(absf(sv[0].angle_to(sv[1]) * R - 1.0) < 0.005 and absf(sv[1].angle_to(sv[2]) * R - 1.0) < 0.005, "start square sides are 1 km")
	var pole_sq := TerritoryGeometry.start_square(89.999, 0.0, R)
	check(absf(Geo.ring_area_km2(pole_sq, R) - 1.0) < 0.02, "start square works at the pole")
	var far := Geo.offset(10.0, 20.0, 22.0, 0.0, R)
	var d22 := Geo.ring_distance_km(sv, Geo.ring_vectors(TerritoryGeometry.start_square(far.x, far.y, R)), R)
	check(absf(d22 - 21.0) < 0.05, "border-to-border distance, not centre distance (22 km centres → %.2f km)" % d22)
	var diag := Geo.offset(10.0, 20.0, 15.0, 15.0, R)
	var dd := Geo.ring_distance_km(sv, Geo.ring_vectors(TerritoryGeometry.start_square(diag.x, diag.y, R)), R)
	check(absf(dd - Vector2(14.0, 14.0).length()) < 0.1, "diagonal neighbours: corner-to-corner distance (%.2f km)" % dd)
	var a_dl := TerritoryGeometry.start_square(0.0, 179.995, R)
	var b_dl := TerritoryGeometry.start_square(0.0, -179.75, R)
	var expected := Geo.distance_km(0.0, 179.995, 0.0, -179.75, R) - 1.0
	check(absf(Geo.ring_distance_km(Geo.ring_vectors(a_dl), Geo.ring_vectors(b_dl), R) - expected) < 0.05, "distance correct across the date line")
	var near_sq := TerritoryGeometry.start_square(Geo.offset(10.0, 20.0, 0.5, 0.0, R).x, Geo.offset(10.0, 20.0, 0.5, 0.0, R).y, R)
	check(Geo.rings_overlap(sv, Geo.ring_vectors(near_sq)) and Geo.ring_distance_km(sv, Geo.ring_vectors(near_sq), R) == 0.0, "overlapping squares are detected")
	check(GeoIndex.token(10.0, 20.0) == GeoIndex.token(10.0, 20.0) and GeoIndex.cover(10.0, 20.0, 21.5, R).has(GeoIndex.token(10.0, 20.0)), "spatial index token and cover")
	var t_here := TerritoryGeometry.make_territory("ter_a", "stl_a", "plr_a", bs["lat"], bs["lon"], R, 0)
	var far_cover := GeoIndex.cover(Geo.offset(bs["lat"], bs["lon"], 900.0, 0.0, R).x, Geo.offset(bs["lat"], bs["lon"], 900.0, 0.0, R).y, 21.5, R)
	check(not GeoIndex.shares_cell(t_here["cover_l8"], far_cover), "index skips territories 900 km away")
	# 20-km founding rule against a territory at the best site.
	var sts := [{"settlement_id": "stl_a", "name": "Testheim", "position": {"lat": bs["lat"], "lon": bs["lon"]}}]
	var in_terr: Dictionary = geo.rate_site(bs["lat"], bs["lon"], sts, [t_here])
	check(not in_terr["valid"] and in_terr["nearest_border_km"] == 0.0, "founding inside a foreign territory is rejected")
	var too_close := Geo.offset(bs["lat"], bs["lon"], 15.0, 0.0, R)
	var tc: Dictionary = geo.rate_site(too_close.x, too_close.y, sts, [t_here])
	check(not tc["valid"] and absf(float(tc["nearest_border_km"]) - 14.0) < 0.1, "14 km to the border is rejected (%.2f km)" % tc["nearest_border_km"])
	var ok_found := false
	for ang in 16:
		var o := Geo.offset(bs["lat"], bs["lon"], 23.0 * cos(TAU * ang / 16.0), 23.0 * sin(TAU * ang / 16.0), R)
		var r: Dictionary = geo.rate_site(o.x, o.y, sts, [t_here])
		if r["sample"]["land"] and r["reasons"].is_empty():
			ok_found = float(r["nearest_border_km"]) >= 20.0
			break
	check(ok_found, "22 km to the border is allowed (another settlement may found there)")
	check(world.found_settlement(tpl, "plr_test", "", {"lat": o_ll.x, "lon": o_ll.y}).is_empty() and world.is_planet_empty(), "invalid site: no settlement is founded")
	# Migration of a Phase-1 save (no position) to the planet.
	var old_save := {"world_id": "wld_prime", "settlements": [{"settlement_id": "stl_old", "name": "Altdorf", "founder_player_id": "plr_old", "resident_player_ids": ["plr_old"], "template_path": tpl}]}
	var mf := FileAccess.open("user://test_world_migrate.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(old_save))
	mf.close()
	world.use_storage("user://test_world_migrate.json", false)
	var migrated: Dictionary = world.get_settlement("stl_old")
	check(migrated.has("position") and migrated.get("region_id", "") != "" and migrated.get("territory_id", "") != "", "Phase-1 save gets a position, region and territory")
	check(world.migrated_settlement_ids.has("stl_old") and world.validate_territories().is_empty(), "migration is recorded, territories valid")
	world.use_storage("user://test_world_migrate.json", false)
	var again_pos: Dictionary = world.get_settlement("stl_old")["position"]
	check(world.migrated_settlement_ids.is_empty() and absf(again_pos["lat"] - migrated["position"]["lat"]) < 0.0002 and absf(again_pos["lon"] - migrated["position"]["lon"]) < 0.0002, "migration happens only once, position is stable")
	# Migration of a Phase-2 save (territory = whole region) to a 1 km² territory.
	var p2_save := {"world_id": "wld_prime", "settlements": [{"settlement_id": "stl_p2", "name": "Zweistadt", "founder_player_id": "plr_p2", "resident_player_ids": ["plr_p2"], "template_path": tpl,
		"position": {"lat": bs["lat"], "lon": bs["lon"]}, "region_id": bs["region_id"], "territory_id": "ter_p2"}],
		"territories": [{"territory_id": "ter_p2", "owner_settlement_id": "stl_p2", "owner_player_id": "plr_p2", "region_ids": [bs["region_id"]], "kind": "settlement", "claimed_at_unix": 1700000000}]}
	mf = FileAccess.open("user://test_world_migrate2.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(p2_save))
	mf.close()
	world.use_storage("user://test_world_migrate2.json", false)
	var t2: Dictionary = world.territory_of_settlement("stl_p2")
	check(world.migrated_territory_ids.has("ter_p2") and t2.has("geometry") and not t2.has("region_ids") and absf(float(t2["area_km2"]) - 1.0) < 0.01, "Phase-2 region claim becomes a 1 km² territory (same ID)")
	check(int(t2["version"]) == 2 and (t2["history"] as Array).size() == 2 and world.get_settlement("stl_p2").has("settlement_area"), "migration keeps history and adds the settlement area")
	var saved_json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://test_world_migrate2.json"))
	check(int(saved_json.get("schema_version", 0)) == WorldState.SCHEMA_VERSION and WorldState.SCHEMA_VERSION == 4, "world save carries schema version 4")
	world.use_storage("user://test_world_state.json", true)

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
	clock.latitude = 85.0
	clock.fixed_utc_unix = float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 6, "day": 21, "hour": 12, "minute": 0, "second": 0}))
	var pday: String = clock.polar_state()
	clock.fixed_utc_unix = float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 12, "day": 21, "hour": 12, "minute": 0, "second": 0}))
	check(pday == "polar_day" and clock.polar_state() == "polar_night" and clock.get_night_factor() > 0.9, "polar settlements get polar day and polar night")
	clock.latitude = 51.0
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
	# Midday: NPCs stand at their workplaces, so the movement tests below also
	# prove that they do not block the town's paths.
	clock.preview_minute_of_day = 12 * 60.0
	_main = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await frames(5)
	print("[start choice]")
	check(_main.start_choice != null and _main.globe == null and not _main.has_node("Settlement"), "without a settlement the game first asks: join or found")
	check(_main.start_choice._join_button.disabled and not _main.start_choice._found_button.disabled, "joining is visibly unavailable (no multiplayer yet), founding is available")
	check(_main.start_choice._other_players_settlements() == 0, "no settlements of other players exist locally (nothing faked)")
	_main.start_choice.found_chosen.emit()
	await frames(3)
	print("[globe & founding]")
	check(_main.globe != null and _main.globe.mode == "found" and not _main.has_node("Settlement"), "'found' opens the globe in founding mode")
	for k in 200:
		if _main.globe.view != null and _main.globe.labels != null:
			break
		await get_tree().process_frame
	var gview: GlobeView = _main.globe.view
	check(gview != null and gview.camera.is_current(), "globe view is built and its camera is current")
	gview.focus(20.0, 30.0, 3.0, true)
	await frames(1)
	var center_pick := gview.pick(Vector2(480, 270) + gview.screen_shift)
	check(absf(center_pick.x - 20.0) < 1.5 and absf(angle_difference(deg_to_rad(center_pick.y), deg_to_rad(30.0))) < deg_to_rad(1.5), "tap in the centre picks the point under the camera (%.1f, %.1f)" % [center_pick.x, center_pick.y])
	check(is_nan(gview.pick(Vector2(5, 5)).x), "tap into space picks nothing")
	var gprobe: Dictionary = gview.project(25.0, 40.0)
	var back := gview.pick(gprobe["pos"])
	check(absf(back.x - 25.0) < 0.6 and absf(back.y - 40.0) < 0.6, "label position and picking agree (%.1f, %.1f)" % [back.x, back.y])
	check(gview.level == "planetar", "far view = planetary zoom level")
	gview.focus(20.0, 30.0, 2.0, true)
	check(gview.level == "kontinental", "closer = continental zoom level")
	gview.focus(20.0, 30.0, 1.3, true)
	check(gview.level == "regional", "closest = regional zoom level")
	var site: Dictionary = geo.best_site(world.get_settlements(), world.get_territories())
	_main.globe.select_point(site["sample"]["lat"], site["sample"]["lon"])
	check(_main.globe.candidate.get("valid", false) and _main.globe.selected_region == site["region"]["region_id"], "selecting a point rates it as founding site")
	_main.found_from_globe(_main.globe.candidate, "")
	await frames(5)
	check(_main.globe == null and _main.has_node("Settlement"), "founding on the globe enters the new settlement")
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
	var rec: Dictionary = founded[0]
	check(rec.has("position") and rec["region_id"] == site["region"]["region_id"] and rec["continent_id"] != "", "settlement stores lat/lon, region and continent")
	var terr: Dictionary = world.territory_of_settlement(rec["settlement_id"])
	check(not terr.is_empty() and rec["territory_id"] == terr["territory_id"] and absf(float(terr["area_km2"]) - 1.0) < 0.01, "founding claims a 1 × 1 km territory (not a region)")
	check(not (terr["cover_l8"] as Array).is_empty() and (terr["history"] as Array).size() == 1 and terr["status"] == "active", "territory stores index cells, history and status")
	check(rec.get("settlement_area", {}).get("size_m", 0) == 1000 and rec.get("difficulty", "") != "", "settlement stores its area (1 km) and difficulty")
	check(world.validate_territories().is_empty(), "territory invariants hold (geometry, index, no overlap)")
	check(world.found_settlement(tpl, profile.player_id, "Zweitgründung").is_empty(), "one active founding per player")
	var region_rule: Dictionary = geo.rate_site(rec["position"]["lat"], rec["position"]["lon"], world.get_settlements(), world.get_territories())
	check(not region_rule["valid"], "own territory now blocks founding at the same spot")
	check(int(_main.settlement.perf_stats().get("visible_objects", 0)) > 0, "settlement reports visible objects for diagnostics")
	# Globe in browse mode shows the 1 km territory (shader) and its zone.
	_main.open_globe("browse")
	for k in 200:
		if _main.globe.view != null and _main.globe.labels != null:
			break
		await get_tree().process_frame
	var mat: ShaderMaterial = _main.globe.view._material
	check(int(mat.get_shader_parameter("terr_count")) == 1 and float(mat.get_shader_parameter("zone_strength")) == 1.0, "globe draws the territory and its 20 km exclusion zone")
	check(absf(float(mat.get_shader_parameter("zone_km")) - 20.5) < 0.001, "zone = 20 km gap + half the new start square")
	_main.close_globe()
	await frames(2)
	check(_main.globe == null and _main.settlement.visible, "closing the map returns to the settlement")

	print("[diagnostics]")
	var perf: Node = get_tree().root.get_node("PerfMonitor")
	var fake: Array = []
	for k in 99:
		fake.append({"dt": 0.02, "cpu_process": 0.004, "cpu_physics": 0.001, "draw_calls": 100, "primitives": 2000, "objects_3d": 0, "visible_objects": 40, "gpu_ms": 0.0, "render_cpu_ms": 0.0})
	fake.append({"dt": 0.05, "cpu_process": 0.004, "cpu_physics": 0.001, "draw_calls": 140, "primitives": 2000, "objects_3d": 0, "visible_objects": 40, "gpu_ms": 0.0, "render_cpu_ms": 0.0})
	var rep: Dictionary = perf.summarize(fake)
	check(absf(rep["fps_avg"] - 100.0 / 2.03) < 0.2 and rep["frame_ms_max"] == 50.0 and rep["frame_ms_p95"] == 20.0 and rep["fps_1pct_low"] == 20.0, "measurement summary: average, p95, max, 1 % low")
	check(rep["draw_calls_max"] == 140.0 and absf(rep["cpu_process_ms_avg"] - 4.0) < 0.01, "measurement summary: draw calls and CPU time")
	perf.set_overlay_visible(true)
	await frames(20)
	check(perf._label.text.contains("Siedlung") and perf._label.text.contains("Draw Calls"), "overlay shows live values in the settlement view")
	perf.set_overlay_visible(false)
	check(settlement.data.region_name == rec["region_name"], "HUD region comes from the planet")
	check(absf(clock.latitude - clampf(rec["position"]["lat"], -60.0, 60.0)) < 0.01, "sun latitude follows the settlement position")

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

	print("[npcs]")
	if root_has_character_assets():
		var roster: Array = founded[0].get("npcs", [])
		var comp_total := 0
		for comp_spec in SettlementSim.load_config()["founding_population"]["composition"]:
			comp_total += int(comp_spec[1])
		var founders := roster.filter(func(r): return r.has("index_in_role")).size()
		check(founders == comp_total and founders >= 20 and founders <= 50, "founding community of %d NPCs (Master §4.2: 20–50) stored in the settlement record" % founders)
		var roles := {}
		var names := {}
		var looks := {}
		var catalog: Node = get_tree().root.get_node("CharacterCatalog")
		for r in roster:
			roles[r["role"]] = true
			names[str(r["name"]).get_slice(" ", 0)] = true
			looks[catalog.appearance_key(r["appearance"], "idle")] = true
		check(roles.size() == 12, "all 12 founding functions are represented (%d)" % roles.size())
		check(names.size() == roster.size() and looks.size() >= roster.size() - 2, "first names are unique and appearances nearly so (%d/%d looks)" % [looks.size(), roster.size()])
		var role_ok := true
		for r in roster:
			var a: Dictionary = r["appearance"]
			match r["role"]:
				"builder":
					role_ok = role_ok and a["head"]["option"] == "beanie" and a["suit"]["option"] == "suit" and a["tool"]["option"] == "hammer"
				"farmer":
					role_ok = role_ok and a["head"]["option"] == "straw_hat" and a["tool"]["option"] in ["shovel", "watercan"]
				"medic":
					role_ok = role_ok and a["top"].get("color", "") == "sky"
				"admin":
					role_ok = role_ok and a["bowtie"]["option"] == "bowtie"
				"merchant":
					role_ok = role_ok and a["bag"]["option"] == "bag"
			if not r["role"] in ["farmer", "builder"] and a["head"]["option"] in ["straw_hat", "beanie"]:
				role_ok = false # role signifiers are reserved
			if not r["role"] in ["resident", "worker"] and r["workplace_id"] == "":
				role_ok = false
		check(role_ok, "every NPC wears its role's clothing and has a workplace")
		check(settlement.npcs.size() == roster.size(), "NPCs are instantiated in the world")
		check(settlement.sim != null and roster.all(func(r): return r.has("personality") and r.has("profession") and r.has("age_at_arrival") and r.has("health") and r.has("employment")), "every NPC has a persistent identity (personality, profession, age, health, employment)")
		check(founded[0].has("sim") and founded[0].has("time_zone"), "living world state and settlement time zone are stored in the record")
		settlement._update_lod(true)
		var present := settlement.npcs.filter(func(n): return n.is_present()).size()
		check(present > 0, "at noon inhabitants are out and about (%d visible)" % present)
		var spot_ok := true
		for n in settlement.npcs:
			if not n.is_present():
				continue
			var g := Iso.world_to_grid(n.position)
			var c := Vector2i(int(floor(g.x)), int(floor(g.y)))
			var t := settlement.data.get_tile(c.x, c.y)
			var bad_pos := t in ["water", ""] or (not n.walking and t == "road")
			for b in settlement.data.buildings:
				if c in settlement.data.get_building_cells(b):
					bad_pos = true
			if bad_pos:
				spot_ok = false
				print("       bad NPC position ", n.npc_id, " ", c, " ", t, " walking=", n.walking)
		check(spot_ok, "visible NPCs are never inside buildings or water, and only cross roads while walking")
		clock.preview_minute_of_day = 3 * 60.0
		settlement._update_lod(true)
		check(settlement.npcs.all(func(n): return not n.visible), "at 03:00 everybody sleeps indoors")
		clock.preview_minute_of_day = 12 * 60.0
		settlement._update_lod(true)
	else:
		check(settlement.npcs.is_empty(), "no NPCs without character art")

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

	if not settlement.npcs.is_empty():
		# Tap on an NPC -> walk over, it turns to the player, its card opens.
		opened.clear()
		var npc: Npc = settlement.npcs[0]
		for cand in settlement.npcs:
			if cand.is_present() and not cand.walking:
				npc = cand
				break
		# freeze the preview time on a whole minute so the NPC keeps its place
		clock.preview_minute_of_day = 12 * 60.0
		player.global_position = npc.position + Vector2(0, 70)
		await frames(2)
		settlement.camera.snap_to_target()
		await frames(1)
		settlement.handle_tap(_world_to_screen(settlement.camera, npc.position + Vector2(0, -25)))
		await frames(120)
		check(opened.size() == 1 and opened[0].get("kind", "") == "npc" and opened[0].get("title", "") == npc.record["name"] \
				and String(opened[0].get("subtitle", "")) == CharacterCatalog.role_label(npc.record["role"]), "tapping an NPC opens its name and role")
		var to_player := player.global_position - npc.position
		check(npc.rig.facing == Iso.facing_index(to_player), "NPC looks at the player")
		hud.close_panel()

	if root_has_character_assets():
		# Menu -> "Figur bearbeiten" -> change -> "Fertig" updates the player.
		var cat: Node = get_tree().root.get_node("CharacterCatalog")
		var rng := RandomNumberGenerator.new()
		rng.seed = 4711
		var new_look: Dictionary = cat.random_appearance(rng)
		_main.open_character_editor("edit")
		await frames(3)
		check(_main.editor != null and not player.input_enabled, "edit mode opens the editor and blocks movement")
		_main.editor.confirmed.emit(new_look, "Testname")
		await frames(3)
		var rig: CharacterRig = player.get_node("Visual").rig if player.has_node("Visual") else null
		check(_main.editor == null and player.input_enabled, "editor closes after Fertig")
		check(cat.appearance_key(profile.character, "idle") == cat.appearance_key(cat.normalize(new_look), "idle") and profile.display_name == "Testname", "edited character is saved")
		check(rig != null and cat.appearance_key(rig.appearance, "idle") == cat.appearance_key(cat.normalize(new_look), "idle"), "player in the world shows the edited character")

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
	var settlement_npc_keys: Array = settlement.npcs.map(func(n): return "%s|%s|%s" % [n.record["name"], n.record["role"], CharacterCatalog.appearance_key(CharacterCatalog.normalize(n.record["appearance"]), "idle")])
	_main.queue_free()
	await get_tree().process_frame
	world.load_world()
	_main = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child(_main)
	await frames(3)
	var again: SettlementScene = _main.get_node("Settlement")
	check(not again.just_founded and world.get_settlements().size() == 1, "relaunch reuses the founded settlement")
	check(again.data.ids.get("settlement_id") == founded[0]["settlement_id"], "settlement ID is persistent")
	if root_has_character_assets():
		var same := again.npcs.size() == settlement_npc_keys.size()
		for i in again.npcs.size():
			var n2: Npc = again.npcs[i]
			var k2 := "%s|%s|%s" % [n2.record["name"], n2.record["role"], CharacterCatalog.appearance_key(CharacterCatalog.normalize(n2.record["appearance"]), "idle")]
			if k2 != settlement_npc_keys[i]:
				print("       ", k2, " != ", settlement_npc_keys[i])
			same = same and k2 == settlement_npc_keys[i]
		check(same, "NPCs keep name, role and appearance across relaunches")
	clock.preview_minute_of_day = -1.0

	_test_living_assets()
	_test_living_world()
	_test_world_authority()
	_test_animations()
	_test_settlement_foundation()
	await _test_gameplay_polish()
	await _test_world_council()
	_test_social_life()

	print("")
	print("Passed: %d  Failed: %d" % [_passed, _failed.size()])
	for f in _failed:
		print("  - ", f)
	get_tree().quit(1 if _failed.size() > 0 else 0)


func _test_living_world() -> void:
	print("[living world]")
	var data := SettlementData.load_from_file("res://data/settlement_templates/founding_basic.json")
	var cfg := SettlementSim.load_config()
	var t0 := int(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 11, "day": 23, "hour": 23, "minute": 0, "second": 0}))   # Tue 24.11.2026 00:00 CET
	var comp: Array = cfg["founding_population"]["composition"]
	var mk := func(id: String) -> Dictionary:
		return {"settlement_id": id, "npcs": NpcRoster.generate(id, data.buildings, comp), "founded_at_unix": t0, "resident_player_ids": ["plr_test"], "time_zone": {"name": "Test/CET", "offset_min": 60}}
	check(NpcBrain.weekday(t0, 60) == 2 and absf(NpcBrain.local_hour(t0, 60)) < 0.01, "settlement local time: 23:00 UTC = Tuesday 00:00 in UTC+1")
	var vals := {}
	for d in 200:
		vals[int(SettlementCore._chance("stl_x#arrive#%d" % d) * 10.0)] = true
	check(vals.size() == 10, "seeded chances are well distributed across consecutive days")
	var rec_a: Dictionary = mk.call("stl_lwtest")
	var rec_b: Dictionary = mk.call("stl_lwtest")
	var a := SettlementSim.create(rec_a, data, t0, cfg, 60)
	var b := SettlementSim.create(rec_b, data, t0, cfg, 60)
	a.advance_to(t0 + 3 * 86400)
	# b: many irregular small steps (LOD switches, frame ticks) to the same time
	var tt := t0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	while tt < t0 + 3 * 86400:
		tt = mini(t0 + 3 * 86400, tt + rng.randi_range(1, 5400))
		b.advance_to(tt)
	check(JSON.stringify(a.states) == JSON.stringify(b.states) and JSON.stringify(rec_a["core"]) == JSON.stringify(rec_b["core"]), "advance in one jump == advance in many small steps (micro and day steps)")
	var c := SettlementSim.create(mk.call("stl_lwtest"), data, t0, cfg, 60)
	c.advance_to(t0 + 3 * 86400)
	check(JSON.stringify(a.states) == JSON.stringify(c.states), "simulation is deterministic")
	# Friday (t0 + 3 days = Fri 00:00 local): duty roster from the operating models
	var fri := t0 + 3 * 86400
	a.advance_to(fri + 11 * 3600)
	var plan: Dictionary = rec_a["core"]["plan"][str(SettlementCore.day_index(fri, 60))]
	var due := 0
	var at_work := 0
	var starts := {}
	for id in plan["shifts"]:
		var sh: Array = plan["shifts"][id]
		starts[int(sh[0])] = true
		if int(sh[0]) + 1800 <= fri + 11 * 3600 and int(sh[1]) > fri + 11 * 3600:
			due += 1
			var st: Dictionary = a.states[id]
			var act: String = st["act"] if st["travel"].is_empty() else str(st["travel"]["next"])
			if act in ["work", "pause"]:
				at_work += 1
	check(due >= 10 and at_work >= due - 1, "on a workday at 11:00 everybody on duty is at work or on break (%d/%d)" % [at_work, due])
	check(starts.size() >= 8, "shifts are staggered (%d different start times on one day)" % starts.size())
	var sun := SettlementCore.roster_for_day(rec_a, data, cfg, SettlementCore.day_index(fri, 60) + 2, 60)
	var sun_bids := {}
	for id in sun["shifts"]:
		sun_bids[str(sun["shifts"][id][2])] = true
	check(sun_bids.has("bld_water_works") and sun_bids.has("bld_clinic") == false and not sun_bids.has("bld_town_hall"), "Sunday: water works staffed (24/7 operation), town hall and practice closed")
	a.advance_to(fri + 27 * 3600)   # Saturday 03:00
	var sleeping := 0
	for r in a.roster:
		if a.states[r["npc_id"]]["act"] in ["sleep", "rest_sick"]:
			sleeping += 1
	check(sleeping == a.roster.size(), "at 03:00 everybody sleeps (%d/%d)" % [sleeping, a.roster.size()])
	var needs_ok := true
	for r in a.roster:
		var nd := a.needs_now(r["npc_id"], fri + 27 * 3600)
		for k in nd:
			if float(nd[k]) < 0.0 or float(nd[k]) > 1.0:
				needs_ok = false
		if float(nd["food"]) < 0.05:
			needs_ok = false
	check(needs_ok, "needs stay within 0..1 and nobody starves")
	var acts := {}
	for e in a.advance_to(fri + 48 * 3600):
		acts[e.get("act", "")] = true
	check(acts.has("socialize") and acts.has("leisure") and acts.has("eat_home") and acts.has("work") and acts.has("sleep") and acts.has("pause"), "daily life uses work, breaks, meals, plaza, green spaces and sleep (%s)" % str(acts.keys()))
	_test_personality_effects(data, cfg, t0, mk)
	_test_health_and_duty(data, cfg, t0, mk)
	_test_macro_equivalence(data, cfg, t0, mk)
	# navigation
	var nav := a.nav
	var reach := true
	var solid_ok := true
	for id in nav.places:
		var p := nav.path_between("plaza", id)
		if p.is_empty():
			reach = false
			print("       unreachable place ", id)
		for cell in p:
			if nav.astar.is_point_solid(cell) or data.get_tile(cell.x, cell.y) == "water":
				solid_ok = false
	check(reach, "every place is reachable on foot")
	check(solid_ok, "paths never cross buildings or water")
	check(nav.travel_seconds("bld:bld_house_1", "bld:bld_town_hall") > 0 and absi(nav.travel_seconds("bld:bld_house_1", "bld:bld_town_hall") - nav.travel_seconds("bld:bld_town_hall", "bld:bld_house_1")) < 30, "travel times are positive and nearly symmetric")
	# persistence round trip
	a.store()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(rec_a))
	var reloaded := SettlementSim.create(saved, data, a.simulated_at, cfg, 60)
	check(JSON.stringify(reloaded.states) == JSON.stringify(a.states) and JSON.stringify(reloaded.record["core"]) == JSON.stringify(JSON.parse_string(JSON.stringify(rec_a["core"]))), "living world survives save/load (JSON)")
	# absence: 3 days offline, then catch up (event-driven, fast, identical)
	var t_back := a.simulated_at + 3 * 86400
	var us := Time.get_ticks_usec()
	reloaded.advance_to(t_back)
	var catch_ms := (Time.get_ticks_usec() - us) / 1000.0
	a.advance_to(t_back)
	check(JSON.stringify(reloaded.states) == JSON.stringify(a.states) and catch_ms < 3000.0, "3 days of absence are caught up exactly (%.1f ms)" % catch_ms)
	# long absence: EVERY day is processed by the macro layer, micro state is current
	a.store()
	var far_rec: Dictionary = JSON.parse_string(JSON.stringify(rec_a))
	us = Time.get_ticks_usec()
	var far := SettlementSim.create(far_rec, data, a.simulated_at + 120 * 86400, cfg, 60)
	var far_ms := (Time.get_ticks_usec() - us) / 1000.0
	check(far.simulated_at == a.simulated_at + 120 * 86400 and int(far_rec["core"]["day"]) == SettlementCore.day_index(far.simulated_at, 60) and far.states.size() == far.roster.size(), "120 days of absence: all 120 day steps processed, state is current (%.0f ms)" % far_ms)
	# LOD: rendering never changes the simulation
	var before := JSON.stringify(a.states)
	for r in a.roster:
		a.render_info(r["npc_id"], float(t_back) + 0.5)
		a.needs_now(r["npc_id"], t_back)
	a.groups_at(float(t_back))
	check(JSON.stringify(a.states) == before, "rendering (LOD S0) never changes the simulation (S1)")
	# interaction with the player is persisted
	var nid: String = a.roster[0]["npc_id"]
	var soc := float(a.needs_now(nid, t_back)["social"])
	a.player_talk(nid, t_back)
	check(float(a.needs_now(nid, t_back)["social"]) > soc and int(a.states[nid]["needs_at"]) == t_back, "talking to an NPC changes its needs (stored)")
	# visual router: active effects from the current state + persistent building state
	var cook := {}
	for r in a.roster:
		var st: Dictionary = a.states[r["npc_id"]]
		st["travel"] = {}
		st["act"] = "eat_home"
		st["place"] = a._ctx[r["npc_id"]]["home"]
		cook = st
		break
	a._plan_cache.clear()
	var fx := VisualEventRouter.active_effects(a, float(NpcBrain.day_start(t_back, 60) + 7 * 3600))
	check(fx.any(func(e): return e["vfx"] == "chimney_smoke"), "cooking at home shows chimney smoke (derived from state, never stale)")
	var vrec := {}
	check(VisualEventRouter.apply_building_event(vrec, "bld_house_1", "fire_large", t_back, cfg) and VisualEventRouter.visual_state_of(vrec, "bld_house_1").fire == 2, "simulation events drive persistent Living-Assets states")
	# scale: 1000 NPCs, one simulated day
	var big_roster := []
	for i in 1000:
		var r0: Dictionary = rec_a["npcs"][i % rec_a["npcs"].size()].duplicate(true)
		r0["npc_id"] = "npc_scale_%04d" % i
		r0.erase("personality")
		big_roster.append(r0)
	var big := {"settlement_id": "stl_scale", "npcs": big_roster, "founded_at_unix": t0, "time_zone": {"name": "Test/CET", "offset_min": 60}}
	us = Time.get_ticks_usec()
	var bs := SettlementSim.create(big, data, t0, cfg, 60)
	var ev := bs.advance_to(t0 + 86400)
	var big_ms := (Time.get_ticks_usec() - us) / 1000.0
	print("       1000 NPCs: warm-up + 1 simulated day = %.0f ms, %d events (%.1f µs/event)" % [big_ms, ev.size(), big_ms * 1000.0 / maxf(1.0, ev.size())])
	check(big_ms < 20000.0, "1000 NPCs × 2 simulated days run headless in %.0f ms" % big_ms)
	# credits / licence
	check(Credits.bbcode().contains(Credits.MANDATORY) and Credits.data()["sections"][1]["lines"].size() >= 5, "mandatory Penzilla credit and the list of edits are shown in the game")
	check(GraphicsProfile.PROFILES.has("ultra") and GraphicsProfile.PROFILES.has("leistung"), "graphics profiles ultra/hoch/leistung exist (presentation only)")


func _test_world_authority() -> void:
	print("[world authority / MMO]")
	var cfg := SettlementSim.load_config()
	var tpl := "res://data/settlement_templates/founding_basic.json"
	var data := SettlementData.load_from_file(tpl)
	var t0 := int(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 11, "day": 23, "hour": 23, "minute": 0, "second": 0}))
	var mkrec := func(id: String) -> Dictionary:
		return {"settlement_id": id, "template_path": tpl, "founder_player_id": "plr_founder", "resident_player_ids": ["plr_founder", "plr_neighbour"],
			"admin_player_ids": ["plr_founder", "plr_neighbour"], "founded_at_unix": t0, "region_id": "reg_a", "time_zone": {"name": "Test/CET", "offset_min": 60}}
	var clock := [t0]
	var recs: Array = [mkrec.call("stl_mmo")]
	var auth := WorldAuthority.create(func(): return recs, func(): return int(clock[0]), cfg)
	auth.ensure_population(recs[0])
	check(recs[0]["npcs"].size() >= 20 and recs[0].has("core"), "the authority creates the founding population at founding (%d NPCs, no client needed)" % recs[0]["npcs"].size())
	var client := LocalWorldClient.connect_to(auth, "plr_neighbour")
	var stranger := LocalWorldClient.connect_to(auth, "plr_stranger")
	# the founder is offline for 5 years; another player keeps administering
	var us := Time.get_ticks_usec()
	clock[0] = t0 + 365 * 86400
	var r1 := client.submit({"kind": "set_policy", "settlement_id": "stl_mmo", "payload": {"open_for_newcomers": false}, "command_id": "cmd_fixed_1"})
	var r1b := client.submit({"kind": "set_policy", "settlement_id": "stl_mmo", "payload": {"open_for_newcomers": false}, "command_id": "cmd_fixed_1"})
	check(r1.get("ok", false) and r1b.get("duplicate", false) and int(r1b["seq"]) == int(r1["seq"]) and recs[0]["authority"]["log"].size() == 1, "commands are validated, logged and idempotent (same command_id applied once)")
	check(not stranger.submit({"kind": "set_policy", "settlement_id": "stl_mmo", "payload": {"open_for_newcomers": true}}).get("ok", true), "players without administration rights are rejected")
	check(not client.submit({"kind": "set_priorities", "settlement_id": "stl_mmo", "payload": {"priorities": ["wasser"]}}).get("ok", true), "invalid payloads are rejected")
	check(not stranger.submit({"kind": "join_settlement", "settlement_id": "stl_mmo"}).get("ok", true), "player migration stays disabled until Phase 8")
	var arrivals_y1 := int(recs[0]["core"]["counters"]["arrivals"])
	clock[0] = t0 + 2 * 365 * 86400
	var prio: Array = SettlementCore.FUNCTIONS.duplicate()
	prio.reverse()
	check(client.submit({"kind": "set_priorities", "settlement_id": "stl_mmo", "payload": {"priorities": prio}}).get("ok", false), "administration sets job priorities")
	clock[0] = t0 + 5 * 365 * 86400 + 3600
	var snap := client.snapshot("stl_mmo")
	var five_ms := (Time.get_ticks_usec() - us) / 1000.0
	var today := SettlementCore.day_index(clock[0], 60)
	var cnt: Dictionary = snap["core"]["counters"]
	print("       5 years: %d day steps in %.0f ms, deaths %d, arrivals %d, illnesses %d, accidents %d, fires %d, population %d" % [auth.stats["day_steps"], five_ms, cnt["deaths"], cnt["arrivals"], cnt["illnesses"], cnt["accidents"], cnt["fires"], snap["core"]["stats"]["population"]])
	check(int(snap["core"]["day"]) == today and int(auth.stats["day_steps"]) >= 5 * 365, "the founder returns after 5 years: every one of the %d days was simulated" % auth.stats["day_steps"])
	check(int(cnt["deaths"]) > 0 and int(cnt["arrivals"]) > 0 and int(cnt["illnesses"]) > 20, "the world developed meanwhile (ageing, deaths, newcomers, illness)")
	check(snap["core"]["policy"]["open_for_newcomers"] == false and int(cnt["arrivals"]) == arrivals_y1 and snap["core"]["policy"]["priorities"] == prio, "the other player's decisions shaped the settlement (closed for newcomers since year 1, new priorities)")
	check(snap["lifecycle"]["status"] == "active", "an absent player never makes a settlement 'abandoned'")
	# the same world on every device: two independent authorities, different
	# graphics profiles, different tick patterns, same commands → same state
	var hashes := []
	var old_profile := str(LocalProfile.get_setting("graphics_profile", "auto"))
	for variant in ["ultra", "leistung"]:
		LocalProfile.set_setting("graphics_profile", variant)
		var rr: Array = [mkrec.call("stl_same")]
		var ck := [t0]
		var au := WorldAuthority.create(func(): return rr, func(): return int(ck[0]), cfg)
		au.ensure_population(rr[0])
		# ultra: two big jumps; leistung: 80 small ticks – the command at day 45 in both
		var times: Array = [45.0, 90.0]
		if variant == "leistung":
			times = []
			for i in range(1, 81):
				times.append(90.0 * i / 80.0)
		for day_f in times:
			ck[0] = t0 + int(float(day_f) * 86400.0)
			au.tick(true)
			if absf(float(day_f) - 45.0) < 0.001:
				au.submit({"command_id": "cmd_same_1", "issuer": "plr_founder", "kind": "close_path", "settlement_id": "stl_same", "payload": {"cell": [10, 8]}})
		hashes.append(WorldAuthority.state_hash(au.snapshot("stl_same")))
	LocalProfile.set_setting("graphics_profile", old_profile)
	check(hashes[0] == hashes[1], "identical world state on all devices regardless of graphics profile and update rhythm")
	# restart: the world is stored and continues, it is never reset
	var saved: Array = JSON.parse_string(JSON.stringify(recs, "", true, true))
	clock[0] = t0 + 5 * 365 * 86400 + 30 * 86400
	var auth2 := WorldAuthority.create(func(): return saved, func(): return int(clock[0]), cfg)
	var h_restart := WorldAuthority.state_hash(auth2.snapshot("stl_mmo"))
	var h_cont := WorldAuthority.state_hash(auth.snapshot("stl_mmo"))
	check(h_restart == h_cont, "a restart (save → load) continues the same world exactly")
	# account deletion of the founder: the settlement lives on
	var fclient := LocalWorldClient.connect_to(auth, "plr_founder")
	check(fclient.submit({"kind": "delete_account", "settlement_id": "stl_mmo"}).get("ok", false), "the founder can delete the account")
	var after := auth.snapshot("stl_mmo")
	var log_clean: bool = not JSON.stringify(after.get("authority", {})).contains("plr_founder")
	check(after["founder_status"] == "deleted" and after["founder_player_id"].begins_with("plr_deleted_") and log_clean and after["lifecycle"]["status"] == "active", "founder account deleted: the settlement persists, references are pseudonymised")
	check(WorldState._check_record(after) == "", "a settlement without its founder is still a valid world record")
	# truly abandoned: nobody lives there → decay; resettlement keeps the place
	var ab: Array = [mkrec.call("stl_empty")]
	var ck2 := [t0]
	var au2 := WorldAuthority.create(func(): return ab, func(): return int(ck2[0]), cfg)
	au2.ensure_population(ab[0])
	ab[0]["resident_player_ids"] = []
	for r in ab[0]["npcs"]:
		r["alive"] = false
	ck2[0] = t0 + 300 * 86400
	var abs_snap := au2.snapshot("stl_empty")
	var worn := 0
	for bid in abs_snap.get("visual_states", {}):
		if int(abs_snap["visual_states"][bid].get("wear", 0)) >= 3:
			worn += 1
	check(abs_snap["lifecycle"]["status"] == "abandoned" and worn >= 5, "a truly abandoned settlement decays visibly over time (%d worn buildings)" % worn)
	var kept: Array = [mkrec.call("stl_kept")]
	var ck3 := [t0]
	var au4 := WorldAuthority.create(func(): return kept, func(): return int(ck3[0]), cfg)
	au4.ensure_population(kept[0])
	ck3[0] = t0 + 2 * 365 * 86400
	var ks := au4.snapshot("stl_kept")
	var heavy := 0
	for bid in ks.get("visual_states", {}):
		if int(ks["visual_states"][bid].get("wear", 0)) >= 3:
			heavy += 1
	print("       inhabited, open settlement after 2 years: population %d, heavily worn buildings %d, stocks %s" % [ks["core"]["stats"]["population"], heavy, str(ks["core"]["stocks"])])
	check(heavy <= 2 and int(ks["core"]["stats"]["population"]) >= 20, "an inhabited settlement keeps its population and is maintained by its builders")
	# tiers
	var tiers: Array = [{"settlement_id": "a", "region_id": "reg_a"}, {"settlement_id": "b", "region_id": "reg_b"}]
	var au3 := WorldAuthority.create(func(): return tiers, func(): return t0, cfg)
	au3.observer_region = "reg_a"
	check(au3.tier_of(tiers[0]) == "S2" and au3.tier_of(tiers[1]) == "S3", "tiers: nearby settlements warm (S2), distant ones cold (S3, on access)")
	check(not RemoteWorldClient.new().submit({}).get("ok", true), "the remote client is a clear placeholder until Phase 12")
	_test_dynamic_navigation(data, cfg, t0)


func _test_dynamic_navigation(data: SettlementData, cfg: Dictionary, t0: int) -> void:
	var comp: Array = cfg["founding_population"]["composition"]
	var rec := {"settlement_id": "stl_nav", "template_path": "res://data/settlement_templates/founding_basic.json", "npcs": NpcRoster.generate("stl_nav", data.buildings, comp),
		"founder_player_id": "plr_founder", "resident_player_ids": ["plr_founder"], "founded_at_unix": t0, "time_zone": {"name": "Test/CET", "offset_min": 60}}
	var recs: Array = [rec]
	var clock := [t0]
	var auth := WorldAuthority.create(func(): return recs, func(): return int(clock[0]), cfg)
	var sim := SettlementSim.create(rec, data, t0, cfg, 60)
	auth.attach_hot(sim)
	# find someone walking and close a cell in the middle of the remaining route
	var t := t0 + 7 * 3600
	var walker := ""
	var cell := Vector2i.ZERO
	while t < t0 + 20 * 3600 and walker == "":
		t += 60
		sim.advance_to(t)
		for id in sim.states:
			var tr: Dictionary = sim.states[id]["travel"]
			if tr.is_empty() or int(tr["arrive"]) - t < 40:
				continue
			var p := sim.nav.path_between(tr["from"], tr["to"])
			if p.size() > 12:
				var f := float(t - int(tr["depart"])) / float(int(tr["arrive"]) - int(tr["depart"]))
				var k := clampi(int(f * p.size()) + 4, 1, p.size() - 3)
				cell = p[k]
				walker = id
				break
	clock[0] = t
	var res := auth.submit({"command_id": "cmd_nav_1", "issuer": "plr_founder", "kind": "close_path", "settlement_id": "stl_nav", "payload": {"cell": [cell.x, cell.y]}})
	var tr2: Dictionary = sim.states.get(walker, {}).get("travel", {})
	var avoids := true
	for c in tr2.get("path", []):
		if int(c[0]) == cell.x and int(c[1]) == cell.y:
			avoids = false
	check(walker != "" and res.get("ok", false) and tr2.has("path") and avoids and sim.nav.version == 1, "a closure mid-journey re-plans the walk around the obstacle (%s at %s)" % [walker, str(cell)])
	var reach := true
	for id in sim.nav.places:
		var pth := sim.nav.path_between("plaza", id)
		for c in pth:
			if c == cell:
				reach = false
	check(reach, "cached routes through the closed cell were invalidated")
	clock[0] = t + 600
	check(auth.submit({"command_id": "cmd_nav_2", "issuer": "plr_founder", "kind": "open_path", "settlement_id": "stl_nav", "payload": {"cell": [cell.x, cell.y]}}).get("ok", false) and sim.nav.is_walkable(cell), "reopening restores the cell")
	# no persistent overlaps: unique standing spots and avoidance while walking
	sim.advance_to(t0 + 12 * 3600)
	var infos := {}
	for r in sim.roster:
		infos[r["npc_id"]] = sim.render_info(r["npc_id"], float(t0 + 12 * 3600))
	SettlementScene._avoid(infos)
	var overlaps := 0
	var ids: Array = infos.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = infos[ids[i]]
			var b: Dictionary = infos[ids[j]]
			if a["visible"] and b["visible"] and (a["grid"] as Vector2).distance_to(b["grid"]) < 0.3:
				overlaps += 1
	check(overlaps == 0, "no two visible inhabitants stand inside each other (unique spots + avoidance)")
	auth.detach_hot("stl_nav")


func _test_animations() -> void:
	print("[animations]")
	var cat: Node = get_tree().root.get_node("CharacterCatalog")
	var farmer := {"tool": {"option": "shovel"}}
	var builder := {"tool": {"option": "hammer"}}
	var plain := {"tool": {"option": "none"}}
	check(cat.resolve_anim(farmer, "dig") == "dig" and cat.resolve_anim(builder, "dig") == "interact" and cat.resolve_anim(builder, "swing") == "swing" and cat.resolve_anim(plain, "swing") == "interact", "work animations match the tool (dig needs a shovel, swing a hammer or axe)")
	check(cat.resolve_anim(builder, "walk") == "walk_tool" and cat.resolve_anim(builder, "sit") == "sit_tool" and cat.resolve_anim(plain, "sit") == "sit", "carrying a tool uses the tool variants of walk/sit/idle")
	check(["sit", "get_up", "run", "dig", "swing", "walk_tool", "sit_tool", "get_up_tool"].all(func(a): return int(cat.anim_info(a).get("frames", 0)) > 0), "animation library: sit, get up, run, dig, swing (+ tool variants)")
	if not root_has_character_assets():
		print("       (Penzilla character layers not imported – texture checks skipped)")
		return
	# facing: measure on the real sheet which way row 2 looks, then check that
	# joystick right/left end up facing right/left on screen
	var face_img: Image = (cat.layer_texture("idle", "face_regular") as Texture2D).get_image()
	var body_img: Image = (cat.layer_texture("idle", "body") as Texture2D).get_image()
	var fsz: Vector2 = cat.frame_size("idle")
	var cx := func(img: Image, row: int) -> float:
		var sum := 0.0
		var n := 0
		for y in range(int(row * fsz.y), int((row + 1) * fsz.y)):
			for x in int(fsz.x):
				if img.get_pixel(x, y).a > 0.5:
					sum += x
					n += 1
		return sum / maxf(1.0, n)
	var row2_looks_left: bool = cx.call(face_img, 2) < cx.call(body_img, 2) - 2.0
	var screen_dir := func(stick: Vector2) -> int:
		# +1 = figure looks right on screen, -1 = left
		var rule: Array = CharacterRig.FACING_ROWS[Iso.facing_index(Iso.screen_input_to_world(stick))]
		var looks_left_in_sheet: bool = int(rule[0]) in [1, 2, 3] and row2_looks_left
		return (1 if rule[1] else -1) if looks_left_in_sheet else 0
	print("       sheet row 2 looks %s; stick right → %d, stick left → %d" % ["left" if row2_looks_left else "right", screen_dir.call(Vector2(1, 0)), screen_dir.call(Vector2(-1, 0))])
	check(screen_dir.call(Vector2(1, 0)) == 1 and screen_dir.call(Vector2(-1, 0)) == -1 and screen_dir.call(Vector2(0.7, 0.7)) == 1 and screen_dir.call(Vector2(-0.7, -0.7)) == -1, "joystick right/left (and diagonals) show the figure facing right/left")
	check(CharacterRig.FACING_ROWS[2] == [4, false] and CharacterRig.FACING_ROWS[6] == [0, false], "up shows the back, down the front")
	var f := 0
	f = Iso.facing_with_hysteresis(Vector2(1, -0.45), 0)   # ~24° – just past the sector edge
	check(f == 0 and Iso.facing_with_hysteresis(Vector2(1, -1), 0) == 1, "facing has hysteresis near diagonal boundaries (no flicker)")
	var ok := true
	for a in cat.data["anims"]:
		var tex: Texture2D = cat.layer_texture(a, "body")
		var fs: Vector2 = cat.frame_size(a)
		if tex == null or absf(tex.get_width() - fs.x * int(cat.anim_info(a)["frames"])) > 1.0 or absf(tex.get_height() - fs.y * 5) > 1.0:
			ok = false
			print("       sheet size mismatch: ", a, " ", tex.get_size() if tex else Vector2.ZERO, " frame ", fs)
	check(ok, "every animation sheet matches its frame size (per-animation crop)")
	var feet_ok := true
	for a in ["dig", "swing", "sit_tool"]:
		# feet stay at the same world position across different crops
		var off_a: Vector2 = cat.feet_in_frame(a) / cat.file_scale() + Vector2(cat.anim_info(a)["crop_src"][0], cat.anim_info(a)["crop_src"][1])
		var off_i: Vector2 = cat.feet_in_frame("idle") / cat.file_scale() + Vector2(cat.data["frame"]["crop_src"][0], cat.data["frame"]["crop_src"][1])
		if off_a.distance_to(off_i) > 0.5:
			feet_ok = false
	check(feet_ok, "feet anchor is identical for all crops (no jumping between animations)")
	# state machine
	var n := Npc.new()
	n.setup({"npc_id": "npc_anim", "name": "A B", "role": "farmer", "appearance": cat.role_appearance("farmer", 5)})
	add_child(n)
	n.apply_render({"visible": true, "grid": Vector2(5, 5), "act": "leisure", "walking": false, "seat": true, "place": "park"}, Vector2.ZERO, Vector2.ZERO, Vector2.INF, false)
	var sat: bool = n.seated and n.rig.anim == "sit_down"
	n.apply_render({"visible": true, "grid": Vector2(5, 5), "act": "leisure", "walking": false, "place": "park"}, Vector2.ZERO, Vector2.ZERO, Vector2.INF, false)
	var got_up: bool = n.rig.anim == "stand_up" and not n.seated
	n.apply_render({"visible": true, "grid": Vector2(5, 5), "act": "walk", "walking": true, "hurry": true, "place": "a", "target": "b"}, Vector2.ZERO, Vector2(1, 0), Vector2.INF, false)
	var ran: bool = n.rig.anim == "run"
	n.apply_render({"visible": true, "grid": Vector2(5, 5), "act": "walk", "walking": true, "door": "enter", "door_f": 0.4, "place": "a", "target": "bld:x"}, Vector2.ZERO, Vector2(1, 0), Vector2.INF, false)
	var opens: bool = n.rig.anim == "open_door" and n.modulate.a > 0.9
	n.apply_render({"visible": true, "grid": Vector2(5, 5), "act": "walk", "walking": true, "door": "enter", "door_f": 0.9, "place": "a", "target": "bld:x"}, Vector2.ZERO, Vector2(1, 0), Vector2.INF, false)
	var door: bool = opens and n.modulate.a < 0.5
	n.apply_render({"visible": true, "grid": Vector2(5, 5), "act": "work", "walking": false, "place": "bld:farm"}, Vector2.ZERO, Vector2.ZERO, Vector2.INF, false)
	var dig: bool = n.rig.anim == "dig"
	n.queue_free()
	check(sat and got_up and ran and door and dig, "NPC animation states: sit down, get up, run when late, open the door then step in, dig at work")
	# the door opens with the hand on it and closes once the person is inside
	check(SettlementScene.door_open_amount("enter", 0.2) == 0.0 and SettlementScene.door_open_amount("enter", 0.6) == 1.0 and SettlementScene.door_open_amount("enter", 1.0) == 0.0 and SettlementScene.door_open_amount("exit", 0.3) == 1.0, "doors open while people pass and close behind them")
	# every clip refers to existing animations and frames
	var clips_ok := true
	for cid in cat.data["clips"]:
		if cid.begins_with("_"):
			continue
		for sg in cat.data["clips"][cid]["segments"]:
			var info: Dictionary = cat.anim_info(sg["base"])
			if info.is_empty() or (sg["seq"] as Array).any(func(f): return int(f) >= int(info["frames"])):
				clips_ok = false
				print("       bad clip ", cid, " ", sg["base"])
	check(clips_ok and cat.data["clips"].size() >= 25, "clip library: %d clips, all frames exist" % (cat.data["clips"].size() - 1))
	var tables_ok := true
	for act in cat.data["activity_clips"]:
		if act.begins_with("_"):
			continue
		for o in cat.data["activity_clips"][act]:
			if not cat.data["clips"].has(o[0]):
				tables_ok = false
	for aid in ActionLibrary.actions():
		var c: String = ActionLibrary.actions()[aid].get("clip", "")
		if c != "" and not cat.data["clips"].has(c):
			tables_ok = false
			print("       action without clip ", aid, " ", c)
	check(tables_ok, "NPC activity tables and player actions use the same clip library")


## Phase 4 – Settlement Foundation.
func _test_settlement_foundation() -> void:
	print("[phase 4: settlement foundation]")
	var cfg := SettlementSim.load_config()
	var data := SettlementData.load_from_file("res://data/settlement_templates/founding_basic.json")
	var comp: Array = cfg["founding_population"]["composition"]
	var day0 := 20800
	# resources: the site decides the basic supply
	var food := {}
	for site in ["rich", "poor"]:
		var site_in := {"factors": {"soil": 1.0 if site == "rich" else 0.05, "climate": 0.9 if site == "rich" else 0.2, "water": 1.0 if site == "rich" else 0.2, "resources": 0.8 if site == "rich" else 0.1, "terrain": 1.0}, "difficulty": {"drivers": {"cold_heat": 0.0 if site == "rich" else 0.6}}}
		var rf := WorldState.region_factors(site_in)
		var rec := {"settlement_id": "stl_res", "npcs": NpcRoster.generate("stl_res", data.buildings, comp), "resident_player_ids": ["plr_a"], "region_factors": rf}
		SettlementCore.ensure(rec, cfg, day0)
		var prod := 0.0
		for d in 28:
			SettlementCore.day_step(rec, data, cfg, day0 + d, 60)
			prod += float(rec["core"]["stats"]["food_prod"])
		food[site] = [prod / 28.0, rf]
	print("       food production per day: rich site %.1f %s, poor site %.1f %s" % [food["rich"][0], str(food["rich"][1]), food["poor"][0], str(food["poor"][1])])
	check(float(food["rich"][0]) > float(food["poor"][0]) * 1.3 and float(food["poor"][1]["energy"]) < float(food["rich"][1]["energy"]), "the site's soil, water and climate shape the basic supply (Ressourcen)")
	# basic supply reaches the inhabitants: a food shortage makes meals less filling
	var needs := {"food": 300000, "energy": 500000, "social": 500000, "leisure": 500000, "hygiene": 500000}
	var fed: int = NpcBrain._integrate(needs, "eat_home", 1800, {}, cfg)["food"]
	var short: int = NpcBrain._integrate(needs, "eat_home", 1800, {}, cfg, {"food_short": true})["food"]
	var dirty: int = NpcBrain._integrate(needs, "wash", 1200, {}, cfg, {"water_short": true})["hygiene"]
	var clean: int = NpcBrain._integrate(needs, "wash", 1200, {}, cfg)["hygiene"]
	check(short < fed and dirty < clean, "shortages are felt in daily life (less filling meals, poor hygiene without water)")
	# administration (town hall)
	var rec2 := {"settlement_id": "stl_adm", "founder_player_id": "plr_boss", "resident_player_ids": ["plr_boss", "plr_guest"], "npcs": NpcRoster.generate("stl_adm", data.buildings, comp), "region_factors": {"food": 1.0, "water": 1.0, "energy": 1.0, "materials": 1.0}}
	SettlementCore.ensure(rec2, cfg, day0)
	for d in 15:
		SettlementCore.day_step(rec2, data, cfg, day0 + d, 60)
	var t := SettlementCore.day_start_utc(day0 + 14, 60) + 10 * 3600
	var txt := SettlementReport.town_hall_text(rec2, data, cfg, t, 60)
	check(txt.contains("Bevölkerung") and txt.contains("Grundversorgung") and txt.contains("Dienste heute") and txt.contains("Chronik") and txt.contains("Entwicklung"), "the town hall shows population, supply, services, development and the chronicle")
	check(not SettlementReport.admin_actions(rec2, "plr_boss").is_empty() and SettlementReport.admin_actions(rec2, "plr_guest").is_empty(), "only the administration gets the administration buttons")
	var recs: Array = [rec2]
	var auth := WorldAuthority.create(func(): return recs, func(): return t, cfg)
	var boss := LocalWorldClient.connect_to(auth, "plr_boss")
	var cmd := SettlementReport.admin_command(rec2, "admin_toggle_newcomers")
	check(boss.submit(cmd).get("ok", false) and rec2["core"]["policy"]["open_for_newcomers"] == false, "closing the settlement for newcomers is an authority command")
	check(boss.submit(SettlementReport.admin_command(rec2, "admin_prio_bau")).get("ok", false) and rec2["core"]["policy"]["priorities"][0] == "bau", "the administration sets which jobs are filled first")
	# jobs: a death opens a position, the administration fills it from the pool
	var victim: Dictionary = SettlementCore.staff_of(rec2, "bld_clinic")[0]
	victim["alive"] = false
	check(SettlementReport.vacancies(rec2, data, cfg).any(func(v): return v["building_id"] == "bld_clinic"), "a vacancy appears when a medic dies")
	var p := ["medizin"]
	for f in SettlementCore.FUNCTIONS:
		if f != "medizin":
			p.append(f)
	rec2["core"]["policy"]["priorities"] = p
	var hired := false
	for d in range(15, 25):
		for e in SettlementCore.day_step(rec2, data, cfg, day0 + d, 60):
			if e["kind"] == "hired" and e.get("building", "") == "bld_clinic":
				hired = true
	check(hired, "the administration hires a general worker for the vacant clinic post")
	# building cards
	var card := SettlementReport.building_text(rec2, data, cfg, "bld_water_works", "", SettlementCore.day_start_utc(day0 + 20, 60) + 10 * 3600, 60)
	var night := SettlementReport.building_text(rec2, data, cfg, "bld_town_hall", "", SettlementCore.day_start_utc(day0 + 20, 60) + 2 * 3600, 60)
	check(card.contains("jetzt geöffnet") and card.contains("Personal") and night.contains("jetzt geschlossen") and card.contains("Zustand"), "building cards show operating hours, open/closed, staff and condition")
	var house := SettlementReport.building_text(rec2, data, cfg, "bld_house_1", "", t, 60)
	check(house.contains("Bewohner"), "houses list their inhabitants and capacity")
	# migration of a 0.5.0 save (12 NPCs, old personality keys)
	var old_rec := {"settlement_id": "stl_old", "npcs": NpcRoster.generate("stl_old", data.buildings), "founded_at_unix": 1764547200, "time_zone": {"name": "X", "offset_min": 60}, "resident_player_ids": ["plr_a"]}
	for r in old_rec["npcs"]:
		r["personality"] = {"openness": 0.8, "diligence": 0.2, "sociability": 0.5, "ambition": 0.5, "risk": 0.5}
		r["birth_day"] = 1000
	var sim := SettlementSim.create(old_rec, data, 1764547200 + 3 * 86400, cfg, 60)
	var r0: Dictionary = old_rec["npcs"][0]
	check(sim.roster.size() == 12 and r0["personality"]["curiosity"] == 0.8 and r0["personality"]["conscientiousness"] == 0.2 and r0.has("employment") and old_rec.has("core"), "0.5.0 saves migrate (personality keys, health, employment, settlement core)")


## Gameplay polish: interiors, doors, footprints, lamps, version.
func _test_gameplay_polish() -> void:
	print("[gameplay polish]")
	var v := WorldsVersion.data()
	check(WorldsVersion.product() == "v0.1" and WorldsVersion.technical() == str(ProjectSettings.get_setting("application/config/version")), "one version source: product %s, build %s = project.godot" % [WorldsVersion.product(), WorldsVersion.technical()])
	check(WorldsVersion.full_label().begins_with("WORLDS v0.1"), "version label shown in the menu and on the loading screen")
	# footprints: the clinic's parking is walkable, the building is not
	var data := SettlementData.load_from_file("res://data/settlement_templates/founding_basic.json")
	var entry: Dictionary = {}
	for b in data.buildings:
		if b["id"] == "bld_clinic":
			entry = b.duplicate(true)
	var bld := Building.new()
	bld.setup(entry)
	add_child(bld)
	var polys: Array = bld.get_children().filter(func(c): return c is CollisionPolygon2D)
	var inside := func(g: Vector2) -> bool:
		var w := Iso.grid_to_world(entry["grid_v"] + g) - bld.position
		return polys.any(func(cp): return Geometry2D.is_point_in_polygon(w, cp.polygon))
	check(not inside.call(Vector2(1.6, 1.0)) and inside.call(Vector2(0.5, 1.0)) and bld.surfaces.any(func(s): return s["kind"] == "parking"), "clinic: the parking inside the footprint is walkable, the building blocks")
	bld.queue_free()
	# street lamps are street-lamp sized (≈ 2.6 × a person)
	check(StreetLamp.HEIGHT_SCALE >= 2.2, "street lamps are drawn ~4.5 m high (person 1.75 m)")
	# doors: every building with a door has opening frames and a nav door on the painted side
	var doors_ok := true
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/doors/doors.json"))
	for ty in spec["nav_by_type"]:
		if ty.begins_with("_"):
			continue
		for b in data.buildings:
			if b["type"] == ty and NavGrid.door_front_cell(b).x < 0:
				doors_ok = false
	check(doors_ok, "people walk to the door that is painted on the sprite (door side per building type)")
	if FileAccess.file_exists("res://assets/penzilla/doors/doors.json"):
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/penzilla/doors/doors.json"))
		var all_frames := true
		for key in meta["doors"]:
			for d in meta["doors"][key]:
				if d["type"] != "none" and not ResourceLoader.exists("res://assets/penzilla/doors/" + str(d["file"])):
					all_frames = false
		check(all_frames and meta["doors"].size() >= 19, "door opening frames exist for all %d building sprites" % meta["doors"].size())
	# unified clothing palette: black is black, violet is violet, all clothing shares it
	var catn: Node = get_tree().root.get_node("CharacterCatalog")
	var cloth: Dictionary = catn.palette("cloth")
	var blk: Color = catn.tint_color("cloth", "black")
	var vio: Color = catn.tint_color("cloth", "violett_kräftig")
	var shared := true
	for slot in ["top", "pants", "suit", "sleeves", "bag", "scarf", "bowtie"]:
		for oid in catn.data["slots"][slot]["options"]:
			var o: Dictionary = catn.data["slots"][slot]["options"][oid]
			if o.has("palette") and o["palette"] != "cloth":
				shared = false
	check(cloth.size() >= 128 and cloth.size() <= 200, "clothing palette has %d colours" % cloth.size())
	check(blk.v < 0.12 and blk.s < 0.2 and vio.h > 0.7 and vio.h < 0.8 and vio.s > 0.5, "black is neutral black, violet stays violet")
	check(shared, "all clothing pieces use the same palette")
	# globe: picking matches what is drawn; land/water as drawn; suggestions differ
	var pl := Geography.planet()
	var agree := 0
	var n_pts := 0
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 11
	for k in 400:
		var la := rng2.randf_range(-60.0, 60.0)
		var lo := rng2.randf_range(-180.0, 180.0)
		n_pts += 1
		if pl.sample(la, lo)["land"] == (pl.display_value_at(la, lo) >= PlanetData.SEA_LEVEL):
			agree += 1
	var centre_ok := true
	for k in 200:
		var i := rng2.randi_range(0, pl.width * pl.height - 1)
		var ll := pl.cell_lat_lon(i)
		if pl.is_land_at(ll.x, ll.y) != pl.is_land(i):
			centre_ok = false
	check(agree == n_pts and centre_ok, "land/water at a tapped point is decided like the globe draws the coast (cell centres unchanged)")
	var sites := Geography.good_sites([], [], 12)
	var distinct := {}
	for st in sites:
		distinct[str(st["sample"]["region_id"])] = true
	check(sites.size() >= 8 and distinct.size() == sites.size() and sites.all(func(x): return x["valid"]), "the suggestion button cycles through %d different valid sites" % sites.size())
	var gv := GlobeView.new()
	add_child(gv)
	gv.setup(pl)
	gv.screen_shift = Vector2(40, -60)
	gv.focus(40.0, 15.0, 1.8, true)
	await get_tree().process_frame
	var max_err := 0.0
	for q in [[48.0, 10.0], [36.9, 13.3], [30.0, 25.0], [42.0, 18.0]]:
		var pr := gv.project(q[0], q[1])
		if pr["visible"]:
			var back := gv.pick(pr["pos"])
			max_err = maxf(max_err, Vector2(q[0], q[1]).distance_to(back))
	gv.queue_free()
	check(max_err < 0.001, "globe: a pin's screen position picks exactly its own coordinates (err %.5f°)" % max_err)
	# interiors
	if not InteriorScene.assets_available():
		print("       (interior art not imported – interior checks skipped)")
		return
	for key in ["player_home", "shop_baker", "shop_grocer", "shop_smith", "town_hall", "clinic", "farm_shop", "workshop"]:
		check(InteriorScene.has_layout(key), "interior exists: %s" % key)
	var home := InteriorScene.create("player_home")
	home.position = Vector2(0, 50000)
	add_child(home)
	await get_tree().process_frame
	var acts := {}
	for n in home.find_children("*", "Interactable", true, false):
		acts[n.get_meta("action", n.kind)] = true
	check(acts.has("sleep") and acts.has("shower") and acts.has("toilet") and acts.has("cook") and acts.has("interior_exit"), "starter home: mattress, shower, toilet, simple kitchen and a way out (%s)" % str(acts.keys()))
	# the shape follows the building: L-shaped clinic, long workshop
	var clinic := InteriorScene.create("clinic")
	add_child(clinic)
	await get_tree().process_frame
	check(not clinic.is_inside(Vector2i(14, 1)) and clinic.is_inside(Vector2i(2, 1)) and clinic.is_inside(Vector2i(14, 8)), "the clinic interior is L-shaped like the building")
	var ws: Array = InteriorScene.layouts()["workshop"]["size"]
	check(int(ws[0]) >= int(ws[1]) * 1.6, "the long workshop has a long room")
	check(clinic._is_entrance_cell(Vector2i(8, 9)) and home._is_entrance_cell(Vector2i(3, 9)) and not home._is_entrance_cell(Vector2i(8, 9)), "entrances are 2-tile gaps in the front wall")
	# walking inside: the entrance is free, furniture blocks
	var space := home.get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.position = home.to_global(home.spawn_point)
	check(space.intersect_point(q).is_empty(), "the player stands free at the entrance inside")
	var fridge_blocked := false
	for n in home.item_nodes:
		if str(n.name).begins_with("fridge"):
			q.position = n.global_position + Vector2(0, -6)
			fridge_blocked = not space.intersect_point(q).is_empty()
	check(fridge_blocked, "furniture blocks walking (fridge)")
	# interaction buttons only at the object: the exit area is small
	var exit_it: Interactable = home.find_children("*", "Interactable", true, false).filter(func(i): return i.kind == "interior_exit")[0]
	var cp: CollisionPolygon2D = exit_it.get_child(0)
	var r := Rect2(cp.polygon[0], Vector2.ZERO)
	for pt in cp.polygon:
		r = r.expand(pt)
	check(r.size.x < 120 and r.size.y < 80, "the exit button area is only at the doorway (%s)" % str(r.size))
	home.queue_free()
	clinic.queue_free()
	await _test_interior_standard()


## Personality has measurable effects (population-level A/B with fixed seeds).
func _test_personality_effects(data: SettlementData, cfg: Dictionary, t0: int, mk: Callable) -> void:
	var social := {}
	var first_out := {}
	for variant in ["low", "high"]:
		var rec: Dictionary = mk.call("stl_ptest")
		for r in rec["npcs"]:
			NpcBrain.ensure_profile(r, cfg, t0)
			r["personality"]["extraversion"] = 0.1 if variant == "low" else 0.9
			r["personality"]["chronotype"] = -0.8 if variant == "low" else 0.8
		var sim := SettlementSim.create(rec, data, t0, cfg, 60)
		var n_social := 0
		var wake_sum := 0.0
		var wake_n := 0
		var seen := {}
		for e in sim.advance_to(t0 + 7 * 86400):
			if e["kind"] == "activity_start" and e["act"] == "socialize":
				n_social += 1
			# Saturday (day 4 after t0): first activity that is not sleep
			var sat0 := t0 + 4 * 86400
			if e["t"] >= sat0 + 4 * 3600 and e["t"] < sat0 + 14 * 3600 and not seen.has(e["npc"]) and e.get("act", "") != "sleep":
				seen[e["npc"]] = true
				wake_sum += float(e["t"] - sat0) / 3600.0
				wake_n += 1
		social[variant] = n_social
		first_out[variant] = wake_sum / maxf(1.0, wake_n)
	print("       personality: social activities low/high extraversion %d/%d, Saturday wake-up early/late chronotype %.1f/%.1f h" % [social["low"], social["high"], first_out["low"], first_out["high"]])
	check(float(social["high"]) > float(social["low"]) * 1.5, "extraverts meet people far more often than introverts")
	check(float(first_out["high"]) - float(first_out["low"]) > 1.0, "night owls start their weekend later than early risers")
	# the same person does not live the same day twice
	var rec2: Dictionary = mk.call("stl_ptest")
	var sim2 := SettlementSim.create(rec2, data, t0, cfg, 60)
	var seqs := {}
	var who := ""
	for r in rec2["npcs"]:
		if r["role"] == "resident":
			who = r["npc_id"]
	var day_seq := {}
	for e in sim2.advance_to(t0 + 6 * 86400):
		if e.get("npc", "") == who and e["kind"] == "activity_start":
			var d := SettlementCore.day_index(e["t"], 60)
			day_seq[d] = str(day_seq.get(d, "")) + "," + str(e["act"])
	for d in day_seq:
		seqs[day_seq[d]] = true
	check(seqs.size() >= day_seq.size() - 1 and day_seq.size() >= 5, "daily routines vary from day to day (%d different days out of %d)" % [seqs.size(), day_seq.size()])


## Illness, duty rosters, substitution and reliability.
func _test_health_and_duty(data: SettlementData, cfg: Dictionary, t0: int, mk: Callable) -> void:
	var rec: Dictionary = mk.call("stl_htest")
	var sim := SettlementSim.create(rec, data, t0, cfg, 60)
	var day0 := SettlementCore.day_index(t0, 60)
	# one water-works employee falls ill for three days (from tomorrow)
	var sick := {}
	var colleagues := SettlementCore.staff_of(rec, "bld_water_works")
	for r in colleagues:
		r["health"] = {"status": "ill", "until_day": day0 + 4, "since_day": day0}
	sick = colleagues[0] if not colleagues.is_empty() else {}
	sim._plan_cache.clear()
	var evs := sim.advance_to(t0 + 2 * 86400 + 20 * 3600)
	var plan: Dictionary = rec["core"]["plan"][str(day0 + 1)]
	check(not sick.is_empty() and not plan["shifts"].has(sick["npc_id"]), "an ill employee is taken off the duty roster")
	var subst := false
	for id in plan["shifts"]:
		if str(plan["shifts"][id][2]) == "bld_water_works":
			subst = true
	check(subst and evs.any(func(e): return e["kind"] == "substitution"), "critical services get a substitute when the whole team is ill (Master §13.6)")
	var sick_acts := {}
	for e in evs:
		if e.get("npc", "") == sick.get("npc_id", "") and e["kind"] == "activity_start" and e["t"] >= t0 + 86400:
			sick_acts[e["act"]] = true
	check(not sick_acts.has("work") and (sick_acts.has("rest_sick") or sick_acts.has("see_doctor")), "illness changes the daily routine: rest at home, visit to the doctor (%s)" % str(sick_acts.keys()))
	# reliability: unreliable people miss shifts more often (macro, 120 days)
	var absent := {}
	for variant in ["low", "high"]:
		var r2: Dictionary = mk.call("stl_rtest")
		for r in r2["npcs"]:
			NpcBrain.ensure_profile(r, cfg, t0)
			r["personality"]["reliability"] = 0.05 if variant == "low" else 0.95
		SettlementCore.ensure(r2, cfg, day0)
		var n_abs := 0
		for d in 120:
			for e in SettlementCore.day_step(r2, data, cfg, day0 + d, 60):
				if e["kind"] == "absent_unexcused":
					n_abs += 1
		absent[variant] = n_abs
	print("       unexcused absences in 120 days: unreliable %d, reliable %d" % [absent["low"], absent["high"]])
	check(int(absent["low"]) > int(absent["high"]) * 2, "unreliable people miss shifts far more often")


## The detail tier decides computing effort, never what happens: a settlement
## simulated in full detail and one advanced by day steps only end in the
## identical long-term state.
func _test_macro_equivalence(data: SettlementData, cfg: Dictionary, t0: int, mk: Callable) -> void:
	var hot: Dictionary = mk.call("stl_etest")
	var cold: Dictionary = mk.call("stl_etest")
	var sim := SettlementSim.create(hot, data, t0, cfg, 60)
	sim.advance_to(t0 + 21 * 86400 + 3600)
	var day0 := SettlementCore.day_index(t0, 60)
	for r in cold["npcs"]:
		NpcBrain.ensure_profile(r, cfg, t0)
	SettlementCore.ensure(cold, cfg, day0 - 1)
	for d in range(day0 - 1, day0 + 22):
		if int(cold["core"]["day"]) < d:
			SettlementCore.day_step(cold, data, cfg, d, 60)
	var macro_view := func(rec: Dictionary) -> String:
		var people := []
		for r in rec["npcs"]:
			people.append([r["npc_id"], r.get("alive", true), r.get("health", {}), r.get("employment", {})])
		return JSON.stringify([rec["core"], people, rec.get("visual_states", {})])
	check(int(hot["core"]["day"]) == int(cold["core"]["day"]) and macro_view.call(hot) == macro_view.call(cold), "full detail (S0/S1) and day steps only (S2/S3) give the identical settlement state after 3 weeks")



func _test_living_assets() -> void:
	print("[living assets]")
	# VisualState: persistence round trip, clamping, tolerant loading
	var vs := VisualState.create("partial", 9, 5, 1, 0, 0)
	check(vs.wear == 3 and vs.damage == 2, "visual state clamps trait levels")
	vs.apply_event("repaired", 1700000000)
	check(vs.structure == "intact" and vs.damage == 0 and vs.repair == 2, "repair fixes damage, keeps visible repair traces")
	var back := VisualState.from_dict(JSON.parse_string(JSON.stringify(vs.to_dict())))
	check(back.equals(vs), "visual state survives save/load (JSON)")
	var legacy := VisualState.from_dict({"structure": "ruin", "unknown": 1})
	check(legacy.structure == "ruin" and legacy.wear == 0, "visual state loads old/partial records tolerantly")
	# absence rule: loading an old record never changes it (no wall-clock decay)
	var old_rec := VisualState.create("intact", 0).to_dict()
	old_rec["changed_at_unix"] = 1
	var reloaded := VisualState.from_dict(old_rec)
	check(reloaded.wear == 0 and reloaded.structure == "intact", "absence does not cause decay (record unchanged after any time)")
	var s2 := VisualState.create()
	for e in ["damaged", "damaged"]:
		s2.apply_event(e, 1)
	check(s2.structure == "partial" and s2.damage == 2, "second damage event leads to partial collapse")
	s2.apply_event("destroyed", 2)
	s2.apply_event("became_ruin", 3)
	s2.apply_event("restored", 4)
	check(s2.structure == "intact" and s2.repair == 1 and s2.history.size() == 5, "destroy -> ruin -> restore is recorded permanently")
	check(not s2.apply_event("time_passed", 5), "unknown events are rejected")
	check(VisualState.create("intact", 2, 1, 2, 1, 0).layer_names() == ["wear_2", "damage_1", "fire_2", "overgrowth_1"], "traits combine into independent overlays")
	# composer decisions with a synthetic manifest (no textures needed)
	var lay := {}
	for n in ["wear_2", "wear_3", "damage_1", "damage_2", "fire_1", "fire_2", "overgrowth_1", "repair_1", "repair_2", "snow_1"]:
		lay[n] = {"file": "b/overlay_%s.png" % n, "offset_src": [2, 4]}
	lay["damage_2"]["clipped"] = {"partial": "b/overlay_damage_2@partial.png"}
	lay["snow_1"]["own"] = {"ruin": {"file": "b/overlay_snow_1@ruin.png", "offset_src": [6, 8]}}
	var fake := {"version": 2, "file_scale": 0.5, "layer_order": ["wear_2", "wear_3", "repair_1", "repair_2", "damage_1", "damage_2", "fire_1", "fire_2", "overgrowth_1", "overgrowth_2", "snow_1"],
		"allowed": {"intact": lay.keys(), "partial": ["wear_2", "damage_1", "damage_2", "fire_1", "fire_2", "snow_1"], "ruin": ["snow_1"]},
		"assets": {"b": {"category": "building", "profile": "building", "canvas_src": [100, 100],
			"bases": {"partial": {"file": "b/base_partial.png", "pad_src": [0, 0]}, "ruin": {"file": "b/base_ruin.png", "pad_src": [0, 0]}}, "layers": lay},
			"h": {"category": "prop", "profile": "prop", "bases": {"broken": {"file": "h/base_broken.png"}}, "layers": {}}}}
	LivingComposer.set_manifest_for_tests(fake)
	var combo := VisualState.create("intact", 2, 1, 2)
	var r_hi := LivingComposer.resolve("b", combo, "hoch")
	var names := []
	for l in r_hi["layers"]:
		names.append(l["name"])
	check(names == ["wear_2", "damage_1", "fire_2"] and r_hi["shader"] != null, "composer: dirty + damaged + partly burnt in draw order")
	var r_low := LivingComposer.resolve("b", VisualState.create("intact", 3, 1, 2, 2, 0), "leistung")
	check(r_low["layers"].size() == 2 and r_low["layers"][0]["name"] == "damage_1" and r_low["shader"] == null, "profile 'leistung': overlay budget keeps the story-relevant traits, no shader")
	var r_part := LivingComposer.resolve("b", VisualState.create("partial", 0, 2), "ultra")
	check(r_part["base"] == "b/base_partial.png" and r_part["layers"][0]["file"].ends_with("@partial.png"), "composer uses the structural base and the pre-clipped overlay")
	var r_ruin := LivingComposer.resolve("b", VisualState.create("ruin", 3, 2, 2), "ultra", {"snow": true})
	check(r_ruin["layers"].size() == 1 and r_ruin["layers"][0]["offset_src"] == [6, 8], "ruin: only allowed overlays, snow lies on the ruin itself")
	var r_h := LivingComposer.resolve("h", VisualState.create("ruin"), "hoch")
	check(r_h["base"] == "" and r_h["structure"] == "intact", "objects without a matching base fall back to the original")
	var same_sim := VisualState.create("intact", 2, 1, 2)
	LivingComposer.resolve("b", same_sim, "leistung")
	check(same_sim.equals(combo), "quality profile never changes the visual/simulation state")
	LivingComposer.set_manifest_for_tests({})


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


func _test_world_council() -> void:
	print("[world council]")
	var d := Landmarks.get_def(Landmarks.WORLD_COUNCIL)
	check(not d.is_empty() and d["continent_name"] == "Kalistia", "World Council is a fixed landmark on Kalistia")
	var p := Geography.planet()
	var ll := Landmarks.position_of(Landmarks.WORLD_COUNCIL)
	var smp := p.sample(ll.x, ll.y)
	var cont := p.continent(smp["continent_id"])
	check(smp["land"] and cont.get("name", "") == "Kalistia", "its position lies on land of Kalistia (%s)" % Geo.format(ll.x, ll.y))
	check(float(smp["temperature_c"]) > 8.0 and float(smp["temperature_c"]) < 24.0 and smp["biome"] in ["plain", "hills", "forest"], "temperate, habitable site (%.0f °C, %s)" % [smp["temperature_c"], smp["biome"]])
	# same position on every load (part of the world definition)
	Landmarks._defs = []
	check(Landmarks.position_of(Landmarks.WORLD_COUNCIL) == ll, "position is fixed, not re-rolled")
	# names: place, official assembly name and interface names are separate
	check(Landmarks.site_name() == "Concordium" and d["name"] == "CONCORDIUM", "the place is called Concordium (with C)")
	check(Landmarks.assembly_official_name() == "Concilium Mundi", "official ceremonial name of the annual assembly: Concilium Mundi")
	check(Landmarks.assembly_ui_name("de") == "Weltversammlung" and Landmarks.institution_ui_name("de") == "Weltrat" and Landmarks.assembly_ui_name("en") == "World Assembly", "interface names stay localised (Weltrat / Weltversammlung / World Assembly)")
	check(Landmarks.ceremonial_heading() == "CONCORDIUM\nConcilium Mundi\nDer Ort, an dem die Welt zusammenkommt.", "ceremonial heading for boards and invitations")
	check(Landmarks.describe(Landmarks.WORLD_COUNCIL, 0).contains("Concilium Mundi") and Landmarks.describe(Landmarks.WORLD_COUNCIL, 0).contains("Weltversammlung"), "info text names both: Concilium Mundi (Weltversammlung)")
	# height ~ 33 figure heights
	check(absf(float(d["height_m"]) - 56.0) < 1.0, "highest point ~56 m (33 figure heights)")
	# neutral zone = exactly the property polygon, no radius around it
	check(not d.has("reserve_radius_km"), "no 18 km reserve any more")
	check(absf(Landmarks.property_area_m2(Landmarks.WORLD_COUNCIL) - 172.0 * 172.0) < 1.0, "property: 172 x 172 m polygon")
	var inside_ll := Landmarks.from_site(Landmarks.WORLD_COUNCIL, Vector2(80, -80), p.radius_km)
	var outside_ll := Landmarks.from_site(Landmarks.WORLD_COUNCIL, Vector2(186, 0), p.radius_km)
	check(not Landmarks.zone_at(inside_ll.x, inside_ll.y, p.radius_km).is_empty(), "a point inside the boundary is neutral ground")
	check(Landmarks.zone_at(outside_ll.x, outside_ll.y, p.radius_km).is_empty(), "100 m outside the boundary the normal rules apply")
	var rt := Landmarks.to_site(Landmarks.WORLD_COUNCIL, inside_ll.x, inside_ll.y, p.radius_km)
	check(rt.distance_to(Vector2(80, -80)) < 0.5, "site metres <-> lat/lon round trip (%.2f m)" % rt.distance_to(Vector2(80, -80)))
	# founding: the start square may not include the property, but right next to it is allowed
	var inside := Geography.rate_site(ll.x, ll.y, [], [])
	check(not inside["valid"] and inside.get("landmark", "") == Landmarks.WORLD_COUNCIL, "no settlement territory over the neutral property")
	var near_ll := Landmarks.from_site(Landmarks.WORLD_COUNCIL, Vector2(0, 700), p.radius_km)
	var near := Geography.rate_site(near_ll.x, near_ll.y, [], [])
	check(not near.has("landmark"), "700 m away (start square outside the boundary): normal founding rules")
	# neutrality tiers
	var ctx_in := {"inside": true}
	check(Landmarks.classify_act("attack_player", {"inside": false}) == "normal", "outside the property: ordinary rules")
	check(Landmarks.classify_act("attack_player", ctx_in) == "prevented", "ordinary attack inside: technically prevented")
	check(Landmarks.classify_act("attack_player", {"inside": true, "repeat": true}) == "violation", "repeated attempts: security violation")
	check(Landmarks.classify_act("carry_weapon", ctx_in) == "violation" and Landmarks.classify_act("block_entrance", ctx_in) == "violation", "weapons and blockades: violation with intervention")
	check(Landmarks.classify_act("declared_state_attack", {"inside": true, "declared_by_state_government": true, "server_validated": true}) == "violation", "no crisis attack while the conflict system is not enabled")
	check(Landmarks.classify_act("declared_state_attack", {"inside": true, "declared_by_state_government": false, "server_validated": true, "crisis_enabled": true}) == "violation", "an individual player can never trigger the crisis event")
	check(Landmarks.classify_act("declared_state_attack", {"inside": true, "declared_by_state_government": true, "server_validated": true, "crisis_enabled": true}) == "crisis", "a declared, server-validated state attack is a crisis event (later phases)")
	check(d["neutrality"]["owner"] == null and d["neutrality"]["humanitarian"]["access"] == "unconditional", "owned by no nation; humanitarian access unconditional")
	# interior programme: every building has its own interior shaped like the exterior
	var prog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/landmarks/concordium_interiors.json"))
	var ids := []
	for b in prog["buildings"]:
		ids.append(b["id"])
	var needed := ["assembly_hall", "portico", "palace_west", "palace_east", "pavilion_corner", "pavilion_west", "pavilion_north", "stoa_west", "stoa_east", "tholos"]
	check(needed.all(func(x): return ids.has(x)), "interior programme covers every building")
	var hall: Dictionary = prog["buildings"][ids.find("assembly_hall")]
	check(hall["shape"]["kind"] == "circle" and Vector2(hall["shape"]["centre"][0], hall["shape"]["centre"][1]) == Vector2(-16, -16), "council chamber is round and lies inside the rotunda")
	check(prog["buildings"].all(func(b): return b["status"] in ["walkable", "preview", "concept"]), "every interior has an explicit status")
	# boundary changes only by the world authority after a resolution
	WorldState.use_storage("user://test_world_council_b.json", true)
	var bigger := PackedVector2Array([Vector2(-86, -86), Vector2(120, -86), Vector2(120, 86), Vector2(-86, 86)])
	check(WorldState.update_landmark_property(Landmarks.WORLD_COUNCIL, bigger, "plr_someone", "res_1") != "", "a player cannot move the boundary")
	check(WorldState.update_landmark_property(Landmarks.WORLD_COUNCIL, bigger, Landmarks.AUTHORITY_ISSUER, "") != "", "no boundary change without a resolution")
	var smaller := PackedVector2Array([Vector2(-50, -50), Vector2(50, -50), Vector2(50, 50), Vector2(-50, 50)])
	check(WorldState.update_landmark_property(Landmarks.WORLD_COUNCIL, smaller, Landmarks.AUTHORITY_ISSUER, "res_2") != "", "the neutral property can never shrink")
	check(WorldState.update_landmark_property(Landmarks.WORLD_COUNCIL, bigger, Landmarks.AUTHORITY_ISSUER, "res_3") == "", "extension by resolution + server update")
	WorldState.load_world()
	var stb := WorldState.landmark_state(Landmarks.WORLD_COUNCIL)
	var east_ll := Landmarks.from_site(Landmarks.WORLD_COUNCIL, Vector2(110, 0), p.radius_km)
	check(int(stb["property"]["version"]) == 2 and not Landmarks.zone_at(east_ll.x, east_ll.y, p.radius_km, {Landmarks.WORLD_COUNCIL: stb}).is_empty(), "extended boundary persists and is neutral")
	WorldState.use_storage(WorldState.DEFAULT_SAVE_PATH, false)
	# persistent state: read through WorldState, survives save/load
	WorldState.use_storage("user://test_world_council.json", true)
	var st := WorldState.landmark_state(Landmarks.WORLD_COUNCIL)
	check(int(st["stage"]) == 1 and st["components"].has("great_fountain"), "initial state: stage 1, components from the definition")
	st["components"]["great_fountain"]["restored"] = 0.5
	WorldState.save_world()
	WorldState.load_world()
	check(float(WorldState.landmark_state(Landmarks.WORLD_COUNCIL)["components"]["great_fountain"]["restored"]) == 0.5, "landmark state persists across save/load")
	WorldState.use_storage(WorldState.DEFAULT_SAVE_PATH, false)
	# assembly on 24 June, world time (UTC)
	var t := Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 11, "day": 25, "hour": 12, "minute": 0, "second": 0})
	var nxt := Landmarks.next_assembly(Landmarks.WORLD_COUNCIL, t)
	var dd := Time.get_datetime_dict_from_unix_time(int(nxt["start"]))
	check(int(nxt["year"]) == 2027 and dd["month"] == 6 and dd["day"] == 24 and dd["hour"] == 0, "next World Assembly: 24 June 2027, 00:00 UTC")
	var during := Landmarks.next_assembly(Landmarks.WORLD_COUNCIL, Time.get_unix_time_from_datetime_dict({"year": 2027, "month": 6, "day": 24, "hour": 15, "minute": 0, "second": 0}))
	check(int(during["year"]) == 2027, "on 24 June the assembly is the current one")
	# preview site: tiles, walk grid, heights, occlusion data
	var v := CouncilSiteView.new()
	check(v.load_site(1), "site data (tiles, walk grid) present")
	check(v.cell_kind(Vector2(-16, 83.4)) == 0 and v.cell_kind(Vector2(-16, 78.5)) == 0, "the gate's central arch is a passage")
	check(v.cell_kind(Vector2(-16, 55)) != 0, "water and the fountain block the way")
	check(absf(v.surface_height(Vector2(-9.5, 12.0)) - 6.9) < 0.2 and v.surface_height(Vector2(-9.5, 26.5)) > 1.0, "podium (6.9 m) reached over the stairs")
	var ok_steps := true
	var h := v.surface_height(Vector2(-9.5, 45.0))
	for y2 in range(90, 16, -1):
		var h2 := v.surface_height(Vector2(-9.5, y2 * 0.5))
		ok_steps = ok_steps and absf(h2 - h) <= CouncilSiteView.STEP_MAX
		h = h2
	check(ok_steps, "the grand stairs can be climbed step by step")
	check(v.cell_kind(Vector2(-16, -16)) != 0, "closed rotunda (stage 1) is not walkable")
	check(absf(float(v.site.get("height_m", 0.0)) - float(d["height_m"])) < 0.05, "exported art has the defined height (%.2f m)" % float(v.site.get("height_m", 0.0)))
	# reachable from the entrance (flood fill on the walk grid)
	var reach := {}
	var start := Vector2i(int((-16.0 - v._x0) / v._cell_m), int((83.4 - v._y0) / v._cell_m))
	var queue: Array[Vector2i] = [start]
	reach[start] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		var hc := float(v._heights[c.y * v._nx + c.x]) / 10.0
		for dlt in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n2: Vector2i = c + dlt
			if n2.x < 0 or n2.y < 0 or n2.x >= v._nx or n2.y >= v._ny or reach.has(n2):
				continue
			var i2 := n2.y * v._nx + n2.x
			if v._kinds[i2] == 0 and absf(float(v._heights[i2]) / 10.0 - hc) <= CouncilSiteView.STEP_MAX:
				reach[n2] = true
				queue.append(n2)
	var at := func(m: Vector2) -> bool: return reach.has(Vector2i(int((m.x - v._x0) / v._cell_m), int((m.y - v._y0) / v._cell_m)))
	check(at.call(Vector2(-40, 45)) and at.call(Vector2(-9.5, 12.0)) and at.call(Vector2(-56, 40)), "reachable from the gate: forum, portico/podium (stairs), west stoa")
	check(at.call(Vector2(4.0, 4.0)), "peristyle walkway around the rotunda reachable")
	check(at.call(Vector2(25.0, -6.0)) and at.call(Vector2(42.0, -6.0)) and at.call(Vector2(60.0, -40.0)), "all three water terraces reachable over the stair flights")
	check(at.call(Vector2(76.0, 71.0)) and at.call(Vector2(38.5, 41.5)) and at.call(Vector2(31.0, 41.5)), "theatre garden reachable (stoa passage, path to the theatre)")
	check(at.call(Vector2(44.0, 46.0)) and at.call(Vector2(57.0, 52.0)), "theatre: the aisle leads down the rows to the orchestra")
	check(at.call(Vector2(65.0, -10.0)) and at.call(Vector2(65.0, -11.0)), "tholos reached over the footbridge across the pool")
	check(at.call(Vector2(25.0, -70.5)), "castellum (Wasserschloss) door reachable beside the north pavilion")
	var unreached := []
	for door in CouncilSiteView.DOORS:
		if not at.call(door["at"]):
			unreached.append(door["key"])
	check(unreached.is_empty() and CouncilSiteView.DOORS.size() >= 8, "every building's door is reachable from the gate (%d doors) %s" % [CouncilSiteView.DOORS.size(), str(unreached)])
	check(v.screen_dir_to_grid(Vector2(1, 0)).normalized().distance_to(Vector2(1, -1).normalized()) < 0.01, "screen right = grid (+x, -y)")
	var k := v.depth_key(Vector2(3, 4))
	check(is_equal_approx(k, 20700.0), "depth key = (x + y + 200) * 100")
	var img: Image = (load("res://assets/landmarks/world_council/stage1/depth_%s.png" % v.site["tiles"][0]["name"]) as Texture2D).get_image()
	check(img.get_width() > 0, "per-pixel depth tiles present")
	# living water: effects list + water codes in the depth tiles
	var kinds := {}
	for fx in v.site.get("fx", []):
		kinds[fx["type"]] = int(kinds.get(fx["type"], 0)) + 1
	check(kinds.get("jet", 0) >= 1 and kinds.get("veil", 0) >= 2 and kinds.get("splash", 0) >= 8, "fountain jet, falling veils and cascade spray defined (%s)" % str(kinds))
	var fpt := Vector2(-16.0, 58.8 + 5.0)                      # basin water south of the fountain column
	var wpos := v.ground_to_world(fpt, 0.1)
	var org := Vector2(float(v.site["origin_m"][0]), -float(v.site["origin_m"][1])) * CouncilSiteView.M_PX
	var kk := CouncilSiteView.M_PX / float(v.site["px_per_m"])
	var ipx := (wpos - org) / kk
	var code := -1
	for tl in v.site["tiles"]:
		if ipx.x >= tl["x"] and ipx.y >= tl["y"] and ipx.x < tl["x"] + tl["w"] and ipx.y < tl["y"] + tl["h"]:
			var di: Image = (load("res://assets/landmarks/world_council/stage1/depth_%s.png" % tl["name"]) as Texture2D).get_image()
			code = int(round(di.get_pixel(int(ipx.x - tl["x"]), int(ipx.y - tl["y"])).b * 255.0)) % 128
	check(code == 1, "fountain basin is marked as water surface in the depth tile (code %d)" % code)
	v.free()
	var live := CouncilSiteView.new()
	add_child(live)
	await get_tree().process_frame
	var st2: Dictionary = live.perf_stats()
	var wat := 0
	for tl in live._tiles:
		var m: ShaderMaterial = (tl["sprite"] as Sprite2D).material
		if m and m.shader.resource_path.ends_with("landmark_water.gdshader"):
			wat += 1
	check(int(st2["effects"]) >= 11 and int(st2["particles"]) < 1200, "water effects running (%d emitters, %d particles)" % [st2["effects"], st2["particles"]])
	check(wat == live._tiles.size(), "every tile draws living water (shader)")
	check(live.figure.get_parent() == live.actors and live.actors.y_sort_enabled, "figure and fountains share one y-sorted layer")
	live.queue_free()
	# globe marker on the drawn surface point
	var gv := GlobeView.new()
	add_child(gv)
	gv.setup(p)
	gv.focus(ll.x, ll.y, 1.8, true)
	await get_tree().process_frame
	var pr := gv.project(ll.x, ll.y)
	var back := gv.pick(pr["pos"])
	check(pr["visible"] and back.distance_to(ll) < 0.05, "globe marker sits on the exact position (pick error %.3f°)" % back.distance_to(ll))
	gv.queue_free()


## Interior standard (docs/INTERIOR_STANDARD.md): straight 3/4 projection,
## furnished rooms without overlaps, art in the same perspective.
func _test_interior_standard() -> void:
	print("[interior standard]")
	check(InteriorScene.to_px(Vector2(1, 0)) == Vector2(InteriorScene.T, 0) and InteriorScene.to_px(Vector2(0, 1)) == Vector2(0, InteriorScene.T), "straight projection: room axes horizontal/vertical, square tiles (no diamonds)")
	check(InteriorScene.MOVE_Y_SCALE == 1.0, "no vertical squash inside (square floor tiles)")
	var atlas := InteriorScene.atlas_data()
	var items: Dictionary = atlas["items"]
	var missing := []
	var too_tall := []
	var keys: Array = InteriorScene.layouts().keys().filter(func(k): return not str(k).begins_with("_") and not InteriorScene.layouts()[k].has("alias"))
	for k in keys:
		var l: Dictionary = InteriorScene.layouts()[k]
		var wall := float(l.get("wall_tiles", InteriorScene.WALL_TILES))
		for e in l.get("items", []):
			var ids: Array = e["item"] if e["item"] is Array else [e["item"]]
			for id in ids:
				if not items.has(id):
					missing.append("%s:%s" % [k, id])
					continue
				var d: Dictionary = items[id]
				if e.has("at") and not e.has("lift") and not d.get("wall", false):
					var sol: Array = d.get("solid", [0, 0, 0, 0])
					var h := (float(d["rect"][3]) - float(sol[3])) / 16.0
					if float(sol[3]) > 0 and h > wall + 0.3:
						too_tall.append("%s:%s %.1f>%.1f" % [k, id, h, wall])
	check(missing.is_empty(), "every piece in the layouts exists in the atlas %s" % str(missing.slice(0, 5)))
	check(too_tall.is_empty(), "no standing piece is taller than the room's walls %s" % str(too_tall.slice(0, 5)))
	var own_missing := []
	for id in items.keys():
		var sh := str(items[id].get("sheet", ""))
		if sh.begins_with("worlds/") and not ResourceLoader.exists("res://assets/interior/" + sh):
			own_missing.append(id)
	check(own_missing.is_empty(), "own interior art present (%d pieces)" % items.values().filter(func(d): return str(d.get("sheet", "")).begins_with("worlds/")).size())
	for sk in ["player_home", "house_1", "house_2", "house_3", "house_4", "house_5", "house_6", "shop_baker", "shop_grocer", "shop_smith", "town_hall", "clinic", "farm_shop", "workshop", "depot", "emergency_post", "energy_station", "water_works"]:
		if not InteriorScene.has_layout(sk):
			missing.append(sk)
	check(missing.is_empty(), "every enterable building of a settlement has its own interior")
	var problems := 0
	var counts := {}
	var art := InteriorScene.assets_available()
	for k in keys:
		if not art and not bool(InteriorScene.layouts()[k].get("own_art_only", false)):
			continue
		var sc := InteriorScene.create(k, [], 3, 0.6)
		sc.position = Vector2(0, 90000)
		add_child(sc)
		await get_tree().process_frame
		var pr := sc.layout_problems()
		if not pr.is_empty():
			print("       ", k, ": ", pr)
		problems += pr.size()
		counts[k] = sc.item_nodes.size()
		sc.queue_free()
	check(problems == 0, "all interiors furnished without overlaps, pieces outside the room or blocked entrances (%d rooms)" % counts.size())
	check(counts.values().all(func(n): return n >= 4), "no empty rooms (fewest pieces: %d)" % (counts.values().min() if not counts.is_empty() else 0))
	# variants: two houses of the same type differ
	if art:
		var a := InteriorScene.create("house_2", [], 11, 0.2)
		var b := InteriorScene.create("house_2", [], 12, 0.9)
		add_child(a)
		add_child(b)
		await get_tree().process_frame
		var na: String = a.item_nodes.map(func(n): return str(n.name).get_slice("_", 0) + str(n.name).get_slice("_", 1)).reduce(func(x, y): return x + y, "")
		var nb: String = b.item_nodes.map(func(n): return str(n.name).get_slice("_", 0) + str(n.name).get_slice("_", 1)).reduce(func(x, y): return x + y, "")
		check(na != nb or a._sheet_swap != b._sheet_swap, "furnishing varies with the building and the settlement's prosperity")
		a.queue_free()
		b.queue_free()
	# Concordium: doors reachable on the site, interiors enterable
	var v := CouncilSiteView.new()
	v.load_site(1)
	var bad := []
	for d in CouncilSiteView.DOORS:
		if v.cell_kind(d["at"]) != 0:
			bad.append(d["key"])
	check(bad.is_empty(), "every Concordium door stands on walkable ground %s" % str(bad))
	v.free()
	var live := CouncilSiteView.new()
	add_child(live)
	await get_tree().process_frame
	live.enter_interior("concordium_chamber")
	await get_tree().process_frame
	await get_tree().physics_frame
	check(live.interior != null and live.walker != null and live.interior.layout.get("label", "") == "Großer Ratssaal", "the council chamber can be entered from the site")
	live._process_inside(0.016)
	check(str(live._context.get("kind", "")) == "exit", "inside, the way out is offered right at the entrance")
	live.leave_interior()
	check(live.interior == null, "leaving returns to the site")
	# doors: rendered with the scene in 4 phases (exact shape, size and occlusion)
	var patched: Array = CouncilSiteView.DOORS.filter(func(d): return d.has("patch"))
	check(patched.size() >= 4 and patched.all(func(d): return live._door_patches.has(d["patch"]) and (live._door_patches[d["patch"]]["frames"] as Array).size() == 4),
		"every door (chamber gate, castellum, refuge, guest house) has 4 rendered opening phases plus x-ray patches")
	live.set_door_phase("chamber", 3)
	check(live.door_phase("chamber") == 3 and (live._door_patches["chamber"]["over"] as Sprite2D).texture == live._door_patches["chamber"]["frames"][3], "door phases swap the patch art")
	live.set_door_phase("chamber", 0)
	# ghosting: at a door the parts in front of it become faint
	live.pos_m = Vector2(-16.0, 9.2)
	live.height_m = live.surface_height(live.pos_m)
	live._place_figure()
	var gm := (live._door_patches["chamber"]["over"] as Sprite2D).material as ShaderMaterial
	check(live._ghost_door == "chamber" and (gm.get_shader_parameter("ghost_b_radius") as Vector2).x > 0.0, "at the chamber door the portico in front of it is ghosted (x-ray of the gate)")
	live.pos_m = Vector2(-16.0, 70.0)
	live.height_m = live.surface_height(live.pos_m)
	live._place_figure()
	check(live._ghost_door == "" and (gm.get_shader_parameter("ghost_b_radius") as Vector2).x == 0.0, "away from doors nothing is x-rayed")
	live.queue_free()
	await _test_council_chamber()
	await _test_interior_generator()


## The Great Council Chamber: >= 1000 delegate places, galleries as a real
## level, doors synced with collisions, everything reachable.
func _test_council_chamber() -> void:
	print("[great council chamber]")
	var l := InteriorScene.resolve("concordium_chamber")
	var t0 := Time.get_ticks_msec()
	var it := InteriorScene.create("concordium_chamber", [], 1, 1.0)
	it.position = Vector2(0, 90000)
	add_child(it)
	await get_tree().process_frame
	var ms := Time.get_ticks_msec() - t0
	check(it.seats.size() >= 1000, "at least 1000 delegate places (%d)" % it.seats.size())
	var ids := {}
	var rows := {}
	var dup := false
	for id in it.seats:
		dup = dup or ids.has(id)
		ids[id] = true
		rows[int(it.seats[id]["row"])] = true
	check(not dup and rows.size() >= 12, "seats have unique ids, rows (%d) and sectors – ready for the council system (phase 10)" % rows.size())
	check(it.layout_problems().is_empty(), "chamber layout without overlaps %s" % str(it.layout_problems().slice(0, 3)))
	var R := it.reachable(it.spawn_point)
	var lost := 0
	for id in it.seats:
		var sp: Vector2 = it.seats[id]["stand"]
		if sp.x < 0.0 or not R.has(it.nav_index(sp)):
			lost += 1
	check(lost == 0, "every delegate place can be reached from the entrance (%d unreachable)" % lost)
	var gal := Vector2(30, 58.5) * InteriorScene.T
	check(it.levels.has("gallery") and absf(it.nav_height(gal) - 4.0) < 0.01 and R.has(it.nav_index(gal)), "the gallery is a real raised level (4 tiles), reached over its stairs")
	check(R.has(it.nav_index(Vector2(4, 30) * InteriorScene.T)) and R.has(it.nav_index(Vector2(116, 30) * InteriorScene.T)), "west and east galleries reachable")
	check(not R.has(it.nav_index(Vector2(30, 52) * InteriorScene.T + Vector2(0, 0))) or it.nav_height(Vector2(30, 52) * InteriorScene.T) == 0.0, "the hall floor stays below the gallery (no jump between levels)")
	# wherever gallery and floor meet (outside the stairs) both collisions are there:
	# the gallery edge for figures up on it, the base for figures below
	var edges: Array = it._blockers.filter(func(bk): return bk["kind"] == "edge").map(func(bk): return (bk["rect"] as Rect2).grow(10.0))
	var bases: Array = it._blockers.filter(func(bk): return bk["kind"] == "level_base").map(func(bk): return bk["rect"])
	var open_jumps := 0
	var pairs := 0
	for j in it.nav_size.y - 1:
		for i in it.nav_size.x - 1:
			var k := j * it.nav_size.x + i
			for k2 in [k + 1, k + it.nav_size.x]:
				if it.nav_h[k] >= 0.0 and it.nav_h[k2] >= 0.0 and absf(it.nav_h[k] - it.nav_h[k2]) > InteriorScene.STEP_MAX:
					pairs += 1
					var up: int = k if it.nav_h[k] > it.nav_h[k2] else k2
					var lo: int = k2 if up == k else k
					var pu := (Vector2(up % it.nav_size.x, up / it.nav_size.x) + Vector2(0.5, 0.5)) * InteriorScene.T / InteriorScene.NAV_RES
					var pl := (Vector2(lo % it.nav_size.x, lo / it.nav_size.x) + Vector2(0.5, 0.5)) * InteriorScene.T / InteriorScene.NAV_RES
					var guarded := edges.any(func(r): return (r as Rect2).has_point((pu + pl) * 0.5)) and bases.any(func(r): return (r as Rect2).has_point(pu))
					if not guarded:
						open_jumps += 1
	check(pairs > 0 and open_jumps == 0, "gallery edges: every drop to the floor is guarded by edge and base collisions (%d edge cells)" % pairs)
	var gate: Array = it.door_states().filter(func(d): return d["type"] == "gate")
	check(gate.size() == 1 and gate[0]["blocking"], "monumental bronze gate between vestibule and hall, closed it blocks")
	check(ms < 3000, "chamber builds quickly (%d ms) – no black screen on mobile" % ms)
	# door opening synced with collision, also for NPCs
	var npc := CharacterBody2D.new()
	var sh := CollisionShape2D.new()
	sh.shape = CircleShape2D.new()
	(sh.shape as CircleShape2D).radius = 9.0
	npc.add_child(sh)
	it.objects.add_child(npc)
	npc.position = gate[0]["pos"] + Vector2(0, InteriorScene.T * 2.0)
	for f in 90:
		it._process(1.0 / 30.0)
	var g2: Array = it.door_states().filter(func(d): return d["type"] == "gate")
	check(float(g2[0]["open"]) > 0.95 and not g2[0]["blocking"], "the gate opens for an approaching figure (NPC) and then lets it through")
	npc.position = Vector2(60, 30) * InteriorScene.T
	for f in 120:
		it._process(1.0 / 30.0)
	g2 = it.door_states().filter(func(d): return d["type"] == "gate")
	check(float(g2[0]["open"]) < 0.05 and g2[0]["blocking"], "and closes again behind it (collision back on)")
	# a figure on the gallery is drawn lifted and collides with the gallery edges
	var body := CharacterBody2D.new()
	var rig := Node2D.new()
	body.add_child(rig)
	it.objects.add_child(body)
	body.position = gal
	var hh := it.carry(body, rig)
	check(absf(hh - 4.0) < 0.01 and is_equal_approx(rig.position.y, -4.0 * InteriorScene.T) and body.collision_mask & InteriorScene.LAYER_LEVEL_EDGE != 0, "on the gallery: drawn 4 tiles up, gallery edges collide")
	body.position = Vector2(60, 30) * InteriorScene.T
	it.carry(body, rig)
	check(body.collision_mask & InteriorScene.LAYER_LEVEL_BASE != 0 and is_equal_approx(rig.position.y, 0.0), "on the floor: gallery base collides, drawn at floor level")
	check(str(l.get("label", "")) == "Großer Ratssaal" and it.nearest_seat(it.seats.values()[0]["pos"]) != "", "a seat can be taken at its place")
	# upper level / walls in front of the player become faint
	var walker := CharacterBody2D.new()
	walker.name = "Walker"
	it.objects.add_child(walker)
	walker.position = Vector2(30, 54.2) * InteriorScene.T      # on the floor just behind the south gallery
	body.queue_free()
	for f in 30:
		it._process(1.0 / 30.0)
	check(it.ghosted_count() > 0, "the gallery in front of the player turns faint, so the player sees where they are (%d parts)" % it.ghosted_count())
	walker.position = Vector2(60, 20) * InteriorScene.T
	for f in 30:
		it._process(1.0 / 30.0)
	check(it.ghosted_count() == 0, "in the open hall nothing is faded")
	it.queue_free()


## Generated interiors: deterministic, valid, connected – from small houses to palaces.
func _test_interior_generator() -> void:
	print("[interior generator]")
	var fails := []
	var n := 0
	for type in InteriorGenerator.TYPES:
		for sz in [Vector2i(8, 7), Vector2i(14, 10), Vector2i(24, 16), Vector2i(36, 28), Vector2i(50, 50)]:
			for sd in [1, 2]:
				n += 1
				var key := InteriorGenerator.key_for(type, sz, sd, 0.45 * sd)
				var l := InteriorScene.resolve(key)
				if l.is_empty() or not InteriorGenerator.unreachable_rooms(l).is_empty():
					fails.append(key)
					continue
				var it := InteriorScene.create(key, [], sd, 0.5)
				it.position = Vector2(0, 120000)
				add_child(it)
				await get_tree().process_frame
				var R := it.reachable(it.spawn_point)
				var ok := it.layout_problems().is_empty()
				for r in l["rooms"]:
					var c := Vector2(r["rect"][0], r["rect"][1])
					var found := false
					for j in range(int(float(r["rect"][1]) * InteriorScene.NAV_RES), int((float(r["rect"][1]) + float(r["rect"][3])) * InteriorScene.NAV_RES)):
						for i in range(int(c.x * InteriorScene.NAV_RES), int((c.x + float(r["rect"][2])) * InteriorScene.NAV_RES)):
							if R.has(j * it.nav_size.x + i):
								found = true
								break
						if found:
							break
					ok = ok and found
				if not ok:
					fails.append(key)
				it.queue_free()
	check(fails.is_empty(), "%d generated interiors (6 types, 8×7 … 50×50): no overlaps, every room reachable %s" % [n, str(fails.slice(0, 4))])
	var a := JSON.stringify(InteriorGenerator.generate("palace", Vector2i(40, 32), 7, 0.8))
	check(a == JSON.stringify(InteriorGenerator.generate("palace", Vector2i(40, 32), 7, 0.8)), "generation is reproducible (same key, same interior)")
	check(a != JSON.stringify(InteriorGenerator.generate("palace", Vector2i(40, 32), 8, 0.8)), "another seed gives another interior")
	var big := InteriorGenerator.generate("palace", Vector2i(40, 32), 3, 0.9)
	var kinds: Array = big["rooms"].map(func(r): return r["kind"])
	check(kinds.has("corridor") and kinds.has("hall") and kinds.size() >= 8, "a palace gets a hall, corridors and many rooms (%d)" % kinds.size())
	var small := InteriorGenerator.generate("house", Vector2i(9, 8), 3, 0.5)
	check(not small["rooms"].map(func(r): return r["kind"]).has("corridor") and small["rooms"].size() >= 2, "a small house: living room and back rooms, no corridor")
	check(InteriorScene.layout_available(InteriorGenerator.key_for("house", Vector2i(12, 10), 1)), "generated interiors need only own art (work in every build)")


## Phase 5 – social life: relationships, families and children, groups,
## memories, goals, conversations (docs/SOCIAL_SYSTEM.md).
func _test_social_life() -> void:
	print("[social life – phase 5]")
	var cfg := SettlementSim.load_config()
	var data := SettlementData.load_from_file("res://data/settlement_templates/founding_basic.json")
	var comp: Array = cfg.get("founding_population", {}).get("composition", [])
	var day0 := 20800
	var mk := func(sid: String) -> Dictionary:
		var r := {"settlement_id": sid, "npcs": NpcRoster.generate(sid, data.buildings, comp), "resident_player_ids": ["plr_a"], "region_factors": {"food": 1.0, "water": 1.0, "energy": 1.0, "materials": 1.0}}
		SettlementCore.ensure(r, cfg, day0)
		return r
	var a: Dictionary = mk.call("stl_soc_t")
	var b: Dictionary = mk.call("stl_soc_t")
	var us := Time.get_ticks_usec()
	for d in 360:
		SettlementCore.day_step(a, data, cfg, day0 + d, 60)
	var ms := (Time.get_ticks_usec() - us) / 1000.0
	for d in 360:
		SettlementCore.day_step(b, data, cfg, day0 + d, 60)
	check(JSON.stringify(a["social"]) == JSON.stringify(b["social"]) and JSON.stringify(a["npcs"]) == JSON.stringify(b["npcs"]), "social life is reproducible (same seeds, same relationships, families and groups)")
	var day := day0 + 359
	var edges: Dictionary = a["social"]["edges"]
	var kinds := {}
	for k in edges:
		kinds[edges[k]["kind"]] = int(kinds.get(edges[k]["kind"], 0)) + 1
	var friends := int(kinds.get("friend", 0)) + int(kinds.get("close_friend", 0))
	var people: Array = SettlementCore.alive_npcs(a)
	check(friends >= 5 and friends <= people.size() * 3, "friendships grow from shared work, home and leisure – not with everybody (%d friendships, %d people)" % [friends, people.size()])
	check(int(kinds.get("partner", 0)) >= 1, "partnerships form between adults who are close (%d couples)" % int(kinds.get("partner", 0)))
	var groups: Dictionary = a["social"]["groups"]
	check(groups.size() >= 1 and groups.values().all(func(g): return (g["members"] as Array).size() >= 1) and groups.size() <= maxi(1, people.size() / 8), "social groups (clubs) are founded by people who share an interest (%s)" % ", ".join(PackedStringArray(groups.values().map(func(g): return "%s %d" % [g["name"], g["members"].size()]))))
	var mem_ok := people.all(func(r): return (SocialCore.person(r)["memories"] as Array).size() <= SocialCore.MAX_MEMORIES)
	var with_mem := people.filter(func(r): return not (SocialCore.person(r)["memories"] as Array).is_empty()).size()
	check(mem_ok and with_mem >= people.size() / 2, "important events become memories, trivial ones do not (%d of %d with memories, at most %d each)" % [with_mem, people.size(), SocialCore.MAX_MEMORIES])
	var with_goal := people.filter(func(r): return not SocialCore.is_child(r, day, cfg) and not (SocialCore.person(r)["goals"] as Array).is_empty()).size()
	check(with_goal == people.filter(func(r): return not SocialCore.is_child(r, day, cfg)).size(), "every adult pursues personal goals")
	var met_group := people.filter(func(r): return not (SocialCore.person(r).get("meetings", []) as Array).is_empty())
	check(met_group.size() >= 3 and met_group.all(func(r): return (r["social"]["meetings"][0] as Array).size() == 3), "club members carry their meeting times into the daily routine")
	print("       one simulated year of social life: %.0f ms (%.1f ms/day incl. Phase 4)" % [ms, ms / 360.0])
	# a child: family links, half-capacity housing, never dies, grows up
	var couple: Array = people.filter(func(r): return str(SocialCore.person(r)["partner_id"]) != "")
	var pa: Dictionary = couple[0] if not couple.is_empty() else people[0]
	var pb: Dictionary = SettlementCore._npc(a, str(SocialCore.person(pa)["partner_id"])) if not couple.is_empty() else people[1]
	var child := SocialCore._new_child(a, cfg, pa, pb, day)
	check(child["employment"]["status"] == "child" and SocialCore.person(child)["parents"].has(pa["npc_id"]) and SocialCore.person(pa)["children"].has(child["npc_id"]) and SocialCore.edge(a, pa["npc_id"], child["npc_id"])["kind"] == "family",
		"a newborn belongs to its parents' household with family ties (%s)" % SocialCore.life_stage(child, day, cfg))
	var deadly := cfg.duplicate(true)
	deadly["demography"]["gompertz_a"] = 10.0
	SettlementCore.day_step(a, data, deadly, day + 1, 60)
	check(child.get("alive", true), "Master §13.7: a child never dies in the simulation – not even when the adults' mortality is extreme")
	check(SettlementCore._pool(a).all(func(r): return r["employment"]["status"] != "child") and not SettlementCore._pool(a).has(child), "children are not given jobs or shifts")
	child["arrived_day"] = day + 1 - int(19 * float(cfg["demography"]["days_per_year"]))
	var evs := SettlementCore.day_step(a, data, cfg, day + 2, 60)
	check(child["employment"]["status"] == "pool" and evs.any(func(e): return e["kind"] == "grown_up"), "at 18 a young person becomes an adult and looks for work")
	# conversations: first meeting, topics grow with familiarity, no grinding, promises
	var c: Dictionary = mk.call("stl_soc_talk")
	var npc: Dictionary = SettlementCore.alive_npcs(c)[3]
	var pid := "player:plr_a"
	check(SocialCore.topics_for(c, npc, pid, day0, cfg) == ["chat", "wellbeing", "interests"], "strangers only chat; deeper topics need familiarity")
	var r1 := SocialCore.talk(c, npc, pid, "Test", "chat", day0, cfg, 0.8)
	check(r1["first"] and SocialCore.person(npc)["memories"].any(func(m): return m["kind"] == "met_player"), "the first conversation is remembered (\"%s\")" % r1["line"])
	var aff1 := float(r1["edge"]["affinity"])
	for i in 9:
		SocialCore.talk(c, npc, pid, "Test", "chat", day0, cfg, 0.8)
	var aff10 := float(SocialCore.edge(c, npc["npc_id"], pid)["affinity"])
	check(aff10 < aff1 * 6.0, "talking ten times a day does not buy a friendship (diminishing effect: %.2f after 1, %.2f after 10)" % [aff1, aff10])
	for d in 6:
		SocialCore.talk(c, npc, pid, "Test", "wellbeing", day0 + 1 + d, cfg, 0.7)
	check(SocialCore.topics_for(c, npc, pid, day0 + 8, cfg).has("help"), "after some days of conversations you can talk about goals and offer help")
	var e0: Dictionary = SocialCore.edge(c, npc["npc_id"], pid)
	e0["trust"] = 0.4
	SocialCore.talk(c, npc, pid, "Test", "help", day0 + 8, cfg, 0.7)
	var tr0 := float(e0["trust"])
	var kept := SocialCore.talk(c, npc, pid, "Test", "chat", day0 + 10, cfg, 0.7)
	check(float(kept["edge"]["trust"]) > tr0 and SocialCore.person(npc)["memories"].any(func(m): return m["kind"] == "promise_kept"), "a promise kept in time is remembered and builds trust")
	# absence without obligation is no problem (Master §13.1): player contacts fade very slowly
	var fam0 := float(e0["familiarity"])
	for d in 70:
		SocialCore.day_step(c, data, cfg, day0 + 20 + d, t0_social(day0 + 20 + d), [])
	check(float(e0["familiarity"]) >= fam0 - 0.05 and e0["kind"] == SocialCore.edge(c, npc["npc_id"], pid)["kind"], "70 days away: the relationship with the player is still there (familiarity %.2f → %.2f)" % [fam0, float(e0["familiarity"])])
	# the world authority accepts conversations from residents only (server-capable)
	var recs: Array = [{"settlement_id": "stl_soc_auth", "template_path": "res://data/settlement_templates/founding_basic.json", "founder_player_id": "plr_founder",
		"resident_player_ids": ["plr_founder"], "admin_player_ids": ["plr_founder"], "founded_at_unix": 1795000000, "time_zone": {"name": "Test/CET", "offset_min": 60}}]
	var auth := WorldAuthority.create(func(): return recs, func(): return 1795000000 + 3600, cfg)
	auth.ensure_population(recs[0])
	var target: String = recs[0]["npcs"][2]["npc_id"]
	var res := LocalWorldClient.connect_to(auth, "plr_founder").submit({"kind": "talk", "settlement_id": "stl_soc_auth", "payload": {"npc_id": target, "topic": "chat", "name": "Gründer"}})
	var res2 := LocalWorldClient.connect_to(auth, "plr_stranger").submit({"kind": "talk", "settlement_id": "stl_soc_auth", "payload": {"npc_id": target, "topic": "chat"}})
	check(res.get("ok", false) and str(res.get("result", {}).get("line", "")) != "" and not res2.get("ok", true), "conversations are commands to the world authority: residents may talk, strangers are refused")
	check(WorldAuthority.state_hash(recs[0]) != "" and recs[0].has("social"), "social state is part of the shared, hashed settlement state")


static func t0_social(day: int) -> int:
	return day * 86400 - 3600
