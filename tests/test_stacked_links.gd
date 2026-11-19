extends RefCounted
## Stacked stairs and escalators (#259): flights of one kind meet at exactly one floor, in the same
## columns. Placement, the refusals that stay, routes through a chain, bulldoze, save and load.
## No loops and no waits: each step is one sim command or one query, so every check can fail.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestElevatorRoutes := preload("res://tests/test_elevator_routes.gd")
const TestLinks := preload("res://tests/test_links.gd")


static func _stairs_legs(t: TowerSim, from_floor: int, from_x: int, to_floor: int, to_x: int) -> int:
	var route := RoutesScript.find(t.floors, t.rooms, t.grid, from_floor, from_x, to_floor, to_x)
	if route["reason"] != RoutesScript.OK:
		return -1
	return TestLinks._kinds(route).count(RoutesScript.STAIRS)


static func run(check: Callable) -> void:
	var t := TestElevatorRoutes._plain(6)
	check.call(TestLinks._stairs(t, 1, 100) == RoomsScript.OK, "stacked: the first flight, floors 1 to 2")
	check.call(TestLinks._stairs(t, 2, 100) == RoomsScript.OK, "stacked: a second flight above it, floors 2 to 3, in the same columns")
	check.call(TestLinks._stairs(t, 3, 100) == RoomsScript.OK, "stacked: a third flight, floors 3 to 4")
	check.call(TestLinks._stairs(t, 1, 100) == RoomsScript.OVERLAPS_LINK, "stacked: the same flight twice is refused")
	check.call(TestLinks._stairs(t, 2, 100) == RoomsScript.OVERLAPS_LINK, "stacked: a flight over the middle of the chain is refused")
	check.call(TestLinks._stairs(t, 2, 102) == RoomsScript.OVERLAPS_LINK and TestLinks._stairs(t, 2, 98) == RoomsScript.OVERLAPS_LINK, "stacked: a flight shifted sideways over the chain is refused")
	check.call(TestLinks._escalator(t, 3, 100) == RoomsScript.OVERLAPS_LINK, "stacked: another kind on the same columns is refused")
	check.call(TestLinks._stairs(t, 4, 102) == RoomsScript.OVERLAPS_LINK, "stacked: a flight over only part of the columns is refused")
	check.call(TestLinks._shaft(t, 1, 4, 100) == RoomsScript.OVERLAPS_LINK, "stacked: a shaft over the chain is refused")
	check.call(t.rooms.links_over.occupant_count() == 2, "stacked: the halves that found their cell taken sit in the second layer")
	check.call(_stairs_legs(t, 1, 101, 4, 101) == 3, "stacked: a route from 1 to 4 takes all three flights")
	check.call(_stairs_legs(t, 1, 101, 3, 103) == 2, "stacked: a route from 1 to 3 goes through both flights")
	check.call(_stairs_legs(t, 4, 100, 1, 100) == 3, "stacked: the way down uses the chain too")

	# Escalators stack the same way.
	var e := TestElevatorRoutes._plain(5)
	check.call(TestLinks._escalator(e, 3, 110) == RoomsScript.OK and TestLinks._escalator(e, 4, 110) == RoomsScript.OK, "stacked: two escalators stack")
	check.call(TestLinks._escalator(e, 3, 110) == RoomsScript.OVERLAPS_LINK, "stacked: a duplicate escalator is refused")
	check.call(TestLinks._stairs(e, 4, 110) == RoomsScript.OVERLAPS_LINK, "stacked: stairs do not stack on an escalator")

	# Placing the lower flight last also works.
	var u := TestElevatorRoutes._plain(5)
	check.call(TestLinks._stairs(u, 2, 100) == RoomsScript.OK and TestLinks._stairs(u, 1, 100) == RoomsScript.OK, "stacked: the lower flight may be placed after the upper")
	check.call(_stairs_legs(u, 1, 100, 3, 100) == 2, "stacked: and the chain routes")

	# Save and load keep the second layer; the hash is the same afterwards.
	var data := t.save()
	var loaded := TowerSim.new(1, 0)
	check.call(loaded.load_state(data) and loaded.state_hash() == t.state_hash(), "stacked: save and load round-trip the chain")
	check.call(loaded.rooms.links_over.state_ints() == t.rooms.links_over.state_ints(), "stacked: the second layer survives a load")
	check.call(_stairs_legs(loaded, 1, 101, 3, 103) == 2, "stacked: a loaded tower still routes through the chain")

	# Bulldozing the lower flight lets the next one take the front layer.
	check.call(TestRooms._send(t, Command.BULLDOZE, [1, 100] as Array[int]) == RoomsScript.OK, "stacked: the lower flight is bulldozed")
	check.call(t.rooms.kind_of(t.rooms.link_at(2, 100)) == "stairs" and t.rooms.links_over.occupant_count() == 1, "stacked: the next flight moves into the front layer")
	check.call(_stairs_legs(t, 2, 101, 4, 101) == 2, "stacked: the rest of the chain still routes")
