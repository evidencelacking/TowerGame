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
## Resident hours (condos, 3.4): out to work from RESIDENT_OUT, back at RESIDENT_BACK, on weekdays.
## On the weekend (#274) they stay home except a short outing from WEEKEND_OUT to WEEKEND_BACK.
## Guesses, tunable.
const RESIDENT_OUT := 480  ## 8:00
const RESIDENT_BACK := 1080  ## 18:00
const WEEKEND_OUT := 660  ## 11:00
const WEEKEND_BACK := 900  ## 15:00
const BREAK_LENGTH := 15  ## Minutes, then back to work.
const LUNCH_LENGTH := 60  ## Minutes, then back to work.
const ARRIVAL_SPREAD := 15  ## Each person arrives 0 to this many minutes late, drawn once from the seeded RNG.

## Where a plan entry sends a person. Break and lunch are at the work room until food rooms exist.
const DEST_HOME := 0
const DEST_WORK := 1
const DEST_BREAK := 2
const DEST_LUNCH := 3
const DEST_AWAY := 4  ## Outside the tower (residents at work elsewhere).

const TRIP_IDLE := 0  ## At the goal.
const TRIP_REQUESTED := 1  ## The goal changed; waiting for the router to start moving.
const TRIP_MOVING := 2  ## Routing has the person in transit.
const TRIP_RIDING := 3  ## Waiting for or riding an elevator; trips.gd ends it when they alight (#95).

const STRESS_MAX := 300
const MOOD_MAX := 100
const MOOD_START := 75  ## A new person arrives fairly content.
## Stress bands (3.6, docs/gameplay-reference.md): under 80 calm, 80 to 120 uneasy, over 120 angry.
const BAND_CALM := 0
const BAND_UNEASY := 1
const BAND_ANGRY := 2
const UNEASY_FROM := 80  ## Stress at or above this is uneasy.
const ANGRY_OVER := 120  ## Stress above this is angry.

const FIELDS := 14  ## Per person: id, home, work, offset, goal, trip_state, location, stress, trip_left, trip_total, trip_from, trip_leg, mood, low_days.
const _ID := 0
const _HOME := 1
const _WORK := 2
const _OFFSET := 3
const _GOAL := 4
const _TRIP := 5
const _LOCATION := 6
const _STRESS := 7
const _TRIP_LEFT := 8  ## Minutes of travel left while moving; while idle, minutes before a given-up trip is retried.
const _TRIP_TOTAL := 9  ## Minutes the current trip takes in all (for drawing).
const _TRIP_FROM := 10  ## Room the current trip started in, or NONE for outside (for drawing).
const _MOOD := 12  ## 0 to MOOD_MAX; moves once a day (mood.gd).
const _LOW_DAYS := 13  ## Consecutive days the mood has been low (mood.gd).
const _TRIP_LEG := 11  ## Route leg the person is on: the first leg of the walking stretch, or the elevator leg.

var _core := PeopleCore.new()  ## C# (spike #422): the flat data and the hot loops.


func count() -> int:
	return _core.Count()

## Adds a person living in home and working in work (room ids or NONE), starting at home (or at
## work if homeless). Draws their arrival offset from rng. Returns the person's id.
func add_person(home: int, work: int, rng: Object) -> int:
	var start := home if home != NONE else work
	var goal := DEST_HOME if home != NONE else DEST_WORK
	var offset: int = rng.next_below(ARRIVAL_SPREAD + 1)
	return _core.AddRow(home, work, offset, goal, TRIP_IDLE, start)

## Hotel seam: set by Tower to a Callable(room: int) -> bool that is true for hotel rooms. A guest
## stays put in their room, so the resident day plan (out 8:00, back 18:00) does not apply to them.
var guest_home: Callable = Callable()


## Adds a hotel guest of room, arriving from outside the tower: they start outside with their trip
## to the room already requested. Draws an arrival offset like add_person (to keep one draw per person).
func add_guest(room: int, rng: Object) -> int:
	var offset: int = rng.next_below(ARRIVAL_SPREAD + 1)
	return _core.AddRow(room, NONE, offset, DEST_HOME, TRIP_REQUESTED, NONE)

## Removes everyone whose home or work is room (it was bulldozed or replaced), wherever they are,
## mid-trip included. Returns how many went. Keeps _data compact and in id order; ids are not
## reused. They vanish at once: no walk-out animation (a possible later improvement).
func remove_room(room: int) -> int:
	return _core.RemoveRoom(room)

## Removes one person by index (they leave town, retire from the tower, ...). Ids are not reused.
func remove_person(i: int) -> void:
	_core.RemovePerson(i)

## Moves a person's home to another room (a couple moving in together).
func set_home(i: int, room: int) -> void:
	_core.SetHome(i, room)

## How many people work in this room.
func workers_in(room: int) -> int:
	return _core.WorkersIn(room)

## Workers per room, room id -> count, for callers that ask about many rooms at once.
func worker_counts() -> Dictionary:
	return _core.WorkerCounts()

## Index of the person with this id, or -1.
func index_of(id: int) -> int:
	return _core.IndexOf(id)

func _rebuild_index() -> void:
	pass

func id_at(i: int) -> int:
	return _core.IdAt(i)

func home_of(i: int) -> int:
	return _core.HomeOf(i)

func work_of(i: int) -> int:
	return _core.WorkOf(i)

func goal_of(i: int) -> int:
	return _core.GoalOf(i)

func trip_state(i: int) -> int:
	return _core.TripState(i)

## The room the person is in (NONE while travelling between rooms).
func location_of(i: int) -> int:
	return _core.LocationOf(i)

## People inside the tower now: everyone unless their location is NONE and they are not moving.
## Mid-trip counts (an arrival's trip starts outside but they are already inside).
func in_tower_count() -> int:
	return _core.InTowerCount()

func stress_of(i: int) -> int:
	return _core.StressOf(i)

## Sets stress, clamped to 0 to STRESS_MAX.
func set_stress(i: int, value: int) -> void:
	_core.SetStress(i, value)

## The stress band for a stress value: BAND_CALM, BAND_UNEASY or BAND_ANGRY.
static func band_of(stress: int) -> int:
	if stress > ANGRY_OVER:
		return BAND_ANGRY
	if stress >= UNEASY_FROM:
		return BAND_UNEASY
	return BAND_CALM


func stress_band(i: int) -> int:
	return band_of(stress_of(i))


func mood_of(i: int) -> int:
	return _core.MoodOf(i)

## Sets mood, clamped to 0 to MOOD_MAX.
func set_mood(i: int, value: int) -> void:
	_core.SetMood(i, value)

## Consecutive days this person's mood has been low.
func low_days_of(i: int) -> int:
	return _core.LowDaysOf(i)

func set_low_days(i: int, days: int) -> void:
	_core.SetLowDays(i, days)

func trip_left(i: int) -> int:
	return _core.TripLeft(i)

func trip_from(i: int) -> int:
	return _core.TripFrom(i)

func trip_total(i: int) -> int:
	return _core.TripTotal(i)

func add_stress(i: int, amount: int) -> void:
	_core.AddStress(i, amount)

## The room a goal means for this person, or NONE.
func goal_room(i: int) -> int:
	return _core.GoalRoom(i)

## The person's day plan for a clock day (Clock.WD1, WD2 or WE) as [minute, destination] pairs in
## time order. A worker's weekend plan is empty; a resident's is a short outing. Derived, not stored.
func day_plan(i: int, day: int) -> Array[Array]:
	var plan: Array[Array] = []
	if work_of(i) == NONE:
		if home_of(i) != NONE and not (guest_home.is_valid() and guest_home.call(home_of(i))):  # a resident
			if day == Clock.WE:
				plan.append([WEEKEND_OUT, DEST_AWAY] as Array[int])
				plan.append([WEEKEND_BACK, DEST_HOME] as Array[int])
			else:
				plan.append([RESIDENT_OUT, DEST_AWAY] as Array[int])
				plan.append([RESIDENT_BACK, DEST_HOME] as Array[int])
		return plan
	if day == Clock.WE:
		return plan
	var arrive := ARRIVE + _core.OffsetOf(i)
	plan.append([arrive, DEST_WORK] as Array[int])
	plan.append([BREAK, DEST_BREAK] as Array[int])
	plan.append([BREAK + BREAK_LENGTH, DEST_WORK] as Array[int])
	plan.append([LUNCH, DEST_LUNCH] as Array[int])
	plan.append([LUNCH + LUNCH_LENGTH, DEST_WORK] as Array[int])
	plan.append([LEAVE, DEST_HOME] as Array[int])
	return plan


## The destination the day plan puts this person at, at a minute of a clock day. Before the first
## entry (and all weekend) a worker is away: DEST_HOME, which is outside the tower (NONE) for
## office workers. Break and lunch are the single seam for food rooms (#74): today both resolve to
## the work room in goal_room, so people stay at their desks.
func scheduled_goal(i: int, day: int, minute: int) -> int:
	return _core.ScheduledGoalOf(i, day, minute, Clock.WE, guest_home)

## Called once per tick after the clock. When the minute of day changes, every worker's goal is
## set from the schedule (so a worker who moves in mid-day, or on a weekend, is placed correctly),
## and if the goal room differs from where they are a trip is requested. People without a work
## room keep their goal.
func tick(clock: Clock) -> void:
	_core.Tick(clock.minute_of_day(), clock.day_of_week(), Clock.WE, guest_home)

## Routing seam: marks a requested trip as under way (the person is between rooms).
func start_trip(i: int, minutes: int = 1) -> void:
	_core.StartTrip(i, minutes)

func trip_leg(i: int) -> int:
	return _core.TripLeg(i)

## Trips seam: the person walks the stretch of the route starting at leg for minutes.
func set_segment(i: int, leg: int, minutes: int) -> void:
	_core.SetSegment(i, leg, minutes)

## Trips seam: the person waits for or rides the elevator leg.
func set_riding(i: int, leg: int) -> void:
	_core.SetRiding(i, leg)

## Routing seam: the person arrives at their goal room.
func finish_trip(i: int) -> void:
	_core.FinishTrip(i)

## Trips seam: the person spends one minute of the trip. Returns the minutes left.
func spend_trip_minute(i: int) -> int:
	return _core.SpendTripMinute(i)

## Trips seam: the person gives up the requested trip and stays where they are; the retry
## waits cooldown minutes.
func give_up_trip(i: int, cooldown: int) -> void:
	_core.GiveUpTrip(i, cooldown)

## Trips seam: counts an idle retry cooldown down.
func cool_down(i: int) -> void:
	_core.CoolDown(i)

## Flat ints for hashing and saving: next id, last minute, count, then the people.
func state_ints() -> Array[int]:
	return _core.StateInts()

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
		if ints[b + _GOAL] < DEST_HOME or ints[b + _GOAL] > DEST_AWAY or ints[b + _TRIP] < TRIP_IDLE or ints[b + _TRIP] > TRIP_RIDING:
			return false
		if ints[b + _OFFSET] < 0 or ints[b + _OFFSET] > ARRIVAL_SPREAD or ints[b + _STRESS] < 0 or ints[b + _STRESS] > STRESS_MAX:
			return false
		if ints[b + _MOOD] < 0 or ints[b + _MOOD] > MOOD_MAX or ints[b + _LOW_DAYS] < 0:
			return false
		if ints[b + _TRIP_LEFT] < 0 or ints[b + _TRIP_TOTAL] < 0 or ints[b + _TRIP_LEG] < 0:
			return false
		for field in [_HOME, _WORK, _LOCATION, _TRIP_FROM]:
			if ints[b + field] < NONE:
				return false
	return true


func load_ints(ints: Array) -> void:
	_core.LoadInts(ints)