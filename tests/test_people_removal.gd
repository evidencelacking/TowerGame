extends RefCounted
## Removing people with their room (#81): bulldozing an office or condo removes its people.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const TestPopulation := preload("res://tests/test_population.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")
const TestRooms := preload("res://tests/test_rooms.gd")


static func _dozer(t: TowerSim, x: int) -> void:
	TestRooms._send(t, Command.BULLDOZE, [3, x] as Array[int])


static func _has_room(t: TowerSim, room: int) -> bool:
	for i in t.people.count():
		if t.people.home_of(i) == room or t.people.work_of(i) == room:
			return true
	return false


## The test tower after the condo sold and the workers moved in, then the day to mid-morning.
static func _filled() -> TowerSim:
	var t := TestPopulation._tower()
	TestPopulation._at(t, 10 * 60, 10)
	return t


static func _run_bulldoze() -> TowerSim:
	var t := _filled()
	_dozer(t, 112)
	TestPopulation._at(t, 12 * 60)
	return t


static func run(check: Callable) -> void:
	var t := _filled()
	var office := t.grid.cell_at(3, 112)
	var condo := t.grid.cell_at(3, 122)
	var before := t.population()
	var others: Array[int] = []
	for i in t.people.count():
		if t.people.home_of(i) == condo:
			others.append(t.people.id_at(i))
	check.call(t.people.count() == 9 and others.size() == 3, "setup: 9 people, 3 live in the condo")
	_dozer(t, 112)
	check.call(not _has_room(t, office) and t.people.count() == 3, "bulldozing an office removes its 6 workers")
	check.call(t.population() == before - 6, "the population drops by 6")
	var kept := true
	for id in others:
		kept = kept and t.people.index_of(id) != -1
	check.call(kept, "other rooms' people are untouched")
	TestPopulation._at(t, 18 * 60)
	check.call(t.people.count() == 3, "later ticks run without errors or new people")

	var c := _filled()
	_dozer(c, 122)
	check.call(not _has_room(c, condo) and c.people.count() == 6, "bulldozing a sold condo removes its 3 residents")

	# Mid-trip: step until someone is moving, then bulldoze their room.
	var m := TestPopulation._tower()
	TestPopulation._at(m, 10 * 60, 10)
	m.clock.set_to_tick(TestOfficeDay._tick_at(17 * 60, 0))
	var victim := -1
	for k in 60:
		m.step()
		for i in m.people.count():
			if m.people.trip_state(i) == m.people.TRIP_MOVING and m.people.work_of(i) != -1:
				victim = m.people.work_of(i)
		if victim != -1:
			break
	check.call(victim != -1, "setup: someone is mid-trip")
	if victim != -1:
		_dozer(m, 112)
		check.call(not _has_room(m, victim), "a person mid-trip is removed with their room")
		TestPopulation._at(m, 18 * 60, 80)
		check.call(m.people.count() == 3, "ticks after removing a mid-trip person run clean")

	# Save round trip after a removal.
	var copy := TowerSim.new(1, 0)
	check.call(copy.load_state(t.save()) and copy.state_hash() == t.state_hash() and copy.people.count() == 3, "a tower saves and loads after a removal")

	# Determinism.
	check.call(_run_bulldoze().state_hash() == _run_bulldoze().state_hash(), "a same-seed run with a bulldoze is identical twice")
