extends Node
## Central lookup for every visual asset, driven by data/asset_manifest.json.
##
## Game code never hard-codes texture paths. It asks for a logical key such as
## "exterior.building.town_hall". If the manifest has no usable file yet the
## caller receives null and draws its clearly marked placeholder instead.
##
## Art-direction guard (docs/ASSET_INVENTORY.md, "Art Direction"):
##   * Keys in the "exterior" domain may only resolve to sources whose vendor
##     is listed in art_direction.exterior_allowed_vendors (Penzilla).
##   * Violations are reported and the asset is NOT used.

const MANIFEST_PATH := "res://data/asset_manifest.json"

var _manifest: Dictionary = {}
var _cache: Dictionary = {}
var _violations: PackedStringArray = []


func _ready() -> void:
	reload()


func reload() -> void:
	_cache.clear()
	_violations.clear()
	_manifest = _load_json(MANIFEST_PATH)
	_violations = validate()
	for v in _violations:
		push_warning("AssetRegistry: " + v)


func get_entry(key: String) -> Dictionary:
	var entries: Dictionary = _manifest.get("entries", {})
	return entries.get(key, {})


func get_source(source_id: String) -> Dictionary:
	var sources: Dictionary = _manifest.get("sources", {})
	return sources.get(source_id, {})


## Returns the texture for `key`, or null when it is missing, not imported yet,
## or blocked by the art-direction guard.
func get_texture(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var entry := get_entry(key)
	var path: String = entry.get("path", "")
	if path != "" and is_allowed(key) and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[key] = tex
	return tex


## Generic resource lookup (SpriteFrames, Theme, ...).
func get_resource(key: String) -> Resource:
	var entry := get_entry(key)
	var path: String = entry.get("path", "")
	if path == "" or not is_allowed(key) or not ResourceLoader.exists(path):
		return null
	return load(path)


func is_placeholder(key: String) -> bool:
	return get_texture(key) == null and get_resource(key) == null


## Domain is the first segment of the key: exterior / interior / character / ui.
func get_domain(key: String) -> String:
	var dot := key.find(".")
	return key if dot < 0 else key.substr(0, dot)


func is_allowed(key: String) -> bool:
	return _check_entry(key, get_entry(key)) == ""


## Returns a list of human readable art-direction violations.
func validate() -> PackedStringArray:
	var out: PackedStringArray = []
	var entries: Dictionary = _manifest.get("entries", {})
	for key in entries.keys():
		var problem := _check_entry(key, entries[key])
		if problem != "":
			out.append(problem)
	return out


func get_violations() -> PackedStringArray:
	return _violations


## Summary for the HUD / debug panel.
func get_status_summary() -> Dictionary:
	var entries: Dictionary = _manifest.get("entries", {})
	var total := entries.size()
	var resolved := 0
	for key in entries.keys():
		if not is_placeholder(key):
			resolved += 1
	return {"total": total, "resolved": resolved, "placeholders": total - resolved,
		"violations": _violations.size()}


func _check_entry(key: String, entry: Dictionary) -> String:
	if entry.is_empty():
		return ""
	var domain := get_domain(key)
	var source_id: String = entry.get("source", "")
	var source := get_source(source_id)
	if source_id != "" and source.is_empty():
		return "%s: unknown source '%s'" % [key, source_id]
	if domain == "exterior":
		var allowed: Array = _manifest.get("art_direction", {}).get("exterior_allowed_vendors", [])
		var vendor: String = source.get("vendor", "")
		if not allowed.has(vendor):
			return "%s: exterior assets must come from %s, got vendor '%s'" % [key, str(allowed), vendor]
	return ""


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("AssetRegistry: manifest missing: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("AssetRegistry: manifest is not a JSON object: " + path)
		return {}
	return parsed
