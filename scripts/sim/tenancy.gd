class_name Tenancy
extends RefCounted
## Condo sales (3.4): a condo sells once it is reachable from the lobby, never from SALE_STOP to
## SALE_RESUME, on any day. A sale marks it sold, credits its price and moves in its 3 residents.
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
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")

const LEASE_END := 780  ## 13:00: no leasing from here on (docs/gameplay-reference.md).
const SALE_STOP := 1260  ## 21:00: no condo sales from here until SALE_RESUME (docs/gameplay-reference.md).
const SALE_RESUME := 420  ## 7:00.
const GROUND_FLOOR := 1

var _last_minute: int = -1  ## Not saved: a reload simply rechecks once, and the check is idempotent.


## Called once per tick after the clock. Fills reachable offices, at most once per sim minute.
func tick(clock: Clock, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, rng: Object, ledger: LedgerScript, at_tick: int) -> void:
	var minute := clock.minute_of_day()
	if minute == _last_minute:
		return
	_last_minute = minute
	if not floors.has_lobby():
		return
	var entry_x := floors.lobby_span()[0]  # left-edge entry
	var leasing := clock.day_of_week() != Clock.WE and minute < LEASE_END
	var selling := minute >= SALE_RESUME and minute < SALE_STOP
	for id in rooms.room_ids():
		var kind := rooms.kind_of(id)
		if kind == "office" and leasing:
			var need := rooms.people_in(id) - people.workers_in(id)
			if need > 0 and _reachable(floors, rooms, grid, id, entry_x):
				for n in need:
					people.add_person(PeopleScript.NONE, id, rng)
		elif kind == "condo" and selling and not rooms.is_sold(id) and _reachable(floors, rooms, grid, id, entry_x):
			rooms.set_sold(id, true)
			ledger.income(at_tick, CatalogueScript.cost(kind), id)
			for n in rooms.people_in(id):
				people.add_person(id, PeopleScript.NONE, rng)


func _reachable(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, id: int, entry_x: int) -> bool:
	var run := grid.run_of(id)
	if run.is_empty():
		return false
	var route := RoutesScript.find(floors, rooms, grid, GROUND_FLOOR, entry_x, run[0], run[1])
	return route["reason"] == RoutesScript.OK
