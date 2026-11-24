class_name Festival
extends RefCounted
## Street festival (M9 9.12, #474): our own event, no original equivalent. Integers only.
##
## When it happens: its own PCG32 stream (seed XOR SEED_SALT), one draw when WD2 begins (the weekday before the weekend),
## whatever else is true. A draw of 0 in `one_in` (1 in 4) arms a festival when the tower has MIN_STARS stars and
## MIN_SHOPS food or shop rooms, it is not the fourth quarter (the fly-past owns Q4) and the year's cap is not used up
## (YEARLY_CAP a year: with three weekends a year outside Q4 that is about once a year). While armed on WD2 the card opens
## (Events.open, manual kind 106, floor 1: the lobby is where the crowd lands) and stays open until 04:00 that night, so the
## owner can answer all day; the weekend begins at 05:00.
##
## The card's choices (0 is the default, taken at the timeout):
##   0 ignore   the crowd comes anyway: outside visitors +IGNORE_PERCENT on the weekend day.
##   1 sponsor  SPONSOR_COST dollars: +SPONSOR_PERCENT.
## The boost is full for food and shops (fast food, restaurant, retail) and half for the other kinds that draw outside visitors.
## Commerce reads boost_percent when a meal's outside visitors arrive; it is applied before the rain's cut, both
## multiplicatively (Weather.cut), so a rainy festival is smaller than a dry one but never negative. Extra visitors still need
## a seat: the per-room customer caps (seats per meal) hold. They are NOT outside visitors in the population sense: they are
## counted apart (Commerce.festival_today) and never reach visitors_inside, visitors_today, population or the stars (owner
## ruling, #456).
##
## "The crowd loads the lobby and the ground elevators": each minute of the festival day, everyone waiting in a hall queue on
## floor 1 gains QUEUE_STRESS (ignore) or SPONSOR_QUEUE_STRESS (sponsor), so an unprepared tower sees stress offset the takings.
## UNVERIFIED tunable.
##
## Saved: the stream, the phase, the open card's id, the level (0 none, 1 ignore, 2 sponsor), whether a festival is armed for
## WD2, and the year and count of festivals held (for the yearly cap). The yearly numbers are UNVERIFIED tunables.

const EventsScript := preload("res://scripts/sim/events.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const Rng := preload("res://scripts/sim/sim_rng.gd")

const SEED_SALT := 0x46455354  ## "FEST".
const KIND := 106
const MIN_STARS := 3
const MIN_SHOPS := 4
const ONE_IN := 4  ## A WD2 rolls this for a festival that weekend.
const YEARLY_CAP := 1
const SPONSOR_COST := 50000
const SPONSOR_PERCENT := 60
const IGNORE_PERCENT := 20
const OTHER_KINDS_SHARE := 50  ## Percent of the boost kinds other than food and shops get.
const FULL_KINDS: Array[String] = ["fast_food", "restaurant", "retail"]
const QUEUE_STRESS := 1  ## Per minute, for each person queued at floor 1 on the festival day (ignored).
const SPONSOR_QUEUE_STRESS := 2  ## The same when sponsored: a bigger crowd.
const DEADLINE_MINUTE := 240  ## 04:00 on the night before: the card is answered before the weekend begins.
const LOBBY_FLOOR := 1
const DEFAULT_STREAM := 0x2545F4914F6CDD1D  ## A mixed state: a tiny one (0) draws 0 first. A migrated old save starts its stream here (save_migration.gd, v48 to v49).

const IDLE := 0
const NOTICE := 1  ## The card is open or answered, the weekend not here yet.
const ACTIVE := 2  ## It is the festival day.

const CHOICE_IGNORE := 0
const CHOICE_SPONSOR := 1
const LEVEL_NONE := 0
const LEVEL_IGNORE := 1
const LEVEL_SPONSOR := 2

var one_in: int = ONE_IN  ## A test sets 1 to force one.
var _rooms: RoomsScript
var _rng := Rng.new()
var _phase: int = IDLE
var _event: int = 0
var _level: int = LEVEL_NONE
var _armed: bool = false
var _year: int = 0
var _count: int = 0


func _init(rooms: RoomsScript) -> void:
	_rooms = rooms


func reseed(tower_seed: int) -> void:
	_rng.reseed(tower_seed ^ SEED_SALT)


## The save's ints at rest, with the stream at DEFAULT_STREAM (the migration step).
static func rest_ints() -> Array[int]:
	return [DEFAULT_STREAM, 0, 0, 0, 0, 0, 0] as Array[int]


func is_active() -> bool:
	return _phase == ACTIVE


## True from the announcement to the weekend.
func is_announced() -> bool:
	return _phase == NOTICE


## 0 none, 1 ignored, 2 sponsored: the crowd's size today.
func level() -> int:
	return _level if _phase == ACTIVE else LEVEL_NONE


## Festivals held in the given year (only the latest year is remembered).
func held_this_year(year: int) -> int:
	return _count if _year == year else 0


## Percent added to a shop kind's outside visitors right now: 0 outside a festival day.
func boost_percent(kind: String) -> int:
	if _phase != ACTIVE:
		return 0
	var full := SPONSOR_PERCENT if _level == LEVEL_SPONSOR else IGNORE_PERCENT
	return full if FULL_KINDS.has(kind) else full * OTHER_KINDS_SHARE / 100


## Count after the boost, in integers, rounded half up.
static func boost(count: int, percent: int) -> int:
	return (count * (100 + percent) + 50) / 100


## True when the tower has enough food and shop rooms for a festival.
func has_shops() -> bool:
	var n := 0
	for id in _rooms.room_ids():  # a finite list
		if FULL_KINDS.has(_rooms.kind_of(id)) and not _rooms.is_charred(id):
			n += 1
	return n >= MIN_SHOPS


func kind() -> Dictionary:
	return {"id": KIND, "class": EventsScript.ORDINARY, "manual": true, "choices": 2, "timeout": EventsScript.DAY_TICKS, "floor": LOBBY_FLOOR,
		"deadline_minute": DEADLINE_MINUTE, "default": CHOICE_IGNORE, "costs": [0, SPONSOR_COST], "title": "Street festival",
		"text": "A street festival is planned on the block this weekend. Sponsor it ($50,000) and outside visitors rise 60% on the day, food and shops most. Ignore it and they rise 20% anyway. Either way the crowd loads the lobby and the ground elevators, and waiting riders there get more stressed.",
		"labels": ["Ignore it", "Sponsor it ($50,000)"],
		"ignored": "The crowd comes anyway: outside visitors rise 20% on the weekend day."}


## Called once a tick after the clock. `slow` is true on the ticks the tower looks for a card to open.
func tick(clock: ClockScript, stars: int, people: PeopleScript, events: EventsScript, messages: MessagesScript, at_tick: int, slow: bool) -> void:
	if clock.day_started:
		if _phase == ACTIVE:
			_phase = IDLE
			_level = LEVEL_NONE
		var day := clock.day_of_week()
		if day == ClockScript.WD2:
			var draw := _rng.next_below(maxi(1, one_in))  # one draw a WD2, always
			_armed = draw == 0
		else:
			_armed = false
			if day == ClockScript.WE and _phase == NOTICE:
				_begin(events, messages, clock, at_tick)
	if _armed and _phase == IDLE and slow:
		_announce(clock, stars, events, messages, at_tick)
	if _phase == ACTIVE:
		_crowd_stress(clock, people)


func _announce(clock: ClockScript, stars: int, events: EventsScript, messages: MessagesScript, at_tick: int) -> void:
	if stars < MIN_STARS or clock.quarter() == ClockScript.QUARTERS_PER_YEAR or held_this_year(clock.year()) >= YEARLY_CAP or not has_shops():
		return
	var card := events.open(KIND, LOBBY_FLOOR, at_tick, clock)
	if card == 0:
		return  # the event list is full: try again on a later check
	_event = card
	_phase = NOTICE
	_armed = false
	messages.add(at_tick, MessagesScript.FESTIVAL_NOTICE)


func _begin(events: EventsScript, messages: MessagesScript, clock: ClockScript, at_tick: int) -> void:
	var choice := CHOICE_IGNORE
	for entry in events.resolved():  # a finite log
		if entry[0] == _event:
			choice = entry[2]
	if not events.event_of(_event).is_empty():
		events.withdraw(_event)  # still open at the weekend (it should have timed out): treated as ignored
	_event = 0
	_level = LEVEL_SPONSOR if choice == CHOICE_SPONSOR else LEVEL_IGNORE
	_phase = ACTIVE
	if _year != clock.year():
		_year = clock.year()
		_count = 0
	_count += 1
	messages.add(at_tick, MessagesScript.FESTIVAL_BEGAN, 1 if _level == LEVEL_SPONSOR else 0)


## Each minute of the festival day the crowd stresses those waiting for a car at the lobby.
func _crowd_stress(clock: ClockScript, people: PeopleScript) -> void:
	if clock.minutes_over_last(1) == 0:
		return  # no new sim minute this tick (read from the clock, so a load cannot repeat one)
	var amount := SPONSOR_QUEUE_STRESS if _level == LEVEL_SPONSOR else QUEUE_STRESS
	for id in _rooms.queued_on_floor(LOBBY_FLOOR):  # a finite list
		var i := people.index_of(id)
		if i != -1:
			people.add_stress(i, amount)


func state_ints() -> Array[int]:
	return [_rng.state, _phase, _event, _level, 1 if _armed else 0, _year, _count] as Array[int]


## What the state hash takes: nothing while no festival has been armed, announced or held.
func hash_ints() -> Array[int]:
	if _phase == IDLE and not _armed and _count == 0:
		return [] as Array[int]
	return state_ints().slice(1)


static func valid_ints(ints: Array) -> bool:
	if ints.size() != 7:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	return ints[1] >= IDLE and ints[1] <= ACTIVE and ints[2] >= 0 and ints[3] >= LEVEL_NONE and ints[3] <= LEVEL_SPONSOR and (ints[4] == 0 or ints[4] == 1) and ints[5] >= 0 and ints[6] >= 0


func load_ints(ints: Array) -> void:
	_rng.state = ints[0]
	_phase = ints[1]
	_event = ints[2]
	_level = ints[3]
	_armed = ints[4] == 1
	_year = ints[5]
	_count = ints[6]
