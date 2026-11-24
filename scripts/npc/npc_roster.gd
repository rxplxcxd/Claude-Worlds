class_name NpcRoster
extends RefCounted
## Founding community of a settlement (identities only, no simulation).
##
## Generated ONCE when a player founds a settlement (deterministic from the
## settlement ID) and stored in the WorldState record, so every NPC keeps its
## name, role, workplace and appearance permanently (and can later be synced
## to Firestore: worlds/{id}/npcs/{npcId}). NPCs only exist inside settlements
## founded by humans (empty-planet rule, docs/WORLD_DESIGN.md §1).
## Needs, daily routines and AI follow in Phase 3.

## role -> how many, in the order they are created.
const COMPOSITION := [
	["admin", 1], ["merchant", 2], ["medic", 1], ["security", 1], ["builder", 2],
	["craftsman", 1], ["farmer", 2], ["resident", 2],
]
const FIRST_NAMES := ["Mara", "Jonas", "Lea", "Emil", "Ida", "Finn", "Nora", "Paul", "Greta", "Ole", "Lina", "Theo",
	"Mila", "Karl", "Frieda", "Anton", "Ella", "Henry", "Romy", "Jakob", "Alma", "Levi", "Clara", "Milan"]
const LAST_NAMES := ["Hoffmann", "Becker", "Wagner", "Schulz", "Krüger", "Lange", "Brandt", "Vogel", "Seidel", "Hahn",
	"Arnold", "Keller", "Roth", "Winter", "Sommer", "Berg", "Jäger", "Franke"]


## Creates the roster for a settlement. `buildings` = SettlementData.buildings.
static func generate(settlement_id: String, buildings: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(settlement_id + "#npcs")
	var by_type := {}
	for b in buildings:
		by_type[b.get("type", "")] = b.get("id", "")
	var homes: Array = buildings.filter(func(b): return b.get("type", "") == "house").map(func(b): return b.get("id", ""))
	# First names are drawn without repetition (shuffled), surnames freely.
	var first: Array = FIRST_NAMES.duplicate()
	for i in range(first.size() - 1, 0, -1):
		var k := rng.randi_range(0, i)
		var tmp: Variant = first[i]
		first[i] = first[k]
		first[k] = tmp
	var out: Array = []
	var n := 0
	for spec in COMPOSITION:
		for i in int(spec[1]):
			var role: String = spec[0]
			var name := "%s %s" % [first[n % first.size()], LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)]]
			var seed := rng.randi()
			var workplace := ""
			for t in CharacterCatalog.data.get("roles", {}).get(role, {}).get("workplace", []):
				workplace = by_type.get(t, "")
			out.append({
				"npc_id": "npc_%s_%02d" % [settlement_id.trim_prefix("stl_"), n],
				"name": name,
				"role": role,
				"workplace_id": workplace,
				"home_id": homes[n % homes.size()] if not homes.is_empty() else "",
				"appearance": CharacterCatalog.role_appearance(role, seed),
				"index_in_role": i,
			})
			n += 1
	return out


## Tiles NPCs may stand on.
const STAND_TILES := ["sidewalk", "path", "grass", "plaza", "dirt", "sand"]


## Finds a standing spot for every NPC: next to (never in front of) the door
## of its workplace during the day and of its home in the evening. Residents
## without a workplace spend the day around the plaza. Spots avoid roads,
## water, buildings, entrances, props and street furniture and are unique.
## Returns npc_id -> {"work": Vector2, "home": Vector2} (grid coordinates).
static func plan_spots(data: SettlementData, roster: Array, extra_blocked: Array = []) -> Dictionary:
	var blocked := {}
	for b in data.buildings:
		for c in data.get_building_cells(b):
			blocked[c] = true
		for c in StreetPlanner.entrance_cells(b):
			blocked[c] = true
	for p in data.props:
		var g: Vector2 = p["grid_v"]
		var f: Vector2 = p.get("footprint_v", Vector2.ZERO)
		if f != Vector2.ZERO:
			for y in range(int(floor(g.y - f.y * 0.5)), int(ceil(g.y + f.y * 0.5))):
				for x in range(int(floor(g.x - f.x * 0.5)), int(ceil(g.x + f.x * 0.5))):
					blocked[Vector2i(x, y)] = true
		else:
			blocked[Vector2i(int(floor(g.x)), int(floor(g.y)))] = true
	for c in extra_blocked:
		blocked[c] = true
	var by_id := {}
	for b in data.buildings:
		by_id[b.get("id", "")] = b
	var out := {}
	for npc in roster:
		var spots := {}
		for key in ["work", "home"]:
			var bid: String = npc.get("workplace_id" if key == "work" else "home_id", "")
			var cell := Vector2i(-1, -1)
			if by_id.has(bid):
				cell = _spot_near_building(data, by_id[bid], blocked)
			if cell.x < 0:
				cell = _spot_near_point(data, Vector2(data.size) * 0.5, blocked)
			if cell.x >= 0:
				blocked[cell] = true
				spots[key] = Vector2(cell) + Vector2(0.5, 0.5)
		out[npc["npc_id"]] = spots
	return out


## Ring of cells around the building, visible sides (+y, +x) first, cells
## beside the entrance before cells further away.
static func _spot_near_building(data: SettlementData, b: Dictionary, blocked: Dictionary) -> Vector2i:
	var g: Vector2 = b["grid_v"]
	var f: Vector2 = b["footprint_v"]
	var door := Vector2(g.x + f.x * 0.5, g.y + f.y + 0.5)
	var best := Vector2i(-1, -1)
	var best_score := INF
	for y in range(int(g.y) - 2, int(g.y + f.y) + 3):
		for x in range(int(g.x) - 2, int(g.x + f.x) + 3):
			var c := Vector2i(x, y)
			if blocked.has(c) or not data.get_tile(x, y) in STAND_TILES:
				continue
			var front := y >= int(g.y + f.y) or x >= int(g.x + f.x)
			var score := Vector2(c).distance_to(door) + (0.0 if front else 4.0)
			if score < best_score:
				best_score = score
				best = c
	return best


static func _spot_near_point(data: SettlementData, p: Vector2, blocked: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for y in data.size.y:
		for x in data.size.x:
			var c := Vector2i(x, y)
			if blocked.has(c) or not data.get_tile(x, y) in STAND_TILES:
				continue
			var d := Vector2(c).distance_to(p)
			if d < best_d and d > 2.2:
				best_d = d
				best = c
	return best
