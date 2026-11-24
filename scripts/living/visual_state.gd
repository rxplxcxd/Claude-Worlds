class_name VisualState
extends RefCounted
## Living Assets – the persistent VISUAL state of one world object
## (building, prop, vehicle, plant). Pure data, no rendering.
##
## Combinable traits instead of one picture per named state
## (docs/living_assets/STATE_MATRIX.md §2):
##   structure   "intact" | "partial" | "shell" | "collapsed" | "ruin"  (buildings)
##               "broken" | "burnt" | "wreck" | "dry" | "dead" | … (per profile)
##   wear        0..3   0 new/maintained … 3 run-down
##   damage      0..2   0 none, 1 damaged, 2 heavily damaged
##   fire        0..2   0 none, 1 soot/scorch, 2 partly burnt
##   overgrowth  0..2
##   repair      0..2   traces of a restoration (2 = fresh, clearly visible)
## Weather (snow, wetness) is NOT part of this record – it is transient and
## comes from the environment at render time.
##
## Persistence: to_dict()/from_dict() – a repair, restoration or destruction
## is stored permanently with the object (later: WorldState / Firebase).
## IMPORTANT (design rule): nothing in here advances decay over wall-clock
## time. A player's absence never changes this record; only explicit
## simulation events (apply_event) do.

const SCHEMA := 1
const MAX_HISTORY := 12
const STRUCTURES_BUILDING := ["intact", "partial", "shell", "collapsed", "ruin"]

var structure := "intact"
var wear := 0
var damage := 0
var fire := 0
var overgrowth := 0
var repair := 0
var changed_at_unix := 0
var history: Array = []   # [{"event": String, "at": int}], newest last


static func create(p_structure := "intact", p_wear := 0, p_damage := 0, p_fire := 0, p_overgrowth := 0, p_repair := 0) -> VisualState:
	var s := VisualState.new()
	s.structure = p_structure
	s.wear = clampi(p_wear, 0, 3)
	s.damage = clampi(p_damage, 0, 2)
	s.fire = clampi(p_fire, 0, 2)
	s.overgrowth = clampi(p_overgrowth, 0, 2)
	s.repair = clampi(p_repair, 0, 2)
	return s


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA, "structure": structure, "wear": wear, "damage": damage, "fire": fire,
		"overgrowth": overgrowth, "repair": repair, "changed_at_unix": changed_at_unix, "history": history.duplicate(true),
	}


## Tolerant loader: unknown/missing fields fall back to defaults, values are
## clamped. Loading never applies any time-based change.
static func from_dict(d: Dictionary) -> VisualState:
	var s := VisualState.create(str(d.get("structure", "intact")), int(d.get("wear", 0)), int(d.get("damage", 0)),
		int(d.get("fire", 0)), int(d.get("overgrowth", 0)), int(d.get("repair", 0)))
	s.changed_at_unix = int(d.get("changed_at_unix", 0))
	var h = d.get("history", [])
	if h is Array:
		for e in (h as Array).slice(maxi(0, (h as Array).size() - MAX_HISTORY)):
			if e is Dictionary:
				# JSON turns integers into floats – normalise
				s.history.append({"event": str(e.get("event", "")), "at": int(e.get("at", 0))})
	return s


func equals(o: VisualState) -> bool:
	return to_dict().hash() == o.to_dict().hash()


## Explicit simulation events (the only way the record changes).
## Returns false for unknown events. `now` = unix time of the event.
func apply_event(event: String, now: int) -> bool:
	match event:
		"maintained":       # cleaned / cared for
			wear = maxi(0, wear - 1)
		"neglected":        # e.g. owner chose to abandon (never: plain absence)
			wear = mini(3, wear + 1)
		"damaged":
			damage = mini(2, damage + 1)
			if damage >= 2 and structure == "intact":
				structure = "partial"
		"fire_small":
			fire = maxi(fire, 1)
		"fire_large":
			fire = 2
		"burnt_out":
			structure = "shell"
			fire = 0
		"destroyed":
			structure = "collapsed"
			damage = 0
			fire = 0
		"became_ruin":     # a collapsed site left alone for a long SIMULATED period
			if structure == "collapsed":
				structure = "ruin"
		"repaired":        # damage fixed, traces stay
			if damage > 0 or fire > 0 or structure == "partial":
				repair = 2
			damage = 0
			fire = 0
			if structure == "partial":
				structure = "intact"
		"restored":        # full restoration (also after shell / ruin = rebuild)
			structure = "intact"
			damage = 0
			fire = 0
			wear = 0
			overgrowth = 0
			repair = 1
		"traces_faded":    # repair traces weathered in (simulation decides when)
			repair = maxi(0, repair - 1)
		"overgrown":
			overgrowth = mini(2, overgrowth + 1)
		"cleared":
			overgrowth = 0
		_:
			return false
	changed_at_unix = now
	history.append({"event": event, "at": now})
	if history.size() > MAX_HISTORY:
		history = history.slice(history.size() - MAX_HISTORY)
	return true


## Overlay names for this state (as produced by tools/assets/living_traits.py).
func layer_names() -> Array:
	var out := []
	if wear >= 3:
		out.append("wear_3")
	elif wear == 2:
		out.append("wear_2")
	if repair > 0:
		out.append("repair_%d" % repair)
	if damage > 0:
		out.append("damage_%d" % damage)
	if fire > 0:
		out.append("fire_%d" % fire)
	if overgrowth > 0:
		out.append("overgrowth_%d" % overgrowth)
	return out


## Tier-1 shader parameters (dirt, fade, darken) for the wear level.
func shader_params() -> Vector3:
	match wear:
		0:
			return Vector3(0.12 if repair == 0 else 0.1, 0.0, 0.0)
		1:
			return Vector3(0.4, 0.08, 0.01)
		2:
			return Vector3(0.55, 0.22, 0.04)
		_:
			return Vector3(0.72, 0.4, 0.08)


## The 12 named states of the matrix as trait combinations.
static func preset(key: String) -> VisualState:
	match key:
		"01_neu", "02_gepflegt":
			return VisualState.create()
		"03_benutzt", "04_leicht_verschmutzt":
			return VisualState.create("intact", 1)
		"05_vernachlaessigt":
			return VisualState.create("intact", 2)
		"06_heruntergekommen":
			return VisualState.create("intact", 3, 0, 0, 1)
		"07_beschaedigt":
			return VisualState.create("intact", 1, 1)
		"08_schwer_beschaedigt":
			return VisualState.create("partial", 1, 2)
		"09_ausgebrannt":
			return VisualState.create("shell")
		"10_zerstoert":
			return VisualState.create("collapsed")
		"11_ruine":
			return VisualState.create("ruin")
		"12_restauriert":
			return VisualState.create("intact", 0, 0, 0, 0, 1)
	return VisualState.create()
