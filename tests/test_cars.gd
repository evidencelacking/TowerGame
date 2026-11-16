extends RefCounted
## Local elevator car tests (4.3): up to 8 cars per shaft, star cap, 17 per car, home floor.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const Harness := preload("res://tests/harness.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestShafts := preload("res://tests/test_shafts.gd")


static func _add(t: TowerSim, id: int, home: int) -> int:
	return TestRooms._send(t, Command.ADD_CAR, [id, home] as Array[int])


static func _shaft_id(t: TowerSim, floor_number: int, x: int) -> int:
	return t.rooms._shaft_base(t.rooms.link_at(floor_number, x))


static func run(check: Callable) -> void:
	var t := TestShafts._tall()
	TestShafts._shaft(t, 1, 10, 100)
	var id := _shaft_id(t, 1, 100)

	# Star cap: 1 star allows 2 cars.
	check.call(t.stars == 1 and _add(t, id, 1) == RoomsScript.OK and _add(t, id, 5) == RoomsScript.OK, "two cars at 1 star are accepted")
	check.call(_add(t, id, 1) == RoomsScript.STAR_CAR_CAP and t.rooms.car_count(id) == 2, "the star cap refuses the 3rd car at 1 star")
	t.stars = 3
	for n in 6:
		_add(t, id, 2)
	check.call(t.rooms.car_count(id) == 8, "the 8th car is accepted at 3 stars")
	var funds := t.ledger.balance
	check.call(_add(t, id, 2) == RoomsScript.MAX_CARS and t.rooms.car_count(id) == 8 and t.ledger.balance == funds, "the 9th car is refused, free")

	# Home floor, price, capacity, state.
	var u := TestShafts._tall()
	TestShafts._shaft(u, 3, 8, 100)
	var uid := _shaft_id(u, 3, 100)
	funds = u.ledger.balance
	check.call(_add(u, uid, 9) == RoomsScript.BAD_HOME_FLOOR and _add(u, uid, 2) == RoomsScript.BAD_HOME_FLOOR, "a home floor outside the span is refused")
	TestRooms._send(u, Command.SET_SHAFT_STOP, [uid, 5, 0] as Array[int])
	check.call(_add(u, uid, 5) == RoomsScript.BAD_HOME_FLOOR and u.ledger.balance == funds, "a non-stop home floor is refused, free")
	check.call(_add(u, 999999, 4) == RoomsScript.NOTHING_THERE, "an unknown shaft is refused")
	check.call(_add(u, uid, 4) == RoomsScript.OK and funds - u.ledger.balance == CatalogueScript.cost("local_car"), "a car is charged the catalogue price")
	check.call(u.rooms.cars_of(uid) == [[uid, 4, 4, 0, 0, 0, 0, 0, 0]] and u.rooms.car_capacity() == 17, "a car starts at home, empty; capacity is 17")
	TestShafts._shaft(u, 3, 8, 110, "express_shaft")
	check.call(_add(u, _shaft_id(u, 3, 110), 4) == RoomsScript.NO_CARS_HERE, "express shafts take no cars")

	# Remove: newest car, no refund.
	_add(u, uid, 6)
	funds = u.ledger.balance
	check.call(TestRooms._send(u, Command.REMOVE_CAR, [uid] as Array[int]) == RoomsScript.OK and u.rooms.cars_of(uid) == [[uid, 4, 4, 0, 0, 0, 0, 0, 0]] and u.ledger.balance == funds, "remove takes the newest car, no refund")

	# Shrink dropping the home floor is refused; one keeping it is fine.
	check.call(TestRooms._send(u, Command.RESIZE_SHAFT, [uid, 5, 8] as Array[int]) == RoomsScript.HOME_DROPPED, "a shrink dropping a home floor is refused")
	check.call(u.rooms.cars_of(uid) == [[uid, 4, 4, 0, 0, 0, 0, 0, 0]] and u.rooms.link_at(4, 100) != 0, "a refused shrink changes nothing")
	check.call(TestRooms._send(u, Command.RESIZE_SHAFT, [uid, 4, 8] as Array[int]) == RoomsScript.OK, "a shrink keeping the home floor is accepted")

	# Shaft id stays stable even when the occupant ids must move.
	var v := TestShafts._tall()
	TestShafts._shaft(v, 1, 3, 100)
	TestShafts._shaft(v, 1, 3, 110)
	var vid := _shaft_id(v, 1, 100)
	_add(v, vid, 2)
	check.call(TestRooms._send(v, Command.RESIZE_SHAFT, [vid, 1, 10] as Array[int]) == RoomsScript.OK, "growing past the next shaft's ids is accepted")
	check.call(_shaft_id(v, 10, 100) == vid and _shaft_id(v, 1, 100) == vid and v.rooms.car_count(vid) == 1 and v.rooms.cars_of(vid)[0][1] == 2, "the shaft id and its car survive a resize that moves the cells")
	check.call(v.rooms.is_stop(vid, 7), "stops use the same id")

	# Save round trip.
	var w := Harness.clone_via_save(t)
	check.call(w != null and w.state_hash() == t.state_hash() and w.rooms.car_count(id) == 8 and w.rooms.cars_of(id) == t.rooms.cars_of(id), "cars save and load exactly")
	var x := Harness.clone_via_save(v)
	check.call(x != null and x.state_hash() == v.state_hash(), "a moved shaft saves and loads")

	# Bulldoze removes the cars.
	check.call(TestRooms._send(v, Command.BULLDOZE, [4, 100] as Array[int]) == RoomsScript.OK and v.rooms.car_count(vid) == 0, "bulldozing a shaft removes its cars")

	# Determinism.
	var local := CatalogueScript.IDS.find("local_shaft")
	var script: Array[Command] = [
		Command.make(1, Command.BUILD_LOBBY, [1, 100, 131, 1] as Array[int]),
		Command.make(2, Command.BUILD_FLOOR, [2, 100, 131] as Array[int]),
		Command.make(3, Command.PLACE_SHAFT, [local, 1, 2, 100] as Array[int]),
		Command.make(4, Command.ADD_CAR, [1000, 2] as Array[int]),
		Command.make(5, Command.ADD_CAR, [1000, 1] as Array[int]),
		Command.make(6, Command.REMOVE_CAR, [1000] as Array[int]),
	]
	check.call(Harness.is_deterministic(7, script, 20), "the same seed and car commands give the same hashes")
