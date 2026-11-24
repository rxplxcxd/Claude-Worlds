class_name Credits
extends RefCounted
## Credits / licence notices (data/credits.json). The Penzilla Standard
## Licence requires the credit "Graphics created by Penzilla Design" to be
## visible in the project and every edit of the graphics to be listed next to
## it – shown in the in-game menu and mirrored in CREDITS.md.

const PATH := "res://data/credits.json"
const MANDATORY := "Graphics created by Penzilla Design"


static func data() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return d if d is Dictionary else {}


static func bbcode() -> String:
	var out := PackedStringArray()
	for sec in data().get("sections", []):
		out.append("[b]%s[/b]" % sec.get("title", ""))
		for l in sec.get("lines", []):
			out.append(str(l))
		out.append("")
	return "\n".join(out)
