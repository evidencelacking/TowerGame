extends RefCounted
## Tower fixtures built through real PLACE and REMOVE commands, never by poking internals.
## A spec is [floor, column, length]; occupant ids are 1.. in spec order.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const Harness := preload("res://tests/harness.gd")


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
