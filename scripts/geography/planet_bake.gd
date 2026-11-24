extends SceneTree
## Bakes the planet once from data/world/genesis.json into data/world/planet/.
##   godot --headless --path . -s res://scripts/geography/planet_bake.gd
## The baked files are committed: every client (and later the server) loads
## the identical planet instead of re-running the generator (floating point
## differences between platforms must never move a region border).

func _init() -> void:
	var genesis: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/genesis.json"))
	var spec: Dictionary = genesis.get("planet", {})
	spec["planet_id"] = genesis.get("planet_id", "pln_aurel")
	spec["planet_name"] = genesis.get("planet_name", "Aurel")
	var t := Time.get_ticks_msec()
	var p := PlanetGenerator.new().generate(spec)
	var err := p.save_to(ProjectSettings.globalize_path("res://data/world/planet"))
	print("planet %s: %d continents, %d regions, %d ms, fingerprint %s, save %s" % [p.name, p.continents.size(), p.regions.size(), Time.get_ticks_msec() - t, p.fingerprint(), error_string(err)])
	quit(0 if err == OK else 1)
