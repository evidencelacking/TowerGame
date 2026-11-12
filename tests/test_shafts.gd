extends RefCounted
## Elevator shaft tests (4.1): up to 30 floors including basements, 24 shafts in all.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const Harness := preload("res://tests/harness.gd")
const TestRooms := preload("res://tests/test_rooms.gd")


static func _shaft(tower: TowerSim, bottom: int, top: int, x_left: int, kind: String = "local_shaft") -> int:
	return TestRooms._send(tower, Command.PLACE_SHAFT, [CatalogueScript.IDS.find(kind), bottom, top, x_left] as Array[int])


## A rich tower with a lobby on floor 1 at columns 100 to 131 and floors built from B10 to 40 there.
static func _tall(funds: int = 100000000) -> TowerSim:
	var t := TowerSim.new(1, funds)
	TestRooms._send(t, Command.BUILD_LOBBY, [1, 100, 131, 1] as Array[int])
	for f in range(2, 41):
		t.floors.fill_span(f, 100, 131)
	for f in range(-1, -11, -1):
		t.floors.fill_span(f, 100, 131)
	return t


static func run(check: Callable) -> void:
	var local_cost: int = CatalogueScript.cost("local_shaft")
	# Span limit: basements count, so B10 to 20 is 30 floors and B10 to 21 is 31.
	var t := _tall()
	var funds := t.ledger.balance
	check.call(RoomsScript.shaft_span(-10, 20) == 30 and RoomsScript.shaft_span(-1, 1) == 2 and RoomsScript.shaft_span(1, 30) == 30, "spans count basements and skip floor 0")
	check.call(_shaft(t, 1, 31, 100) == RoomsScript.MAX_SHAFT_FLOORS and _shaft(t, 1, 32, 100) == RoomsScript.MAX_SHAFT_FLOORS, "31 floors above ground are refused")
	check.call(_shaft(t, -10, 21, 100) == RoomsScript.MAX_SHAFT_FLOORS, "31 floors across basements are refused")
	check.call(_shaft(t, 5, 3, 100) == RoomsScript.BAD_SHAFT_SPAN, "a top below the bottom is refused")
	check.call(t.ledger.balance == funds and t.rooms.shaft_count() == 0, "refusals are free and place nothing")
	check.call(_shaft(t, 1, 30, 100) == RoomsScript.OK, "30 floors above ground are accepted")
	check.call(funds - t.ledger.balance == local_cost, "a shaft is charged once at the catalogue price")
	check.call(_shaft(t, -10, 20, 110) == RoomsScript.OK, "30 floors across basements are accepted")
	var base: int = t.grid.cell_at(-10, 110)
	check.call(base != 0 and t.grid.cell_at(20, 113) != 0 and t.grid.cell_at(1, 110) != 0 and t.grid.cell_at(21, 110) == 0, "a shaft holds one cell column on each floor it spans")
	check.call(t.floors.has_shaft(-5, 111) and t.floors.has_shaft(20, 110) and not t.floors.has_shaft(21, 110), "shaft cells are marked on every floor")
	check.call(_shaft(t, 1, 30, 120, "express_shaft") == RoomsScript.OK, "express shafts take any height under the limit")

	# Overlap and missing floors.
	funds = t.ledger.balance
	check.call(_shaft(t, 5, 8, 102) == RoomsScript.OVERLAPS_ROOM, "overlapping a shaft is refused")
	check.call(TestRooms._room(t, 5, 3, 100) == RoomsScript.OVERLAPS_ROOM, "a room cannot sit on a shaft")
	check.call(_shaft(t, 35, 45, 100) == RoomsScript.NO_FLOOR_FOR_SHAFT, "a floor missing under the shaft is refused")
	check.call(_shaft(t, 1, 2, 300) == RoomsScript.NO_FLOOR_FOR_SHAFT, "no floor at all is refused")
	check.call(_shaft(t, 1, 2, 398) == RoomsScript.OFF_TOWER, "a shaft past the tower width is refused")
	check.call(t.ledger.balance == funds, "refusals are free")

	# Bulldoze frees every cell.
	var occupants := t.grid.occupant_count()
	check.call(TestRooms._send(t, Command.BULLDOZE, [7, 111] as Array[int]) == RoomsScript.OK, "a shaft can be bulldozed from any floor")
	check.call(occupants - t.grid.occupant_count() == 30 and t.rooms.shaft_count() == 2, "bulldozing removes all 30 per-floor occupants")
	check.call(t.grid.cell_at(-10, 110) == 0 and t.grid.cell_at(20, 110) == 0 and not t.floors.has_shaft(3, 110), "bulldozing frees every cell and mark")
	check.call(_shaft(t, -10, 20, 110) == RoomsScript.OK, "the freed column takes a shaft again")

	# Save round trip.
	var u := TowerSim.new(0)
	check.call(u.load_state(t.save()) and u.state_hash() == t.state_hash() and u.rooms.shaft_count() == 3, "shafts save and load exactly")
	check.call(TestRooms._send(u, Command.BULLDOZE, [25, 101] as Array[int]) == RoomsScript.OK and u.grid.cell_at(25, 100) == 0, "a loaded shaft can be bulldozed")

	# 24 shafts, not 25.
	var m := TowerSim.new(1, 100000000)
	TestRooms._send(m, Command.BUILD_LOBBY, [1, 0, 399, 1] as Array[int])
	m.floors.fill_span(2, 0, 399)
	var results: Array[int] = []
	for i in 25:
		results.append(_shaft(m, 1, 2, i * 4))
	var accepted := results.slice(0, 24).count(RoomsScript.OK)
	check.call(accepted == 24 and results[24] == RoomsScript.MAX_SHAFTS and m.rooms.shaft_count() == 24, "24 shafts are accepted and the 25th refused")
	TestRooms._send(m, Command.BULLDOZE, [1, 0] as Array[int])
	check.call(_shaft(m, 1, 2, 0) == RoomsScript.OK, "a bulldozed shaft frees a slot")

	# Determinism.
	var script: Array[Command] = [
		Command.make(1, Command.BUILD_LOBBY, [1, 100, 131, 1] as Array[int]),
		Command.make(2, Command.BUILD_FLOOR, [2, 100, 131] as Array[int]),
		Command.make(3, Command.PLACE_SHAFT, [CatalogueScript.IDS.find("local_shaft"), 1, 2, 100] as Array[int]),
		Command.make(4, Command.PLACE_SHAFT, [CatalogueScript.IDS.find("local_shaft"), 1, 2, 101] as Array[int]),
	]
	check.call(Harness.is_deterministic(7, script, 20), "the same seed and shaft commands give the same hashes")
