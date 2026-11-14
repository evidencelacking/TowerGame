extends RefCounted
## Idle cars return home (#109): after IDLE_DWELL with no calls, stops or riders a car heads to its
## home floor. A returning car counts as moving, not waiting, and dispatch can still take it.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const Harness := preload("res://tests/harness.gd")
const TestShafts := preload("res://tests/test_shafts.gd")
const TestCars := preload("res://tests/test_cars.gd")

const UP := CarsScript.UP


## A local shaft on floors 1 to 30 with one car whose home is floor 1.
static func _setup() -> TowerSim:
	var t := TestShafts._tall()
	TestShafts._shaft(t, 1, 30, 100)
	t.stars = 3
	TestCars._add(t, TestCars._shaft_id(t, 1, 100), 1)
	return t


static func _id(t: TowerSim) -> int:
	return TestCars._shaft_id(t, 1, 100)


static func _car(t: TowerSim) -> Array:
	return t.rooms._cars[0]


## Sends car 0 to floor 5 and steps until it parks there; returns the ticks stepped.
static func _park_at_five(t: TowerSim) -> int:
	t.rooms.send_car(0, 5)
	for n in range(1, 21):
		t.step()
		if _car(t)[CarsScript.STATE] == CarsScript.IDLE:
			return n
	return -1


## Steps until car 0 has parked after its current trip.
static func _until_idle(t: TowerSim) -> void:
	for n in 30:
		t.step()
		if _car(t)[CarsScript.STATE] == CarsScript.IDLE:
			return


## Steps until car 0 is moving or the limit passes; returns the ticks stepped, or -1.
static func _until_moving(t: TowerSim, limit: int) -> int:
	for n in range(1, limit + 1):
		t.step()
		if _car(t)[CarsScript.STATE] == CarsScript.MOVING:
			return n
	return -1


static func _positions(seed_value: int) -> Array[int]:
	var t := _setup()
	t.rooms.send_car(0, 5)
	var trace: Array[int] = []
	for n in 40:
		if n == 12:
			t.rooms.place_call(_id(t), 3, UP)
		t.step()
		trace.append(_car(t)[CarsScript.FLOOR] * 100 + _car(t)[CarsScript.STATE])
	return trace


static func run(check: Callable) -> void:
	check.call(CarsScript.IDLE_DWELL > 0 and CarsScript.IDLE_DWELL % CarsScript.TICK_UNITS == 0, "the dwell is a whole number of ticks")
	var dwell_ticks := CarsScript.IDLE_DWELL / CarsScript.TICK_UNITS

	# An idle car returns home after exactly the dwell, and a returning car is moving, not waiting.
	var t := _setup()
	check.call(_park_at_five(t) == 2 and _car(t)[CarsScript.FLOOR] == 5, "the car parks at floor 5 after 2 ticks")
	check.call(t.rooms.car_waiting_at(_id(t), 5), "a parked idle car is waiting")
	for n in dwell_ticks - 1:
		t.step()
	check.call(_car(t)[CarsScript.STATE] == CarsScript.IDLE and _car(t)[CarsScript.FLOOR] == 5, "it stays put until the dwell has passed")
	t.step()
	check.call(_car(t)[CarsScript.STATE] == CarsScript.IDLE and _car(t)[CarsScript.FLOOR] == 1, "on the dwell's tick it goes home (4 floors fit in one tick) and parks")
	check.call(t.rooms.car_waiting_at(_id(t), 1), "a car at home is waiting")
	var parked: Array = _car(t).duplicate()
	for n in dwell_ticks * 3:
		t.step()
	check.call(_car(t) == parked, "a car at home stays put")

	# A far car is seen moving, not waiting, on the way home.
	var far := _setup()
	far.rooms.send_car(0, 20)
	_until_idle(far)
	check.call(_car(far)[CarsScript.FLOOR] == 20 and _car(far)[CarsScript.STATE] == CarsScript.IDLE, "the car parks at floor 20")
	var moving_ticks := _until_moving(far, dwell_ticks + 2)
	check.call(moving_ticks > 0 and moving_ticks <= dwell_ticks, "it starts home within the dwell of parking")
	check.call(_car(far)[CarsScript.TARGET] == 1 and not far.rooms.car_waiting_at(_id(far), 1), "a car heading home is moving, not waiting at its home floor")
	check.call(CarsScript.going_home(far.rooms, 0), "it is recognised as going home")

	# A call during the dwell postpones the return.
	var p := _setup()
	_park_at_five(p)
	for n in dwell_ticks - 2:
		p.step()
	p.rooms.place_call(_id(p), 5, UP)
	p.step()
	check.call(_car(p)[CarsScript.FLOOR] == 5 and p.rooms.calls().is_empty() and _car(p)[CarsScript.STATE] == CarsScript.IDLE, "a call at the car's floor is served at once, and the car idles again")
	for n in dwell_ticks - 1:
		p.step()
	check.call(_car(p)[CarsScript.FLOOR] == 5, "the dwell restarts: it has not gone home before a full dwell after the call")
	p.step()
	check.call(_car(p)[CarsScript.FLOOR] == 1, "and it goes home one dwell after the call was served")

	# A call mid-return is served by normal dispatch, from where the car is.
	var m := _setup()
	m.rooms.send_car(0, 25)
	_until_idle(m)
	_until_moving(m, dwell_ticks + 2)
	var at: int = _car(m)[CarsScript.FLOOR]
	check.call(at < 25 and at > 1 and _car(m)[CarsScript.DIR] == -1, "the car is part-way home")
	m.rooms.place_call(_id(m), 10, CarsScript.DOWN)
	m.step()
	check.call(m.rooms.calls().is_empty() and _car(m)[CarsScript.FLOOR] == 10, "the returning car served the call at floor 10 from where it was, not from home")
	var up := _setup()
	up.rooms.send_car(0, 25)
	_until_idle(up)
	_until_moving(up, dwell_ticks + 2)
	up.rooms.place_call(_id(up), 28, UP)
	up.step()
	check.call(up.rooms.calls()[0][CarsScript.CALL_CAR] == 0 and _car(up)[CarsScript.TARGET] == 28 and _car(up)[CarsScript.DIR] == 1, "a call behind a returning car turns it round")

	# A loaded car never heads home.
	var l := _setup()
	_park_at_five(l)
	_car(l)[CarsScript.LOAD] = 1
	l.rooms._riders[0].append([1, 5])
	for n in dwell_ticks * 3:
		l.step()
	check.call(_car(l)[CarsScript.FLOOR] == 5 and _car(l)[CarsScript.STATE] == CarsScript.IDLE, "a car with a rider never heads home")

	# Same commands, same tick-by-tick positions.
	check.call(_positions(7) == _positions(7), "the same commands give the same positions every tick")
	var trace := _positions(7)
	check.call(trace[5] == 500 and trace[6] == 100 and trace[12] == 300 and trace[17] == 100, "the trace has the car at 5 until tick 6, home on tick 7, at 3 for the call, home again")
