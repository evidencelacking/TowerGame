extends RefCounted
## Elevator schedules, #188: weekday and weekend, 3 periods each; per period a mode (express to top
## or bottom), a response distance and a departure wait of 0 to 90 sim seconds.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const Clock := preload("res://scripts/sim/clock.gd")
const TestRooms := preload("res://tests/test_rooms.gd")
const TestDispatch := preload("res://tests/test_dispatch.gd")
const TestBoarding := preload("res://tests/test_boarding.gd")


static func _put(t: TowerSim, slot: int, mode: int, response: int, wait: int) -> int:
	return TestRooms._send(t, Command.SET_SCHEDULE, [TestDispatch._id(t), slot, mode, response, wait] as Array[int])


static func _zeros() -> Array[int]:
	var out: Array[int] = []
	out.resize(RoomsScript.SCHEDULE_INTS)
	out.fill(0)
	return out


## Queues one person at floor 1 for floor 10, then steps until the car sets off with them; returns
## the ticks that took, or -1.
static func _ticks_to_depart(t: TowerSim) -> int:
	TestBoarding._queue(t, 0, 1, 1, 10)
	for n in range(1, 40):
		t.step()
		if t.rooms.riders_of(0).size() > 0 and t.rooms._cars[0][CarsScript.STATE] == CarsScript.MOVING:
			return n
	return -1


static func run(check: Callable) -> void:
	# Slots: weekday then weekend, 3 periods each (the clock's 6 periods pair up).
	var slots: Array[int] = []
	for weekend in [false, true]:
		for period in range(1, 7):
			slots.append(RoomsScript.slot_for(weekend, period))
	check.call(slots == ([0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5] as Array[int]), "clock periods map to morning, midday and evening, weekday and weekend")

	# Setting a slot: defaults, clamps and refusals.
	var t := TestBoarding._setup([1] as Array[int], 20)
	var id := TestDispatch._id(t)
	check.call(t.rooms.schedule_of(id) == _zeros(), "a new shaft has the default schedule: normal, no limit, no wait")
	check.call(_put(t, 2, RoomsScript.MODE_TOP, 12, 60) == RoomsScript.OK and t.rooms.schedule_field(id, 2, 0) == 1 and t.rooms.schedule_field(id, 2, 1) == 12 and t.rooms.schedule_field(id, 2, 2) == 60, "a slot keeps its mode, response distance and wait")
	check.call(t.rooms.schedule_field(id, 0, 2) == 0, "the other slots are untouched")
	check.call(_put(t, 1, 0, 0, 91) == RoomsScript.OK and t.rooms.schedule_field(id, 1, 2) == 90, "a wait of 91 clamps to 90")
	check.call(_put(t, 1, 0, 500, 5000) == RoomsScript.OK and t.rooms.schedule_field(id, 1, 2) == 90 and t.rooms.schedule_field(id, 1, 1) == 100, "a huge wait clamps to 90 and a huge distance to 100")
	check.call(_put(t, 1, 0, -4, -9) == RoomsScript.OK and t.rooms.schedule_field(id, 1, 1) == 0 and t.rooms.schedule_field(id, 1, 2) == 0, "negative values clamp to 0")
	check.call(_put(t, 6, 0, 0, 0) == RoomsScript.BAD_SCHEDULE and _put(t, -1, 0, 0, 0) == RoomsScript.BAD_SCHEDULE and _put(t, 0, 3, 0, 0) == RoomsScript.BAD_SCHEDULE, "a bad slot or mode is refused")
	check.call(TestRooms._send(t, Command.SET_SCHEDULE, [9999, 0, 0, 0, 0] as Array[int]) == RoomsScript.NOTHING_THERE, "a schedule for no shaft is refused")

	# A save keeps the schedule.
	var u := TowerSim.new(0)
	check.call(u.load_state(t.save()) and u.state_hash() == t.state_hash() and u.rooms.schedule_field(id, 2, 1) == 12, "a schedule survives a save")

	# The weekend uses the WE slots: the tower reads the clock into the slot each tick.
	var w := TestBoarding._setup([1] as Array[int], 20)
	check.call(w.clock.day_of_week() == Clock.WD1, "fixture: a new tower starts on a weekday")
	w.step()
	check.call(w.rooms.schedule_slot == 0, "a weekday morning reads slot 0")
	w.clock.set_to_tick(2 * 2550 + 10)  # the third day of the quarter, just after 5:00
	w.step()
	check.call(w.clock.day_of_week() == Clock.WE and w.rooms.schedule_slot == RoomsScript.slot_for(true, w.clock.period()) and w.rooms.schedule_slot == 3, "the weekend reads the weekend slot")

	# Departure wait: 0 leaves at once; 60 holds about 2.5 ticks more; full leaves early.
	var quick := TestBoarding._setup([1] as Array[int], 40)
	var base := _ticks_to_depart(quick)
	check.call(base > 0, "fixture: with no wait the car sets off with its rider")
	var held := TestBoarding._setup([1] as Array[int], 40)
	_put(held, 0, RoomsScript.MODE_NORMAL, 0, 60)
	var held_ticks := _ticks_to_depart(held)
	check.call(held_ticks - base >= 2 and held_ticks - base <= 4, "a 60 second wait holds the car for about 2.5 ticks")
	var longest := TestBoarding._setup([1] as Array[int], 40)
	_put(longest, 0, RoomsScript.MODE_NORMAL, 0, 90)
	var long_ticks := _ticks_to_depart(longest)
	check.call(long_ticks > held_ticks, "a 90 second wait holds longer than 60")
	var full := TestBoarding._setup([1] as Array[int], 40)
	_put(full, 0, RoomsScript.MODE_NORMAL, 0, 90)
	TestBoarding._queue(full, 0, 1, 1, 10)
	var waited := 0
	while waited < 40 and full.rooms._cars[0][CarsScript.STATE] != CarsScript.DOORS_OPEN:
		full.step()
		waited += 1
	check.call(full.rooms._cars[0][CarsScript.STATE] == CarsScript.DOORS_OPEN, "fixture: the car opens its doors at the home floor")
	TestBoarding._queue(full, 1, 17, 1, 10)  # 16 more join: with the first rider the car is full
	var steps := 0
	while steps < 40 and full.rooms._cars[0][CarsScript.STATE] != CarsScript.MOVING:
		full.step()
		steps += 1
	check.call(full.rooms.riders_of(0).size() == full.rooms.car_capacity(id) and steps <= 2, "a car that fills during the wait leaves at once")

	# Express to top: an idle, empty car goes up and parks at the top stop; to bottom parks below.
	var top := TestBoarding._setup([5] as Array[int], 0)
	_put(top, 0, RoomsScript.MODE_TOP, 0, 0)
	var arrived := -1
	for n in range(1, 40):
		top.step()
		if top.rooms._cars[0][CarsScript.FLOOR] == 30 and top.rooms._cars[0][CarsScript.STATE] == CarsScript.IDLE:
			arrived = n
			break
	check.call(arrived > 0, "express to top sends an empty car up to the top stop and parks it")
	var bottom := TestBoarding._setup([5] as Array[int], 0)
	_put(bottom, 0, RoomsScript.MODE_BOTTOM, 0, 0)
	for n in 40:
		bottom.step()
	check.call(bottom.rooms._cars[0][CarsScript.FLOOR] == 1 and bottom.rooms._cars[0][CarsScript.STATE] == CarsScript.IDLE, "express to bottom parks an empty car at the bottom stop")
	var normal := TestBoarding._setup([5] as Array[int], 0)
	for n in 40:
		normal.step()
	check.call(normal.rooms._cars[0][CarsScript.FLOOR] == 5, "in normal mode an idle car stays at its home floor")

	# Response distance: a moving car does not divert for a call farther ahead than the distance.
	var near := TestBoarding._setup([1] as Array[int], 0)
	var near_id := TestDispatch._id(near)
	near.rooms.send_car(0, 30)
	near.rooms.place_call(near_id, 20, CarsScript.UP)
	near.rooms.set_schedule(near_id, 0, 0, 5, 0)
	CarsScript._dispatch(near.rooms)
	check.call(near.rooms._calls[0][CarsScript.CALL_CAR] == -1, "a call 19 floors ahead is not answered with a distance of 5")
	near.rooms.set_schedule(near_id, 0, 0, 0, 0)
	CarsScript._dispatch(near.rooms)
	check.call(near.rooms._calls[0][CarsScript.CALL_CAR] == 0, "with no limit the moving car takes it")
