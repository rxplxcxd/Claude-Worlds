class_name CharacterRig
extends Node2D
## Animated, modular Penzilla character (player, NPCs, editor preview).
##
## Draws an APPEARANCE (see CharacterCatalog) as three parts that share one
## frame clock:
##   lower  – layers below the face (tool behind the body, body)
##   face   – separate, so the character can blink and change expression
##   upper  – everything above the face (clothes, hair, hats, tools)
## In "composite" mode lower/upper are merged into one texture each by the
## CharacterComposer (cheap for many NPCs); in "stacked" mode every layer is
## its own sprite (instant updates, used by the editor). Facing uses the 5
## Penzilla rows (s, se, e, ne, n); WEST-facing directions are mirrored
## (verified in the browser: row 2 faces right).

signal animation_finished(anim: String)
## Fired by clip event markers (e.g. "door_open" when the hand reaches the door).
signal clip_event(event: String)

## facing index (Iso.facing_index: 0 E, 1 NE, 2 N, 3 NW, 4 W, 5 SW, 6 S, 7 SE)
## -> [sheet row, mirrored]. Penzilla rows (measured on the sheets: the face
## layer lies 31–41 px LEFT of the body centre in rows 1 and 2, rows 3/4 show
## the back): 0 = S, 1 = SW, 2 = W, 3 = NW, 4 = N. East-facing directions are
## the mirrored west rows. (0.5.0 had this mirrored – walking right showed the
## figure facing left; tests/run_tests.gd checks the mapping now.)
const FACING_ROWS := [[2, true], [3, true], [4, false], [3, false], [2, false], [1, false], [0, false], [1, true]]

## World units per ORIGINAL Penzilla pixel (characters are drawn a bit smaller
## than the building grid, see docs/CHARACTER_SYSTEM.md).
@export var world_per_src: float = Iso.WORLD_PER_SRC_PX * 0.62
@export var use_composite: bool = true
@export var draw_shadow: bool = true
@export var blink: bool = true

var appearance: Dictionary = {}
var anim := "idle"
var facing := 6
var frame := 0

var _resolved := ""
var _time := 0.0
var _blink_timer := 3.0
var _blinking := 0.0
var _parts: Array[Sprite2D] = []
var _face_sprite: Sprite2D
var _build_id := 0
var _held := false
var speed_scale := 1.0             # animation rate multiplier (movement speed)
var _stop_grace := 0.0
## Clip playback (CharacterCatalog clips: sequences of Penzilla frames with
## face changes, head/body offsets and event markers).
var _clip: Dictionary = {}
var _seg := 0
var _seg_frames: Array = []
var _repeat := 0
var _offset_body := Vector2.ZERO
var _offset_face := Vector2.ZERO
var _face_item := ""
var _fired: Dictionary = {}


func _ready() -> void:
	if appearance.is_empty():
		appearance = CharacterCatalog.default_appearance()
	_rebuild()


func set_appearance(app: Dictionary) -> void:
	appearance = CharacterCatalog.normalize(app)
	if is_inside_tree():
		_rebuild()


## Changes the animation – a Penzilla animation ("idle", "walk", "sit" …) or
## a clip from the library ("greet", "eat", "open_door" …). Restarts one-shots.
func play(new_anim: String, restart: bool = false) -> void:
	if new_anim == anim and not restart:
		return
	anim = new_anim
	frame = 0
	_time = 0.0
	_held = false
	_clip = CharacterCatalog.clip(new_anim)
	_seg = 0
	_repeat = 0
	_fired = {}
	_offset_body = Vector2.ZERO
	_offset_face = Vector2.ZERO
	_face_item = ""
	_rebuild()


func is_playing_clip() -> bool:
	return not _clip.is_empty()


func _segment() -> Dictionary:
	var segs: Array = _clip.get("segments", [])
	return segs[mini(_seg, segs.size() - 1)] if not segs.is_empty() else {}


func set_facing(f: int) -> void:
	if f == facing:
		return
	facing = clampi(f, 0, 7)
	_apply_frame()


## Convenience for moving characters.
func set_motion(speed01: float, new_facing: int) -> void:
	set_facing(new_facing)
	# step rate follows the real speed (slow stick = slower steps, no sliding feet)
	speed_scale = clampf(speed01, 0.55, 1.15) if speed01 > 0.05 else 1.0
	if speed01 > 0.05:
		_stop_grace = 0.12
		if anim != "walk":
			play("walk")
		return
	if anim == "interact" or (anim == "walk" and _stop_grace > 0.0):
		return   # one-shot runs to the end / brief stop keeps the stride
	play("idle")


func is_ready_to_draw() -> bool:
	return not _parts.is_empty()


func _process(delta: float) -> void:
	if _parts.is_empty():
		return
	_stop_grace = maxf(0.0, _stop_grace - delta)
	if not _clip.is_empty():
		_process_clip(delta)
		_update_blink(delta)
		return
	var info := CharacterCatalog.anim_info(_resolved)
	var frames: int = int(info.get("frames", 1))
	var fps: float = float(info.get("fps", 8))
	_time += delta * speed_scale
	var step := int(_time * fps)
	var new_frame := step % frames if info.get("loop", true) else mini(step, frames - 1)
	if not info.get("loop", true) and step >= frames and info.get("hold", false):
		# held poses (sitting): stay on the last frame until another anim plays
		if not _held:
			_held = true
			animation_finished.emit(anim)
	elif not info.get("loop", true) and step >= frames:
		var finished := anim
		anim = "idle"
		frame = 0
		_time = 0.0
		_rebuild()
		animation_finished.emit(finished)
		return
	if new_frame != frame:
		frame = new_frame
		_apply_frame()
	_update_blink(delta)


func _process_clip(delta: float) -> void:
	var seg := _segment()
	var seq: Array = seg.get("seq", [0])
	var fps := float(seg.get("fps", _clip.get("fps", 8)))
	_time += delta * speed_scale
	var step := int(_time * fps)
	if step >= seq.size():
		var segs: Array = _clip.get("segments", [])
		if _seg + 1 < segs.size():
			_seg += 1
			_time = 0.0
			_fired = {}
			_rebuild()
			return
		_repeat += 1
		if bool(_clip.get("loop", false)) or _repeat < int(_clip.get("repeat", 1)):
			_seg = 0
			_time = 0.0
			_fired = {}
			if segs.size() > 1:
				_rebuild()
			return
		if bool(_clip.get("hold", false)):
			if not _held:
				_held = true
				animation_finished.emit(anim)
			step = seq.size() - 1
		else:
			var finished := anim
			play(str(_clip.get("then", "idle")), true)
			animation_finished.emit(finished)
			return
	var ev: Dictionary = seg.get("events", {})
	if ev.has(str(step)) and not _fired.has(step):
		_fired[step] = true
		clip_event.emit(str(ev[str(step)]))
	var bob: Array = seg.get("body_dy", [])
	var fdx: Array = seg.get("face_dx", [])
	var fdy: Array = seg.get("face_dy", [])
	var body := Vector2(0, float(bob[step % bob.size()]) if not bob.is_empty() else 0.0)
	var facev := Vector2(float(fdx[step % fdx.size()]) if not fdx.is_empty() else 0.0, float(fdy[step % fdy.size()]) if not fdy.is_empty() else 0.0)
	var new_frame := int(seq[mini(step, seq.size() - 1)])
	if new_frame != frame or body != _offset_body or facev != _offset_face:
		frame = new_frame
		_offset_body = body
		_offset_face = facev
		_apply_frame()


func _update_blink(delta: float) -> void:
	if not blink or _face_sprite == null or not _resolved.begins_with("idle") or _face_item != "":
		return
	if _blinking > 0.0:
		_blinking -= delta
		if _blinking <= 0.0:
			_set_face(false)
		return
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = randf_range(2.5, 6.0)
		_blinking = 0.13
		_set_face(true)


func _set_face(closed: bool) -> void:
	var item: String = "face_blink" if closed else CharacterCatalog.option("face", appearance.get("face", {}).get("option", "regular")).get("layer", "face_regular")
	var tex := CharacterCatalog.layer_texture(_resolved, item)
	if tex:
		_face_sprite.texture = tex


func _rebuild() -> void:
	_build_id += 1
	var my_build := _build_id
	for s in _parts:
		s.queue_free()
	_parts.clear()
	_face_sprite = null
	var face_override := ""
	if not _clip.is_empty():
		var seg := _segment()
		_resolved = CharacterCatalog.resolve_anim(appearance, str(seg.get("base", "idle")))
		var f := str(seg.get("face", _clip.get("face", "")))
		face_override = ("face_" + f) if f != "" else ""
	else:
		_resolved = CharacterCatalog.resolve_anim(appearance, anim)
	_face_item = face_override
	var layers := CharacterCatalog.layers_for(appearance, _resolved, face_override)
	if layers.is_empty():
		queue_redraw()
		return
	var lower: Array = []
	var upper: Array = []
	var face: Dictionary = {}
	for l in layers:
		if l["slot"] == "face":
			face = l
		elif face.is_empty():
			lower.append(l)
		else:
			upper.append(l)
	var key_base := CharacterCatalog.appearance_key(appearance, _resolved)
	var groups := [[lower, key_base + "#lower"], [face, ""], [upper, key_base + "#upper"]]
	var pending: Array = []
	for g in groups:
		if g[1] == "":
			if not face.is_empty():
				_face_sprite = _add_part(face["texture"], face["modulate"], false)
			continue
		var group: Array = g[0]
		if group.is_empty():
			continue
		var cached := CharacterComposer.cached(g[1]) if use_composite else null
		if cached:
			_add_part(cached, Color.WHITE, true)
		else:
			for l in group:
				var part := _add_part(l["texture"], l["modulate"], false)
				CharacterCatalog.apply_layer_color(part, l)
			if use_composite and CharacterComposer.can_compose():
				pending.append(g)
	_apply_frame()
	queue_redraw()
	if not pending.is_empty():
		_compose_async(pending, my_build)


func _compose_async(pending: Array, build: int) -> void:
	for g in pending:
		await CharacterComposer.compose(g[1], g[0])
	if build == _build_id and is_inside_tree():
		_rebuild()


func _add_part(tex: Texture2D, mod: Color, premult: bool) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.region_enabled = true
	s.self_modulate = mod
	if premult:
		s.material = CharacterComposer.premult_material()
	var scale_f := world_per_src / CharacterCatalog.file_scale()
	s.scale = Vector2.ONE * scale_f
	add_child(s)
	_parts.append(s)
	return s


func _apply_frame() -> void:
	if _parts.is_empty():
		return
	var fs := CharacterCatalog.frame_size(_resolved)
	var rule: Array = FACING_ROWS[facing]
	var region := Rect2(frame * fs.x, int(rule[0]) * fs.y, fs.x, fs.y)
	var scale_f := world_per_src / CharacterCatalog.file_scale()
	var feet := CharacterCatalog.feet_in_frame(_resolved)
	var mirror := -1.0 if rule[1] else 1.0
	for s in _parts:
		s.region_rect = region
		s.flip_h = rule[1]
		# Mirror around the feet so the character does not jump sideways.
		var x := -(fs.x - feet.x) if rule[1] else -feet.x
		s.position = Vector2(x, -feet.y) * scale_f + _offset_body * world_per_src
		if s == _face_sprite:
			s.position += Vector2(_offset_face.x * mirror, _offset_face.y) * world_per_src


func _draw() -> void:
	if draw_shadow:
		var r := world_per_src * 95.0
		IsoPainter.ellipse(self, Vector2(0, 1), Vector2(r, r * 0.42), Color(0, 0, 0, 0.22), 24)
