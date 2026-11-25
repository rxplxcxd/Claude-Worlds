class_name BusinessTexts
extends RefCounted
## Descriptions of businesses by kind (data/texts/businesses.json): every shop
## gets a text that fits what it is (the bread sign → bakery), chosen stably
## per building from a pool of templates. No AI. Player businesses will write
## their own (record.business_texts, Phase 6).

const PATH := "res://data/texts/businesses.json"
static var _d: Dictionary = {}


static func data() -> Dictionary:
	if _d.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_d = d if d is Dictionary else {"kinds": {}}
	return _d


static func kinds() -> Array:
	return data().get("kinds", {}).keys()


static func function_of(kind: String, fallback: String = "") -> String:
	return str(data().get("kinds", {}).get(kind, {}).get("function", fallback))


static func describe(kind: String, building_id: String, name: String = "") -> String:
	var pool: Array = data().get("kinds", {}).get(kind, {}).get("templates", [])
	if pool.is_empty():
		return ""
	var t := str(pool[SettlementCore.mix(building_id + "#text") % pool.size()])
	return t.replace("{name}", name)


## Development hint about later phases – stays visible during development.
static func dev_note() -> String:
	return str(data().get("dev_note", ""))
