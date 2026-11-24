class_name RemoteWorldClient
extends WorldClient
## Phase 12 placeholder: authoritative world service (Firebase Auth for the
## identity, a simulation service for the world – docs/FIREBASE_SCHEMA.md).
## No paid service has been commissioned; this stub keeps the interface
## stable and reports clearly that it is not available yet.

const REASON := "remote world service is planned for Phase 12 (not available)"


func is_remote() -> bool:
	return true


func now() -> int:
	return int(Time.get_unix_time_from_system())


func snapshot(_settlement_id: String) -> Dictionary:
	return {}


func submit(_cmd: Dictionary) -> Dictionary:
	return {"ok": false, "reason": REASON}
