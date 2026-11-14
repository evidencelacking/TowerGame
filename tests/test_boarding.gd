extends RefCounted
## Boarding and unloading tests (4.6): FIFO queues, a 17-person capacity, unloading before
## boarding, full cars passing, wait stress, save round trip and determinism.

const TowerSim := preload("res://scripts/sim/tower.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const Harness := preload("res://tests/harness.gd")
const TestDispatch := preload("res://tests/test_dispatch.gd")

const UP := CarsScript.UP


## A tower (shaft floors 1 to 30) with one car per home floor and count people.
static func _setup(homes: Array[int], count: int) -> TowerSim:
	var t := TestDispatch._setup(homes)
	for _i in count:
		t.people.add_person(-1, -1, t.rng)
	return t


## Queues people first_id up to (not including) end_id at floor from bound for dest.
static func _queue(t: TowerSim, first_id: int, end_id: int, from_floor: int, dest: int) -> void:
	for pid in range(first_id, end_id):
		t.rooms.join_queue(pid, TestDispatch._id(t), from_floor, dest)


## Steps until car 0 holds at least one rider (or 60 ticks).
static func _until_boarded(t: TowerSim) -> void:
	for _i in 60:
		if t.rooms.riders_of(0).size() > 0:
			return
		t.step()


static func _ints(values: Array) -> Array[int]:
	var result: Array[int] = []
	result.append_array(values)
	return result


static func _alighted_ids(t: TowerSim) -> Array[int]:
	var ids: Array[int] = []
	for entry: Array in t.rooms.alighted:
		ids.append(entry[0])
	return ids


static func run(check: Callable) -> void:
	# The 18th person waits, then boards the next pass.
	var t := _setup([1] as Array[int], 18)
	_queue(t, 0, 18, 1, 30)
	check.call(t.rooms.queue_at(TestDispatch._id(t), 1).size() == 18, "eighteen people queue at one floor")
	_until_boarded(t)
	var first: Array[int] = t.rooms.riders_of(0)
	check.call(first.size() == 17 and t.rooms._cars[0][CarsScript.LOAD] == 17, "seventeen board a car")
	check.call(t.rooms.queue_at(TestDispatch._id(t), 1) == _ints([17]), "the 18th waits")
	check.call(first[0] == 0 and first[16] == 16, "people board in arrival order")
	check.call(t.rooms.calls().size() == 1 and t.rooms.calls()[0][CarsScript.CALL_FLOOR] == 1, "the 18th's call stays pending")
	var before: int = t.people.stress_of(t.people.index_of(17))
	Harness.step(t, 10)
	check.call(t.people.stress_of(t.people.index_of(17)) > before, "waiting stress rises for the person left behind")
	for _i in 200:
		if _alighted_ids(t).size() == 18:
			break
		t.step()
	var ids := _alighted_ids(t)
	check.call(ids.size() == 18 and ids[17] == 17 and t.rooms.queue_at(TestDispatch._id(t), 1).is_empty(), "the 18th boards the next pass and arrives")
	check.call(t.rooms.alighted[0][1] == 30, "riders alight at their destination")
	check.call(t.rooms._cars[0][CarsScript.LOAD] == 0, "an emptied car holds nobody")

	# Unloading happens before boarding at the same stop.
	var u := _setup([1] as Array[int], 18)
	_queue(u, 0, 17, 1, 20)
	u.rooms.join_queue(17, TestDispatch._id(u), 20, 28)
	_until_boarded(u)
	check.call(u.rooms.riders_of(0).size() == 17, "the car is full leaving the ground")
	var most_riders := 0
	for _i in 60:
		u.step()
		most_riders = maxi(most_riders, u.rooms.riders_of(0).size())
	var order := _alighted_ids(u)
	check.call(most_riders <= 17 and order.size() == 18 and order[16] == 16 and order[17] == 17 and u.rooms.alighted[17][1] == 28, "a full car lets riders off before a queued person boards")

	# A full car passes a hall-call floor without stopping; another car serves the call.
	var f := _setup([1, 1] as Array[int], 18)
	_queue(f, 0, 17, 1, 30)
	_until_boarded(f)
	f.rooms.join_queue(17, TestDispatch._id(f), 15, 20)
	var stopped_at_15 := false
	for _i in 60:
		f.step()
		var car: Array = f.rooms._cars[0]
		stopped_at_15 = stopped_at_15 or (car[CarsScript.FLOOR] == 15 and car[CarsScript.STATE] != CarsScript.MOVING and car[CarsScript.LOAD] == 17)
	check.call(not stopped_at_15, "a full car passes the call floor without stopping")
	check.call(_alighted_ids(f).size() >= 17 and f.rooms.queue_at(TestDispatch._id(f), 15).is_empty(), "the call is taken by the other car and the full car delivers")

	# A boarded rider's destination becomes a stop.
	var s := _setup([1] as Array[int], 2)
	_queue(s, 0, 2, 1, 20)
	_until_boarded(s)
	check.call(s.rooms._stops[0] == [20], "a rider's destination becomes a car stop")
	for _i in 40:
		s.step()
	check.call(_alighted_ids(s) == _ints([0, 1]) and s.rooms._cars[0][CarsScript.STATE] == CarsScript.IDLE, "riders alight there and the empty car goes idle")

	# Save with queues and riders round-trips and continues identically.
	var v := _setup([1] as Array[int], 20)
	_queue(v, 0, 20, 1, 30)
	_until_boarded(v)
	Harness.step(v, 1)
	var w := Harness.clone_via_save(v)
	check.call(w != null and w.state_hash() == v.state_hash() and w.rooms.riders_of(0) == v.rooms.riders_of(0) and v.rooms.riders_of(0).size() == 17 and w.rooms.queued_ids() == v.rooms.queued_ids() and v.rooms.queued_ids().size() == 3, "a save with queues and riders loads the same")
	Harness.step(v, 120)
	Harness.step(w, 120)
	check.call(w.state_hash() == v.state_hash() and v.rooms.queued_ids().is_empty(), "the loaded tower continues identically")

	# Same seed, same boarding.
	var a := _setup([1, 3] as Array[int], 20)
	var b := _setup([1, 3] as Array[int], 20)
	_queue(a, 0, 20, 1, 7)
	_queue(b, 0, 20, 1, 7)
	Harness.step(a, 80)
	Harness.step(b, 80)
	check.call(a.state_hash() == b.state_hash(), "the same queues give the same state")
