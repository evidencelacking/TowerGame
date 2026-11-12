extends RefCounted
## Person model tests (3.1): home, work, day plan, trip, stress clamp, determinism, save and load.

const TowerSim := preload("res://scripts/sim/tower.gd")
const People := preload("res://scripts/sim/people.gd")
const Clock := preload("res://scripts/sim/clock.gd")


static func _tower(seed_value: int) -> TowerSim:
	var t := TowerSim.new(seed_value)
	t.people.add_person(5, 7, t.rng)
	t.people.add_person(People.NONE, 8, t.rng)
	return t


static func run(check: Callable) -> void:
	# Day plan test: the same seed gives the same plan; the weekend office plan is empty.
	var a := _tower(42)
	var b := _tower(42)
	check.call(a.people.day_plan(0, Clock.WD1) == b.people.day_plan(0, Clock.WD1) and a.people.day_plan(0, Clock.WD1).size() == 6, "same seed gives the same day plan")
	var plan := a.people.day_plan(0, Clock.WD1)
	check.call(plan[0][0] >= People.ARRIVE and plan[0][0] <= People.ARRIVE + People.ARRIVAL_SPREAD and plan[1][0] == People.BREAK and plan[3][0] == People.LUNCH and plan[5][0] == People.LEAVE, "weekday plan follows the office hours")
	check.call(a.people.day_plan(0, Clock.WE).is_empty(), "the weekend office plan is empty")
	var workless := People.new()
	workless.add_person(People.NONE, People.NONE, a.rng)
	check.call(workless.day_plan(0, Clock.WD1).is_empty(), "a person with no home or work has no plan")

	# Model fields.
	check.call(a.people.count() == 2 and a.people.home_of(0) == 5 and a.people.work_of(0) == 7 and a.people.home_of(1) == People.NONE, "home and work are kept, either may be none")
	check.call(a.people.id_at(0) == 0 and a.people.id_at(1) == 1 and a.people.index_of(1) == 1, "ids are sequential and findable")
	check.call(a.people.trip_state(0) == People.TRIP_IDLE and a.people.location_of(0) == 5, "a new person is idle at home")

	# Stress clamps at 0 and 300.
	a.people.add_stress(0, 1000)
	check.call(a.people.stress_of(0) == 300, "stress clamps at 300")
	a.people.add_stress(0, -1000)
	check.call(a.people.stress_of(0) == 0, "stress clamps at 0")
	a.people.set_stress(0, 120)
	check.call(a.people.stress_of(0) == 120, "stress is set in range")

	# Ticking: before the arrival minute nothing is requested; at it, a worker requests a trip to work.
	var t := _tower(7)
	var arrive: int = t.people.day_plan(0, Clock.WD1)[0][0]
	var guard := 0
	while t.clock.minute_of_day() < arrive - 1 and guard < 10000:
		t.step()
		guard += 1
	check.call(guard < 10000 and t.people.trip_state(0) == People.TRIP_IDLE, "no trip is requested before the arrival time")
	while t.clock.minute_of_day() < arrive and guard < 10000:
		t.step()
		guard += 1
	check.call(guard < 10000 and t.people.goal_of(0) == People.DEST_WORK and t.people.trip_state(0) == People.TRIP_REQUESTED, "arrival time requests a trip to work")
	t.people.start_trip(0)
	check.call(t.people.trip_state(0) == People.TRIP_MOVING and t.people.location_of(0) == People.NONE, "a started trip is moving between rooms")
	t.people.finish_trip(0)
	check.call(t.people.trip_state(0) == People.TRIP_IDLE and t.people.location_of(0) == 7, "a finished trip leaves the person at the goal")

	# Determinism and save/load, including a stable id across save.
	t.people.set_stress(0, 200)
	var saved := t.save()
	var u := TowerSim.new(7)
	check.call(u.load_state(saved) and u.people.state_ints() == t.people.state_ints() and u.state_hash() == t.state_hash(), "people save and load exactly")
	check.call(u.people.index_of(1) == 1 and u.people.stress_of(0) == 200, "ids and stress survive a save")
	for _i in 500:
		t.step()
		u.step()
	check.call(t.state_hash() == u.state_hash(), "loaded people tick the same as the original")
	var bad := saved.duplicate(true)
	bad["people"] = [0, -1, 1]
	check.call(not TowerSim.new(0).load_state(bad), "a malformed people save is refused")
