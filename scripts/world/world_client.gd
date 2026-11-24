class_name WorldClient
extends RefCounted
## The ONLY way game code reads or changes the shared world (MMO contract).
## Implementations:
##   LocalWorldClient  – development adapter: authority in the same process
##   RemoteWorldClient – Phase 12: Firebase Auth + simulation service (stub)
## Results are dictionaries ({ok, ...}) so a network transport fits later
## without changing callers.

func is_remote() -> bool:
	return false


## Authority time (UTC seconds) – never the device clock in multiplayer.
func now() -> int:
	return 0


## Current shared state of a settlement (read-only for the caller).
func snapshot(_settlement_id: String) -> Dictionary:
	return {}


## Sends a command {kind, settlement_id, payload}; command_id and issuer are
## filled in. Returns {ok, seq} or {ok: false, reason}.
func submit(_cmd: Dictionary) -> Dictionary:
	return {"ok": false, "reason": "not implemented"}


static func new_command(kind: String, settlement_id: String, issuer: String, payload: Dictionary = {}) -> Dictionary:
	return {"command_id": Ids.generate("cmd", 16), "kind": kind, "settlement_id": settlement_id, "issuer": issuer, "payload": payload}
