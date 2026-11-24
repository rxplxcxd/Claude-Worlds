class_name Player
extends CharacterBody2D
## The locally controlled player character.
##
## Input sources (merged every physics frame):
##   * keyboard actions (move_*),
##   * virtual joystick (EventBus.move_vector_changed),
##   * tap/click-to-move targets (move_to()).
## Movement is straight-line with wall sliding; real path finding arrives with
## the navigation system in Phase 3 (docs/NPC_SYSTEM.md).

signal interaction_requested(interactable: Interactable)
## Emitted when the player starts moving by direct input (camera re-follows).
signal moved_by_input

const SPEED := 190.0
const ARRIVE_DISTANCE := 6.0
const DETECT_RADIUS := 64.0

var player_id: String = ""
## False while a full-screen UI (character editor) owns the input.
var input_enabled := true
var facing: int = 6

var _joystick := Vector2.ZERO
var _target: Variant = null # Vector2 or null
var _pending_interaction: Interactable = null
var _stuck_time := 0.0
var _nearby: Array[Interactable] = []
var _focused: Interactable = null
var _visual: PlayerVisual
var _detector: Area2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 1 << 1 # "player"
	collision_mask = 1 # "world"
	var body := CollisionPolygon2D.new()
	body.polygon = _ellipse(11.0, 0.55, 10)
	add_child(body)

	_detector = Area2D.new()
	_detector.name = "InteractionDetector"
	_detector.collision_layer = 0
	_detector.collision_mask = 1 << 2 # "interaction"
	_detector.monitorable = false
	var dshape := CollisionPolygon2D.new()
	dshape.polygon = _ellipse(DETECT_RADIUS, 0.6, 16)
	_detector.add_child(dshape)
	add_child(_detector)
	_detector.area_entered.connect(_on_area_entered)
	_detector.area_exited.connect(_on_area_exited)

	_visual = PlayerVisual.new()
	_visual.name = "Visual"
	add_child(_visual)

	EventBus.move_vector_changed.connect(func(v: Vector2) -> void: _joystick = v)
	EventBus.interact_pressed.connect(try_interact)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		try_interact()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _joystick.length_squared() > input.length_squared():
		input = _joystick
	if not input_enabled:
		input = Vector2.ZERO
	var dir := Vector2.ZERO
	if input.length_squared() > 0.01:
		if _target != null:
			cancel_move_target()
		dir = Iso.screen_input_to_world(input)
		moved_by_input.emit()
	elif _target != null:
		dir = _steer_to_target()

	velocity = dir * SPEED
	var before := global_position
	move_and_slide()
	_update_stuck(delta, before)
	if velocity.length_squared() > 1.0:
		facing = Iso.facing_index(velocity)
	_visual.set_motion(velocity.length() / SPEED, facing)
	_update_focus()


## Walk to a world position. Optionally interact when the object is reached.
func move_to(world_pos: Vector2, interactable: Interactable = null) -> void:
	_target = world_pos
	_pending_interaction = interactable
	_stuck_time = 0.0
	if interactable and interactable == _focused:
		_arrive_and_interact()


func cancel_move_target() -> void:
	_target = null
	_pending_interaction = null


## Applies the saved character after the editor was closed.
func refresh_appearance() -> void:
	_visual.refresh_appearance()


func has_move_target() -> bool:
	return _target != null


func get_focused_interactable() -> Interactable:
	return _focused


func try_interact() -> void:
	if _focused:
		_face_towards(_focused.global_position)
		_visual.play_interact()
		interaction_requested.emit(_focused)


func _steer_to_target() -> Vector2:
	var to: Vector2 = _target - global_position
	# Ground-plane distance: vertical screen pixels count more (see Iso).
	var ground := Vector2(to.x, to.y / Iso.MOVE_Y_SCALE)
	if ground.length() <= ARRIVE_DISTANCE:
		cancel_move_target()
		return Vector2.ZERO
	return to / ground.length()


func _update_stuck(delta: float, before: Vector2) -> void:
	if _target == null:
		return
	if global_position.distance_to(before) < SPEED * delta * 0.15:
		_stuck_time += delta
		if _stuck_time > 0.35:
			cancel_move_target()
	else:
		_stuck_time = 0.0


func _on_area_entered(area: Area2D) -> void:
	if area is Interactable and not _nearby.has(area):
		_nearby.append(area)


func _on_area_exited(area: Area2D) -> void:
	_nearby.erase(area)


func _update_focus() -> void:
	var best: Interactable = null
	var best_d := INF
	for it in _nearby:
		if not is_instance_valid(it):
			continue
		var d := global_position.distance_squared_to(it.get_approach_point())
		if d < best_d:
			best_d = d
			best = it
	if _pending_interaction and _nearby.has(_pending_interaction):
		best = _pending_interaction
	if best != _focused:
		_focused = best
		EventBus.interaction_focus_changed.emit(_focused)
	if _pending_interaction and _pending_interaction == _focused:
		_arrive_and_interact()


func _arrive_and_interact() -> void:
	var it := _pending_interaction
	cancel_move_target()
	_face_towards(it.global_position)
	_visual.play_interact()
	interaction_requested.emit(it)


func _face_towards(world_pos: Vector2) -> void:
	var d := world_pos - global_position
	if d.length_squared() > 1.0:
		facing = Iso.facing_index(d)
		_visual.set_motion(0.0, facing)


static func _ellipse(r: float, y_scale: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(Vector2(cos(a) * r, sin(a) * r * y_scale))
	return pts
