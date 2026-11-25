extends Node
## Social-life analysis (docs/SOCIAL_SYSTEM.md): runs the real settlement day
## step (Phase 4 + Phase 5) for the founding population over several years
## and three seeds; prints friendships, partnerships, births, groups, goals.
##   godot --headless --path . res://tools/sim/social_analysis.tscn [days]

func _ready() -> void:
	var cfg := SettlementSim.load_config()
	var data := SettlementData.load_from_file("res://data/settlement_templates/founding_basic.json")
	var comp: Array = cfg.get("founding_population", {}).get("composition", [])
	var days := int(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else 720
	var day0 := 20800
	if OS.get_cmdline_user_args().has("--off"):
		cfg["social"]["enabled"] = false
	var t0 := Time.get_ticks_msec()
	print("| Seed | Tage | Bevölkerung | Kinder | Freundschaften | eng | Paare | Geburten | Vereine (Mitglieder) | Rivalitäten | erreichte Ziele | Erinnerungen Ø | Kanten |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for seed in 3:
		var sid := "stl_soc_%d" % seed
		var rec := {"settlement_id": sid, "npcs": NpcRoster.generate(sid, data.buildings, comp), "resident_player_ids": ["plr_a"], "region_factors": {"food": 1.0, "water": 1.0, "energy": 1.0, "materials": 1.0}}
		SettlementCore.ensure(rec, cfg, day0)
		var goals := 0
		for d in days:
			for e in SettlementCore.day_step(rec, data, cfg, day0 + d, 60):
				if e["kind"] == "goal_reached":
					goals += 1
		var day := day0 + days - 1
		var alive := SettlementCore.alive_npcs(rec)
		var kids := alive.filter(func(r): return SocialCore.is_child(r, day, cfg)).size()
		var edges: Dictionary = SocialCore.state(rec)["edges"]
		var k := {}
		for key in edges:
			k[edges[key]["kind"]] = int(k.get(edges[key]["kind"], 0)) + 1
		var groups: Dictionary = SocialCore.state(rec)["groups"]
		var gtxt := PackedStringArray()
		for g in groups.values():
			gtxt.append("%s %d" % [g["name"], g["members"].size()])
		var mem := 0.0
		for r in alive:
			mem += float((SocialCore.person(r)["memories"] as Array).size())
		var c: Dictionary = SocialCore.state(rec)["counters"]
		print("| %d | %d | %d | %d | %d | %d | %d | %d | %s | %d | %d | %.1f | %d |" % [seed, days, alive.size(), kids, int(k.get("friend", 0)) + int(k.get("close_friend", 0)),
			int(k.get("close_friend", 0)), int(k.get("partner", 0)), int(c.get("births", 0)), ", ".join(gtxt), int(k.get("rival", 0)), goals, mem / maxf(1.0, alive.size()), edges.size()])
	print("Laufzeit: %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit()
