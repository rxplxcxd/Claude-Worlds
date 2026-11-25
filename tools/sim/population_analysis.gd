extends Node
## Founding-population analysis (docs/SETTLEMENT_SYSTEM.md §2a).
## Runs the settlement day step (the same code as the game) for candidate
## founding compositions, two site qualities and three seeds over two years
## and prints a Markdown table. Usage:
##   godot --headless --path . res://tools/sim/population_analysis.tscn

const CANDIDATES := {
	"16 (Minimum)": [["admin", 1], ["utility", 2], ["rescue", 1], ["security", 1], ["medic", 1], ["farmer", 3], ["builder", 1], ["merchant", 4], ["worker", 1], ["resident", 1]],
	"20": [["admin", 1], ["utility", 3], ["rescue", 1], ["security", 1], ["medic", 2], ["farmer", 4], ["builder", 2], ["merchant", 4], ["worker", 1], ["resident", 1]],
	"26": [["admin", 1], ["utility", 4], ["rescue", 2], ["security", 1], ["medic", 2], ["farmer", 4], ["builder", 2], ["transport", 1], ["craftsman", 1], ["merchant", 5], ["worker", 2], ["resident", 1]],
	"30": [["admin", 1], ["utility", 4], ["rescue", 2], ["security", 1], ["medic", 2], ["farmer", 4], ["builder", 3], ["transport", 1], ["craftsman", 1], ["merchant", 5], ["worker", 4], ["resident", 2]],
	"34": [["admin", 1], ["utility", 4], ["rescue", 2], ["security", 1], ["medic", 2], ["farmer", 5], ["builder", 3], ["transport", 1], ["craftsman", 1], ["merchant", 5], ["worker", 6], ["resident", 3]],
	"44": [["admin", 2], ["utility", 4], ["rescue", 3], ["security", 2], ["medic", 3], ["farmer", 6], ["builder", 3], ["transport", 2], ["craftsman", 2], ["merchant", 6], ["worker", 8], ["resident", 3]],
}
const SITES := {"gut": {"food": 1.05, "water": 1.0, "energy": 1.0, "materials": 1.0}, "schwach": {"food": 0.65, "water": 0.75, "energy": 0.8, "materials": 0.8}}
const DAYS := 730
var OPEN := true


func _ready() -> void:
	var cfg := SettlementSim.load_config()
	var data := SettlementData.load_from_file("res://data/settlement_templates/founding_basic.json")
	var day0 := 20800
	OPEN = not OS.get_cmdline_user_args().has("--closed")
	print("Zuzug: ", "offen" if OPEN else "geschlossen (Eigenleistung der Gründung)")
	print("| Gründung | Standort | Engpasstage (Nahrung/Wasser/Energie) | kritische Abdeckung Ø | offene Dienststunden/Tag | Vertretungen/Jahr | Bevölkerung nach 2 J. | Arbeitssuchend Ø | Zustand Gebäude Ø |")
	print("|---|---|---|---|---|---|---|---|---|")
	for name in CANDIDATES:
		for site in SITES:
			var acc := {"short_f": 0.0, "short_w": 0.0, "short_e": 0.0, "crit": 0.0, "gap": 0.0, "subst": 0.0, "pop": 0.0, "unemp": 0.0, "cond": 0.0}
			for seed in 3:
				var sid := "stl_ana_%d" % seed
				var rec := {"settlement_id": sid, "npcs": NpcRoster.generate(sid, data.buildings, CANDIDATES[name]), "resident_player_ids": ["plr_a"], "region_factors": SITES[site]}
				SettlementCore.ensure(rec, cfg, day0)
				rec["core"]["policy"]["open_for_newcomers"] = OPEN
				for d in DAYS:
					for e in SettlementCore.day_step(rec, data, cfg, day0 + d, 60):
						if e["kind"] == "substitution":
							acc["subst"] += 1.0
					var st: Dictionary = rec["core"]["stats"]
					acc["short_f"] += 1.0 if st.get("food_short", false) else 0.0
					acc["short_w"] += 1.0 if st.get("water_short", false) else 0.0
					acc["short_e"] += 1.0 if st.get("energy_short", false) else 0.0
					var cov: Dictionary = rec["core"]["coverage"]
					acc["crit"] += (float(cov["wasser"]) + float(cov["energie"]) + float(cov["medizin"]) + float(cov["notfall"])) / 4.0
					var gaps: Dictionary = rec["core"]["plan"][str(day0 + d)]["gaps"]
					for b in gaps:
						acc["gap"] += float(gaps[b])
					acc["unemp"] += float(st.get("unemployed", 0))
				acc["pop"] += float(rec["core"]["stats"]["population"])
				var c := 0.0
				for b in rec["core"]["condition"]:
					c += float(rec["core"]["condition"][b])
				acc["cond"] += c / maxf(1.0, rec["core"]["condition"].size())
			var runs := 3.0
			var days := DAYS * runs
			print("| %s | %s | %.0f / %.0f / %.0f | %.0f %% | %.1f | %.0f | %.0f | %.1f | %.0f %% |" % [name, site, acc["short_f"] / runs, acc["short_w"] / runs, acc["short_e"] / runs,
				acc["crit"] / days * 100.0, acc["gap"] / days, acc["subst"] / runs / 2.0, acc["pop"] / runs, acc["unemp"] / days, acc["cond"] / runs * 100.0])
	get_tree().quit()
