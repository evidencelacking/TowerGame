extends RefCounted
## The event scheduler, #214: own seeded stream, one roll per kind per period, at most 3 open,
## a day between a fire and a threat, timeout to decline, choices only as commands, saved.

const TowerSim := preload("res://scripts/sim/tower.gd")
const Command := TowerSim.Command
const EventsScript := preload("res://scripts/sim/events.gd")


static func _kind(id: int, chance: int, cls: int = EventsScript.ORDINARY, timeout: int = 100000) -> Dictionary:
	return {"id": id, "class": cls, "chance": chance, "min_stars": 1, "choices": 3, "timeout": timeout, "floor": 0}


static func _tower(seed_value: int, kinds: Array[Dictionary]) -> TowerSim:
	var t := TowerSim.new(seed_value)
	t.events.kinds = kinds
	return t


static func _run(t: TowerSim, ticks: int) -> void:
	for _i in ticks:
		t.step()


static func _of_kind(t: TowerSim, kind: int) -> Array[Array]:
	var found: Array[Array] = []
	for event in t.events.open_events():
		if event[1] == kind:
			found.append(event)
	return found


static func _mixed() -> Array[Dictionary]:
	return [_kind(1, 400, EventsScript.ORDINARY, 400), _kind(2, 300, EventsScript.THREAT, 800)] as Array[Dictionary]


static func run(check: Callable) -> void:
	# No kinds, no events, and the scheduler never touches the tower's own random stream.
	var quiet := TowerSim.new(5)
	quiet.events.kinds = [] as Array[Dictionary]  # a tower registers the fire kind itself
	var busy := _tower(5, [_kind(1, 500), _kind(2, 500)] as Array[Dictionary])
	_run(quiet, 3000)
	_run(busy, 3000)
	check.call(quiet.events.open_count() == 0 and quiet.events.rolls == 0, "with no kinds nothing is rolled")
	check.call(busy.events.rolls > 0 and quiet.rng.state == busy.rng.state, "events use their own stream and leave the tower's draws alone")

	# One roll per kind per period: a day has six periods.
	var rolled := _tower(1, [_kind(1, 0), _kind(2, 0)] as Array[Dictionary])
	_run(rolled, EventsScript.DAY_TICKS)
	check.call(rolled.events.rolls == 12, "each kind rolls once in each of a day's six periods")
	var half_day := _tower(1, [_kind(1, 0)] as Array[Dictionary])
	_run(half_day, 599)
	check.call(half_day.events.rolls == 0, "no roll happens inside a period")

	# At most 3 open events.
	var crowd := _tower(2, [_kind(1, 1000)] as Array[Dictionary])
	var most := 0
	for _i in EventsScript.DAY_TICKS * 2:
		crowd.step()
		most = maxi(most, crowd.events.open_count())
	check.call(most == 3 and crowd.events.open_count() == 3, "never more than 3 events open")
	var first: Array = crowd.events.open_events()[0]
	check.call(first[0] == 1 and first[1] == 1 and first[3] == EventsScript.OPEN and first[6] == 3, "an event is data: id, kind, floor, state, deadline and choices")

	# A kind needs its stars.
	var gated_kind := _kind(1, 1000)
	gated_kind["min_stars"] = 3
	var gated := _tower(2, [gated_kind] as Array[Dictionary])
	_run(gated, 2000)
	check.call(gated.events.open_count() == 0 and gated.events.rolls > 0, "a kind rolls but does not fire below its star rating")

	# A day between a fire and a threat.
	var gap := _tower(3, [_kind(1, 1000, EventsScript.FIRE), _kind(2, 1000, EventsScript.THREAT)] as Array[Dictionary])
	_run(gap, 600)  # the first period ends and both kinds roll
	check.call(_of_kind(gap, 1).size() == 1 and _of_kind(gap, 2).is_empty(), "a threat does not fire in the period of a fire")
	gap.events.kinds[0]["chance"] = 0
	_run(gap, 4000)
	var fires := _of_kind(gap, 1)
	var threats := _of_kind(gap, 2)
	var fire_at: int = fires[0][4] if not fires.is_empty() else 0
	check.call(not fires.is_empty() and not threats.is_empty() and threats[0][4] - fire_at >= EventsScript.DAY_TICKS, "the first threat comes at least a day after the fire")
	check.call(not threats.is_empty() and threats[0][4] - fire_at < EventsScript.DAY_TICKS + 700, "and at the first period start after that day")

	# Timeout to decline.
	var slow := _tower(4, [_kind(1, 1000, EventsScript.ORDINARY, 150)] as Array[Dictionary])
	_run(slow, 650)
	check.call(slow.events.open_count() == 1 and slow.events.resolved().is_empty(), "an unanswered event stays open until its deadline")
	_run(slow, 160)
	var gone := slow.events.resolved()
	check.call(not gone.is_empty() and gone[0][2] == EventsScript.DECLINE, "an unanswered event times out to decline")

	# Choices reach the sim only as commands.
	var t := _tower(6, [_kind(1, 1000)] as Array[Dictionary])
	_run(t, 650)
	check.call(t.events.open_count() == 1, "the tower has an event to answer")
	var id: int = t.events.open_events()[0][0]
	check.call(t.enqueue(Command.make(t.tick + 1, Command.CHOOSE_EVENT, [id, 9] as Array[int])), "a choice is queued as a command")
	t.step()
	check.call(not t.events.event_of(id).is_empty(), "an out-of-range choice is refused and the event stays open")
	t.enqueue(Command.make(t.tick + 1, Command.CHOOSE_EVENT, [id + 50, 1] as Array[int]))
	t.step()
	check.call(not t.events.event_of(id).is_empty(), "a choice for an event that is not open does nothing")
	t.enqueue(Command.make(t.tick + 1, Command.CHOOSE_EVENT, [id, 2] as Array[int]))
	t.step()
	var answered := t.events.resolved()
	check.call(t.events.event_of(id).is_empty() and answered.size() == 1 and answered[0][0] == id and answered[0][2] == 2, "a valid choice closes the event and is logged")

	# Determinism: the same seed and commands give the same events; another seed gives others.
	var a := _tower(7, _mixed())
	var b := _tower(7, _mixed())
	var c := _tower(8, _mixed())
	for tower in [a, b, c]:
		_run(tower, 7000)
	check.call(a.state_hash() == b.state_hash() and a.events.state_ints() == b.events.state_ints(), "the same seed gives the same events")
	check.call(a.events.rolls > 10 and a.events.resolved() != c.events.resolved(), "a different seed gives different events")

	# Save and load mid-event resume identically.
	var m := _tower(9, _mixed())
	_run(m, 1700)
	var saved := m.save()
	check.call(m.events.open_count() > 0, "the tower has an event open when saved")
	var u := _tower(0, _mixed())
	check.call(u.load_state(saved) and u.state_hash() == m.state_hash(), "a save mid-event loads the same")
	_run(m, 3000)
	_run(u, 3000)
	check.call(u.state_hash() == m.state_hash() and u.events.resolved() == m.events.resolved(), "a loaded tower goes on exactly like the original")
	var bad := m.save()
	bad["events"] = [1, 2]
	check.call(not _tower(0, [] as Array[Dictionary]).load_state(bad), "a damaged event block is refused")
