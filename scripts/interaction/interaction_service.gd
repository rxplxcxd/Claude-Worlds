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
	var info := it.to_info()
	if it.kind == "notice_board" and settlement:
		info["title"] = settlement.notice_board.get("title", it.title)
		info["subtitle"] = "%s · %s" % [settlement.settlement_name, settlement.development_status]
		info["text"] = settlement.notice_board.get("text", "")
	EventBus.interaction_opened.emit(info)


func run_action(interaction_id: String, action_id: String) -> void:
	match action_id:
		"rest":
			# Real time cannot be skipped; resting is a moment of calm.
			EventBus.toast_requested.emit("Du ruhst dich einen Moment aus. Es ist %s Uhr." % GameClock.format_time())
		"drink":
			EventBus.toast_requested.emit("Das Brunnenwasser ist kühl und klar.")
		_:
			push_warning("InteractionService: unknown action %s on %s" % [action_id, interaction_id])
