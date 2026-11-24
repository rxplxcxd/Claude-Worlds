class_name LocalWorldClient
extends WorldClient
## Development adapter: talks to an in-process WorldAuthority. Behaves like
## the later remote client (commands, snapshots, authority time); it can only
## simulate while the game runs – on start the authority catches up to now
## with exactly the logic a server would run continuously.

var authority: WorldAuthority
var player_id := ""


static func connect_to(p_authority: WorldAuthority, p_player_id: String) -> LocalWorldClient:
	var c := LocalWorldClient.new()
	c.authority = p_authority
	c.player_id = p_player_id
	return c


func now() -> int:
	return authority.now()


func snapshot(settlement_id: String) -> Dictionary:
	return authority.snapshot(settlement_id)


func submit(cmd: Dictionary) -> Dictionary:
	var c := cmd.duplicate(true)
	if not c.has("command_id"):
		c["command_id"] = Ids.generate("cmd", 16)
	c["issuer"] = player_id   # the transport authenticates the issuer, never the payload
	return authority.submit(c)
