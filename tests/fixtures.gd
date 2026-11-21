extends RefCounted
## Tower fixtures built through real PLACE and REMOVE commands, never by poking internals.
## A spec is [floor, column, length]; occupant ids are 1.. in spec order.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Catalogue := preload("res://scripts/sim/room_catalogue.gd")
const Harness := preload("res://tests/harness.gd")


## A local elevator from the ground floor to `top` at column `x`, so every room on the floors it serves is reachable from
## the lobby (#368: rooms no route reaches earn and serve nothing). Needs the lobby and the floors at its column.
static func connect_floors(tower: TowerSim, top: int, x: int = 156) -> int:
	var code: int = tower.rooms.place_shaft(tower.grid, tower.floors, tower.ledger, 0, Catalogue.IDS.find("local_shaft"), 1, top, x)
	assert(code == 0, "the connecting shaft places, refusal %d" % code)
	return code


## Two flights of stairs from the lobby up to floor 3 at columns 156 and 160, which reach floor 3 without a lift's
## upkeep (so a test that counts the ledger is not disturbed). Needs floors 1 to 3 built there.
static func connect_by_stairs(tower: TowerSim) -> void:
	assert(tower.rooms.place_stairs(tower.grid, tower.floors, tower.ledger, 0, 1, 156) == 0, "the lower flight places")
	assert(tower.rooms.place_stairs(tower.grid, tower.floors, tower.ledger, 0, 2, 160) == 0, "the upper flight places")


## A tower at tick 1 with every spec placed (all commands apply at tick 1, in order).
static func with_rooms(seed_value: int, specs: Array) -> TowerSim:
	var tower := TowerSim.new(seed_value)
	var id := 1
	for spec: Array in specs:
		place(tower, id, spec[0], spec[1], spec[2], tower.tick + 1)
		id += 1
	tower.step()
	return tower


## Queues a PLACE for the given tick (the next tick by default). Returns false if refused.
static func place(tower: TowerSim, id: int, floor_number: int, column: int, length: int, at_tick: int = -1) -> bool:
	var when := tower.tick + 1 if at_tick < 0 else at_tick
	return tower.enqueue(Command.make(when, Command.PLACE, [id, floor_number, column, length] as Array[int]))


## Queues a REMOVE for the given tick (the next tick by default).
static func remove(tower: TowerSim, id: int, at_tick: int = -1) -> bool:
	var when := tower.tick + 1 if at_tick < 0 else at_tick
	return tower.enqueue(Command.make(when, Command.REMOVE, [id] as Array[int]))


## One room per floor on floors first to last (skipping the missing floor 0), each at
## column 0 and length wide. Returns the tower at tick 1.
static func stack(seed_value: int, first: int, last: int, wide: int) -> TowerSim:
	var specs: Array = []
	for floor_number in range(first, last + 1):
		if floor_number != 0:
			specs.append([floor_number, 0, wide])
	return with_rooms(seed_value, specs)


## The grid fixture the grid tests share: B10 room, wide floor 1 room, top-floor edge room,
## and a floor-5 room that is placed then removed. Returns the tower at tick 6.
static func grid_sample(seed_value: int) -> TowerSim:
	var tower := TowerSim.new(seed_value)
	place(tower, 1, -10, 0, 4, 1)
	place(tower, 2, 1, 10, 30, 2)
	place(tower, 3, 100, 399, 1, 3)
	place(tower, 4, 5, 20, 6, 4)
	remove(tower, 4, 5)
	Harness.step(tower, 6)
	return tower
