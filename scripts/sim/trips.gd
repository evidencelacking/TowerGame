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
const ESCALATOR_MINUTES := 1  ## Guess: minutes per escalator segment (it never waits).
const STRESS_PER_QUEUE_MINUTE := STRESS_PER_TRAVEL_MINUTE  ## Waiting for a car builds stress at the stairs rate (owner, #96); tune in playtest.
const STRESS_PER_WAIT_MINUTE := 3  ## Guess: stress for each minute spent requested before moving.
const STRESS_RECOVERY_PER_MINUTE := 1  ## Guess: stress lost each idle minute.
const STRESS_NO_ROUTE := 30  ## Guess: stress when a trip has no route and is given up.
const NO_ROUTE_RETRY_MINUTES := 30  ## Guess: minutes before a given-up trip is requested again.
const GROUND_FLOOR := 1

var _last_minute: int = -1  ## Not saved: resume() sets it after a load.
var _routes: Dictionary = {}  ## person id -> legs of the trip under way; a cache, rebuilt from trip_from and the goal.


## After a load: the minute's work was already done before the save.
func resume(clock: Object) -> void:
	_last_minute = clock.minute_of_day()
	_routes.clear()


## Whole minutes a route takes: walked columns (rounded up) plus stairs segments, at least 1.
static func route_minutes(legs: Array) -> int:
	var columns := 0
	var minutes := 0
	for leg: Dictionary in legs:
		if leg["kind"] == RoutesScript.WALK:
			columns += absi((leg["to_x"] as int) - (leg["from_x"] as int))
		elif leg["kind"] == RoutesScript.STAIRS:
			minutes += STAIRS_MINUTES
		elif leg["kind"] == RoutesScript.ESCALATOR:
			minutes += ESCALATOR_MINUTES
	minutes += (columns + WALK_COLUMNS_PER_MINUTE - 1) / WALK_COLUMNS_PER_MINUTE
	return maxi(1, minutes)


## The legs from first up to (not including) the next elevator leg: one walking stretch.
static func segment(legs: Array, first: int) -> Array:
	var out: Array = []
	for n in range(first, legs.size()):
		if legs[n]["kind"] == RoutesScript.ELEVATOR:
			break
		out.append(legs[n])
	return out


## Called once per tick. Acts once per sim minute.
func tick(clock: Object, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript) -> void:
	var minute: int = clock.minute_of_day()
	if minute == _last_minute:
		return
	_last_minute = minute
	for id: int in rooms.queued_ids():  # waiting in an elevator hall queue (#94)
		var queued: int = people.index_of(id)
		if queued != -1:
			people.add_stress(queued, STRESS_PER_QUEUE_MINUTE)
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
			PeopleScript.TRIP_RIDING:
				pass  # queued for a car (stress above, at STRESS_PER_QUEUE_MINUTE) or riding one
			_:
				people.cool_down(i)
				people.add_stress(i, -STRESS_RECOVERY_PER_MINUTE)


func _spot(room: int, grid: GridScript, entry: Array[int]) -> Array[int]:
	if room == PeopleScript.NONE:
		return entry
	var run := grid.run_of(room)
	return entry if run.is_empty() else run


func _start(i: int, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, entry: Array[int]) -> void:
	var legs: Variant = _find_legs(i, floors, rooms, grid, people, entry, people.location_of(i))
	if legs == null:
		_give_up(i, people)
		return
	people.start_trip(i, 1)  # sets the start room; the first stretch is set below
	_routes[people.id_at(i)] = legs
	_enter_leg(i, 0, legs, rooms, people)


## The route for person i from the room `from_room` to their goal, or null when there is none.
func _find_legs(i: int, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, entry: Array[int], from_room: int) -> Variant:
	var goal_room := people.goal_room(i)
	var from := _spot(from_room, grid, entry)
	var to: Array[int] = entry
	if goal_room != PeopleScript.NONE:
		to = grid.run_of(goal_room)
	if to.is_empty():
		return null
	var route: Dictionary = RoutesScript.find(floors, rooms, grid, from[0], from[1], to[0], to[1])
	if route["reason"] != RoutesScript.OK:
		return null
	return route["legs"]


## The person's route: cached, or rebuilt from where the trip started (null if it can't be).
func _legs_of(i: int, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, entry: Array[int]) -> Variant:
	var id := people.id_at(i)
	if not _routes.has(id):
		var legs: Variant = _find_legs(i, floors, rooms, grid, people, entry, people.trip_from(i))
		if legs == null:
			return null
		_routes[id] = legs
	return _routes[id]


func _give_up(i: int, people: PeopleScript) -> void:
	_routes.erase(people.id_at(i))
	people.give_up_trip(i, NO_ROUTE_RETRY_MINUTES)
	people.add_stress(i, STRESS_NO_ROUTE)


## The person is at the start of leg `leg`: walk the stretch up to the next elevator, or ride.
func _enter_leg(i: int, leg: int, legs: Array, rooms: RoomsScript, people: PeopleScript) -> void:
	if leg < legs.size() and legs[leg]["kind"] == RoutesScript.ELEVATOR:
		var l: Dictionary = legs[leg]
		var result := rooms.join_queue(people.id_at(i), l["shaft"], l["floor"], l["to_floor"])
		if result != RoomsScript.OK:
			_give_up(i, people)
			return
		people.set_riding(i, leg)
		return
	var stretch := segment(legs, leg)
	people.set_segment(i, leg, route_minutes(stretch))


## A walking stretch ended: ride the next elevator, or arrive.
func _segment_done(i: int, floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript, entry: Array[int]) -> void:
	var legs: Variant = _legs_of(i, floors, rooms, grid, people, entry)
	if legs == null:
		_give_up(i, people)
		return
	var next := people.trip_leg(i) + segment(legs, people.trip_leg(i)).size()
	if next >= legs.size():
		_routes.erase(people.id_at(i))
		people.finish_trip(i)
	else:
		_enter_leg(i, next, legs, rooms, people)


## After the cars have moved: people who alighted at their ride's destination carry on.
## Only reads the log while somebody is riding, so other users of it are left alone.
func collect_arrivals(floors: FloorsScript, rooms: RoomsScript, grid: GridScript, people: PeopleScript) -> void:
	var riding := false
	for i in people.count():
		riding = riding or people.trip_state(i) == PeopleScript.TRIP_RIDING
	if not riding or not floors.has_lobby():
		return
	var entry: Array[int] = [GROUND_FLOOR, floors.lobby_span()[0]]
	for event: Array in rooms.take_alighted():
		var i := people.index_of(event[0])
		if i == -1 or people.trip_state(i) != PeopleScript.TRIP_RIDING:
			continue
		var legs: Variant = _legs_of(i, floors, rooms, grid, people, entry)
		if legs == null:
			_give_up(i, people)
			continue
		var leg: int = people.trip_leg(i)
		if leg >= legs.size() or legs[leg]["to_floor"] != event[1]:
			continue
		if leg + 1 >= legs.size():
			_routes.erase(people.id_at(i))
			people.finish_trip(i)
		else:
			_enter_leg(i, leg + 1, legs, rooms, people)

	# A rider whose shaft was bulldozed is neither queued nor in a car: the trip is given up.
	for i in people.count():
		if people.trip_state(i) == PeopleScript.TRIP_RIDING and not rooms.in_elevator(people.id_at(i)):
			_give_up(i, people)
