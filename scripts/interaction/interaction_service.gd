class_name InteractionService
extends Node
## Resolves what an interaction does.
##
## World nodes (Interactable) carry data; this service turns them into UI
## panels and executes actions. In multiplayer phases, `run_action` becomes a
## request to the authoritative server instead of a local state change.

var settlement: SettlementData


func _ready() -> void:
	EventBus.interaction_action.connect(run_action)


func open(it: Interactable) -> void:
	if it == null:
		return
	# doors act immediately – the button at the door says what happens
	if it.kind == "door_enter":
		EventBus.interaction_action.emit(it.interaction_id, "enter")
		return
	if it.kind == "interior_exit":
		EventBus.interaction_action.emit(it.interaction_id, "leave")
		return
	var info := it.to_info()
	if it.kind == "notice_board" and settlement:
		info["title"] = settlement.notice_board.get("title", it.title)
		info["subtitle"] = "%s · %s" % [settlement.settlement_name, settlement.development_status]
		info["text"] = settlement.notice_board.get("text", "")
	EventBus.interaction_opened.emit(info)


## Feedback for object actions (ActionLibrary). The animation itself is
## played by the settlement scene (Player.perform) – same clips as NPCs.
func run_action(interaction_id: String, action_id: String) -> void:
	if action_id in ["talk", "enter", "leave"] or action_id.begins_with("admin_"):
		return   # handled by the settlement (simulation, interiors, administration)
	var a := ActionLibrary.get_action(action_id)
	if a.is_empty():
		push_warning("InteractionService: unknown action %s on %s" % [action_id, interaction_id])
		return
	var text := str(a.get("toast", ""))
	if action_id == "rest":
		# real time cannot be skipped; resting is a moment of calm
		text = "Du ruhst dich einen Moment aus. Es ist %s Uhr." % GameClock.format_time()
	if text != "":
		EventBus.toast_requested.emit(text)
