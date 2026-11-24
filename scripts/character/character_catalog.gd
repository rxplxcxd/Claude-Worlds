extends Node
## Character catalog (autoload "CharacterCatalog").
##
## Reads data/character_catalog.json: slots, options, Penzilla colour palettes,
## outfits, NPC roles and the frame geometry of the imported layer sheets.
## An APPEARANCE is a plain Dictionary (JSON/Firestore friendly):
##   { "version": 1, "<slot>": {"option": "<id>", "color": "<palette colour>"} }
## Everything that turns an appearance into drawable layers lives here, so the
## editor, the player and NPCs share exactly the same rules.

const CATALOG_PATH := "res://data/character_catalog.json"
const LAYER_DIR := "res://assets/penzilla/character/layers/%s/%s.png"
const APPEARANCE_VERSION := 1

var data: Dictionary = {}
var _tex_cache: Dictionary = {}


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	data = parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## True when the imported Penzilla character layers are available.
func is_available() -> bool:
	return ResourceLoader.exists(LAYER_DIR % ["idle", "body"])


# --- geometry -----------------------------------------------------------

func frame_size(anim: String = "") -> Vector2:
	var f: Dictionary = data.get("frame", {})
	var c := _crop(anim)
	return Vector2(c[2] - c[0], c[3] - c[1]) * float(f.get("file_scale", 1.0))


## Source crop of an animation (wide swings and sitting poses have their own).
func _crop(anim: String) -> Array:
	var f: Dictionary = data.get("frame", {})
	return anim_info(anim).get("crop_src", f.get("crop_src", [0, 0, 460, 460])) if anim != "" else f.get("crop_src", [0, 0, 460, 460])


## Feet position inside one frame, in file pixels.
func feet_in_frame(anim: String = "") -> Vector2:
	var f: Dictionary = data.get("frame", {})
	var c := _crop(anim)
	var feet: Array = f.get("feet_src", [230, 426])
	return (Vector2(feet[0], feet[1]) - Vector2(c[0], c[1])) * float(f.get("file_scale", 1.0))


## File pixels per original artwork pixel.
func file_scale() -> float:
	return float(data.get("frame", {}).get("file_scale", 1.0))


func rows() -> Array:
	return data.get("frame", {}).get("rows", ["s", "sw", "w", "nw", "n"])


func anim_info(anim: String) -> Dictionary:
	return data.get("anims", {}).get(anim, {})


# --- appearance ---------------------------------------------------------

func default_appearance() -> Dictionary:
	var app: Dictionary = (data.get("default", {}) as Dictionary).duplicate(true)
	app["version"] = APPEARANCE_VERSION
	return app


## Fills missing slots, drops unknown options/colours. Always returns a valid
## appearance (safe for data coming from storage or, later, the network).
func normalize(app: Dictionary) -> Dictionary:
	var out := default_appearance()
	var slots: Dictionary = data.get("slots", {})
	for slot in slots.keys():
		if not app.has(slot) or typeof(app[slot]) != TYPE_DICTIONARY:
			continue
		var opt_id: String = str(app[slot].get("option", ""))
		var opts: Dictionary = slots[slot].get("options", {})
		if not opts.has(opt_id):
			continue
		var sel := {"option": opt_id}
		var palette: String = opts[opt_id].get("palette", "")
		if palette != "":
			var color: String = str(app[slot].get("color", ""))
			var pal: Dictionary = data.get("palettes", {}).get(palette, {})
			sel["color"] = color if pal.has(color) else str(pal.keys()[0])
		out[slot] = sel
	out["version"] = APPEARANCE_VERSION
	return out


func option(slot: String, option_id: String) -> Dictionary:
	return data.get("slots", {}).get(slot, {}).get("options", {}).get(option_id, {})


func palette(name: String) -> Dictionary:
	return data.get("palettes", {}).get(name, {})


func tint_color(palette_name: String, color_id: String) -> Color:
	var entry: Dictionary = palette(palette_name).get(color_id, {})
	var t: Array = entry.get("tint", [1, 1, 1])
	return Color(float(t[0]), float(t[1]), float(t[2]))


## Display colour for a swatch (the tint applied to white).
func swatch_color(slot: String, option_id: String, color_id: String) -> Color:
	var opt := option(slot, option_id)
	if opt.has("swatch"):
		return Color(opt["swatch"])
	if opt.has("palette"):
		return tint_color(opt["palette"], color_id)
	return Color(0.5, 0.5, 0.5)


## Animation actually used for a requested state (tool holders use the
## "HoldingTool" variants while standing).
func resolve_anim(app: Dictionary, anim: String) -> String:
	var tool: String = app.get("tool", {}).get("option", "none")
	var has_tool := tool != "none"
	if has_tool and anim_info(anim + "_tool").size() > 0:
		return anim + "_tool"          # idle/walk/sit while carrying the tool
	# work animations need the matching tool, otherwise "interact"
	if anim == "dig" and tool != "shovel":
		return "interact"
	if anim == "swing" and not tool in ["hammer", "axe"]:
		return "interact"
	if anim_info(anim).is_empty():
		return "idle_tool" if has_tool else "idle"
	return anim


## Ordered drawable layers for an appearance and animation:
## [{ "slot", "item", "texture", "modulate" }]. Missing files are skipped.
func layers_for(app: Dictionary, anim: String, face_override: String = "") -> Array:
	var by_slot := {}
	for slot in data.get("slots", {}).keys():
		var sel: Dictionary = app.get(slot, {})
		var opt := option(slot, str(sel.get("option", "none")))
		if opt.is_empty() or not opt.has("layer"):
			continue
		var layer_slot: String = data["slots"][slot].get("layer_slot", slot)
		var mod := Color.WHITE
		if opt.has("palette"):
			mod = tint_color(opt["palette"], str(sel.get("color", "")))
		var item: String = opt["layer"]
		if slot == "face" and face_override != "":
			item = face_override
		by_slot[layer_slot] = {"item": item, "modulate": mod}
		if opt.has("back_layer"):
			by_slot["tool_back"] = {"item": opt["back_layer"], "modulate": Color.WHITE}
	var out: Array = []
	for layer_slot in data.get("layer_order", []):
		if not by_slot.has(layer_slot):
			continue
		var tex := layer_texture(anim, by_slot[layer_slot]["item"])
		if tex:
			out.append({"slot": layer_slot, "item": by_slot[layer_slot]["item"], "texture": tex, "modulate": by_slot[layer_slot]["modulate"]})
	return out


func layer_texture(anim: String, item: String) -> Texture2D:
	var path := LAYER_DIR % [anim, item]
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex_cache[path] = tex
	return tex


## Drops cached layer textures (after compositing, to free GPU memory).
func release_layer_cache() -> void:
	_tex_cache.clear()


## Stable key of the visible appearance (for composite caching).
func appearance_key(app: Dictionary, anim: String) -> String:
	var parts: PackedStringArray = [anim]
	for slot in data.get("slots", {}).keys():
		var sel: Dictionary = app.get(slot, {})
		parts.append("%s=%s/%s" % [slot, sel.get("option", ""), sel.get("color", "")])
	return "|".join(parts)


# --- presets, roles, randomisation --------------------------------------

func apply_outfit(app: Dictionary, outfit: Dictionary) -> Dictionary:
	var out := app.duplicate(true)
	for slot in outfit.keys():
		out[slot] = (outfit[slot] as Dictionary).duplicate()
	return normalize(out)


func apply_preset(app: Dictionary, preset_id: String) -> Dictionary:
	var preset: Dictionary = data.get("presets", {}).get(preset_id, {})
	return apply_outfit(app, preset.get("outfit", {}))


## Random but tasteful appearance for the editor's "Zufall" button.
func random_appearance(rng: RandomNumberGenerator) -> Dictionary:
	var app := default_appearance()
	app["body"] = {"option": "default", "color": _pick(rng, palette("skin").keys())}
	app["face"] = {"option": _pick(rng, ["regular", "happy", "regular", "tired"])}
	var heads := ["short", "long", "curly", "waves", "ponytail", "bun", "mohawk", "spikes", "beanie", "straw_hat", "short", "long"]
	var head: String = _pick(rng, heads)
	app["head"] = {"option": head, "color": _pick(rng, palette(option("head", head).get("palette", "hair")).keys())}
	app["head_acc"] = {"option": "bow", "color": _pick(rng, palette("bow").keys())} if rng.randf() < 0.15 else {"option": "none"}
	var preset: String = _pick(rng, (data.get("presets", {}) as Dictionary).keys())
	if rng.randf() < 0.35:
		app = apply_preset(app, preset)
		return normalize(app)
	var top: String = _pick(rng, ["shirt", "shirt", "dress", "none"])
	app["top"] = {"option": top, "color": _pick(rng, palette(top if top != "none" else "shirt").keys())}
	app["sleeves"] = {"option": "long", "color": app["top"].get("color", "grey")} if top == "shirt" and rng.randf() < 0.5 else {"option": "none"}
	app["suit"] = {"option": "suit", "color": _pick(rng, palette("suit").keys())} if top == "none" else {"option": "none"}
	app["pants"] = {"option": "pants", "color": _pick(rng, palette("pants").keys())} if top != "dress" else {"option": "none"}
	app["shoes"] = {"option": _pick(rng, ["black", "brown", "beige", "blue", "red", "yellow"])}
	app["bag"] = {"option": "bag", "color": _pick(rng, palette("bag").keys())} if rng.randf() < 0.3 else {"option": "none"}
	app["scarf"] = {"option": "scarf", "color": _pick(rng, palette("scarf").keys())} if rng.randf() < 0.2 else {"option": "none"}
	app["bowtie"] = {"option": "none"}
	app["necklace"] = {"option": _pick(rng, ["gold", "silver"])} if rng.randf() < 0.15 else {"option": "none"}
	return normalize(app)


## Appearance for an NPC role. Deterministic for a given seed, so the same
## NPC always looks the same (also on other clients later).
## Headwear reserved as a role signifier (farmer, builder).
const ROLE_SIGNIFIER_HEADS := ["straw_hat", "beanie"]


func role_appearance(role: String, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var app := random_appearance(rng)
	# Civil base, then the role's uniform on top.
	var role_def: Dictionary = data.get("roles", {}).get(role, {})
	for slot in (role_def.get("outfit", {}) as Dictionary).keys():
		var rule: Dictionary = role_def["outfit"][slot]
		var opt: String = rule.get("option", "")
		if rule.has("options"):
			opt = _pick(rng, rule["options"])
		if opt == "":
			opt = str(app.get(slot, {}).get("option", "none"))
		var sel := {"option": opt}
		var opt_def := option(slot, opt)
		if opt_def.has("palette"):
			var pal_keys: Array = palette(opt_def["palette"]).keys()
			var colors: Array = rule.get("colors", pal_keys)
			sel["color"] = _pick(rng, colors.filter(func(c): return pal_keys.has(c)) if colors.any(func(c): return pal_keys.has(c)) else pal_keys)
		app[slot] = sel
	if role != "resident":
		# Uniforms: no fancy extras unless the role defines them.
		for slot in ["necklace", "head_acc", "scarf"]:
			if not (role_def.get("outfit", {}) as Dictionary).has(slot):
				app[slot] = {"option": "none"}
	if not (role_def.get("outfit", {}) as Dictionary).has("head") and str(app.get("head", {}).get("option", "")) in ROLE_SIGNIFIER_HEADS:
		# Straw hat and beanie identify farmers and builders; others wear hair.
		var hair: String = _pick(rng, ["short", "long", "curly", "waves", "ponytail", "bun"])
		app["head"] = {"option": hair, "color": _pick(rng, palette(option("head", hair).get("palette", "hair")).keys())}
	if not (role_def.get("outfit", {}) as Dictionary).has("tool"):
		app["tool"] = {"option": "none"}
	return normalize(app)


func role_label(role: String) -> String:
	return data.get("roles", {}).get(role, {}).get("label", role)


static func _pick(rng: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[rng.randi_range(0, arr.size() - 1)] if arr.size() > 0 else null
