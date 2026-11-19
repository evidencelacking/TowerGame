extends RefCounted
## Elevator shafts, #228: click to place, drag either end, machine rooms above the top stop and below
## the bottom stop, missing floors built at the floor price.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const ElevatorTools := preload("res://scripts/view/elevator_tools.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestShafts := preload("res://tests/test_shafts.gd")

const COLUMN := 102  ## Pointer column that puts a 4-wide shaft at columns 100 to 103.
const UNIT := 500  ## FLOOR_COST_PER_UNIT, as the tests below read it.


static func _office(t: TowerSim, floor_number: int, x: int) -> int:
	return TestRooms._room(t, CatalogueScript.IDS.find("office"), floor_number, x)


## Resizes the shaft that has a stop on floor_number at column 100.
static func _resize(t: TowerSim, floor_number: int, bottom: int, top: int) -> int:
	var id: int = t.rooms._shaft_base(t.rooms.link_at(floor_number, 100))
	return TestRooms._send(t, Command.RESIZE_SHAFT, [id, bottom, top] as Array[int])


static func run(check: Callable) -> void:
	check.call(CatalogueScript.FLOOR_COST_PER_UNIT == UNIT, "fixture: the floor price is $500 a unit")
	var width: int = CatalogueScript.field("local_shaft", "width")
	var local_cost: int = CatalogueScript.cost("local_shaft")

	# Machine rooms: the floors above the top stop and below the bottom stop; floor 1 has them in the ground.
	check.call(RoomsScript.machine_floors(5, 8) == ([4, 9] as Array[int]), "a shaft has a machine room above and below")
	check.call(RoomsScript.machine_floors(1, 8) == ([9] as Array[int]), "a bottom stop on floor 1 has its machine room in the ground")
	check.call(RoomsScript.machine_floors(-1, 3) == ([-2, 4] as Array[int]) and RoomsScript.machine_floors(-3, -1) == ([-4, 1] as Array[int]), "machine rooms cross the ground floor like the stops do")
	check.call(RoomsScript.machine_floors(2, 99) == ([1, 100] as Array[int]), "floor 100 can hold a machine room")

	# A click places a one-floor shaft: the price, the machine rooms, no B1 needed.
	var t := TestShafts._tall()
	var funds := t.ledger.balance
	var click := ElevatorTools.evaluate_shaft(t, "local_shaft", 5, 5, COLUMN, 1)
	check.call(click["valid"] and click["mode"] == "place" and click["floor"] == 5 and click["top"] == 5 and click["cost"] == local_cost and click["machines"] == ([4, 6] as Array[int]), "a click on empty ground previews a one-floor shaft with two machine rooms")
	var args: Array[int] = [CatalogueScript.IDS.find("local_shaft"), 5, 5, 100]
	check.call(click["command"] == Command.PLACE_SHAFT and click["args"] == args, "a click queues PLACE_SHAFT over the one floor")
	check.call(TestShafts._shaft(t, 5, 5, 100) == RoomsScript.OK and funds - t.ledger.balance == local_cost and t.rooms.shaft_count() == 1, "a click-placed shaft is charged the catalogue price only")
	var id: int = t.rooms._shaft_base(t.rooms.link_at(5, 100))
	check.call(t.rooms.stops_of(id) == ([5] as Array[int]), "the machine rooms are not stops")
	check.call(t.rooms.machine_room_at(4, 101) and t.rooms.machine_room_at(6, 103) and not t.rooms.machine_room_at(5, 100) and not t.rooms.machine_room_at(4, 104) and not t.rooms.machine_room_at(7, 100), "machine rooms stand above and below the shaft on its columns")

	# Dragging the top and the bottom end: free over floors that exist.
	funds = t.ledger.balance
	var up := ElevatorTools.evaluate_shaft(t, "local_shaft", 9, 5, COLUMN, 1)
	check.call(up["valid"] and up["mode"] == "resize" and up["floor"] == 5 and up["top"] == 9 and up["cost"] == 0 and "free" in up["note"], "dragging the top end up previews a taller shaft, free")
	check.call(_resize(t, 5, 5, 9) == RoomsScript.OK and t.ledger.balance == funds, "growing the top over built floors is free")
	check.call(_resize(t, 5, 3, 9) == RoomsScript.OK and t.ledger.balance == funds, "growing the bottom over built floors is free")
	check.call(t.rooms.machine_room_at(2, 100) and t.rooms.machine_room_at(10, 100) and not t.rooms.machine_room_at(4, 100), "the machine rooms follow the ends")
	check.call(_resize(t, 3, 4, 6) == RoomsScript.OK and t.ledger.balance == funds and t.rooms.machine_room_at(3, 100) and t.rooms.machine_room_at(7, 100), "shortening is free and refunds nothing")

	# A drag onto floors that do not exist builds them, and the machine room floor, at the floor price.
	var rich := TestShafts._tall()
	funds = rich.ledger.balance
	TestShafts._shaft(rich, 38, 40, 100)  # the machine room above, on floor 41, is built too
	check.call(funds - rich.ledger.balance == local_cost + width * UNIT and rich.floors.has_floor(41, 103) and not rich.floors.has_floor(42, 100), "a missing machine room floor is built and charged at the floor price")
	funds = rich.ledger.balance
	check.call(_resize(rich, 38, 38, 44) == RoomsScript.OK and funds - rich.ledger.balance == 4 * width * UNIT, "growing over floors 42 to 45 builds them under the shaft and its machine room")
	check.call(rich.floors.has_floor(45, 101) and rich.floors.has_floor(44, 103) and rich.rooms.machine_room_at(45, 100), "the built floors are under the shaft and the machine room")
	var floating := ElevatorTools.evaluate_shaft(rich, "local_shaft", 62, 60, 110, 1)
	check.call(not floating["valid"] and floating["code"] == RoomsScript.NO_FLOOR_FOR_SHAFT, "a drag with no floor to rest on is refused")
	var short := TowerSim.new(1, 100000000)
	TestRooms._send(short, Command.BUILD_LOBBY, [1, 100, 131, 1] as Array[int])
	TestRooms._send(short, Command.PURCHASE, [short.ledger.balance - 100000, 1] as Array[int])
	var short_funds := short.ledger.balance
	check.call(TestShafts._shaft(short, 1, 3, 100) == RoomsScript.SHORT_OF_FUNDS and short.ledger.balance == short_funds and not short.floors.has_floor(2, 100) and short.rooms.shaft_count() == 0, "a shaft the player cannot afford builds nothing")

	# Floor 1 at the bottom: the machine room is in the ground, so no B1 is needed or built.
	var bare := TowerSim.new(1, 100000000)
	TestRooms._send(bare, Command.BUILD_LOBBY, [1, 100, 131, 1] as Array[int])
	bare.floors.fill_span(2, 100, 131)
	funds = bare.ledger.balance
	check.call(TestShafts._shaft(bare, 1, 2, 100) == RoomsScript.OK and not bare.floors.has_floor(-1, 100), "a shaft from floor 1 needs no B1")
	check.call(funds - bare.ledger.balance == local_cost + width * UNIT, "only the machine room above (floor 3) is built and charged")
	check.call(not bare.rooms.machine_room_at(-1, 100) and bare.rooms.machine_room_at(3, 100), "the ground machine room takes no B1 cell")
	var g := TestShafts._tall()
	TestShafts._shaft(g, 1, 3, 100)
	check.call(g.floors.has_floor(-1, 100) and not g.rooms.machine_room_at(-1, 100), "B1 under a floor-1 shaft stays free")

	# The ends of the tower: floor 100 and B10 have no room for a machine room.
	var tall := TowerSim.new(1, 1000000000)
	TestRooms._send(tall, Command.BUILD_LOBBY, [1, 100, 131, 1] as Array[int])
	for f in range(2, 101):
		tall.floors.fill_span(f, 100, 131)
	for f in range(-1, -11, -1):
		tall.floors.fill_span(f, 100, 131)
	check.call(TestShafts._shaft(tall, 95, 100, 100) == RoomsScript.NO_MACHINE_ROOM, "a top stop on floor 100 is refused")
	check.call(TestShafts._shaft(tall, -10, -5, 100) == RoomsScript.NO_MACHINE_ROOM, "a bottom stop on B10 is refused")
	check.call(TestShafts._shaft(tall, 95, 99, 100) == RoomsScript.OK and TestShafts._shaft(tall, -9, -5, 110) == RoomsScript.OK, "floor 99 and B9 are the last stops")
	check.call(_resize(tall, 95, 95, 100) == RoomsScript.NO_MACHINE_ROOM, "a drag of the top end to floor 100 is refused")

	# Rooms and machine rooms keep apart, whichever comes first.
	var r := TestShafts._tall()
	_office(r, 4, 100)
	check.call(TestShafts._shaft(r, 5, 6, 100) == RoomsScript.OVERLAPS_ROOM and r.rooms.shaft_count() == 0, "a room on a machine room cell blocks the shaft")
	check.call(TestShafts._shaft(r, 4, 6, 100) == RoomsScript.OK, "a room on a floor the shaft spans is fine (links sit in front)")
	check.call(_office(r, 7, 100) == RoomsScript.MACHINE_ROOM, "a room cannot be placed on the machine room above")
	var rooms_before := r.rooms.room_count()
	check.call(_office(r, 7, 96) == RoomsScript.MACHINE_ROOM and r.rooms.room_count() == rooms_before, "a room that reaches into a machine room cell is refused")
	check.call(_office(r, 7, 104) == RoomsScript.OK, "a room beside the machine room is fine")
	check.call(TestShafts._shaft(r, 8, 9, 100) == RoomsScript.OVERLAPS_LINK, "another shaft cannot share a machine room cell")

	# The lobby is a room too: a machine room cannot be in it.
	var l := TestShafts._tall()
	check.call(TestShafts._shaft(l, 2, 4, 100) == RoomsScript.OVERLAPS_LOBBY, "a shaft starting above the lobby has no place for its machine room")

	# A save keeps the machine rooms, and bulldozing the shaft frees them.
	var u := TowerSim.new(0)
	check.call(u.load_state(r.save()) and u.state_hash() == r.state_hash(), "a tower with machine rooms saves and loads exactly")
	check.call(_office(u, 7, 100) == RoomsScript.MACHINE_ROOM, "a loaded tower keeps its machine rooms")
	TestRooms._send(r, Command.BULLDOZE, [5, 100] as Array[int])
	check.call(r.rooms.shaft_count() == 0 and not r.rooms.machine_room_at(7, 100) and not r.rooms.machine_room_at(3, 100), "bulldozing the shaft frees its machine rooms")
