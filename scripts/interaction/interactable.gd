class_name Interactable
extends Area2D
## Something the player can use when standing close to it.
##
## The world node only carries data. What happens on use is decided by the
## InteractionService (scripts/interaction/interaction_service.gd), which keeps
## UI and world decoupled and later allows server-validated actions.

## Stable ID, usually the ID of the owning entity (e.g. "bld_town_hall").
@export var interaction_id: String = ""
## "info", "notice_board", ... (handled by InteractionService).
@export var kind: String = "info"
## false = only reachable by tapping it (no interaction button by proximity),
## e.g. the body of a building – its door has its own small interactable.
@export var proximity: bool = true
@export var title: String = ""
@export var subtitle: String = ""
@export_multiline var text: String = ""
## Verb shown on the interact button, e.g. "Ansehen".
@export var verb: String = "Ansehen"
## Optional buttons: Array of {"id": String, "label": String}.
var actions: Array = []
## Where the player should stand, relative to this node.
var approach_offset: Vector2 = Vector2(0, 24)


func _init() -> void:
	collision_layer = 1 << 2 # "interaction"
	collision_mask = 0
	monitoring = false
	monitorable = true


## Builds an interactable whose shape is a polygon (world-relative to parent).
static func create(id: String, p_title: String, polygon: PackedVector2Array) -> Interactable:
	var it := Interactable.new()
	it.name = "Interactable"
	it.interaction_id = id
	it.title = p_title
	var shape := CollisionPolygon2D.new()
	shape.polygon = polygon
	it.add_child(shape)
	return it


func to_info() -> Dictionary:
	return {
		"id": interaction_id,
		"kind": kind,
		"title": title,
		"subtitle": subtitle,
		"text": text,
		"actions": actions,
	}


## World position the player should walk to (slightly in front of the object).
func get_approach_point() -> Vector2:
	return global_position + approach_offset
