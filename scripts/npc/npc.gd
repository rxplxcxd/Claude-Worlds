class_name Npc
extends StaticBody2D
## A member of the settlement's founding community, drawn with the same
## modular Penzilla character as the player (CharacterRig, composite mode).
##
## Phase 1 scope ("presence", no simulation): the NPC keeps its persistent
## identity (name, role, workplace, home, appearance), stands beside its
## workplace door during working hours and beside its home in the evening,
## and is indoors at night. It idles, occasionally turns or uses its tool and
## looks at the player who comes close. Needs, routines, pathfinding and
## conversations follow in Phase 3 (docs/NPC_SYSTEM.md).

const LOOK_DISTANCE := 70.0
## Local hours: [from, to) -> where the NPC is.
const WORK_HOURS := Vector2(7.5, 18.5)
const HOME_HOURS := Vector2(18.5, 22.0)

var npc_id := ""
var record: Dictionary = {}
var spots: Dictionary = {}
var rig: CharacterRig
var where := ""
var _interactable: Interactable
var _shape: CollisionPolygon2D
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _base_facing := 6
var _player: Node2D


func setup(p_record: Dictionary, p_spots: Dictionary, building_names: Dictionary) -> void:
	record = p_record
	npc_id = record.get("npc_id", "npc")
	spots = p_spots
	name = npc_id
	collision_layer = 1
	collision_mask = 0
	_rng.seed = hash(npc_id)
	_timer = _rng.randf_range(1.0, 5.0)
	_shape = CollisionPolygon2D.new()
	_shape.polygon = _ellipse(7.0, 0.55, 10)
	add_child(_shape)

	rig = CharacterRig.new()
	rig.name = "Rig"
	rig.appearance = CharacterCatalog.normalize(record.get("appearance", {}))
	add_child(rig)

	var role: String = record.get("role", "resident")
	# Tap/focus area: the whole figure, from the feet up to the head.
	var poly := PackedVector2Array([Vector2(-22, 10), Vector2(22, 10), Vector2(18, -50), Vector2(-18, -50)])
	_interactable = Interactable.create(npc_id, str(record.get("name", "")), poly)
	_interactable.kind = "npc"
	_interactable.subtitle = CharacterCatalog.role_label(role)
	_interactable.verb = "Ansprechen"
	_interactable.text = _describe(role, building_names)
	_interactable.approach_offset = Vector2(0, 22)
	add_child(_interactable)
	update_presence(true)


func _describe(role: String, building_names: Dictionary) -> String:
	var lines := PackedStringArray()
	var work: String = building_names.get(record.get("workplace_id", ""), "")
	var home: String = building_names.get(record.get("home_id", ""), "")
	lines.append("%s gehört zur Gründungsgemeinschaft der Siedlung." % record.get("name", ""))
	if work != "":
		lines.append("Arbeitet in: %s (tagsüber)" % work)
	elif role == "resident":
		lines.append("Ist tagsüber meist am Dorfplatz anzutreffen.")
	if home != "":
		lines.append("Wohnt in: %s" % home)
	lines.append("")
	lines.append("[i]Gespräche, Bedürfnisse und Tagesabläufe folgen in Phase 3.[/i]")
	return "\n".join(lines)


## Where the NPC should be at the given local hour: "work", "home" or "" (indoors).
static func place_for_hour(hour: float) -> String:
	if hour >= WORK_HOURS.x and hour < WORK_HOURS.y:
		return "work"
	if hour >= HOME_HOURS.x and hour < HOME_HOURS.y:
		return "home"
	return ""


func update_presence(force: bool = false) -> void:
	var want := place_for_hour(GameClock.get_minute_of_day() / 60.0)
	if not spots.has(want):
		want = ""
	if want == where and not force:
		return
	where = want
	var present := want != ""
	visible = present
	_shape.disabled = not present
	_interactable.monitorable = present
	_interactable.input_pickable = present
	if present:
		position = Iso.grid_to_world(spots[want])
		_base_facing = _facing_away_from_building()
		rig.set_facing(_base_facing)
		rig.play("idle")


func is_present() -> bool:
	return where != ""


## Workers face the street (south-east on screen = away from the building).
func _facing_away_from_building() -> int:
	return [6, 7, 0, 5][_rng.randi_range(0, 3)]


func _process(delta: float) -> void:
	if not is_present():
		return
	if _player == null:
		var s := get_parent()
		while s and not s is SettlementScene:
			s = s.get_parent()
		if s:
			_player = (s as SettlementScene).player
	if _player and _player.global_position.distance_to(global_position) < LOOK_DISTANCE:
		var d := _player.global_position - global_position
		if d.length_squared() > 4.0:
			rig.set_facing(Iso.facing_index(d))
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _rng.randf_range(4.0, 9.0)
	if record.get("appearance", {}).get("tool", {}).get("option", "none") != "none" and _rng.randf() < 0.5:
		rig.play("interact", true)
	else:
		rig.set_facing(posmod(_base_facing + _rng.randi_range(-1, 1), 8))


static func _ellipse(r: float, y_scale: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(Vector2(cos(a) * r, sin(a) * r * y_scale))
	return pts
