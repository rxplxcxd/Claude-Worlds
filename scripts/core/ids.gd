class_name Ids
extends RefCounted
## Identifier helpers.
##
## Every persistent entity (player, NPC, settlement, building, ...) gets a
## string ID of the form "<prefix>_<random base36>". Prefixes are documented in
## docs/ARCHITECTURE.md. Data files may also use stable, hand-written IDs
## (e.g. "stl_lichtfeld"), which keeps them readable and diff-friendly.

const ALPHABET := "0123456789abcdefghijklmnopqrstuvwxyz"


static func generate(prefix: String, length: int = 12) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := ""
	for i in length:
		s += ALPHABET[rng.randi_range(0, ALPHABET.length() - 1)]
	return "%s_%s" % [prefix, s]


static func has_prefix(id: String, prefix: String) -> bool:
	return id.begins_with(prefix + "_")
