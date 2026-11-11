class_name People
extends RefCounted
## The person model (3.1): each person has a home room, a work room (either may be NONE), a
## weekday/weekend day plan, a trip state and stress 0 to 300. Integers only, flat state, so it
## saves and hashes exactly. Person ids are stable: they are never reused or reordered.
##
## Seams for later work: tenancy (#66) calls add_person; routing (#69) moves people whose
## trip_state is TRIP_REQUESTED and calls start_trip and finish_trip; stress rules (#70) call
## add_stress.

const Clock := preload("res://scripts/sim/clock.gd")

const NONE := -1  ## No room.

## Office hours, minutes since midnight. Tunable (owner ruling, #67).
const ARRIVE := 540  ## 9:00
const BREAK := 630  ## 10:30
const LUNCH := 720  ## 12:00
const LEAVE := 1020  ## 17:00
const BREAK_LENGTH := 15  ## Minutes, then back to work.
const LUNCH_LENGTH := 60  ## Minutes, then back to work.
const ARRIVAL_SPREAD := 15  ## Each person arrives 0 to this many minutes late, drawn once from the seeded RNG.

## Where a plan entry sends a person. Break and lunch are at the work room until food rooms exist.
const DEST_HOME := 0
const DEST_WORK := 1
const DEST_BREAK := 2
const DEST_LUNCH := 3

const TRIP_IDLE := 0  ## At the goal.
const TRIP_REQUESTED := 1  ## The goal changed; waiting for the router to start moving.
const TRIP_MOVING := 2  ## Routing has the person in transit.

const STRESS_MAX := 300
const FIELDS := 8  ## Per person: id, home, work, offset, goal, trip_state, location, stress.
const _ID := 0
const _HOME := 1
const _WORK := 2
const _OFFSET := 3
const _GOAL := 4
const _TRIP := 5
const _LOCATION := 6
const _STRESS := 7

var _next_id: int = 0
var _last_minute: int = -1  ## The last minute of day the plan was checked at.
var _data: Array[int] = []  ## Flat: FIELDS ints per person, in id order.


func count() -> int:
	return _data.size() / FIELDS


## Adds a person living in home and working in work (room ids or NONE), starting at home (or at
## work if homeless). Draws their arrival offset from rng. Returns the person's id.
func add_person(home: int, work: int, rng: Object) -> int:
	var id := _next_id
	_next_id += 1
	var start := home if home != NONE else work
	var goal := DEST_HOME if home != NONE else DEST_WORK
	var offset: int = rng.next_below(ARRIVAL_SPREAD + 1)
	_data.append_array([id, home, work, offset, goal, TRIP_IDLE, start, 0] as Array[int])
	return id


## Index of the person with this id, or -1.
func index_of(id: int) -> int:
	for i in count():
		if _data[i * FIELDS + _ID] == id:
			return i
	return -1


func id_at(i: int) -> int:
	return _data[i * FIELDS + _ID]


func home_of(i: int) -> int:
	return _data[i * FIELDS + _HOME]


func work_of(i: int) -> int:
	return _data[i * FIELDS + _WORK]


func goal_of(i: int) -> int:
	return _data[i * FIELDS + _GOAL]


func trip_state(i: int) -> int:
	return _data[i * FIELDS + _TRIP]


## The room the person is in (NONE while travelling between rooms).
func location_of(i: int) -> int:
	return _data[i * FIELDS + _LOCATION]


func stress_of(i: int) -> int:
	return _data[i * FIELDS + _STRESS]


## Sets stress, clamped to 0 to STRESS_MAX.
func set_stress(i: int, value: int) -> void:
	_data[i * FIELDS + _STRESS] = clampi(value, 0, STRESS_MAX)


func add_stress(i: int, amount: int) -> void:
	set_stress(i, stress_of(i) + amount)


## The room a goal means for this person, or NONE.
func goal_room(i: int) -> int:
	return home_of(i) if goal_of(i) == DEST_HOME else work_of(i)


## The person's day plan for a clock day (Clock.WD1, WD2 or WE) as [minute, destination] pairs in
## time order. Only people with a work room have one; the weekend plan is empty. Derived, not stored.
func day_plan(i: int, day: int) -> Array[Array]:
	var plan: Array[Array] = []
	if work_of(i) == NONE or day == Clock.WE:
		return plan
	var arrive := ARRIVE + _data[i * FIELDS + _OFFSET]
	plan.append([arrive, DEST_WORK] as Array[int])
	plan.append([BREAK, DEST_BREAK] as Array[int])
	plan.append([BREAK + BREAK_LENGTH, DEST_WORK] as Array[int])
	plan.append([LUNCH, DEST_LUNCH] as Array[int])
	plan.append([LUNCH + LUNCH_LENGTH, DEST_WORK] as Array[int])
	plan.append([LEAVE, DEST_HOME] as Array[int])
	return plan


## Called once per tick after the clock. Plan entries whose minute fell in (last checked, now] fire:
## the person's goal changes, and if it is a different room a trip is requested. A drop in the
## minute of day means midnight passed, so the check restarts from the start of the day.
func tick(clock: Clock) -> void:
	var minute := clock.minute_of_day()
	if minute == _last_minute:
		return
	var from := _last_minute if minute > _last_minute else -1
	_last_minute = minute
	for i in count():
		for entry in day_plan(i, clock.day_of_week()):
			if entry[0] > from and entry[0] <= minute:
				_data[i * FIELDS + _GOAL] = entry[1]
				if goal_room(i) != location_of(i):
					_data[i * FIELDS + _TRIP] = TRIP_REQUESTED


## Routing seam: marks a requested trip as under way (the person is between rooms).
func start_trip(i: int) -> void:
	_data[i * FIELDS + _TRIP] = TRIP_MOVING
	_data[i * FIELDS + _LOCATION] = NONE


## Routing seam: the person arrives at their goal room.
func finish_trip(i: int) -> void:
	_data[i * FIELDS + _TRIP] = TRIP_IDLE
	_data[i * FIELDS + _LOCATION] = goal_room(i)


## Flat ints for hashing and saving: next id, last minute, count, then the people.
func state_ints() -> Array[int]:
	var ints: Array[int] = [_next_id, _last_minute, count()]
	ints.append_array(_data)
	return ints


static func valid_ints(ints: Array) -> bool:
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	if ints.size() < 3 or ints[0] < 0 or ints[1] < -1 or ints[1] >= Clock.MINUTES_PER_DAY or ints[2] < 0:
		return false
	if ints.size() != 3 + FIELDS * ints[2] or ints[0] < ints[2]:
		return false
	var previous_id := -1
	for p in ints[2]:
		var b: int = 3 + p * FIELDS
		if ints[b + _ID] <= previous_id or ints[b + _ID] >= ints[0]:
			return false
		previous_id = ints[b + _ID]
		if ints[b + _GOAL] < DEST_HOME or ints[b + _GOAL] > DEST_LUNCH or ints[b + _TRIP] < TRIP_IDLE or ints[b + _TRIP] > TRIP_MOVING:
			return false
		if ints[b + _OFFSET] < 0 or ints[b + _OFFSET] > ARRIVAL_SPREAD or ints[b + _STRESS] < 0 or ints[b + _STRESS] > STRESS_MAX:
			return false
		for field in [_HOME, _WORK, _LOCATION]:
			if ints[b + field] < NONE:
				return false
	return true


func load_ints(ints: Array) -> void:
	_next_id = ints[0]
	_last_minute = ints[1]
	_data = []
	for i in range(3, ints.size()):
		_data.append(ints[i])
