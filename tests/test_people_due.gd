extends RefCounted
## People.tick and Trips.tick visit only the people due a look (#454): the skip must never change a result. Two checks:
## _next_change agrees with the schedule (a goal only changes at a minute it names), and the mixed fixture stepped across
## a night and the morning rush ends on the state_hash recorded on main before the skip was added.

const Mixed := preload("res://tools/bench_mixed.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const Clock := preload("res://scripts/sim/clock.gd")

const WARMUP := 400
const NIGHT_AT := 2200  ## Clock ticks into the day: about 19:40, so the run crosses the 21:00 night, the night and the 9:00 arrivals.
const TICKS := 1700
const PINNED := 7867584463281122288  ## state_hash after the run below on bench_mixed seed 42. Re-recorded for #452 (the evaluation runs one step a tick).


static func run(check: Callable) -> void:
	_next_change_agrees(check)
	var t := Mixed.build(42)
	for _i in WARMUP:
		t.step()
	t.clock.set_to_tick(NIGHT_AT)
	for _i in TICKS:
		t.step()
	check.call(t.people.count() > 0, "the mixed fixture has people")
	var got := t.state_hash()
	check.call(got == PINNED, "state_hash after a night and a morning rush matches the pinned value (got %d)" % got)


## For a worker (every arrival offset, with and without a home), a resident and a person with neither, on each day class:
## _next_change is after the minute asked about, and every minute at which the goal changes is one it names, so a person
## skipped until then cannot miss a change. Every loop is counted.
static func _next_change_agrees(check: Callable) -> void:
	var people := PeopleScript.new()
	var none := PeopleScript.NONE
	var ok := true
	var changes := 0
	var cases: Array[Vector3i] = []
	for offset in PeopleScript.ARRIVAL_SPREAD + 1:
		cases.append(Vector3i(7, 5, offset))
		cases.append(Vector3i(7, none, offset))
	cases.append(Vector3i(none, 5, 0))
	cases.append(Vector3i(none, none, 0))
	for c in cases:
		for day in [Clock.WD1, Clock.WD2, Clock.WE]:
			for minute in Clock.MINUTES_PER_DAY - 1:
				var next := people._next_change(c.x, c.y, c.z, day, minute)
				ok = ok and next > minute
				if people._goal_at(c.x, c.y, c.z, day, minute + 1) != people._goal_at(c.x, c.y, c.z, day, minute):
					changes += 1
					ok = ok and next == minute + 1
	check.call(changes > 0, "the schedule has goal changes to check")
	check.call(ok, "every minute the goal changes at is one _next_change names")
