extends RefCounted
## Route preference (4.8, #96): escalator, then a waiting car, then stairs; waiting builds stress.

const TowerSim := preload("res://scripts/sim/tower.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")
const TripsScript := preload("res://scripts/sim/trips.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const TestElevatorRoutes := preload("res://tests/test_elevator_routes.gd")


## Floors 3 and 4 with stairs at 100, a local shaft (floors 3 to 4, one car at home) at 104 and,
## when with_escalator, an escalator at 108. Trips start and end at column 108 so each is near.
static func _options(with_escalator: bool, car_home: int) -> TowerSim:
	var t := TestElevatorRoutes._plain(6)
	t.stars = 3
	t.rooms.place_stairs(t.grid, t.floors, t.ledger, 0, 3, 100)
	var shaft := TestElevatorRoutes._shaft(t, 3, 4, 104)
	t.rooms.add_car(t.ledger, 0, 3, shaft, car_home)
	if with_escalator:
		t.rooms.place_escalator(t.grid, t.floors, t.ledger, 0, 3, 108)
	return t


static func _first_kind(t: TowerSim) -> int:
	var r := RoutesScript.find(t.floors, t.rooms, t.grid, 3, 108, 4, 108)
	if r["reason"] != RoutesScript.OK:
		return -1
	for leg: Dictionary in r["legs"]:
		if leg["kind"] != RoutesScript.WALK:
			return leg["kind"]
	return -1


static func run(check: Callable) -> void:
	var t := _options(true, 3)
	check.call(_first_kind(t) == RoutesScript.ESCALATOR, "with an escalator, a waiting car and stairs, the escalator is chosen")
	t = _options(false, 3)
	check.call(_first_kind(t) == RoutesScript.ELEVATOR, "with no escalator, a car waiting beats the stairs")
	t = _options(false, 4)
	check.call(t.rooms.car_waiting_at(t.rooms._shaft_base(t.rooms.link_at(3, 104)), 3) == false, "a car idle at another floor is not waiting")
	check.call(_first_kind(t) == RoutesScript.STAIRS, "with no car waiting, the stairs are chosen")

	# What counts as waiting: idle at the floor, or heading there with room; a full one does not.
	t = _options(false, 3)
	var shaft: int = t.rooms._shaft_base(t.rooms.link_at(3, 104))
	check.call(t.rooms.car_waiting_at(shaft, 3), "a car idle at the floor is waiting")
	t = _options(false, 4)
	shaft = t.rooms._shaft_base(t.rooms.link_at(3, 104))
	t.rooms.send_car(0, 3)
	check.call(t.rooms.car_waiting_at(shaft, 3), "a car heading to the floor with room is waiting")
	check.call(_first_kind(t) == RoutesScript.ELEVATOR, "a car heading to the floor is preferred over the stairs")
	t.rooms._cars[0][CarsScript.LOAD] = t.rooms.car_capacity()
	check.call(not t.rooms.car_waiting_at(shaft, 3), "a full car heading to the floor is not waiting")
	check.call(_first_kind(t) == RoutesScript.STAIRS, "with only a full car coming, the stairs are chosen")

	# Escalators carry seven to a trip, stairs four.
	var e := TestElevatorRoutes._plain(12)
	for f in range(3, 11):
		e.rooms.place_escalator(e.grid, e.floors, e.ledger, 0, f, 100 if f % 2 == 1 else 108)
	var r := RoutesScript.find(e.floors, e.rooms, e.grid, 3, 100, 10, 100)
	check.call(r["reason"] == RoutesScript.OK, "seven escalator segments in a trip are allowed")
	r = RoutesScript.find(e.floors, e.rooms, e.grid, 3, 100, 11, 108)
	check.call(r["reason"] == RoutesScript.TOO_MANY_STAIRS, "eight escalator segments in a trip are refused")

	# Waiting for a car builds stress at the stairs rate.
	check.call(TripsScript.STRESS_PER_QUEUE_MINUTE == TripsScript.STRESS_PER_TRAVEL_MINUTE, "the queue stress rate is the stairs rate")
	var w := TestElevatorRoutes._office_tower(7)
	var who := -1
	for _n in 3000:
		w.step()
		var ids := w.rooms.queued_ids()
		if not ids.is_empty():
			who = w.people.index_of(ids[0])
			break
	check.call(who != -1, "a worker queues for a car")
	if who == -1:
		return
	# Take the car away so the person stays queued, then read the stress gain minute by minute.
	var id := w.people.id_at(who)
	w.rooms.remove_car(w.rooms.shaft_ids()[0])
	var deltas: Array[int] = []
	var minute: int = w.clock.minute_of_day()
	var last := w.people.stress_of(who)
	for _n in 60:
		w.step()
		if w.clock.minute_of_day() != minute:
			minute = w.clock.minute_of_day()
			if not w.rooms.queued_ids().has(id):
				break
			var now := w.people.stress_of(who)
			deltas.append(now - last)
			last = now
	check.call(deltas.size() >= 3 and deltas[0] == TripsScript.STRESS_PER_QUEUE_MINUTE and deltas[1] == deltas[0] and deltas[2] == deltas[0], "a queued person gains the queue rate each minute")
