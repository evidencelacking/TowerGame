extends RefCounted
## Office day tests (3.3): arrive, mid-morning break, lunch, leave; nobody on weekends.

const TowerSim := preload("res://scripts/sim/tower.gd")
const TestTenancy := preload("res://tests/test_tenancy.gd")
const People := preload("res://scripts/sim/people.gd")
const Clock := preload("res://scripts/sim/clock.gd")


## The first tick of the given day (0, 1 or 2) at which the clock shows at least this minute.
static func _tick_at(minute: int, day: int) -> int:
	var probe := Clock.new()
	var day_ticks := 0
	for p in Clock.PERIODS:
		day_ticks += probe.period_ticks(p)
	for tick in range(day * day_ticks, (day + 1) * day_ticks):
		probe.set_to_tick(tick)
		if probe.minute_of_day() >= minute:
			return tick
	return -1


## A weekday-filled tower, then the clock jumped to the minute and stepped once.
static func _at(t: TowerSim, minute: int, day: int = 0) -> void:
	t.clock.set_to_tick(_tick_at(minute, day))
	t.step()


static func _all_goal(t: TowerSim, goal_room: int) -> bool:
	for i in t.people.count():
		if t.people.goal_room(i) != goal_room:
			return false
	return t.people.count() > 0


static func _filled() -> TowerSim:
	var t := TestTenancy._tower()
	TestTenancy._link(t)
	TestTenancy._run_at(t, TestTenancy.MORNING_TICK)
	return t


static func _day_ints(seed_value: int) -> Array[int]:
	var t := TowerSim.new(seed_value, 100000000)
	t.floors.build_lobby(t.ledger, 0, 1, 100, 131, 2)
	t.floors.fill_span(3, 100, 131)
	t.rooms.place_room(t.grid, t.floors, t.ledger, 0, TestTenancy.CatalogueScript.IDS.find("office"), 3, 110)
	TestTenancy._link(t)
	t.clock.set_to_tick(_tick_at(8 * 60, 0))
	for i in 2200:
		t.step()
	return t.people.state_ints()


static func run(check: Callable) -> void:
	var t := _filled()
	var office := TestTenancy._office(t)
	check.call(t.people.count() == 6, "office day test tower has 6 workers")

	_at(t, People.ARRIVE - 30)
	check.call(_all_goal(t, People.NONE), "before 9:00 workers are outside the tower")
	_at(t, People.ARRIVE + People.ARRIVAL_SPREAD + 1)
	check.call(_all_goal(t, office), "after arrival plus spread every worker is at work")
	_at(t, People.BREAK + 1)
	check.call(_all_goal(t, office) and t.people.goal_of(0) == People.DEST_BREAK, "during the 10:30 break the goal is the break destination (the office until food rooms exist)")
	_at(t, People.BREAK + People.BREAK_LENGTH + 1)
	check.call(t.people.goal_of(0) == People.DEST_WORK, "after the break they are back at work")
	_at(t, People.LUNCH + 1)
	check.call(t.people.goal_of(0) == People.DEST_LUNCH and _all_goal(t, office), "during lunch the goal is the lunch destination (the office until food rooms exist)")
	_at(t, People.LUNCH + People.LUNCH_LENGTH + 1)
	check.call(t.people.goal_of(0) == People.DEST_WORK, "after lunch they are back at work")
	_at(t, People.LEAVE + 1)
	check.call(_all_goal(t, People.NONE) and t.people.trip_state(0) == People.TRIP_REQUESTED, "after 17:00 they leave the tower")

	for day in [Clock.WE]:
		_at(t, People.ARRIVE + 60, day)
		check.call(t.clock.day_of_week() == Clock.WE and _all_goal(t, People.NONE), "on the weekend no worker targets the office at 10:00")
		_at(t, People.LUNCH + 1, day)
		check.call(_all_goal(t, People.NONE), "on the weekend no worker targets the office at lunch")
	_at(t, People.ARRIVE + 60, Clock.WD1)
	check.call(_all_goal(t, office), "they are back the next weekday")

	check.call(_day_ints(11) == _day_ints(11), "same seed, same people state over a day")
