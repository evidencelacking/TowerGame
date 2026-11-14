extends RefCounted
## Car motion tests (4.4): travel, stops and doors in integer ticks.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const Harness := preload("res://tests/harness.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestShafts := preload("res://tests/test_shafts.gd")
const TestCars := preload("res://tests/test_cars.gd")


## A tower with a local shaft on floors 1 to 30 and one car at home on floor 1.
static func _setup() -> TowerSim:
	var t := TestShafts._tall()
	TestShafts._shaft(t, 1, 30, 100)
	TestCars._add(t, TestCars._shaft_id(t, 1, 100), 1)
	return t


static func _car(t: TowerSim) -> Array:
	return t.rooms._cars[0]


## Steps until the car's state is `state`; returns the ticks stepped, or -1 after 200.
static func _until(t: TowerSim, state: int) -> int:
	for n in range(1, 201):
		t.step()
		if _car(t)[CarsScript.STATE] == state:
			return n
	return -1


static func run(check: Callable) -> void:
	var upf := CarsScript.LOCAL_UNITS_PER_FLOOR
	var t := _setup()
	var id := TestCars._shaft_id(t, 1, 100)
	check.call(t.rooms.send_car(0, 6) == RoomsScript.OK and _car(t)[CarsScript.STATE] == CarsScript.MOVING and _car(t)[CarsScript.TICKS] == upf, "a car sent up starts moving, one floor's units to go")
	# Tick 1 holds 100 units: 5 floors (45), doors opening (20), hold (30), 5 of the 20 closing.
	t.step()
	check.call(_car(t)[CarsScript.FLOOR] == 6 and _car(t)[CarsScript.STATE] == CarsScript.DOORS_CLOSING and _car(t)[CarsScript.TICKS] == 15, "a 5-floor ride and its whole door cycle nearly fit in the first tick")
	t.step()
	check.call(_car(t)[CarsScript.STATE] == CarsScript.IDLE and _car(t)[CarsScript.FLOOR] == 6, "the doors close in the second tick, then the car is idle where it stopped")
	var idle := _car(t).duplicate()
	Harness.step(t, 20)
	check.call(_car(t) == idle, "an idle car with no target stays put")

	# Moving down, and the send refusals.
	check.call(t.rooms.send_car(0, 2) == RoomsScript.OK and _until(t, CarsScript.IDLE) == 2 and _car(t)[CarsScript.FLOOR] == 2, "a 4-floor ride (36 units plus 70 for the doors) is idle after exactly 2 ticks")
	check.call(t.rooms.send_car(0, 5) == RoomsScript.OK and t.rooms.send_car(0, 7) == RoomsScript.NO_SUCH_CAR and t.rooms.send_car(3, 5) == RoomsScript.NO_SUCH_CAR, "a busy car and an unknown car are refused")
	_until(t, CarsScript.IDLE)
	check.call(t.rooms.send_car(0, 31) == RoomsScript.NOT_A_STOP, "a floor outside the shaft is refused")

	# Own floor cycles the doors.
	check.call(t.rooms.send_car(0, _car(t)[CarsScript.FLOOR]) == RoomsScript.OK and _car(t)[CarsScript.STATE] == CarsScript.DOORS_OPENING, "a car can be sent to its own floor, and its doors start opening")
	t.step()
	check.call(_car(t)[CarsScript.STATE] == CarsScript.IDLE and _car(t)[CarsScript.FLOOR] == 5, "the whole door cycle (70 units) fits in one tick, then the car is idle")

	# A disabled floor is passed without stopping.
	var u := _setup()
	var uid := TestCars._shaft_id(u, 1, 100)
	TestRooms._send(u, Command.SET_SHAFT_STOP, [uid, 4, 0] as Array[int])
	check.call(u.rooms.send_car(0, 4) == RoomsScript.NOT_A_STOP, "a disabled floor cannot be a target")
	u.rooms.send_car(0, 7)
	var seen_doors_at: Array[int] = []
	for n in 12:
		u.step()
		if _car(u)[CarsScript.STATE] >= CarsScript.DOORS_OPENING:
			seen_doors_at.append(_car(u)[CarsScript.FLOOR])
	check.call(seen_doors_at.size() > 0 and seen_doors_at.count(7) == seen_doors_at.size(), "a car passes a disabled floor and opens its doors only at the target")

	# Home floor stays a stop.
	var funds := u.ledger.balance
	check.call(TestRooms._send(u, Command.SET_SHAFT_STOP, [uid, 1, 0] as Array[int]) == RoomsScript.HOME_STOP and u.rooms.is_stop(uid, 1) and u.ledger.balance == funds, "turning off a car's home-floor stop is refused")

	# Save mid-motion, continue identically.
	var v := _setup()
	v.rooms.send_car(0, 30)
	Harness.step(v, 1)
	var w := Harness.clone_via_save(v)
	check.call(w != null and w.state_hash() == v.state_hash() and _car(w) == _car(v) and _car(w)[CarsScript.STATE] == CarsScript.MOVING, "a save mid-motion loads the same")
	Harness.step(v, 12)
	Harness.step(w, 12)
	check.call(w.state_hash() == v.state_hash() and _car(w) == _car(v), "the loaded tower continues identically")

	# Same seed.
	var a := _setup()
	var b := _setup()
	a.rooms.send_car(0, 8)
	b.rooms.send_car(0, 8)
	check.call(Harness.hash_trace(a, 30) == Harness.hash_trace(b, 30), "the same seed and send give the same hashes")
