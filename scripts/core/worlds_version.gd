class_name WorldsVersion
extends RefCounted
## The version of WORLDS – read from data/version.json (single source) and the
## build info written at export (data/build_info.json: commit, build time).

static var _v: Dictionary = {}
static var _b: Dictionary = {}


static func data() -> Dictionary:
	if _v.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/version.json"))
		_v = d if d is Dictionary else {"product": "v0.1"}
		if FileAccess.file_exists("res://data/build_info.json"):
			var b = JSON.parse_string(FileAccess.get_file_as_string("res://data/build_info.json"))
			_b = b if b is Dictionary else {}
	return _v


static func product() -> String:
	return str(data().get("product", "v0.1"))


static func technical() -> String:
	return str(data().get("technical", ProjectSettings.get_setting("application/config/version", "")))


static func commit() -> String:
	data()
	return str(_b.get("commit", "lokal"))


## "WORLDS v0.1"
static func short_label() -> String:
	return "WORLDS " + product()


## "WORLDS v0.1 · Entwicklungsstand · Build 0.6.0 (a1b2c3d4e5)"
static func full_label() -> String:
	return "%s · %s · Build %s (%s)" % [short_label(), str(data().get("channel", "")), technical(), commit()]
