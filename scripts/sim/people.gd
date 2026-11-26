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

const DRAWN_ROW := 7  ## Ints per person in drawn_rows().
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

var _next_id: int = 0
var _last_minute: int = -1  ## The last minute of day the plan was checked at.
## Ids of people whose trip was requested since Grades last took them (derived, not saved): Grades marks a first trip from
## this list instead of scanning everyone every tick (#459). Grades drains it every tick and load clears it, so a
## request is never carried across a save.
var trip_requests: Array[int] = []
var _data: Array[int] = []  ## Flat: FIELDS ints per person, in id order.
var _index: Dictionary = {}  ## Person id -> index into _data / FIELDS. Derived (rebuilt on load and removal), not saved.
## Derived, never saved or hashed (#454). Both are conservative: a stale 1 or 0 only costs a visit, never a result.
var _wake: PackedInt32Array = PackedInt32Array()  ## Per person: tick() may skip them while the minute of day is below this (0: look now). Only ever set for a person tick() has found settled.
var _wake_day: int = -1  ## The day of the week the _wake minutes were worked out for.
## Per person, 1 unless they are idle with no stress and no retry cooldown, when Trips has nothing to do for them (#454).
var _active: PackedByteArray = PackedByteArray()
var _riding: int = 0  ## How many people are TRIP_RIDING, so Trips can skip its scans on a quiet tick.
const BREAK_END := BREAK + BREAK_LENGTH  ## The minute the break ends.
const LUNCH_END := LUNCH + LUNCH_LENGTH  ## The minute lunch ends.
const _NO_MORE_TODAY := Clock.MINUTES_PER_DAY  ## A wake minute no minute of the day reaches.


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
	_index[id] = count()
	_data.append_array([id, home, work, offset, goal, TRIP_IDLE, start, 0, 0, 0, NONE, 0, MOOD_START, 0] as Array[int])
	_wake.append(0)
	_active.append(0)
	return id


## The id the next added person will get, and a way to pass one by (assisted living picks a senior, #378).
func next_id() -> int:
	return _next_id


func skip_id() -> void:
	_next_id += 1


## Hotel seam: set by Tower to a Callable(room: int) -> bool that is true for hotel rooms. A guest
## stays put in their room, so the resident day plan (out 8:00, back 18:00) does not apply to them.
var guest_home: Callable = Callable()


## Adds a hotel guest of room, arriving from outside the tower: they start outside with their trip
## to the room already requested. Draws an arrival offset like add_person (to keep one draw per person).
func add_guest(room: int, rng: Object) -> int:
	var id := _next_id
	_next_id += 1
	var offset: int = rng.next_below(ARRIVAL_SPREAD + 1)
	_index[id] = count()
	_data.append_array([id, room, NONE, offset, DEST_HOME, TRIP_REQUESTED, NONE, 0, 0, 0, NONE, 0, MOOD_START, 0] as Array[int])
	_wake.append(0)
	_active.append(1)
	trip_requests.append(id)
	return id


## Removes everyone whose home or work is room (it was bulldozed or replaced), wherever they are,
## mid-trip included. Returns how many went. Keeps _data compact and in id order; ids are not
## reused. They vanish at once: no walk-out animation (a possible later improvement).
func remove_room(room: int) -> int:
	return remove_rooms({room: true})


## remove_room for every room id in rooms (a Dictionary used as a set), in one pass and one index rebuild: the same people go
## and the survivors keep their order. Hotel check-outs on a rush tick use it instead of one pass per room (#467).
func remove_rooms(rooms: Dictionary) -> int:
	var kept: Array[int] = []
	var removed := 0
	var run_start := 0  ## Start of the run of survivors not yet copied.
	var end := _data.size()
	var b := 0
	while b < end:
		if rooms.has(_data[b + _HOME]) or rooms.has(_data[b + _WORK]):
			removed += 1
			if b > run_start:
				kept.append_array(_data.slice(run_start, b))
			run_start = b + FIELDS
		b += FIELDS
	if removed == 0:
		return 0
	if run_start < end:
		kept.append_array(_data.slice(run_start, end))
	_data = kept
	_rebuild_index()
	return removed


## Removes one person by index (they leave town, retire from the tower, ...). Ids are not reused.
func remove_person(i: int) -> void:
	var b := i * FIELDS
	var kept: Array[int] = []
	kept.append_array(_data.slice(0, b))
	kept.append_array(_data.slice(b + FIELDS))
	_data = kept
	_rebuild_index()


## Moves a person's home to another room (a couple moving in together).
func set_home(i: int, room: int) -> void:
	_data[i * FIELDS + _HOME] = room
	_wake[i] = 0


## How many people work in this room.
func workers_in(room: int) -> int:
	var n := 0
	for i in count():
		if _data[i * FIELDS + _WORK] == room:
			n += 1
	return n


## Residents (people whose home is the room) in one room.
func homes_in(room: int) -> int:
	var n := 0
	for i in count():
		if _data[i * FIELDS + _HOME] == room:
			n += 1
	return n


## Workers per room, room id -> count, for callers that ask about many rooms at once.
func worker_counts() -> Dictionary:
	var counts: Dictionary = {}
	var n := _data.size()
	var b := _WORK
	while b < n:
		var room := _data[b]
		counts[room] = int(counts.get(room, 0)) + 1
		b += FIELDS
	return counts


const EVAL_ROW := 7  ## Ints per person in eval_rows().


## One row per person in index order, as EVAL_ROW ints: id, home, work, stress, mood, low days, location. A read-only
## copy built in one pass, so the daily evaluation reads a packed array instead of an accessor per field (#452).
func eval_rows() -> PackedInt64Array:
	var n := _data.size() / FIELDS
	var out := PackedInt64Array()
	out.resize(n * EVAL_ROW)
	var b := 0
	var o := 0
	while o < n * EVAL_ROW:
		out[o] = _data[b + _ID]
		out[o + 1] = _data[b + _HOME]
		out[o + 2] = _data[b + _WORK]
		out[o + 3] = _data[b + _STRESS]
		out[o + 4] = _data[b + _MOOD]
		out[o + 5] = _data[b + _LOW_DAYS]
		out[o + 6] = _data[b + _LOCATION]
		b += FIELDS
		o += EVAL_ROW
	return out


## Residents per room, room id -> count, for callers that ask about many rooms at once (#452).
func home_counts() -> Dictionary:
	var counts: Dictionary = {}
	var n := _data.size()
	var b := _HOME
	while b < n:
		var room := _data[b]
		counts[room] = int(counts.get(room, 0)) + 1
		b += FIELDS
	return counts


## Index of the person with this id, or -1.
func index_of(id: int) -> int:
	return _index.get(id, -1)


func _rebuild_index() -> void:
	_index = {}
	var n := count()
	_wake = PackedInt32Array()
	_wake.resize(n)
	_wake_day = -1
	_active = PackedByteArray()
	_active.resize(n)
	_riding = 0
	for i in n:
		var b := i * FIELDS
		var id := _data[b + _ID]
		if not _index.has(id):  # a repeated id keeps its first person, as the scan did
			_index[id] = i
		var trip := _data[b + _TRIP]
		if trip == TRIP_RIDING:
			_riding += 1
		_active[i] = 0 if trip == TRIP_IDLE and _data[b + _STRESS] == 0 and _data[b + _TRIP_LEFT] == 0 else 1


func id_at(i: int) -> int:
	return _data[i * FIELDS + _ID]


func home_of(i: int) -> int:
	return _data[i * FIELDS + _HOME]


func work_of(i: int) -> int:
	return _data[i * FIELDS + _WORK]


func goal_of(i: int) -> int:
	return _data[i * FIELDS + _GOAL]


## Hotel guests per home room in one pass (#467): [home room -> people inside it, home room -> true while one of them is on a
## trip that is moving or riding]. Everyone with a home counts, as Hotel._count_guests did with an accessor per field.
func home_presence() -> Array[Dictionary]:
	var inside := {}
	var moving := {}
	var end := _data.size()
	var b := 0
	while b < end:
		var home := _data[b + _HOME]
		if home != NONE:
			if _data[b + _LOCATION] == home:
				inside[home] = int(inside.get(home, 0)) + 1
			else:
				var trip := _data[b + _TRIP]
				if trip == TRIP_MOVING or trip == TRIP_RIDING:
					moving[home] = true
		b += FIELDS
	return [inside, moving]


func trip_state(i: int) -> int:
	return _data[i * FIELDS + _TRIP]


## The room the person is in (NONE while travelling between rooms).
func location_of(i: int) -> int:
	return _data[i * FIELDS + _LOCATION]


## People inside the tower now: everyone unless their location is NONE and they are not moving.
## Mid-trip counts (an arrival's trip starts outside but they are already inside).
func in_tower_count() -> int:
	var n := 0
	for b in range(0, _data.size(), FIELDS):
		if _data[b + _LOCATION] != NONE or _data[b + _TRIP] != TRIP_IDLE:
			n += 1
	return n


## Ids of the people in the tower now (in a room or on a trip), in index order: the people in_tower_count counts. One
## pass over the flat data, for Mood.note_event.
func inside_ids() -> Array[int]:
	var ids: Array[int] = []
	for b in range(0, _data.size(), FIELDS):
		if _data[b + _LOCATION] != NONE or _data[b + _TRIP] != TRIP_IDLE:
			ids.append(_data[b + _ID])
	return ids


## The people the view may draw (in a room or on a trip, not idle outside), one row each in index order,
## as DRAWN_ROW ints: index, id, trip state, location, work room, goal, stress. A read-only copy of the
## current state, built in one pass so the view reads a packed array instead of calling an accessor per
## field per person (#434).
func drawn_rows() -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := _data.size()
	var b := 0
	while b < n:
		var location := _data[b + _LOCATION]
		var trip := _data[b + _TRIP]
		if location != NONE or trip != TRIP_IDLE:
			out.append(b / FIELDS)
			out.append(_data[b + _ID])
			out.append(trip)
			out.append(location)
			out.append(_data[b + _WORK])
			out.append(_data[b + _GOAL])
			out.append(_data[b + _STRESS])
		b += FIELDS
	return out


func stress_of(i: int) -> int:
	return _data[i * FIELDS + _STRESS]


## Sets stress, clamped to 0 to STRESS_MAX.
func set_stress(i: int, value: int) -> void:
	var stress := clampi(value, 0, STRESS_MAX)
	_data[i * FIELDS + _STRESS] = stress
	if stress > 0:
		_active[i] = 1


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
	return _data[i * FIELDS + _MOOD]


## Sets mood, clamped to 0 to MOOD_MAX.
func set_mood(i: int, value: int) -> void:
	_data[i * FIELDS + _MOOD] = clampi(value, 0, MOOD_MAX)


## Consecutive days this person's mood has been low.
func low_days_of(i: int) -> int:
	return _data[i * FIELDS + _LOW_DAYS]


func set_low_days(i: int, days: int) -> void:
	_data[i * FIELDS + _LOW_DAYS] = maxi(0, days)


func trip_left(i: int) -> int:
	return _data[i * FIELDS + _TRIP_LEFT]


func trip_from(i: int) -> int:
	return _data[i * FIELDS + _TRIP_FROM]


func trip_total(i: int) -> int:
	return _data[i * FIELDS + _TRIP_TOTAL]


func add_stress(i: int, amount: int) -> void:
	set_stress(i, stress_of(i) + amount)


## The room a goal means for this person, or NONE.
func goal_room(i: int) -> int:
	match goal_of(i):
		DEST_HOME:
			return home_of(i)
		DEST_AWAY:
			return NONE
	return work_of(i)


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
	var arrive := ARRIVE + _data[i * FIELDS + _OFFSET]
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
	return _goal_at(_data[i * FIELDS + _WORK], _data[i * FIELDS + _HOME], _data[i * FIELDS + _OFFSET], day, minute)


## scheduled_goal for a person's fields, without building a plan: this runs for every person who is due a look each minute (#427).
func _goal_at(work: int, home: int, offset: int, day: int, minute: int) -> int:
	# The same answer as the last entry of day_plan(i, day) at or before the minute, entry by entry in list order.
	var goal := DEST_HOME
	if work == NONE:
		if home != NONE and not (guest_home.is_valid() and guest_home.call(home)):  # a resident
			if day == Clock.WE:
				if WEEKEND_OUT <= minute:
					goal = DEST_AWAY
				if WEEKEND_BACK <= minute:
					goal = DEST_HOME
			else:
				if RESIDENT_OUT <= minute:
					goal = DEST_AWAY
				if RESIDENT_BACK <= minute:
					goal = DEST_HOME
		return goal
	if day == Clock.WE:
		return goal
	if ARRIVE + offset <= minute:
		goal = DEST_WORK
	if BREAK <= minute:
		goal = DEST_BREAK
	if BREAK + BREAK_LENGTH <= minute:
		goal = DEST_WORK
	if LUNCH <= minute:
		goal = DEST_LUNCH
	if LUNCH + LUNCH_LENGTH <= minute:
		goal = DEST_WORK
	if LEAVE <= minute:
		goal = DEST_HOME
	return goal


## The first minute after this one at which _goal_at can give a different answer, or _NO_MORE_TODAY: the times of the
## day plan's entries (the same ones _goal_at compares against). tests/test_people.gd checks the two agree.
func _next_change(work: int, home: int, offset: int, day: int, minute: int) -> int:
	var next := _NO_MORE_TODAY
	if work == NONE:
		if home != NONE and not (guest_home.is_valid() and guest_home.call(home)):
			next = _first_after(minute, next, WEEKEND_OUT if day == Clock.WE else RESIDENT_OUT)
			next = _first_after(minute, next, WEEKEND_BACK if day == Clock.WE else RESIDENT_BACK)
	elif day != Clock.WE:
		next = _first_after(minute, next, ARRIVE + offset)
		next = _first_after(minute, next, BREAK)
		next = _first_after(minute, next, BREAK + BREAK_LENGTH)
		next = _first_after(minute, next, LUNCH)
		next = _first_after(minute, next, LUNCH + LUNCH_LENGTH)
		next = _first_after(minute, next, LEAVE)
	return next


## best, or t when t is after minute and earlier than best.
static func _first_after(minute: int, best: int, t: int) -> int:
	return t if t > minute and t < best else best


## Called once per tick after the clock. When the minute of day changes, every worker's goal is
## set from the schedule (so a worker who moves in mid-day, or on a weekend, is placed correctly),
## and if the goal room differs from where they are a trip is requested. People without a work
## room keep their goal.
func tick(clock: Clock) -> void:
	var minute := clock.minute_of_day()
	if minute == _last_minute:
		return
	var day := clock.day_of_week()
	if minute < _last_minute or day != _wake_day:  # a new day, or the clock was set elsewhere: nobody's wake minute holds
		_wake.fill(0)
		_wake_day = day
	_last_minute = minute
	# Only people due a look are visited (#454), in index order as the full scan was. Someone settled (at the room their goal
	# means, or on a trip) is skipped until their plan next changes; anything that could unsettle them resets _wake to 0.
	var d := _data
	var wake := _wake
	var n := wake.size()
	for i in n:
		if wake[i] > minute:
			continue
		var b := i * FIELDS
		var work := d[b + _WORK]
		var home := d[b + _HOME]
		if work == NONE and home == NONE:
			wake[i] = _NO_MORE_TODAY
			continue
		var offset := d[b + _OFFSET]
		var goal: int
		var weekday_worker := work != NONE and day != Clock.WE
		if weekday_worker:  # _goal_at's chain for a weekday worker, inline: the exodus visits thousands of people in one minute
			goal = DEST_HOME
			var arrive := ARRIVE + offset
			if arrive <= minute:
				goal = DEST_WORK
			if BREAK <= minute:
				goal = DEST_BREAK
			if BREAK_END <= minute:
				goal = DEST_WORK
			if LUNCH <= minute:
				goal = DEST_LUNCH
			if LUNCH_END <= minute:
				goal = DEST_WORK
			if LEAVE <= minute:
				goal = DEST_HOME
		else:
			goal = _goal_at(work, home, offset, day, minute)
		if goal != d[b + _GOAL]:
			d[b + _GOAL] = goal
		var room := home if goal == DEST_HOME else (NONE if goal == DEST_AWAY else work)
		var settled := room == d[b + _LOCATION]
		if not settled:
			if d[b + _TRIP] != TRIP_IDLE:
				settled = true
			elif d[b + _TRIP_LEFT] == 0:
				d[b + _TRIP] = TRIP_REQUESTED
				_active[i] = 1
				trip_requests.append(d[b + _ID])
				settled = true
		if not settled:
			wake[i] = 0
		elif weekday_worker:  # _next_change's weekday worker branch, inline
			var next := _NO_MORE_TODAY
			var t := ARRIVE + offset
			if t > minute and t < next:
				next = t
			if BREAK > minute and BREAK < next:
				next = BREAK
			if BREAK_END > minute and BREAK_END < next:
				next = BREAK_END
			if LUNCH > minute and LUNCH < next:
				next = LUNCH
			if LUNCH_END > minute and LUNCH_END < next:
				next = LUNCH_END
			if LEAVE > minute and LEAVE < next:
				next = LEAVE
			wake[i] = next
		else:
			wake[i] = _next_change(work, home, offset, day, minute)


## Sets a person's trip state, keeping the riding count and the derived skip marks current (#454). Anything that changes
## where a person is or whether they are travelling goes through here, so tick() looks at them again.
func _set_trip(i: int, state: int) -> void:
	var at := i * FIELDS + _TRIP
	if _data[at] == TRIP_RIDING:
		_riding -= 1
	if state == TRIP_RIDING:
		_riding += 1
	_data[at] = state
	_wake[i] = 0
	_active[i] = 1


## Routing seam: marks a requested trip as under way (the person is between rooms).
func start_trip(i: int, minutes: int = 1) -> void:
	_data[i * FIELDS + _TRIP_FROM] = location_of(i)
	_set_trip(i, TRIP_MOVING)
	_data[i * FIELDS + _TRIP_LEFT] = minutes
	_data[i * FIELDS + _TRIP_TOTAL] = minutes
	_data[i * FIELDS + _TRIP_LEG] = 0
	_data[i * FIELDS + _LOCATION] = NONE


func trip_leg(i: int) -> int:
	return _data[i * FIELDS + _TRIP_LEG]


## Trips seam: the person walks the stretch of the route starting at leg for minutes.
func set_segment(i: int, leg: int, minutes: int) -> void:
	_set_trip(i, TRIP_MOVING)
	_data[i * FIELDS + _TRIP_LEG] = leg
	_data[i * FIELDS + _TRIP_LEFT] = minutes
	_data[i * FIELDS + _TRIP_TOTAL] = minutes


## Trips seam: the person waits for or rides the elevator leg.
func set_riding(i: int, leg: int) -> void:
	_set_trip(i, TRIP_RIDING)
	_data[i * FIELDS + _TRIP_LEG] = leg
	_data[i * FIELDS + _TRIP_LEFT] = 0


## Routing seam: the person arrives at their goal room.
func finish_trip(i: int) -> void:
	_set_trip(i, TRIP_IDLE)
	_data[i * FIELDS + _TRIP_LEFT] = 0
	_data[i * FIELDS + _TRIP_TOTAL] = 0
	_data[i * FIELDS + _TRIP_LEG] = 0
	_data[i * FIELDS + _LOCATION] = goal_room(i)


## Trips seam: the person spends one minute of the trip. Returns the minutes left.
func spend_trip_minute(i: int) -> int:
	_data[i * FIELDS + _TRIP_LEFT] = maxi(0, trip_left(i) - 1)
	return trip_left(i)


## Trips seam: the person gives up the requested trip and stays where they are; the retry
## waits cooldown minutes.
func give_up_trip(i: int, cooldown: int) -> void:
	if trip_state(i) != TRIP_REQUESTED:  # mid-trip (elevator lost): back to the room they left
		_data[i * FIELDS + _LOCATION] = trip_from(i)
	_set_trip(i, TRIP_IDLE)
	_active[i] = 1
	_data[i * FIELDS + _TRIP_LEFT] = cooldown
	_data[i * FIELDS + _TRIP_TOTAL] = 0
	_data[i * FIELDS + _TRIP_LEG] = 0


## How many people are waiting for or riding an elevator.
func riding_count() -> int:
	return _riding


## Indices of the people waiting for or riding an elevator, ascending.
func rider_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	if _riding == 0:
		return out
	var d := _data
	var b := _TRIP
	var n := d.size()
	while b < n:
		if d[b] == TRIP_RIDING:
			out.append((b - _TRIP) / FIELDS)
		b += FIELDS
	return out


## Indices, ascending, of everyone Trips has something to do for this minute: anyone on a trip, anyone with stress to shed
## or a retry cooldown to count down. The rest are idle at no stress, for whom a minute changes nothing (#454).
func active_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	var flags := _active
	for i in flags.size():
		if flags[i] != 0:
			out.append(i)
	return out


## Trips seam: an idle person's minute: the retry cooldown counts down and stress eases by recovery. The same as cool_down and
## add_stress(-recovery), and it drops the person from active_indices once there is nothing left to ease.
func recover_idle(i: int, recovery: int) -> void:
	var b := i * FIELDS
	var left := maxi(0, _data[b + _TRIP_LEFT] - 1)
	var stress := clampi(_data[b + _STRESS] - recovery, 0, STRESS_MAX)
	_data[b + _TRIP_LEFT] = left
	_data[b + _STRESS] = stress
	if left == 0 and stress == 0:
		_active[i] = 0


## Trips seam: counts an idle retry cooldown down.
func cool_down(i: int) -> void:
	_data[i * FIELDS + _TRIP_LEFT] = maxi(0, trip_left(i) - 1)


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
	_next_id = ints[0]
	_last_minute = ints[1]
	_data = []
	trip_requests.clear()
	for i in range(3, ints.size()):
		_data.append(ints[i])
	_rebuild_index()
