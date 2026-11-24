extends Node
## Central lookup for every visual asset, driven by data/asset_manifest.json.
##
## Game code never hard-codes texture paths. It asks for a logical key such as
## "exterior.building.town_hall". If the manifest has no usable file (e.g. the
## purchased assets were not imported on this machine) the caller receives
## null / {} and draws its clearly marked placeholder instead.
##
## Sprite placement: assets/penzilla/import_meta.json (written by
## tools/assets/import_penzilla.py) stores each file's ORIGINAL pixel size and
## the bottom-centre of its visible content. get_sprite() turns that into a
## world-space offset so every sprite stands exactly on its anchor point.
##   anchor_mode "content" (default): bottom-centre of visible pixels.
##   anchor_mode "canvas": Penzilla grid convention, i.e. the footprint's
##   bottom vertex at (width / 2, height - 149) in original pixels.
##
## Art-direction guard (docs/ASSET_INVENTORY.md, "Art Direction"):
##   * Keys in the "exterior" domain may only resolve to sources whose vendor
##     is listed in art_direction.exterior_allowed_vendors (Penzilla).
##   * Violations are reported and the asset is NOT used.

const MANIFEST_PATH := "res://data/asset_manifest.json"
const IMPORT_META_PATH := "res://assets/penzilla/import_meta.json"
## Depth of the earth block below a Penzilla ground diamond, original pixels.
const CANVAS_BLOCK_DEPTH := 149.0

var _manifest: Dictionary = {}
var _meta: Dictionary = {}
var _cache: Dictionary = {}
var _violations: PackedStringArray = []


func _ready() -> void:
	reload()


func reload() -> void:
	_cache.clear()
	_violations.clear()
	_manifest = _load_json(MANIFEST_PATH)
	_meta = _load_json(IMPORT_META_PATH, false)
	_violations = validate()
	for v in _violations:
		push_warning("AssetRegistry: " + v)


func get_entry(key: String) -> Dictionary:
	var entries: Dictionary = _manifest.get("entries", {})
	return entries.get(key, {})


func get_source(source_id: String) -> Dictionary:
	var sources: Dictionary = _manifest.get("sources", {})
	return sources.get(source_id, {})


## All file paths configured for a key ("path" or "paths" for variants).
func get_paths(key: String) -> PackedStringArray:
	var entry := get_entry(key)
	var out: PackedStringArray = []
	if entry.has("paths"):
		for p in entry["paths"]:
			out.append(str(p))
	elif str(entry.get("path", "")) != "":
		out.append(str(entry["path"]))
	return out


## Number of variants that are actually available on this build.
func variant_count(key: String) -> int:
	var n := 0
	for i in get_paths(key).size():
		if get_texture(key, i) != null:
			n += 1
	return n


## Returns the texture for `key` (variant index wraps), or null when it is
## missing, not imported, or blocked by the art-direction guard.
func get_texture(key: String, variant: int = 0) -> Texture2D:
	var paths := get_paths(key)
	if paths.is_empty():
		return null
	var path := paths[posmod(variant, paths.size())]
	var cache_key := key + "#" + path
	if _cache.has(cache_key):
		return _cache[cache_key]
	var tex: Texture2D = null
	if is_allowed(key) and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[cache_key] = tex
	return tex


## Sprite placement data: {texture, scale, offset}. `offset` is the position
## of the texture's top-left corner relative to the anchor point, in world
## units, for a Sprite2D with centered = false and the given uniform scale.
## Empty dictionary when the asset is unavailable.
func get_sprite(key: String, variant: int = 0) -> Dictionary:
	var tex := get_texture(key, variant)
	if tex == null:
		return {}
	var paths := get_paths(key)
	var path := paths[posmod(variant, paths.size())]
	var entry := get_entry(key)
	var info: Dictionary = (_meta.get("files", {}) as Dictionary).get(path, {})
	var src_size := _vec(info.get("size", [tex.get_width(), tex.get_height()]))
	var anchor := _vec(info.get("anchor", [src_size.x * 0.5, src_size.y]))
	if entry.get("anchor_mode", "content") == "canvas":
		anchor = Vector2(src_size.x * 0.5, src_size.y - CANVAS_BLOCK_DEPTH)
	var world_per_src: float = Iso.WORLD_PER_SRC_PX * float(entry.get("world_scale", 1.0))
	var file_scale := float(tex.get_width()) / maxf(src_size.x, 1.0)
	return {
		"texture": tex,
		"scale": world_per_src / file_scale,
		"offset": -anchor * world_per_src + _vec(entry.get("offset", [0, 0])),
		"src_size": src_size,
		"world_per_src": world_per_src,
	}


## Generic resource lookup (SpriteFrames, Theme, ...).
func get_resource(key: String) -> Resource:
	var paths := get_paths(key)
	if paths.is_empty() or not is_allowed(key) or not ResourceLoader.exists(paths[0]):
		return null
	return load(paths[0])


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


## Summary for the HUD / debug panel. "world_placeholders" only counts what is
## visible in the settlement (exterior + character).
func get_status_summary() -> Dictionary:
	var entries: Dictionary = _manifest.get("entries", {})
	var total := entries.size()
	var resolved := 0
	var world_missing := 0
	for key in entries.keys():
		if not is_placeholder(key):
			resolved += 1
		elif get_domain(key) in ["exterior", "character"]:
			world_missing += 1
	return {"total": total, "resolved": resolved, "placeholders": total - resolved,
		"world_placeholders": world_missing, "violations": _violations.size()}


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


func _load_json(path: String, required: bool = true) -> Dictionary:
	if not FileAccess.file_exists(path):
		if required:
			push_error("AssetRegistry: file missing: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("AssetRegistry: not a JSON object: " + path)
		return {}
	return parsed


static func _vec(a: Variant) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO
