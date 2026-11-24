class_name GraphicsProfile
extends RefCounted
## Quality profiles for presentation only – the simulation is identical in
## every profile (docs/LIVING_WORLD.md §7). Reference device for "ultra":
## iPhone 15 Pro Max; "leistung" keeps older iPhones fluid.

const PROFILES := {
	"ultra": {"label": "Ultra", "npc_detail_cap": 400, "particles": 1.0, "chat_bubbles": true, "npc_anim_hz": 0.0},
	"hoch": {"label": "Hoch", "npc_detail_cap": 150, "particles": 0.6, "chat_bubbles": true, "npc_anim_hz": 0.0},
	"leistung": {"label": "Leistung", "npc_detail_cap": 50, "particles": 0.25, "chat_bubbles": false, "npc_anim_hz": 15.0},
}
const ORDER := ["auto", "ultra", "hoch", "leistung"]


## Setting value: "auto" (default) or a profile name.
static func setting() -> String:
	var s := str(LocalProfile.get_setting("graphics_profile", "auto"))
	return s if s in ORDER else "auto"


static func current() -> String:
	var s := setting()
	return detect() if s == "auto" else s


static func params() -> Dictionary:
	return PROFILES[current()]


## Heuristic device detection (web): many cores / large Apple screen → ultra,
## other phones → hoch, weak devices → leistung. Desktop → ultra.
static func detect() -> String:
	if not OS.has_feature("web"):
		return "ultra"
	var js := "(function(){var n=navigator;return JSON.stringify({c:n.hardwareConcurrency||0,m:n.deviceMemory||0,w:Math.max(screen.width,screen.height),ua:n.userAgent||'',t:('ontouchstart' in window)});})()"
	var info = JSON.parse_string(str(JavaScriptBridge.eval(js, true)))
	if not info is Dictionary:
		return "hoch"
	var cores := int(info.get("c", 0))
	var mem := float(info.get("m", 0))
	var touch := bool(info.get("t", false))
	var ios := str(info.get("ua", "")).contains("iPhone") or str(info.get("ua", "")).contains("iPad")
	if (cores > 0 and cores <= 4) or (mem > 0.0 and mem <= 3.0):
		return "leistung"
	if ios:
		# Safari reports few details; the large Pro Max screen (932 pt) is the reference device
		return "ultra" if int(info.get("w", 0)) >= 932 else "hoch"
	return "hoch" if touch else "ultra"
