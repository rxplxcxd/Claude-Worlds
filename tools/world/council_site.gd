extends Node
## Standortanalyse für den Weltratssitz (docs/WORLD_COUNCIL.md §2).
## Durchsucht alle Landzellen des Kontinents Kalistia und bewertet sie nach
## Klima, Gelände, Wasser, Ebenheit (Platz für Flughafen/Bahnhof), Lage im
## Kontinent und Küstenzugang (Hafen). Gibt die besten Kandidaten aus.
## Aufruf: godot --headless --path . res://tools/world/council_site.tscn

const CONTINENT := "Kalistia"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 3 and args[0] == "refine":
		_refine(float(args[1]), float(args[2]))
		get_tree().quit()
		return
	var p := Geography.planet()
	var cid := ""
	var centre := Vector2.ZERO
	for c in p.continents:
		if c["name"] == CONTINENT:
			cid = c["continent_id"]
			centre = Vector2(c["center"][0], c["center"][1])
	print("continent ", cid, " centre ", centre)
	var cidx := 0
	for k in p.continents.size():
		if p.continents[k]["continent_id"] == cid:
			cidx = k + 1
	var cands := []
	for i in p.width * p.height:
		if p.continent_of[i] != cidx or not p.is_land(i):
			continue
		var b: String = PlanetData.BIOME_IDS[p.biome[i]]
		if not b in ["plain", "hills", "forest"]:
			continue
		var ll := p.cell_lat_lon(i)
		var t: float = p.temperature_c[i]
		var rain: float = p.rainfall[i]
		var e: float = p.elevation_m[i]
		if absf(t - 17.0) > 7.0 or absf(rain - 0.5) > 0.3:
			continue
		var x := i % p.width
		var y := i / p.width
		# neighbourhood (radius 3 cells ≈ 150 km)
		var land := 0
		var tot := 0
		var e_var := 0.0
		var mountains := 0
		var water_near := false
		var coast_near := false
		var river_near := false
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var yy := y + dy
				if yy < 0 or yy >= p.height:
					continue
				var j := p.index(x + dx, yy)
				tot += 1
				if p.is_land(j):
					land += 1
					e_var += absf(p.elevation_m[j] - e)
				if p.biome[j] == PlanetData.Biome.MOUNTAIN and absi(dx) <= 1 and absi(dy) <= 1:
					mountains += 1
				if absi(dx) <= 1 and absi(dy) <= 1:
					if p.biome[j] == PlanetData.Biome.LAKE:
						water_near = true
					if p.river[j] == 1:
						river_near = true
					if p.biome[j] == PlanetData.Biome.OCEAN:
						coast_near = true
		var flat := 1.0 - clampf(e_var / maxf(1, land) / 400.0, 0.0, 1.0)
		var climate := clampf(1.0 - absf(t - 17.0) / 9.0, 0.0, 1.0) * clampf(1.0 - absf(rain - 0.5) * 2.0, 0.0, 1.0)
		var water := 1.0 if river_near else (0.9 if water_near else (0.85 if coast_near else 0.2))
		var central := clampf(1.0 - Vector2(ll.x - centre.x, (ll.y - centre.y) * cos(deg_to_rad(ll.x))).length() / 25.0, 0.0, 1.0)
		var room := float(land) / float(tot)
		var elev := 1.0 if e > 30 and e < 500 else (0.6 if e < 900 else 0.1)
		var terrain: float = {"plain": 1.0, "hills": 0.9, "forest": 0.75}[b]
		var harbour := 1.0 if coast_near else 0.5
		var score := climate * 0.3 + water * 0.15 + flat * 0.12 + central * 0.13 + room * 0.1 + elev * 0.07 + terrain * 0.05 + harbour * 0.08 - mountains * 0.05
		cands.append({"score": score, "lat": ll.x, "lon": ll.y, "b": b, "t": t, "rain": rain, "e": e, "river": river_near, "lake": water_near, "coast": coast_near, "flat": flat, "central": central, "room": room, "region": p.region_of[i]})
	cands.sort_custom(func(a, b): return a["score"] > b["score"])
	for k in mini(25, cands.size()):
		var c: Dictionary = cands[k]
		var reg: Dictionary = p.regions[c["region"] - 1]
		print("%.3f  %.2f,%.2f %s t=%.0f rain=%.2f e=%.0f river=%s lake=%s coast=%s flat=%.2f central=%.2f room=%.2f  %s" % [c["score"], c["lat"], c["lon"], c["b"], c["t"], c["rain"], c["e"], c["river"], c["lake"], c["coast"], c["flat"], c["central"], c["room"], reg.get("name", "")])
	get_tree().quit()


## Fine scan (0.1°) around a candidate: land, coast distance, elevation,
## slope, water in eight directions (LocalTerrain.probe).
func _refine(lat0: float, lon0: float) -> void:
	var p := Geography.planet()
	var rows := []
	for a in range(-12, 13):
		for b in range(-12, 13):
			var lat := lat0 + a * 0.1
			var lon := lon0 + b * 0.1
			if not p.is_land_at(lat, lon):
				continue
			var s := p.sample(lat, lon)
			# distance to drawn coast (km), searched in 8 directions
			var coast_km := INF
			for d in LocalTerrain.DIRS:
				var dn: Vector2 = d.normalized()
				for k in range(1, 40):
					var km := k * 2.5
					if not p.is_land_at(lat - dn.y * km / 111.0, lon + dn.x * km / (111.0 * cos(deg_to_rad(lat)))):
						coast_km = minf(coast_km, km)
						break
			var slope := 0.0
			for d in LocalTerrain.DIRS:
				var dn2: Vector2 = d.normalized()
				var s2 := p.sample(lat - dn2.y * 0.25, lon + dn2.x * 0.25)
				slope = maxf(slope, absf(float(s2["elevation_m"]) - float(s["elevation_m"])))
			rows.append([lat, lon, s["biome"], s["temperature_c"], s["rainfall"], s["elevation_m"], s["river"], coast_km, slope, s["region_id"]])
	rows.sort_custom(func(x, y): return absf(x[7] - 12.0) + x[8] / 40.0 < absf(y[7] - 12.0) + y[8] / 40.0)
	for k in mini(15, rows.size()):
		var r: Array = rows[k]
		print("%.2f,%.2f %s t=%.0f rain=%.2f e=%.0f river=%s coast_km=%.1f slope=%.0f %s" % r)
	var pr := LocalTerrain.probe(lat0, lon0)
	for d in pr["dirs"]:
		print("dir ", d["dir"], " water_km=", d["water_km"], " ", d["water"], " rise=", d["rise_m"])
