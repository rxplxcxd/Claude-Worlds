class_name VisualEventRouter
extends RefCounted
## Phase 3 – connects the simulation to the visual layer (Living Assets + VFX).
##
## Two kinds of output, both data-driven (data/sim/living_world.json →
## "visual_events"):
##  1. ACTIVE EFFECTS derived from the CURRENT simulation state (e.g. chimney
##     smoke while somebody cooks at home). Because they are computed from
##     state and time – not from remembered events – a player entering an
##     area always sees what is true now, never a stale or replayed effect.
##  2. PERSISTENT VISUAL STATES of buildings (VisualState, Living Assets):
##     simulation events such as "fire_large" or "repaired" (later phases)
##     are mapped to VisualState.apply_event and stored in the settlement
##     record (record.visual_states[building_id]) – permanent, absence never
##     changes them.

## Effects that are active at time t: [{vfx, building_id, place, npc}]
static func active_effects(sim: SettlementSim, t: float) -> Array:
	var rules: Dictionary = sim.config.get("visual_events", {}).get("active", {})
	var out := []
	var seen := {}
	var off := sim.offset_min()
	var h := NpcBrain.local_hour(int(t), off)
	for r in sim.roster:
		var st: Dictionary = sim.states.get(r["npc_id"], {})
		if st.is_empty() or not st.get("travel", {}).is_empty():
			continue
		var act: String = st["act"]
		var place: String = st["place"]
		var pl: Dictionary = sim.nav.places.get(place, {})
		for key in [act + "@" + str(pl.get("type", "")), act]:
			if not rules.has(key):
				continue
			var rule: Dictionary = rules[key]
			if rule.has("hours") and not NpcBrain._in_windows(h, rule["hours"]):
				continue
			var id: String = rule["vfx"] + "|" + place
			if seen.has(id):
				continue
			seen[id] = true
			out.append({"vfx": rule["vfx"], "building_id": pl.get("building_id", ""), "place": place, "npc": r["npc_id"]})
			break
	return out


## Applies a simulation event to the persistent visual state of a building.
## Returns true if the visual state changed.
static func apply_building_event(record: Dictionary, building_id: String, sim_event: String, t: int, config: Dictionary) -> bool:
	var map: Dictionary = config.get("visual_events", {}).get("building", {})
	if not map.has(sim_event):
		return false
	var all: Dictionary = record.get("visual_states", {})
	var vs := VisualState.from_dict(all.get(building_id, {}))
	if not vs.apply_event(str(map[sim_event]), t):
		return false
	all[building_id] = vs.to_dict()
	record["visual_states"] = all
	return true


static func visual_state_of(record: Dictionary, building_id: String) -> VisualState:
	return VisualState.from_dict(record.get("visual_states", {}).get(building_id, {}))
