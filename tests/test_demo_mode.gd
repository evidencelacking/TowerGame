extends RefCounted
## Demo mode (#262): a debug command raises the star rating and never lowers it, a demo tower
## starts with the huge balance, and the rating is plain hashed state.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const TestRooms := preload("res://tests/test_rooms.gd")


static func run(check: Callable) -> void:
	var t := TowerSim.new(0, DemoMode.FUNDS)
	check.call(t.ledger.balance == DemoMode.FUNDS and t.stars == 1, "a demo tower starts rich at 1 star")
	var plain := TowerSim.new(0, DemoMode.FUNDS)
	plain.step()
	TestRooms._send(t, Command.DEBUG_SET_STARS, [DemoMode.STARS] as Array[int])
	check.call(t.stars == 5, "the debug command raises the rating to 5")
	check.call(t.tick == plain.tick and t.state_hash() != plain.state_hash(), "the rating is part of the state hash")
	TestRooms._send(t, Command.DEBUG_SET_STARS, [2] as Array[int])
	check.call(t.stars == 5, "the debug command never lowers the rating")
	var other := TowerSim.new(0, DemoMode.FUNDS)
	TestRooms._send(other, Command.DEBUG_SET_STARS, [99] as Array[int])
	check.call(other.stars == 5, "the debug command clamps to 5")
	check.call(not DemoMode.forced, "demo mode is off unless asked for")
