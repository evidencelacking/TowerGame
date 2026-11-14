extends RefCounted
## Shaft resize and per-floor stop tests (4.2).

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const Harness := preload("res://tests/harness.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestShafts := preload("res://tests/test_shafts.gd")


static func _resize(t: TowerSim, id: int, bottom: int, top: int) -> int:
	return TestRooms._send(t, Command.RESIZE_SHAFT, [id, bottom, top] as Array[int])


static func _stop(t: TowerSim, id: int, floor_number: int, on: int) -> int:
	return TestRooms._send(t, Command.SET_SHAFT_STOP, [id, floor_number, on] as Array[int])


## The shaft id at a cell on a floor (its id may change on resize).
static func _id_at(t: TowerSim, floor_number: int, x: int) -> int:
	return t.rooms._shaft_base(t.rooms.link_at(floor_number, x))


static func run(check: Callable) -> void:
	var t := TestShafts._tall()
	TestShafts._shaft(t, 5, 10, 100)
	var id := _id_at(t, 5, 100)
	var funds := t.ledger.balance
	check.call(t.rooms.stops_of(id) == ([5, 6, 7, 8, 9, 10] as Array[int]) and t.rooms.is_stop(id, 7), "every spanned floor is a stop by default")

	# Grow and shrink.
	var first := id
	check.call(_resize(t, id, 3, 12) == RoomsScript.OK, "growing both ways is accepted")
	check.call(_id_at(t, 3, 100) == first and _id_at(t, 12, 100) == first, "the shaft id is unchanged after a grow")
	check.call(t.rooms.link_at(3, 100) != 0 and t.rooms.link_at(12, 103) != 0 and t.rooms.link_at(2, 100) == 0 and t.rooms.link_at(13, 100) == 0, "grow fills the new floors")
	check.call(t.floors.has_shaft(3, 101) and t.floors.has_shaft(12, 100), "grow marks the new floors")
	check.call(t.ledger.balance == funds and t.rooms.shaft_count() == 1, "resize is free and keeps one shaft")
	check.call(t.rooms.stops_of(id).size() == 10 and t.rooms.is_stop(id, 3), "new floors are stops")
	check.call(_resize(t, id, 6, 8) == RoomsScript.OK, "shrinking is accepted")
	check.call(_id_at(t, 6, 100) == first, "the shaft id is unchanged after a shrink")
	check.call(t.rooms.link_at(5, 100) == 0 and t.rooms.link_at(9, 100) == 0 and t.rooms.link_at(7, 100) != 0, "shrink frees dropped cells")
	check.call(not t.floors.has_shaft(5, 100) and not t.floors.has_shaft(12, 103) and t.floors.has_shaft(8, 100), "shrink clears dropped marks")
	check.call(TestShafts._shaft(t, 3, 5, 100) == RoomsScript.OK, "a dropped floor takes another shaft")
	check.call(_resize(t, id, 8, 6) == RoomsScript.BAD_SHAFT_SPAN and _resize(t, id, 6, 8) == RoomsScript.OK, "top below bottom refused, shaft unchanged")
	check.call(_resize(t, 999999, 1, 2) == RoomsScript.NOTHING_THERE, "an unknown shaft is refused")

	# Limits.
	var base := _id_at(t, 6, 100)
	check.call(_resize(t, base, 6, 36) == RoomsScript.MAX_SHAFT_FLOORS, "a resize past 30 floors is refused")
	check.call(t.rooms.link_at(6, 100) != 0 and t.rooms.link_at(8, 100) != 0 and t.floors.has_shaft(8, 100), "a refused resize changes nothing")
	TestShafts._shaft(t, 1, 3, 120, "express_shaft")
	var ex := _id_at(t, 1, 120)
	check.call(_resize(t, ex, 1, 40) == RoomsScript.OK, "express shafts may grow past 30 floors")
	check.call(_resize(t, ex, 1, 45) == RoomsScript.NO_FLOOR_FOR_SHAFT, "a missing floor refuses a resize")
	check.call(_resize(t, base, 3, 8) == RoomsScript.OVER_SHAFT, "an overlapping shaft refuses a resize")
	TestRooms._send(t, Command.BUILD_FLOOR, [41, 100, 131] as Array[int])
	TestRooms._room(t, CatalogueScript.IDS.find("office"), 9, 100)
	check.call(_resize(t, base, 6, 9) == RoomsScript.OK and _resize(t, base, 6, 8) == RoomsScript.OK, "a shaft may grow through a room (links sit in front of rooms)")

	# Stops.
	base = _id_at(t, 6, 100)
	check.call(_stop(t, base, 7, 0) == RoomsScript.OK, "a stop can be turned off")
	check.call(not t.rooms.is_stop(base, 7) and t.rooms.is_stop(base, 6) and t.rooms.stops_of(base) == ([6, 8] as Array[int]), "a disabled floor is skipped")
	check.call(_stop(t, base, 20, 0) == RoomsScript.NOT_IN_SHAFT and _stop(t, base, 5, 1) == RoomsScript.NOT_IN_SHAFT, "a stop outside the span is refused")
	check.call(not t.rooms.is_stop(base, 20), "a floor outside the span is not a stop")
	check.call(_resize(t, base, 7, 8) == RoomsScript.OK, "resize with a disabled floor")
	base = _id_at(t, 7, 100)
	check.call(t.rooms.stops_of(base) == ([8] as Array[int]), "the disabled flag is kept across a resize")
	check.call(_resize(t, base, 6, 8) == RoomsScript.OK, "regrow")
	base = _id_at(t, 6, 100)
	check.call(t.rooms.stops_of(base) == ([6, 8] as Array[int]), "a regrown floor is a stop and the kept flag still holds")
	check.call(_stop(t, base, 7, 1) == RoomsScript.OK and t.rooms.is_stop(base, 7), "a stop can be turned back on")
	_stop(t, base, 8, 0)
	_resize(t, base, 6, 7)
	base = _id_at(t, 6, 100)
	_resize(t, base, 6, 8)
	base = _id_at(t, 6, 100)
	check.call(t.rooms.is_stop(base, 8), "a dropped floor forgets its disabled flag")

	# Save round trip.
	_stop(t, base, 7, 0)
	var u := Harness.clone_via_save(t)
	check.call(u != null and u.state_hash() == t.state_hash() and not u.rooms.is_stop(base, 7) and u.rooms.is_stop(base, 6), "stop flags save and load exactly")
	check.call(u != null and u.rooms.stops_of(ex).size() == 40, "a loaded shaft keeps its span")

	# Determinism.
	var local := CatalogueScript.IDS.find("local_shaft")
	var script: Array[Command] = [
		Command.make(1, Command.BUILD_LOBBY, [1, 100, 131, 1] as Array[int]),
		Command.make(2, Command.BUILD_FLOOR, [2, 100, 131] as Array[int]),
		Command.make(3, Command.BUILD_FLOOR, [3, 100, 131] as Array[int]),
		Command.make(4, Command.PLACE_SHAFT, [local, 1, 2, 100] as Array[int]),
		Command.make(5, Command.RESIZE_SHAFT, [1000, 1, 3] as Array[int]),
		Command.make(6, Command.SET_SHAFT_STOP, [1000, 2, 0] as Array[int]),
	]
	check.call(Harness.is_deterministic(7, script, 20), "the same seed and resize commands give the same hashes")
