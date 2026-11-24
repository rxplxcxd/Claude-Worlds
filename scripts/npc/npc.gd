class_name Npc
extends StaticBody2D
## A settlement inhabitant, drawn with the modular Penzilla character
## (CharacterRig, composite mode).
##
## Phase 3: the NPC node only PRESENTS the simulation (SettlementSim /
## NpcBrain). The settlement scene calls apply_render(info) with the state at
## the current time: walking along its path, working at its workplace,
## chatting on the plaza (speech bubble), or indoors (hidden). Nothing here
## changes the simulation – a hidden NPC (LOD S1) keeps living as data and
## re-appears exactly where its routine has taken it.

const LOOK_DISTANCE := 70.0

var npc_id := ""
var record: Dictionary = {}
var rig: CharacterRig
var where := ""            # "" = not visible (indoors / data-only)
var act := ""
var walking := false
var detailed := true       # false = beyond the profile's detail cap (no idle animations)
var _interactable: Interactable
var _shape: CollisionPolygon2D
var _bubble: ChatBubble
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _base_facing := 6
var _player: Node2D
var _partner_pos := Vector2.INF


func setup(p_record: Dictionary, building_names: Dictionary = {}) -> void:
	record = p_record
	npc_id = record.get("npc_id", "npc")
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

	_bubble = ChatBubble.new()
	_bubble.position = Vector2(14, -62)
	_bubble.visible = false
	add_child(_bubble)

	var role: String = record.get("role", "resident")
	# Tap/focus area: the whole figure, from the feet up to the head.
	var poly := PackedVector2Array([Vector2(-22, 10), Vector2(22, 10), Vector2(18, -50), Vector2(-18, -50)])
	_interactable = Interactable.create(npc_id, str(record.get("name", "")), poly)
	_interactable.kind = "npc"
	_interactable.subtitle = CharacterCatalog.role_label(role)
	_interactable.verb = "Ansprechen"
	_interactable.actions = [{"id": "talk", "label": "Grüßen"}]
	_interactable.text = ""
	_interactable.approach_offset = Vector2(0, 22)
	add_child(_interactable)
	_set_present(false)


func is_present() -> bool:
	return where != ""


func _set_present(on: bool) -> void:
	visible = on
	_shape.disabled = not on
	_interactable.monitorable = on
	_interactable.input_pickable = on
	if not on:
		where = ""
		_bubble.visible = false


## info = SettlementSim.render_info(...); world = its position in world px.
## chat: partner world position (Vector2.INF if none), talking: bubble on.
func apply_render(info: Dictionary, world: Vector2, world_dir: Vector2, chat_partner: Vector2, talking: bool) -> void:
	if not info.get("visible", false):
		if is_present():
			_set_present(false)
		return
	if not is_present():
		_set_present(true)
		_base_facing = [6, 7, 0, 5][_rng.randi_range(0, 3)]
	where = str(info.get("place", ""))
	var new_act := str(info.get("act", ""))
	position = world
	if info.get("walking", false):
		if not walking or rig.anim != "walk":
			rig.play("walk")
		walking = true
		if world_dir.length_squared() > 0.0001:
			rig.set_facing(Iso.facing_index(world_dir))
	else:
		if walking or new_act != act:
			rig.play("idle")
		walking = false
	act = new_act
	_partner_pos = chat_partner
	_bubble.visible = talking and not walking


func _process(delta: float) -> void:
	if not is_present() or walking or not detailed:
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
	if _partner_pos != Vector2.INF:
		var d2 := _partner_pos - global_position
		if d2.length_squared() > 4.0:
			rig.set_facing(Iso.facing_index(d2))
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _rng.randf_range(4.0, 9.0)
	var has_tool: bool = record.get("appearance", {}).get("tool", {}).get("option", "none") != "none"
	if act == "work" and has_tool and _rng.randf() < 0.6:
		rig.play("interact", true)
	elif act in ["eat_out", "errand"] and _rng.randf() < 0.3:
		rig.play("interact", true)
	elif _partner_pos == Vector2.INF:
		rig.set_facing(posmod(_base_facing + _rng.randi_range(-1, 1), 8))


## Info card text from the live simulation state.
func describe(sim: SettlementSim, t: int, building_names: Dictionary) -> String:
	var lines := PackedStringArray()
	var info := sim.render_info(npc_id, t)
	var prof: Dictionary = record.get("profession", {})
	var age := NpcBrain.age_years(record, t)
	lines.append("%s, %d Jahre · %s" % [record.get("name", ""), age, prof.get("title", CharacterCatalog.role_label(record.get("role", "")))])
	var target_name: String = building_names.get(sim.nav.places.get(info.get("target", ""), {}).get("building_id", ""), "")
	var doing := sim.activity_label(str(info.get("act", "")))
	if info.get("walking", false):
		var next_act := str(sim.states[npc_id].get("travel", {}).get("next", ""))
		doing = "ist unterwegs" + (" – " + sim.activity_label(next_act) if next_act != "" else "")
	lines.append("[b]Gerade:[/b] %s%s" % [doing, (" (%s)" % target_name) if target_name != "" else ""])
	var needs := sim.needs_now(npc_id, t)
	var mood := NpcBrain.mood(needs)
	lines.append("[b]Stimmung:[/b] %s" % ("gut gelaunt" if mood > 0.7 else ("zufrieden" if mood > 0.5 else ("angespannt" if mood > 0.3 else "erschöpft"))))
	var hints := PackedStringArray()
	var labels := {"food": "hungrig", "energy": "müde", "social": "einsam", "leisure": "braucht Pause", "hygiene": "möchte sich frisch machen"}
	for k in NpcBrain.NEED_KEYS:
		if float(needs.get(k, 1.0)) < 0.35:
			hints.append(labels[k])
	if not hints.is_empty():
		lines.append("[i]%s[/i]" % ", ".join(hints))
	var work: String = building_names.get(record.get("workplace_id", ""), "")
	var home: String = building_names.get(record.get("home_id", ""), "")
	if work != "":
		lines.append("Arbeitet in: %s · %s" % [work, sim.schedule_text(record)])
	if home != "":
		lines.append("Wohnt in: %s" % home)
	var p: Dictionary = record.get("personality", {})
	var traits := PackedStringArray()
	if float(p.get("sociability", 0.5)) > 0.62:
		traits.append("gesellig")
	elif float(p.get("sociability", 0.5)) < 0.38:
		traits.append("zurückhaltend")
	if float(p.get("diligence", 0.5)) > 0.62:
		traits.append("fleißig")
	if float(p.get("openness", 0.5)) > 0.62:
		traits.append("neugierig")
	if not traits.is_empty():
		lines.append("Wesen: " + ", ".join(traits))
	return "\n".join(lines)


func refresh_card(sim: SettlementSim, t: int, building_names: Dictionary) -> void:
	_interactable.text = describe(sim, t, building_names)


static func _ellipse(r: float, y_scale: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(Vector2(cos(a) * r, sin(a) * r * y_scale))
	return pts
