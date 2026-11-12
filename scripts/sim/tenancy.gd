class_name Tenancy
extends RefCounted
## Office tenancy (3.2): each office takes its 6 workers when it is reachable from the ground
## lobby. Leasing happens on weekdays before LEASE_END only. Tenancy is derived from People (the
## workers whose work room is the office), so it adds nothing to the save. The check runs once per
## sim minute; an unreachable office stays empty and fills at the next eligible check.

const Clock := preload("res://scripts/sim/clock.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")

const LEASE_END := 780  ## 13:00: no leasing from here on (docs/gameplay-reference.md).
const GROUND_FLOOR := 1

var _last_minute: int = -1  ## Not saved: a reload simply rechecks once, and the check is idempotent.


## Called once per tick after the clock. Fills reachable offices, at most once per sim minute.
func tick(clock: Clock, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, rng: Object) -> void:
	var minute := clock.minute_of_day()
	if minute == _last_minute:
		return
	_last_minute = minute
	if clock.day_of_week() == Clock.WE or minute >= LEASE_END or not floors.has_lobby():
		return
	var entry_x := floors.lobby_span()[0]  # left-edge entry
	for id in rooms.room_ids():
		if rooms.kind_of(id) != "office":
			continue
		var need := rooms.people_in(id) - people.workers_in(id)
		if need <= 0:
			continue
		var run := grid.run_of(id)
		if run.is_empty():
			continue
		var route := RoutesScript.find(floors, rooms, grid, GROUND_FLOOR, entry_x, run[0], run[1])
		if route["reason"] != RoutesScript.OK:
			continue
		for n in need:
			people.add_person(PeopleScript.NONE, id, rng)
