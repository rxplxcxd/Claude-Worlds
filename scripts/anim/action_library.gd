class_name ActionLibrary
extends RefCounted
## Object interactions shared by players and NPCs (data/anim/actions.json):
## which clip plays, which pose is taken first (sit / lie), feedback text and
## development notes for systems of later phases.

const PATH := "res://data/anim/actions.json"
static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = d if d is Dictionary else {}
	return _data


static func actions() -> Dictionary:
	return data().get("actions", {})


static func get_action(id: String) -> Dictionary:
	return actions().get(id, {})


## Default actions of an outdoor prop kind as [{id, label}].
static func prop_actions(kind: String) -> Array:
	var out := []
	for id in data().get("props", {}).get(kind, []):
		out.append({"id": id, "label": get_action(id).get("label", id)})
	return out
