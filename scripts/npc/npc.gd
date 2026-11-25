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
var seated := false
var detailed := true       # false = beyond the profile's detail cap (no idle animations)
var _interactable: Interactable
var _shape: CollisionPolygon2D
var _bubble: ChatBubble
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _base_facing := 6
var _player: Node2D
var _partner_pos := Vector2.INF


func setup(p_record: Dictionary, building_names: Dictionary = {}, workplace_type: String = "") -> void:
	record = p_record
	_workplace_type = workplace_type
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
## Animation state machine (presentation only, shared clip library with the
## player – CharacterCatalog clips, played by CharacterRig):
##   door exit/enter → step up, "open_door" (the door opens on the clip's event,
##                     see SettlementScene._update_doors), fade through the doorway
##   walking         → walk / run (late) / walk_hurt (ill) / walk_tired
##   seated          → "sit_down" on a bench seat (held), "stand_up" when leaving
##   working         → tool animation (dig/swing) in bouts + activity clips
##   other           → activity clips (talk, gesture, laugh, eat, drink, look_at …),
##                     greeting the player, yawning when tired
func apply_render(info: Dictionary, world: Vector2, world_dir: Vector2, chat_partner: Vector2, talking: bool) -> void:
	if not info.get("visible", false):
		if is_present():
			_set_present(false)
		seated = false
		return
	if not is_present():
		_set_present(true)
		_base_facing = [6, 7, 0, 5][_rng.randi_range(0, 3)]
	where = str(info.get("place", ""))
	var new_act := str(info.get("act", ""))
	position = world
	var door := str(info.get("door", ""))
	modulate.a = 1.0
	if door != "":
		var f := float(info.get("door_f", 0.0))
		if door == "enter":
			# walk up (0–0.3), open the door (0.3–0.55), step through and vanish
			modulate.a = clampf((1.0 - f) / 0.4, 0.0, 1.0)
			if f >= 0.3 and f < 0.55:
				if rig.anim != "open_door":
					rig.play("open_door", true)
			elif rig.anim != "walk":
				rig.play("walk")
		else:
			# appear in the open doorway, then step out
			modulate.a = clampf((f - 0.1) / 0.3, 0.0, 1.0)
			if rig.anim != "walk":
				rig.play("walk")
		if world_dir.length_squared() > 0.0001:
			rig.set_facing(Iso.facing_index(world_dir))
		walking = true
		seated = false
	elif info.get("walking", false):
		var want := "run" if info.get("hurry", false) else _walk_clip()
		if not walking or rig.anim != want:
			rig.play(want)
		walking = true
		seated = false
		if world_dir.length_squared() > 0.0001:
			rig.set_facing(Iso.facing_index(world_dir))
	else:
		var sit := bool(info.get("seat", false))
		if sit and not seated:
			rig.play("sit_down", true)
			seated = true
			if info.has("seat_facing"):
				rig.set_facing(int(info["seat_facing"]))
		elif not sit and seated:
			rig.play("stand_up", true)
			seated = false
		elif not sit and (walking or new_act != act):
			if new_act == "socialize" or (new_act == "eat_out" and walking):
				rig.play("greet", true)   # joining others: a greeting first
			else:
				rig.play(work_anim() if new_act == "work" else "idle")
			_timer = _rng.randf_range(1.5, 4.0)
		walking = false
	act = new_act
	_partner_pos = chat_partner
	_bubble.visible = talking and not walking and modulate.a > 0.9


func _walk_clip() -> String:
	var h := str(record.get("health", {}).get("status", "healthy"))
	if h != "healthy":
		return "walk_hurt"
	return "walk_tired" if energy < 0.18 else "walk"


## Condition shown in gestures (set by the scene from the simulation).
var mood := 0.6
var energy := 0.6
var _greeted_at := -1000.0


## The work animation that fits the person's tool ("" = no tool animation).
func work_anim() -> String:
	match str(record.get("appearance", {}).get("tool", {}).get("option", "none")):
		"shovel":
			return "dig"
		"hammer", "axe":
			return "swing"
	return "use"


## A clip for the current activity from the data table (weighted, seeded).
func pick_activity_clip() -> String:
	var table: Dictionary = CharacterCatalog.data.get("activity_clips", {})
	var opts: Array = table.get(act + "@" + _workplace_type, table.get(act, []))
	if opts.is_empty():
		return ""
	var total := 0.0
	var weights := []
	for o in opts:
		var w := float(o[1])
		if o[0] == "laugh":
			w *= 0.4 + 1.6 * mood
		elif o[0] == "yawn":
			w *= 0.3 + 3.0 * maxf(0.0, 0.4 - energy) * 4.0
		weights.append(w)
		total += w
	var r := _rng.randf() * total
	for i in opts.size():
		r -= float(weights[i])
		if r <= 0.0:
			return str(opts[i][0])
	return str(opts[0][0])


var _workplace_type := ""


func _process(delta: float) -> void:
	if not is_present() or walking or not detailed:
		return
	if _player == null:
		var s := get_parent()
		while s and not s is SettlementScene:
			s = s.get_parent()
		if s:
			_player = (s as SettlementScene).player
	var now := Time.get_ticks_msec() / 1000.0
	if _player and _player.global_position.distance_to(global_position) < LOOK_DISTANCE:
		var d := _player.global_position - global_position
		if d.length_squared() > 4.0 and not seated:
			rig.set_facing(Iso.facing_index(d))
		if now - _greeted_at > 45.0 and not seated:
			_greeted_at = now
			rig.play("greet", true)   # notices the player and greets
		return
	if _partner_pos != Vector2.INF and not seated:
		var d2 := _partner_pos - global_position
		if d2.length_squared() > 4.0:
			rig.set_facing(Iso.facing_index(d2))
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _rng.randf_range(3.5, 8.0)
	if seated:
		if act in ["socialize", "pause", "eat_out"] and _partner_pos != Vector2.INF:
			_bubble.visible = _rng.randf() < 0.5
		return   # sitting people keep their pose
	if rig.is_playing_clip() and not rig.anim in ["talk", "tired", "hurt_idle"]:
		return   # let a gesture finish
	var tool := work_anim()
	if act == "work" and tool in ["dig", "swing"] and _rng.randf() < 0.6:
		rig.play(tool if rig.anim != tool else "idle")   # work in bouts
		return
	if energy < 0.2 and _rng.randf() < 0.35:
		rig.play("yawn", true)
		return
	var clip := pick_activity_clip()
	if clip != "" and _rng.randf() < 0.75:
		rig.play(clip, true)
	else:
		rig.play("idle")
		if _partner_pos == Vector2.INF:
			rig.set_facing(posmod(_base_facing + _rng.randi_range(-1, 1), 8))


## Info card text from the live simulation state.
func describe(sim: SettlementSim, t: int, building_names: Dictionary) -> String:
	var lines := PackedStringArray()
	var info := sim.render_info(npc_id, t)
	var prof: Dictionary = record.get("profession", {})
	var age := int(SettlementCore.age_years(record, SettlementCore.day_index(t, sim.offset_min()), sim.config))
	lines.append("%s, %d Jahre · %s" % [record.get("name", ""), age, prof.get("title", CharacterCatalog.role_label(record.get("role", "")))])
	var health := str(record.get("health", {}).get("status", "healthy"))
	if health != "healthy":
		lines.append("[i]%s[/i]" % ("krank" if health == "ill" else "verletzt – erholt sich"))
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
	var work: String = building_names.get(record.get("employment", {}).get("workplace_id", record.get("workplace_id", "")), "")
	var home: String = building_names.get(record.get("home_id", ""), "")
	if work != "":
		lines.append("Arbeitet in: %s · %s" % [work, sim.schedule_text(record, t)])
	elif record.get("employment", {}).get("status", "") in ["retired", "unemployed"]:
		lines.append(sim.schedule_text(record, t).capitalize())
	if home != "":
		lines.append("Wohnt in: %s" % home)
	var p: Dictionary = record.get("personality", {})
	var traits := PackedStringArray()
	var words := {"extraversion": ["kontaktfreudig", "introvertiert"], "confidence": ["selbstbewusst", "schüchtern"],
		"conscientiousness": ["pflichtbewusst", "locker"], "reliability": ["zuverlässig", "unzuverlässig"],
		"curiosity": ["neugierig", "gewohnheitsliebend"], "ambition": ["ehrgeizig", ""], "impulsivity": ["spontan", "bedächtig"], "risk": ["wagemutig", "vorsichtig"]}
	for k in words:
		var v := float(p.get(k, 0.5))
		if v > 0.68 and words[k][0] != "":
			traits.append(words[k][0])
		elif v < 0.32 and words[k][1] != "":
			traits.append(words[k][1])
	if float(p.get("chronotype", 0.0)) > 0.5:
		traits.append("Nachteule")
	elif float(p.get("chronotype", 0.0)) < -0.5:
		traits.append("Frühaufsteher:in")
	traits = traits.slice(0, 4)
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
