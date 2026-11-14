extends RefCounted
## Car speed tests (#103): a full-height ride takes about 4 sim minutes (10 ticks), express cars
## are faster than local ones, and stops cost a little time each. All tick counts are exact.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const Harness := preload("res://tests/harness.gd")
const TestShafts := preload("res://tests/test_shafts.gd")
const TestCars := preload("res://tests/test_cars.gd")

const TARGET_TICKS := 10  ## 4 sim minutes at 2.5 ticks per sim minute.


## A tower built to floor 100 with a local shaft on floors 1 to 30 (x 100) and an express shaft
## on floors 1 to 100 (x 110).
static func _setup() -> TowerSim:
	var t := TestShafts._tall()
	for f in range(41, 101):
		t.floors.fill_span(f, 100, 131)
	t.stars = 3
	TestShafts._shaft(t, 1, 30, 100)
	TestShafts._shaft(t, 1, 100, 110, "express_shaft")
	return t


## Puts a car at floor 1 in the shaft at x. Express shafts take no cars by command yet, so the
## car is placed straight into the lists.
static func _car_in(t: TowerSim, x: int) -> int:
	var id := TestCars._shaft_id(t, 1, x)
	t.rooms._cars.append([id, 1, 1, 0, 0, 0, 0, 0, 0])
	t.rooms._riders.append([])
	t.rooms._stops.append([])
	t.rooms._heading.append(0)
	return t.rooms._cars.size() - 1


## True once car n is at a floor with its doors open (a whole stop can fit inside one tick).
static func _doors_opened_at(t: TowerSim, n: int, floor_number: int) -> bool:
	var car: Array = t.rooms._cars[n]
	return car[CarsScript.FLOOR] == floor_number and car[CarsScript.STATE] != CarsScript.MOVING and car[CarsScript.STATE] != CarsScript.DOORS_OPENING


## Sends car n to a floor and steps until its doors have opened there; returns the ticks, or -1.
static func _ride(t: TowerSim, n: int, floor_number: int) -> int:
	t.rooms.send_car(n, floor_number)
	for ticks in range(1, 41):
		t.step()
		if _doors_opened_at(t, n, floor_number):
			return ticks
	return -1


static func run(check: Callable) -> void:
	var local_units := CarsScript.LOCAL_UNITS_PER_FLOOR
	var express_units := CarsScript.EXPRESS_UNITS_PER_FLOOR
	check.call(express_units * 3 <= local_units * 2, "express is at least 1.5 times as fast as local")
	check.call(CarsScript.units_per_floor("express_shaft") == express_units and CarsScript.units_per_floor("local_shaft") == local_units and CarsScript.units_per_floor("service_shaft") == local_units, "speed depends on the shaft kind")
	var stop_units := CarsScript.DOOR_OPEN_UNITS + CarsScript.DOOR_HOLD_UNITS + CarsScript.DOOR_CLOSE_UNITS
	check.call(stop_units > 0 and stop_units <= CarsScript.TICK_UNITS, "a stop costs something, at most 1 tick")

	# 30-floor local ride (floor 1 to 30): 29 floors = 261 units, doors open at 281, so tick 3.
	var t := _setup()
	var local := _car_in(t, 100)
	var express := _car_in(t, 110)
	var local_30 := _ride(t, local, 30)
	check.call(local_30 == 3 and local_30 <= TARGET_TICKS, "a 30-floor local ride has its doors open after exactly 3 ticks")

	# 100-floor express ride: 99 floors = 594 units, doors open at 614, so tick 7.
	var express_100 := _ride(t, express, 100)
	check.call(express_100 == 7 and express_100 <= TARGET_TICKS, "a 100-floor express ride has its doors open after exactly 7 ticks")

	# A local car at the same speed over 100 floors: 99 floors = 891 units, doors at 911, tick 10.
	check.call((99 * local_units + CarsScript.DOOR_OPEN_UNITS + CarsScript.TICK_UNITS - 1) / CarsScript.TICK_UNITS == TARGET_TICKS, "a local car would cover 100 floors in exactly 10 ticks")

	# The same 30-floor ride on an express car beats the local car.
	var u := _setup()
	var slow := _car_in(u, 100)
	var fast := _car_in(u, 110)
	var slow_ticks := _ride(u, slow, 30)
	var fast_ticks := _ride(u, fast, 30)
	check.call(fast_ticks == 2 and fast_ticks < slow_ticks, "an express car beats a local car on the same 30-floor ride")

	# A local ride with intermediate stops is slower than the nonstop ride, and still within bounds.
	var v := _setup()
	var stopper := _car_in(v, 100)
	for floor_number in [8, 14, 20, 26]:
		v.rooms.add_car_stop(stopper, floor_number)
	v.rooms._heading[stopper] = CarsScript.UP
	v.rooms.send_car(stopper, 8)
	var ticks_taken := -1
	for ticks in range(1, 7):
		v.step()
		if ticks_taken == -1 and _doors_opened_at(v, stopper, 26):
			ticks_taken = ticks
	check.call(v.rooms._stops[stopper].is_empty() and v.rooms._cars[stopper][CarsScript.FLOOR] == 26, "the car calls at each pending floor in turn, ending at 26")
	check.call(ticks_taken == 5, "a local ride stopping 4 times on the way to floor 26 takes exactly 5 ticks")
	var nonstop := _setup()
	var direct := _car_in(nonstop, 100)
	var direct_ticks := _ride(nonstop, direct, 26)
	check.call(direct_ticks == 3 and ticks_taken > direct_ticks, "the same ride nonstop to floor 26 takes 3 ticks, so the stops cost time")
	check.call(Harness.hash_trace(_setup(), 20) == Harness.hash_trace(_setup(), 20), "the speed setup is deterministic")
