class_name Trips
extends RefCounted
## Trip executor (3.5/3.6): moves people whose trip is requested along a route and charges
## stress for the time spent waiting and travelling. Once per sim minute. Runs before
## People.tick, so a trip requested at one minute waits that minute (waiting stress, and the
## seam for elevator queues) and starts at the next. Derived from People, so nothing is saved.
## Every value below is a guess, tunable.

const FloorsScript := preload("res://scripts/sim/floors.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const RoutesScript := preload("res://scripts/sim/routes.gd")

const WALK_COLUMNS_PER_MINUTE := 20  ## Guess: columns walked in a sim minute.
const STAIRS_MINUTES := 2  ## Guess: minutes per stairs segment.
const STRESS_PER_TRAVEL_MINUTE := 3  ## Guess: stress for each minute in transit.
const STRESS_PER_WAIT_MINUTE := 3  ## Guess: stress for each minute spent requested before moving.
const STRESS_RECOVERY_PER_MINUTE := 1  ## Guess: stress lost each idle minute.
const STRESS_NO_ROUTE := 30  ## Guess: stress when a trip has no route and is given up.
const NO_ROUTE_RETRY_MINUTES := 30  ## Guess: minutes before a given-up trip is requested again.
const GROUND_FLOOR := 1

var _last_minute: int = -1  ## Not saved: a reload resumes at the next minute change.


## Whole minutes a route takes: walked columns (rounded up) plus stairs segments, at least 1.
static func route_minutes(legs: Array) -> int:
	var columns := 0
	var minutes := 0
	for leg: Dictionary in legs:
		if leg["kind"] == RoutesScript.WALK:
			columns += absi((leg["to_x"] as int) - (leg["from_x"] as int))
		else:
			minutes += STAIRS_MINUTES
	minutes += (columns + WALK_COLUMNS_PER_MINUTE - 1) / WALK_COLUMNS_PER_MINUTE
	return maxi(1, minutes)


## Called once per tick. Acts once per sim minute.
func tick(clock: Object, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript) -> void:
	var minute: int = clock.minute_of_day()
	if minute == _last_minute:
		return
	_last_minute = minute
	if not floors.has_lobby():
		return
	var entry: Array[int] = [GROUND_FLOOR, floors.lobby_span()[0]]  # left-edge entry, outside the tower
	for i in people.count():
		match people.trip_state(i):
			PeopleScript.TRIP_REQUESTED:
				people.add_stress(i, STRESS_PER_WAIT_MINUTE)
				_start(i, floors, rooms, grid, people, entry)
			PeopleScript.TRIP_MOVING:
				people.add_stress(i, STRESS_PER_TRAVEL_MINUTE)
				if people.spend_trip_minute(i) == 0:
					people.finish_trip(i)
			_:
				people.cool_down(i)
				people.add_stress(i, -STRESS_RECOVERY_PER_MINUTE)


func _spot(room: int, grid: GridScript, entry: Array[int]) -> Array[int]:
	if room == PeopleScript.NONE:
		return entry
	var run := grid.run_of(room)
	return entry if run.is_empty() else run


func _start(i: int, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, entry: Array[int]) -> void:
	var goal_room := people.goal_room(i)
	var from := _spot(people.location_of(i), grid, entry)
	var to: Array[int] = entry
	if goal_room != PeopleScript.NONE:
		to = grid.run_of(goal_room)
	var route: Dictionary = {"reason": RoutesScript.NO_ROUTE}
	if not to.is_empty():
		route = RoutesScript.find(floors, rooms, grid, from[0], from[1], to[0], to[1])
	if route["reason"] == RoutesScript.OK:
		people.start_trip(i, route_minutes(route["legs"]))
	else:
		people.give_up_trip(i, NO_ROUTE_RETRY_MINUTES)
		people.add_stress(i, STRESS_NO_ROUTE)
