extends RefCounted
## Stairs tests (2.9): between two floors, not over shafts, shared 64 limit, bulldozable.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const TestRooms := preload("res://tests/test_rooms.gd")

const OFFICE := 5
const ESCALATOR := 13


static func _stairs(tower: TowerSim, floor_number: int, x_left: int) -> int:
	return TestRooms._send(tower, Command.PLACE_STAIRS, [floor_number, x_left] as Array[int])


static func run(check: Callable) -> void:
	# A 2-floor lobby at columns 100 to 131 (floors 1 and 2), then an office floor 3 over it.
	var t := TowerSim.new(1, 2000000)
	TestRooms._send(t, Command.BUILD_LOBBY, [1, 100, 131, 2] as Array[int])
	var funds := t.ledger.balance
	check.call(_stairs(t, 1, 100) == RoomsScript.OK, "stairs are allowed inside a 2-floor lobby")
	check.call(funds - t.ledger.balance == 5000, "stairs cost $5,000")
	check.call(t.rooms.kind_of(t.grid.cell_at(1, 100)) == "stairs" and t.grid.cell_at(2, 103) != 0, "stairs take 4 cells on both floors")
	check.call(_stairs(t, 1, 102) == RoomsScript.OVERLAPS_ROOM, "overlapping stairs are refused")
	check.call(TestRooms._room(t, OFFICE, 2, 100) == RoomsScript.OVERLAPS_ROOM, "an office cannot sit on the stairs' upper floor")
	check.call(_stairs(t, 1, 104) == RoomsScript.OK, "stairs beside stairs are fine")

	# Missing floors.
	funds = t.ledger.balance
	check.call(_stairs(t, 2, 120) == RoomsScript.NO_FLOOR_FOR_STAIRS, "stairs need the upper floor too")
	check.call(_stairs(t, 3, 120) == RoomsScript.NO_FLOOR_FOR_STAIRS, "stairs need the lower floor")
	check.call(_stairs(t, 1, 129) == RoomsScript.NO_FLOOR_FOR_STAIRS, "stairs may not hang past the floor")
	check.call(_stairs(t, 0, 100) == RoomsScript.BAD_FLOOR and _stairs(t, 100, 100) == RoomsScript.BAD_FLOOR, "no stairs from floor 0 or 100")
	check.call(_stairs(t, 1, 398) == RoomsScript.OFF_TOWER, "stairs past the tower width are refused")
	check.call(t.ledger.balance == funds, "refusals are free")

	# Shaft occupancy placed directly in the grid.
	var s := TowerSim.new(1, 2000000)
	TestRooms._send(s, Command.BUILD_LOBBY, [1, 100, 131, 2] as Array[int])
	s.floors.mark_shaft(2, 111)
	funds = s.ledger.balance
	check.call(_stairs(s, 1, 110) == RoomsScript.OVER_SHAFT, "stairs over a shaft on the upper floor are refused")
	check.call(s.ledger.balance == funds, "a shaft refusal is free")
	s.floors.mark_shaft(2, 111, false)
	s.floors.mark_shaft(1, 112)
	check.call(_stairs(s, 1, 110) == RoomsScript.OVER_SHAFT, "stairs over a shaft on the lower floor are refused")

	# Funds.
	var poor := TowerSim.new(1, 1000000)
	TestRooms._send(poor, Command.BUILD_LOBBY, [1, 100, 131, 2] as Array[int])
	poor.ledger.charge(poor.tick, poor.ledger.balance - 4999, 0)
	check.call(_stairs(poor, 1, 100) == RoomsScript.SHORT_OF_FUNDS and poor.rooms.room_count() == 0, "stairs are refused when short of funds")

	# Limit: 64 stairs and escalators share one limit.
	var big := TowerSim.new(1, 100000000)
	TestRooms._send(big, Command.BUILD_LOBBY, [1, 0, 399, 3] as Array[int])
	for i in 62:
		_stairs(big, 1, i * 4)
	big.rooms._kind_of[5000] = ESCALATOR  # an escalator (not placeable yet) counts toward the same limit
	check.call(big.rooms.room_count() == 63, "62 stairs and an escalator are placed")
	var checked := big.rooms.check_place_stairs(big.grid, big.floors, 1, 396)
	check.call(checked["reason"] == RoomsScript.OK and checked["cost"] == 5000, "the 64th is allowed, and check reports its cost")
	check.call(_stairs(big, 1, 396) == RoomsScript.OK, "the 64th stairs is placed")
	funds = big.ledger.balance
	check.call(_stairs(big, 2, 300) == RoomsScript.STAIRS_LIMIT, "the 65th is refused with its own reason")
	check.call(big.ledger.balance == funds, "the limit refusal is free")

	# Bulldoze from either floor, free, frees a slot.
	var before := big.ledger.balance
	check.call(TestRooms._send(big, Command.BULLDOZE, [2, 397] as Array[int]) == RoomsScript.OK, "stairs are bulldozed from the upper floor")
	check.call(big.ledger.balance == before and big.rooms.room_count() == 63, "bulldozing stairs is free")
	check.call(big.grid.cell_at(1, 396) == 0 and big.grid.cell_at(2, 396) == 0, "both floors' cells are freed")
	check.call(_stairs(big, 2, 300) == RoomsScript.OK, "a slot is free again after bulldozing")
	check.call(TestRooms._send(big, Command.BULLDOZE, [2, 300] as Array[int]) == RoomsScript.OK, "stairs are bulldozed from the lower floor of the pair")
	check.call(TestRooms._send(big, Command.BULLDOZE, [1, 396] as Array[int]) == RoomsScript.PERMANENT, "the lobby under removed stairs is still permanent")

	# Save and load, deterministic hash.
	var copy := TowerSim.new(9)
	check.call(copy.load_state(t.save()) and copy.state_hash() == t.state_hash(), "a tower with stairs saves and loads")
