extends RefCounted
## Express elevator tests (8.2): stops only at lobbies and basements, 36 per car, up to 8 cars,
## any height, and local shafts capped at 30 floors with a "shaft too tall" refusal.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const TestShafts := preload("res://tests/test_shafts.gd")
const TestCars := preload("res://tests/test_cars.gd")
const TestRooms := preload("res://tests/test_rooms.gd")


## Floors 1 to 100 and B1 to B10 over columns 100 to 131, ground lobby on floor 1, sky lobbies on
## 15 and 90, an express shaft from B3 to 100 at x 110.
static func _setup() -> TowerSim:
	var t := TestShafts._tall()
	for f in range(41, 101):
		t.floors.fill_span(f, 100, 131)
	t.stars = 3
	t.floors.build_lobby(t.ledger, 0, 15, 100, 131, 1, t.grid)
	t.floors.build_lobby(t.ledger, 0, 90, 100, 131, 1, t.grid)
	TestShafts._shaft(t, -3, 100, 110, "express_shaft")
	return t


static func run(check: Callable) -> void:
	var cat_ok: bool = CatalogueScript.cost("express_shaft") == 400000 and CatalogueScript.cost("express_car") == 150000 and CatalogueScript.star("express_shaft") == 3 and CatalogueScript.star("express_car") == 3
	check.call(cat_ok, "express prices ($400,000 shaft, $150,000 car) and 3-star unlock")

	var t := _setup()
	var id := TestCars._shaft_id(t, -3, 110)
	check.call(id != 0, "a 103-floor express span is accepted (any height)")
	# Stops: basements B3 to B1, the ground lobby (floor 1) and the two sky lobbies; nothing else.
	var stops := t.rooms.stops_of(id)
	check.call(stops == ([-3, -2, -1, 1, 15, 90] as Array[int]), "an express stops only at lobbies and every basement: %s" % [stops])
	check.call(not t.rooms.is_stop(id, 20) and not t.rooms.is_stop(id, 2) and not t.rooms.is_stop(id, 100), "an express cannot stop at an ordinary floor")
	check.call(TestRooms._send(t, Command.SET_SHAFT_STOP, [id, 20, 1] as Array[int]) == RoomsScript.EXPRESS_NO_STOP and not t.rooms.is_stop(id, 20), "switching an ordinary floor on is refused")
	check.call(t.rooms.place_call(id, 20, CarsScript.UP) == RoomsScript.NOT_A_STOP, "a call from an ordinary floor is refused")
	var before_lobby := t.rooms.stops_of(id).size()
	t.floors.build_lobby(t.ledger, 0, 45, 100, 131, 1, t.grid)
	check.call(t.rooms.stops_of(id).size() == before_lobby + 1 and t.rooms.is_stop(id, 45), "a new sky lobby on the shaft becomes a stop")

	# Cars: 36 per car, 8 per shaft, price.
	var funds := t.ledger.balance
	check.call(TestCars._add(t, id, 1) == RoomsScript.OK and funds - t.ledger.balance == 150000, "an express car costs $150,000")
	check.call(TestCars._add(t, id, 20) == RoomsScript.BAD_HOME_FLOOR, "an express car cannot be homed at an ordinary floor")
	check.call(t.rooms.car_capacity(id) == 36 and t.rooms.car_capacity() == 17, "an express car holds 36, a local one 17")
	t.stars = 5
	for _n in 7:
		TestCars._add(t, id, 1)
	check.call(t.rooms.car_count(id) == 8 and TestCars._add(t, id, 1) == RoomsScript.MAX_CARS, "an express shaft takes up to 8 cars")
	# Only one car is needed for the boarding test: a fresh tower.
	var u := _setup()
	u.stars = 3
	var uid := TestCars._shaft_id(u, -3, 110)
	TestCars._add(u, uid, 1)
	for _i in 37:
		u.people.add_person(-1, -1, u.rng)
	for pid in 37:
		u.rooms.join_queue(pid, uid, 1, 90)
	for _i in 60:
		if u.rooms.riders_of(0).size() > 0:
			break
		u.step()
	check.call(u.rooms.riders_of(0).size() == 36, "the 36th rider boards the express car")
	check.call(u.rooms.queue_at(uid, 1).size() == 1 and u.rooms.queue_at(uid, 1)[0] == 36, "the 37th waits")

	# Local shafts are capped at 30 floors.
	var l := TestShafts._tall()
	check.call(TestShafts._shaft(l, 1, 31, 100) == RoomsScript.MAX_SHAFT_FLOORS, "a 31-floor local shaft is refused with 'shaft too tall'")
	check.call(TestShafts._shaft(l, 1, 30, 100) == RoomsScript.OK, "a 30-floor local shaft is accepted")
