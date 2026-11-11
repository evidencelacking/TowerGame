extends RefCounted
## Ground lobby tests (2.2): floor 1 only, 1 to 3 floors tall, cost, floor blocking, width cap.

const Harness := preload("res://tests/harness.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const FloorsScript := preload("res://scripts/sim/floors.gd")


static func _lobby(tower: TowerSim, floor_number: int, x_start: int, x_end: int, height: int) -> int:
	Harness.queue_all(tower, [Command.make(tower.tick + 1, Command.BUILD_LOBBY, [floor_number, x_start, x_end, height])])
	tower.step()
	return tower.last_refusal


static func _floor(tower: TowerSim, floor_number: int, x_start: int, x_end: int) -> int:
	Harness.queue_all(tower, [Command.make(tower.tick + 1, Command.BUILD_FLOOR, [floor_number, x_start, x_end])])
	tower.step()
	return tower.last_refusal


static func run(check: Callable) -> void:
	# Exact cost: (5,000 + 500) x 10 wide x height.
	for height: int in [1, 2, 3]:
		var t := Harness.make(1)
		var start_funds := t.ledger.balance
		check.call(_lobby(t, 1, 100, 109, height) == FloorsScript.OK, "a %d-tall lobby builds" % height)
		check.call(start_funds - t.ledger.balance == 5500 * 10 * height, "a %d-tall lobby costs (lobby + floor) x width x height" % height)
		check.call(t.ledger.lines.size() == 2, "the lobby is one ledger charge")
		check.call(t.floors.has_floor(height, 100) and t.floors.has_floor(height, 109) and not t.floors.has_floor(height + 1, 100), "a %d-tall lobby builds floors 1 to %d" % [height, height])
		check.call(t.floors.lobby_span() == ([100, 109, height] as Array[int]), "lobby_span reports the lobby")

	# A 2-floor lobby takes floor 2 inside its span.
	var tower := Harness.make(1)
	_lobby(tower, 1, 100, 109, 2)
	var funds := tower.ledger.balance
	check.call(_floor(tower, 2, 102, 105) == FloorsScript.OCCUPIED_BY_LOBBY, "floor 2 inside a 2-floor lobby is refused")
	check.call(_floor(tower, 1, 100, 109) == FloorsScript.OCCUPIED_BY_LOBBY and tower.ledger.balance == funds, "the lobby's floor 1 is taken and a refusal is free")
	# Width cap: floor 3 sits on the lobby's top floor and cannot be wider.
	check.call(_floor(tower, 3, 98, 105) == FloorsScript.WIDER_THAN_BELOW, "floor 3 above a 2-floor lobby cannot be wider than it")
	check.call(_floor(tower, 3, 100, 109) == FloorsScript.OK, "floor 3 as wide as the lobby is allowed")

	# A 1-floor lobby caps floor 2; a 3-floor lobby caps floor 4.
	var one := Harness.make(1)
	_lobby(one, 1, 50, 59, 1)
	check.call(_floor(one, 2, 45, 59) == FloorsScript.WIDER_THAN_BELOW, "the lobby's width limits floor 2")
	check.call(_floor(one, 2, 50, 59) == FloorsScript.OK, "floor 2 may match the lobby's width")
	var three := Harness.make(1)
	_lobby(three, 1, 50, 59, 3)
	check.call(_floor(three, 4, 50, 65) == FloorsScript.WIDER_THAN_BELOW, "a 3-floor lobby limits floor 4")
	check.call(_floor(three, 4, 52, 57) == FloorsScript.OK, "floor 4 inside a 3-floor lobby's width is allowed")

	# Refusals.
	var bad := Harness.make(1)
	var start := bad.ledger.balance
	check.call(_lobby(bad, 2, 10, 19, 1) == FloorsScript.LOBBY_BAD_FLOOR, "a lobby off floor 1 is refused")
	check.call(_lobby(bad, 0, 10, 19, 1) == FloorsScript.LOBBY_BAD_FLOOR, "there is no floor 0 lobby")
	check.call(_lobby(bad, 1, 10, 19, 4) == FloorsScript.LOBBY_BAD_HEIGHT, "a 4-tall lobby is refused")
	check.call(_lobby(bad, 1, 10, 19, 0) == FloorsScript.LOBBY_BAD_HEIGHT, "a 0-tall lobby is refused")
	check.call(_lobby(bad, 1, 19, 10, 1) == FloorsScript.BAD_SPAN, "a backwards lobby span is refused")
	check.call(bad.ledger.balance == start and not bad.floors.has_lobby(), "refused lobbies change nothing")
	check.call(_lobby(bad, 1, 10, 19, 1) == FloorsScript.OK, "the first lobby builds")
	check.call(_lobby(bad, 1, 100, 109, 1) == FloorsScript.LOBBY_EXISTS, "a second lobby is refused")

	# Existing floor units are not charged twice.
	var pre := Harness.make(1)
	_floor(pre, 1, 10, 14)
	funds = pre.ledger.balance
	_lobby(pre, 1, 10, 19, 1)
	check.call(funds - pre.ledger.balance == 5000 * 10 + 500 * 5, "floor units already built are not charged again")

	# Funds: 1 tall x 10 wide costs $55,000.
	var poor := TowerSim.new(1, 54999)
	check.call(_lobby(poor, 1, 0, 9, 1) == FloorsScript.SHORT_OF_FUNDS and not poor.floors.has_lobby() and poor.ledger.balance == 54999, "a lobby over the balance is refused and changes nothing")
	var exact := TowerSim.new(1, 55000)
	check.call(_lobby(exact, 1, 0, 9, 1) == FloorsScript.OK and exact.ledger.balance == 0, "an exact-balance lobby succeeds")

	# Save, load and determinism.
	var loaded := TowerSim.new(0)
	check.call(loaded.load_state(tower.save()) and loaded.state_hash() == tower.state_hash() and loaded.floors.lobby_span() == ([100, 109, 2] as Array[int]), "the lobby survives save and load")
	var script: Array[Command] = [
		Command.make(1, Command.BUILD_LOBBY, [1, 20, 39, 3]),
		Command.make(2, Command.BUILD_LOBBY, [1, 50, 59, 1]),
		Command.make(3, Command.BUILD_FLOOR, [4, 25, 30]),
	]
	check.call(Harness.run_script(7, script, 4) == Harness.run_script(7, script, 4), "the same lobby commands give the same hash trace")
