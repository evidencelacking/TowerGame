extends RefCounted
## Elevator routes and trips (4.7): rides beat long stairs, one transfer at a lobby floor, stairs
## limit resets, people ride to work, save mid-ride, bulldozing a shaft mid-ride, determinism.

const TowerSim := preload("res://scripts/sim/tower.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const Harness := preload("res://tests/harness.gd")
const TestRoutes := preload("res://tests/test_routes.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")
const TestCars := preload("res://tests/test_cars.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")


static func _shaft(t: TowerSim, bottom: int, top: int, x: int) -> int:
	t.rooms.place_shaft(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find("local_shaft"), bottom, top, x)
	return t.rooms._shaft_base(t.rooms.link_at(bottom, x))


## Lobby on floors 1 and 2 (columns 100-131), floors 3 to top built, no stairs.
static func _plain(top: int, lobby: bool = true) -> TowerSim:
	var t := TowerSim.new(1, 100000000)
	if lobby:
		t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	else:
		t.floors.fill_span(1, 100, 131)
		t.floors.fill_span(2, 100, 131)
	for f in range(3, top + 1):
		t.floors.fill_span(f, 100, 131)
	return t


static func _kinds(route: Dictionary) -> Array[int]:
	var kinds: Array[int] = []
	for leg: Dictionary in route["legs"]:
		kinds.append(leg["kind"])
	return kinds


## An office on floor 11 reachable only by a local shaft (floors 1 to 11) with a car at home.
static func _office_tower(seed_value: int) -> TowerSim:
	var t := _plain(11)
	t.stars = 3
	var shaft := _shaft(t, 1, 11, 100)
	t.rooms.add_car(t.ledger, 0, 3, shaft, 1)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find("office"), 11, 110)
	t.rng.state = seed_value
	t.clock.set_to_tick(TestOfficeDay._tick_at(PeopleScript.ARRIVE - 5, 0))
	return t


## Steps until some person is riding a car (up to max_ticks); returns that person's index or -1.
static func _until_riding(t: TowerSim, max_ticks: int) -> int:
	for _n in max_ticks:
		t.step()
		for i in t.people.count():
			if t.people.trip_state(i) == PeopleScript.TRIP_RIDING and t.rooms.car_floor_of(t.people.id_at(i)) != 0:
				return i
	return -1


static func run(check: Callable) -> void:
	# An office 10 floors up, reachable only by elevator: workers ride there and arrive.
	var t := _office_tower(7)
	var office: int = t.rooms.room_ids()[-1]
	var rode := _until_riding(t, 3000)
	check.call(rode != -1, "a worker rides the elevator to the office")
	var arrived := 0
	for _n in 1500:
		t.step()
		arrived = 0
		for i in t.people.count():
			if t.people.location_of(i) == office and t.people.trip_state(i) == PeopleScript.TRIP_IDLE:
				arrived += 1
		if arrived == 6:
			break
	check.call(t.people.count() == 6 and arrived == 6, "all six workers arrive at the office by elevator")

	# A ride beats 8 floors of stairs, and stairs win for one floor.
	var s := TestRoutes._chain(9)
	_shaft(s, 1, 9, 120)
	var r := RoutesScript.find(s.floors, s.rooms, s.grid, 1, 100, 9, 100)
	check.call(r["reason"] == RoutesScript.OK and _kinds(r).has(RoutesScript.ELEVATOR) and not _kinds(r).has(RoutesScript.STAIRS), "the route rides instead of 8 flights of stairs")
	r = RoutesScript.find(s.floors, s.rooms, s.grid, 1, 100, 2, 100)
	check.call(r["reason"] == RoutesScript.OK and _kinds(r).size() == 1 and _kinds(r)[0] == RoutesScript.STAIRS, "one floor goes by stairs")

	# Transfers: one at a lobby floor is fine, two are refused, a non-lobby one is refused.
	var x := _plain(12)
	var a := _shaft(x, 1, 5, 100)
	for f in [2, 3, 4]:
		x.rooms.set_shaft_stop(a, f, false)
	var xb := _shaft(x, 1, 8, 110)
	for f in [3, 4, 5]:
		x.rooms.set_shaft_stop(xb, f, false)
	r = RoutesScript.find(x.floors, x.rooms, x.grid, 5, 100, 8, 110)
	var rides := _kinds(r).count(RoutesScript.ELEVATOR)
	check.call(r["reason"] == RoutesScript.OK and rides == 2, "one transfer at the lobby is allowed")
	var y := _plain(12)
	var ya := _shaft(y, 1, 5, 100)
	for f in [2, 3, 4]:
		y.rooms.set_shaft_stop(ya, f, false)
	_shaft(y, 1, 2, 110)
	var yc := _shaft(y, 2, 8, 120)
	for f in [3, 4, 5]:
		y.rooms.set_shaft_stop(yc, f, false)
	r = RoutesScript.find(y.floors, y.rooms, y.grid, 5, 100, 8, 120)
	check.call(r["reason"] == RoutesScript.TOO_MANY_TRANSFERS, "a trip needing two transfers is refused")
	check.call(r["legs"].is_empty(), "a refused trip has no legs")
	var z := _plain(12)
	_shaft(z, 1, 6, 100)
	_shaft(z, 6, 12, 110)
	r = RoutesScript.find(z.floors, z.rooms, z.grid, 1, 100, 12, 110)
	check.call(r["reason"] == RoutesScript.TOO_MANY_TRANSFERS, "a transfer at a non-lobby floor is not used")

	# The stairs count resets: 4 flights down, a ride to the lobby, 4 flights up elsewhere.
	for lobby in [true, false]:
		var w := TowerSim.new(1, 100000000)
		if lobby:
			w.floors.build_lobby(w.ledger, 0, 1, 100, 131, 2)
		else:
			w.floors.fill_span(1, 100, 131)
			w.floors.fill_span(2, 100, 131)
		for f in range(3, 8):  # two wings above the lobby, a gap between them
			w.floors.fill_span(f, 100, 115)
			if f <= 5:
				w.floors.fill_span(f, 120, 131)
		for f in range(3, 7):
			w.rooms.place_stairs(w.grid, w.floors, w.ledger, 0, f, 100 if f % 2 == 1 else 104)
		for f in range(1, 5):
			w.rooms.place_stairs(w.grid, w.floors, w.ledger, 0, f, 120 if f % 2 == 1 else 124)
		_shaft(w, 1, 3, 110)
		var wr := RoutesScript.find(w.floors, w.rooms, w.grid, 7, 100, 5, 121)
		if lobby:
			check.call(wr["reason"] == RoutesScript.OK and _kinds(wr).count(RoutesScript.STAIRS) > 4, "the stairs count resets at the lobby (7 flights in two legs)")
		else:
			check.call(wr["reason"] == RoutesScript.TOO_MANY_STAIRS, "without a lobby the same trip is refused")

	# A save mid-ride resumes identically.
	var m := _office_tower(11)
	var rider := _until_riding(m, 3000)
	var copy := Harness.clone_via_save(m)
	check.call(rider != -1 and copy != null and copy.state_hash() == m.state_hash(), "a save taken mid-ride loads to the same state")
	var same := true
	for _n in 600:
		m.step()
		copy.step()
		same = same and m.state_hash() == copy.state_hash()
	check.call(same and m.people.state_ints() == copy.people.state_ints(), "the saved copy keeps riding identically")

	# Bulldozing the shaft mid-ride gives the trip up.
	var b := _office_tower(13)
	var victim := _until_riding(b, 3000)
	var victim_id := b.people.id_at(victim)
	var before := b.people.stress_of(victim)
	check.call(b.rooms.bulldoze(b.grid, b.floors, b.ledger, b.tick, 1, 100) == RoomsScript.OK, "the shaft can be bulldozed under a rider")
	Harness.step(b, 400)
	var v := b.people.index_of(victim_id)
	check.call(b.people.trip_state(v) != PeopleScript.TRIP_RIDING and not b.rooms.in_elevator(victim_id), "the rider's trip ends")
	check.call(b.people.stress_of(v) > before, "they take the no-route stress")

	# Same seed, same day.
	check.call(_day(21) == _day(21), "same seed, same day with elevators")


static func _day(seed_value: int) -> Array[int]:
	var t := _office_tower(seed_value)
	Harness.step(t, 1500)
	return t.people.state_ints()
