extends Node
## Local player profile + settings (Phase 1, single device).
##
## Stored in user://worlds_local.cfg (IndexedDB in browsers). This is NOT the
## future authoritative player record: once Firebase Auth exists the local
## `player_id` is linked to / replaced by the authenticated UID
## (docs/PLAYER_SYSTEM.md, docs/FIREBASE_SCHEMA.md).

const SAVE_PATH := "user://worlds_local.cfg"
const SAVE_VERSION := 1

var player_id: String = ""
var display_name: String = "Siedler:in"
var settings: Dictionary = {
	"show_debug": false,
	"time_speed": 1.0,
}
var saved_game_minutes: float = -1.0
## The player's character appearance (CharacterCatalog format). Empty until
## the player finished the character editor once.
var character: Dictionary = {}

var _config := ConfigFile.new()


func _ready() -> void:
	load_profile()
	GameClock.hour_changed.connect(func(_d: int, _h: int) -> void: save_profile())


func load_profile() -> void:
	var err := _config.load(SAVE_PATH)
	if err == OK:
		player_id = _config.get_value("profile", "player_id", "")
		display_name = _config.get_value("profile", "display_name", display_name)
		for key in settings.keys():
			settings[key] = _config.get_value("settings", key, settings[key])
		saved_game_minutes = _config.get_value("world", "game_minutes", -1.0)
		var raw_text := str(_config.get_value("character", "appearance", ""))
		var raw: Variant = JSON.parse_string(raw_text) if raw_text != "" else null
		character = raw if typeof(raw) == TYPE_DICTIONARY else {}
	if player_id == "":
		player_id = Ids.generate("plr")
		save_profile()


func save_profile() -> void:
	_config.set_value("meta", "version", SAVE_VERSION)
	_config.set_value("profile", "player_id", player_id)
	_config.set_value("profile", "display_name", display_name)
	for key in settings.keys():
		_config.set_value("settings", key, settings[key])
	_config.set_value("world", "game_minutes", GameClock.get_total_minutes())
	_config.set_value("character", "appearance", JSON.stringify(character) if not character.is_empty() else "")
	var err := _config.save(SAVE_PATH)
	if err != OK:
		push_warning("LocalProfile: could not save (%s)" % error_string(err))


func has_character() -> bool:
	return not character.is_empty()


## Stores the player's character (appearance + name) and persists it.
func set_character(appearance: Dictionary, name_text: String = "") -> void:
	character = appearance.duplicate(true)
	var n := name_text.strip_edges()
	if n != "":
		display_name = n.substr(0, 24)
	save_profile()


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	save_profile()


func get_setting(key: String, fallback: Variant = null) -> Variant:
	return settings.get(key, fallback)
