extends RefCounted
## Hall call and dispatch tests (4.5): calls carry a floor and direction; the nearest idle car,
## or one moving the same way ahead of the floor, takes the oldest call.

const TowerSim := preload("res://scripts/sim/tower.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const Harness := preload("res://tests/harness.gd")
const TestShafts := preload("res://tests/test_shafts.gd")
const TestCars := preload("res://tests/test_cars.gd")

const UP := CarsScript.UP
const DOWN := CarsScript.DOWN


## A tower with a local shaft on floors 1 to 10 and one car at each home floor.
static func _setup(homes: Array[int]) -> TowerSim:
	var t := TestShafts._tall()
	TestShafts._shaft(t, 1, 10, 100)
	t.stars = 3
	for home: int in homes:
		TestCars._add(t, TestCars._shaft_id(t, 1, 100), home)
	return t


static func _id(t: TowerSim) -> int:
	return TestCars._shaft_id(t, 1, 100)


## Steps until no pending call is at floor_number; returns the ticks stepped, or -1 after 200.
static func _until_cleared(t: TowerSim, floor_number: int) -> int:
	for n in range(1, 201):
		t.step()
		var pending := false
		for call: Array in t.rooms.calls():
			pending = pending or call[CarsScript.CALL_FLOOR] == floor_number
		if not pending:
			return n
	return -1


static func _assigned(t: TowerSim, index: int) -> int:
	return t.rooms.calls()[index][CarsScript.CALL_CAR]


static func _scenario() -> TowerSim:
	var t := _setup([1, 10] as Array[int])
	t.rooms.place_call(_id(t), 5, UP)
	t.rooms.place_call(_id(t), 4, DOWN)
	Harness.step(t, 3)
	return t


static func run(check: Callable) -> void:
	# Two calls on one car are served in the order made, at exact ticks.
	var t := _setup([1] as Array[int])
	var id := _id(t)
	check.call(t.rooms.place_call(id, 5, UP) == RoomsScript.OK and t.rooms.place_call(id, 3, DOWN) == RoomsScript.OK, "two calls are accepted")
	check.call(t.rooms.calls().size() == 2 and t.rooms.calls()[0][CarsScript.CALL_FLOOR] == 5, "calls are kept in arrival order")
	check.call(_until_cleared(t, 5) == 6, "the first call clears when the doors open, 6 ticks later")
	check.call(t.rooms.calls().size() == 1 and _until_cleared(t, 3) == 10, "the second call is served after the first, 10 ticks later")

	# The nearest idle car wins; a tie goes to the lower index.
	var n := _setup([2, 6] as Array[int])
	n.rooms.place_call(_id(n), 5, UP)
	n.step()
	check.call(_assigned(n, 0) == 1, "the nearest idle car takes the call")
	var tie := _setup([2, 6] as Array[int])
	tie.rooms.place_call(_id(tie), 4, DOWN)
	tie.step()
	check.call(_assigned(tie, 0) == 0, "a tie between cars goes to the lower index")

	# A moving car takes a call on its path in its direction, and ignores one the other way.
	var m := _setup([1] as Array[int])
	m.rooms.send_car(0, 8)
	Harness.step(m, 2)
	m.rooms.place_call(_id(m), 5, UP)
	m.step()
	check.call(_assigned(m, 0) == 0 and m.rooms._cars[0][CarsScript.TARGET] == 5 and m.rooms._cars[0][CarsScript.NEXT] == 8, "a car moving up takes an up call ahead of it as a stop")
	check.call(_until_cleared(m, 5) > 0 and m.rooms._cars[0][CarsScript.FLOOR] == 5, "it opens its doors at the call floor")
	var resumed := false
	for i in 40:
		m.step()
		resumed = resumed or (m.rooms._cars[0][CarsScript.FLOOR] == 8 and m.rooms._cars[0][CarsScript.STATE] == CarsScript.DOORS_OPENING)
	check.call(resumed, "it then carries on to its original target")
	var o := _setup([1] as Array[int])
	o.rooms.send_car(0, 8)
	Harness.step(o, 2)
	o.rooms.place_call(_id(o), 5, DOWN)
	Harness.step(o, 2)
	check.call(_assigned(o, 0) == -1 and o.rooms._cars[0][CarsScript.TARGET] == 8, "a car moving up ignores a down call")
	check.call(_until_cleared(o, 5) > 0 and o.rooms._cars[0][CarsScript.FLOOR] == 5, "the down call is served once the car is free")

	# Refusals and merging.
	var r := _setup([1] as Array[int])
	var rid := _id(r)
	check.call(r.rooms.place_call(rid, 10, UP) == RoomsScript.BAD_CALL, "an up call at the top stop is refused")
	check.call(r.rooms.place_call(rid, 1, DOWN) == RoomsScript.BAD_CALL, "a down call at the bottom stop is refused")
	check.call(r.rooms.place_call(rid, 11, UP) == RoomsScript.NOT_A_STOP and r.rooms.place_call(rid, 5, 0) == RoomsScript.BAD_CALL, "a non-stop floor and a bad direction are refused")
	check.call(r.rooms.calls().is_empty(), "refused calls are not kept")
	r.rooms.place_call(rid, 5, UP)
	r.rooms.place_call(rid, 5, UP)
	check.call(r.rooms.calls().size() == 1, "a duplicate call is merged")
	r.rooms.place_call(rid, 5, DOWN)
	check.call(r.rooms.calls().size() == 2, "the same floor the other way is a separate call")

	# Save with pending, assigned calls round-trips and continues identically.
	var v := _scenario()
	var w := Harness.clone_via_save(v)
	check.call(w != null and w.state_hash() == v.state_hash() and w.rooms.calls() == v.rooms.calls() and v.rooms.calls().size() == 2, "a save with pending calls loads the same")
	Harness.step(v, 40)
	Harness.step(w, 40)
	check.call(w.state_hash() == v.state_hash() and v.rooms.calls().is_empty(), "the loaded tower serves the calls identically")

	# Same seed, same result.
	var a := _scenario()
	var b := _scenario()
	Harness.step(a, 30)
	Harness.step(b, 30)
	check.call(a.state_hash() == b.state_hash(), "the same calls give the same state")
