class_name Vip
extends RefCounted
## The VIP visit (7.8, #173): the check for the 4-star rating. A VIP stays one night in a suite and
## then gives a verdict. A good verdict is final and sets the star rule's vip_good fact; a bad one
## brings another VIP after RETRY_DAYS.
##
## A visit starts, at VISIT_MINUTE on a day on or after the retry day, when the tower has at least
## VISIT_STARS stars and a suite that is vacant, clean, free of pests, reachable (not "red" in the
## view), and the tower has a free parking space (Hotel.parking_free). The lowest-id such suite
## is reserved: Hotel books no guests into it (Hotel.reserved_room). The VIP leaves, and the
## verdict arrives, from VERDICT_MINUTE the next morning. If the suite is bulldozed meanwhile the
## visit is called off, and a new one is tried the next day.
##
## Verdict (owner ruling, #173): good when the suite is not graded C and the tower's quality is
## at least GOOD_FROM (the B line). Tower quality is the average quality of every graded room (offices,
## condos, hotel rooms; Grades.quality), by integer division. A vacant suite reads as the neutral B
## until guests have stayed in it, so in practice the tower's quality decides. No random draw is used.
##
## The arrival is a full event (#219). When a suite is found the VIP does not simply check in: an arrival notice
## opens as an event card (Events.open: a manual kind, so it makes no draw and shifts no fire or threat roll) and
## the suite is reserved at once. The player chooses: the standard rate (the stay pays the suite's nightly price at
## the verdict, like any guest), a discount (the stay pays nothing), or to turn the VIP away, which puts the visit off
## RETRY_DAYS days with no verdict. Left unanswered, the notice times out after NOTICE_TICKS to the standard rate (the
## kind's "default"): declining is a choice the player makes, never the timeout. A discount buys goodwill (#219
## ruling): the VIP overlooks one travel complaint, so a verdict whose only failing reason is the suite's travel or the
## tower's travel (exactly one of WHY_SUITE_TRAVEL, WHY_TOWER_TRAVEL) passes. Any other reason, or both travel
## reasons, still fails, and the standard rate forgives nothing.
##
## The verdict says why (#219): the message carries a mask of the factors the verdict actually used, so the log can
## say "the suite was poor: slow elevators" or "tower quality was low". See WHY_*.
##
## Helicopter arrival (#409): once a day the VIP's own seeded stream is drawn (always, so the stream never
## shifts); a draw under AIR_PERCENT with a reachable helipad means the visit arrives by air and needs no
## free parking space. The suite and verdict rules are unchanged.
##
## The VIP is not walked through the tower (no transport model for VIPs): the visit is a booking, a
## night and a verdict. The VIP holds no parking space. All numbers are UNVERIFIED tunables.
##
## Saved state: phase, reserved suite, visit day, next visit day, last verdict, visits so far, the stream state,
## the day of the last air draw and its result, the open notice's event id, the chosen rate, the last verdict's reasons.

const RoomsScript := preload("res://scripts/sim/rooms.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const GradesScript := preload("res://scripts/sim/grades.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const EventsScript := preload("res://scripts/sim/events.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const Rng := preload("res://scripts/sim/sim_rng.gd")

const VISIT_STARS := 3  ## No VIP comes before this star rating (the suite itself needs 3 stars).
const RETRY_DAYS := 3  ## After a bad verdict the next VIP comes this many days later.
const VISIT_MINUTE := 1080  ## 18:00: the VIP arrives (the hotel's check-in window opens).
const VISIT_WINDOW := 120  ## A tick may skip minutes, so a visit may start up to this many minutes late.
const VERDICT_MINUTE := 600  ## 10:00 the next morning: the VIP leaves and gives a verdict.
const GOOD_FROM := 150  ## Tower quality must reach this (the B line, which is acceptable) for a good verdict.
const SEED_SALT := 0x56495020  ## "VIP ".
const AIR_PERCENT := 50  ## Chance a visit arrives by helicopter when a reachable pad stands (#409).
const KIND := 103  ## The event kind id in Events.kinds (fire is 101, threat 102).
const NOTICE_TICKS := 240  ## About two game hours to answer the arrival notice; then the standard rate applies.
const DEFAULT_STREAM := 0  ## The stream state a migrated old save gets (save_migration.gd, v45 to v46).

## Phases.
const WAITING := 0  ## No VIP in the tower.
const VISITING := 1  ## A VIP is in the reserved suite.
const NOTICE := 2  ## The arrival notice is open and the suite is held, awaiting the player's choice.

## The notice's choices (Events: 0 declines).
const CHOICE_DECLINE := 0  ## Turn the VIP away: the visit is put off RETRY_DAYS days.
const CHOICE_STANDARD := 1  ## The stay pays the suite's nightly price.
const CHOICE_DISCOUNT := 2  ## The stay pays nothing.

## Why a verdict was bad: a mask of the factors the verdict used (saved, and sent in the message's b).
const WHY_SUITE_TRAVEL := 1  ## The suite graded C and its guest's travel stress alone put it under the B line.
const WHY_SUITE_OTHER := 2  ## The suite graded C because of rent, noise or complaints, not travel.
const WHY_TOWER_TRAVEL := 4  ## Tower quality was under the B line and travel alone would have put it there.
const WHY_TOWER_OTHER := 8  ## Tower quality was under the B line because of rent, noise or complaints.
const WHY_ALL := 15

## Verdicts.
const NONE := 0
const GOOD := 1
const BAD := 2

var _rooms: RoomsScript
var _hotel: HotelScript
var _phase: int = WAITING
var _suite: int = -1
var _visit_day: int = -1
var _next_day: int = 0  ## No visit before this day index (Hotel.night_of).
var _verdict: int = NONE
var _visits: int = 0
var _rng := Rng.new()  ## Its own seeded stream (#409): one draw a day, whatever else is true, so it never shifts.
var _roll_day: int = -1  ## The day the air-arrival draw was last made.
var _by_air: bool = false  ## That day's draw came up "by air".
var _event: int = 0  ## Id of the open arrival notice, 0 for none.
var _rate: int = 0  ## The chosen rate of the visit in progress: CHOICE_STANDARD or CHOICE_DISCOUNT, 0 for none.
var _why: int = 0  ## WHY_* mask of the last bad verdict, 0 after a good one.


func _init(rooms: RoomsScript, hotel: HotelScript) -> void:
	_rooms = rooms
	_hotel = hotel


func reseed(tower_seed: int) -> void:
	_rng.reseed(tower_seed ^ SEED_SALT)


## True when today's visit would arrive by helicopter: the day's draw said so and a reachable pad stands.
func arrives_by_air() -> bool:
	return _by_air and _rooms.helipad_reachable()


## The suite held for the VIP, or -1. Hotel reads this to keep the suite empty.
func reserved_suite() -> int:
	return _suite if _phase != WAITING else -1


## True from the arrival notice until the verdict: a VIP is in play and the suite is held.
func is_visiting() -> bool:
	return _phase != WAITING


## True while the arrival notice waits for the player's choice.
func awaiting_choice() -> bool:
	return _phase == NOTICE


## The rate of the visit in progress: CHOICE_STANDARD, CHOICE_DISCOUNT, or 0 before one is chosen.
func rate() -> int:
	return _rate if _phase == VISITING else 0


## Why the last verdict was bad: WHY_* bits, 0 for a good one or none yet.
func why() -> int:
	return _why


## The arrival notice's event kind (Events.kinds). Manual: Events never rolls it; open() starts it. The labels and
## text follow the held suite's nightly price.
func kind() -> Dictionary:
	return {"id": KIND, "class": EventsScript.ORDINARY, "manual": true, "choices": 3, "timeout": NOTICE_TICKS, "floor": 0,
		"default": CHOICE_STANDARD, "title": "VIP arrival", "dynamic": _live_texts,
		"ignored": "Nothing: the VIP is given the standard rate."}


func _live_texts() -> Dictionary:
	var price := _hotel.price(_suite) if _suite >= 1 and _rooms.has_room(_suite) else 0
	return {
		"text": "A VIP wants to stay one night in your suite and will give a verdict at 10:00 tomorrow. At the standard rate the stay pays $%d. A discount means it pays nothing, but the VIP will overlook one travel complaint. Turn the VIP away and the visit is put off %d days." % [price, RETRY_DAYS],
		"labels": ["Turn the VIP away", "Standard rate ($%d)" % price, "Offer a discount (free)"]}


## The verdict of the last visit: NONE, GOOD or BAD.
func verdict() -> int:
	return _verdict


## True once a good verdict has been given: the star rule's fact. Final.
func is_good() -> bool:
	return _verdict == GOOD


## Visits finished with a verdict, good or bad.
func visits() -> int:
	return _visits


## The day index the next visit may start on.
func next_day() -> int:
	return _next_day


## Average quality of the graded rooms (0 to 300), or the neutral quality when there are none.
static func tower_quality(rooms: RoomsScript, people: PeopleScript, grades: GradesScript) -> int:
	var total := 0
	var count := 0
	for id in rooms.room_ids():
		var quality := grades.quality(rooms, people, id)
		if quality >= 0:
			total += quality
			count += 1
	return total / count if count > 0 else GradesScript.NEUTRAL_QUALITY


## True when a suite can take the VIP now: vacant, clean, no pests, reachable.
func _eligible(suite: int) -> bool:
	return _hotel.state_of(suite) == HotelScript.VACANT and not _hotel.is_dirty(suite) \
		and not _hotel.is_infested(suite) and not _hotel.unreached(suite)


## Called every tick after the clock; acts when called (Tower runs it every SLOW_EVERY ticks); a run in the same minute changes nothing.
func tick(clock: ClockScript, stars: int, people: PeopleScript, grades: GradesScript, messages: MessagesScript, events: EventsScript, ledger: LedgerScript, grid: GridScript, at_tick: int) -> void:
	var minute := clock.minute_of_day()
	var day := HotelScript.night_of(clock)
	if day != _roll_day:  # one draw every day, with or without a pad, so the stream does not depend on the tower
		_roll_day = day
		_by_air = _rng.next_below(100) < AIR_PERCENT
	if _phase == NOTICE:
		_answered(day, events, messages, at_tick)
	if _phase == VISITING:
		_visiting(day, minute, people, grades, messages, ledger, at_tick)
	elif _phase == WAITING and _verdict != GOOD and day >= _next_day and stars >= VISIT_STARS and minute >= VISIT_MINUTE and minute < VISIT_MINUTE + VISIT_WINDOW:
		_start(day, events, grid, messages, at_tick)


## A suite is found: hold it and open the arrival notice. If the event list is full nothing starts, and a later tick
## in the window asks again.
func _start(day: int, events: EventsScript, grid: GridScript, messages: MessagesScript, at_tick: int) -> void:
	if _hotel.parking_free() <= 0 and not arrives_by_air():  # a helicopter needs no parking space (#409)
		return
	for suite in _hotel.suites():  # a finite list, so the loop ends
		if _eligible(suite):
			var floors := _rooms.floors_of(grid, suite)
			_event = events.open(KIND, floors[0] if not floors.is_empty() else 0, at_tick)
			if _event == 0:
				return
			_phase = NOTICE
			_suite = suite
			_visit_day = day
			messages.add(at_tick, MessagesScript.VIP_ARRIVED, suite)
			return


## Reads the player's answer (or the timeout's default) from the resolved log, once the notice has left the open list.
func _answered(day: int, events: EventsScript, messages: MessagesScript, at_tick: int) -> void:
	if not _rooms.has_room(_suite) or not _hotel.is_suite(_suite):  # bulldozed while the notice was open: call it off
		events.withdraw(_event)
		_call_off(day)
		return
	if not events.event_of(_event).is_empty():
		return
	var choice := CHOICE_STANDARD  # the kind's default, should the log have lost the entry
	for entry in events.resolved():  # a finite log
		if entry[0] == _event:
			choice = entry[2]
	_event = 0
	if choice == CHOICE_DECLINE:
		messages.add(at_tick, MessagesScript.VIP_DECLINED, _suite)
		_phase = WAITING
		_suite = -1
		_next_day = day + RETRY_DAYS
		return
	_rate = CHOICE_DISCOUNT if choice == CHOICE_DISCOUNT else CHOICE_STANDARD
	_phase = VISITING


func _call_off(day: int) -> void:
	_phase = WAITING
	_suite = -1
	_event = 0
	_rate = 0
	_next_day = day + 1


func _visiting(day: int, minute: int, people: PeopleScript, grades: GradesScript, messages: MessagesScript, ledger: LedgerScript, at_tick: int) -> void:
	if not _rooms.has_room(_suite) or not _hotel.is_suite(_suite):  # bulldozed: the visit is called off
		_call_off(day)
		return
	if day <= _visit_day or minute < VERDICT_MINUTE:
		return
	var reasons := verdict_reasons(_rooms, people, grades, _suite)
	var forgiven := _rate == CHOICE_DISCOUNT and forgiven_by_discount(reasons)
	var good := reasons == 0 or forgiven
	_verdict = GOOD if good else BAD
	_why = 0 if good else reasons
	_visits += 1
	_next_day = day + RETRY_DAYS
	if _rate == CHOICE_STANDARD:  # the stay pays its nightly price at departure, like any guest
		ledger.hotel(at_tick, _hotel.price(_suite), _suite)
	messages.add(at_tick, MessagesScript.VIP_GOOD if good else MessagesScript.VIP_BAD, _suite, reasons)
	_phase = WAITING
	_suite = -1
	_rate = 0


## True when a discount forgives these WHY_* reasons: exactly one travel bit and nothing else.
static func forgiven_by_discount(reasons: int) -> bool:
	return reasons == WHY_SUITE_TRAVEL or reasons == WHY_TOWER_TRAVEL


## The WHY_* factors that made the verdict bad, 0 when it is good: the suite graded C and the tower's quality under
## GOOD_FROM, each split by whether travel stress alone explains it. Exactly the two tests the verdict uses.
static func verdict_reasons(rooms: RoomsScript, people: PeopleScript, grades: GradesScript, suite: int) -> int:
	var why := 0
	if grades.grade(rooms, people, suite) == GradesScript.GRADE_C:
		var travel := grades.average_stress(rooms, people, suite)
		why |= WHY_SUITE_TRAVEL if travel >= 0 and PeopleScript.STRESS_MAX - travel < GOOD_FROM else WHY_SUITE_OTHER
	if tower_quality(rooms, people, grades) < GOOD_FROM:
		var total := 0
		var count := 0
		for id in rooms.room_ids():  # a finite list
			if grades.quality(rooms, people, id) >= 0:
				var travel := grades.average_stress(rooms, people, id)
				total += PeopleScript.STRESS_MAX - travel if travel >= 0 else GradesScript.NEUTRAL_QUALITY
				count += 1
		why |= WHY_TOWER_TRAVEL if count > 0 and total / count < GOOD_FROM else WHY_TOWER_OTHER
	return why


func state_ints() -> Array[int]:
	return [_phase, _suite, _visit_day, _next_day, _verdict, _visits, _rng.state, _roll_day, 1 if _by_air else 0, _event, _rate, _why]


## What the state hash takes: the saved ints, but the three #219 fields only once they are not at rest, so a tower
## that has had no VIP notice hashes exactly as before them.
func hash_ints() -> Array[int]:
	var ints := state_ints()
	if _event == 0 and _rate == 0 and _why == 0:
		return ints.slice(0, 9)
	return ints


static func valid_ints(ints: Array) -> bool:
	if ints.size() != 12:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	if ints[0] < WAITING or ints[0] > NOTICE:
		return false
	if ints[0] != WAITING and ints[1] < 1:
		return false
	if ints[0] == NOTICE and ints[9] < 1:
		return false
	if ints[9] < 0 or ints[10] < 0 or ints[10] > CHOICE_DISCOUNT or ints[11] < 0 or ints[11] > WHY_ALL:
		return false
	return ints[3] >= 0 and ints[4] >= NONE and ints[4] <= BAD and ints[5] >= 0 and ints[7] >= -1 and (ints[8] == 0 or ints[8] == 1)


func load_ints(ints: Array) -> void:
	_phase = ints[0]
	_suite = ints[1]
	_visit_day = ints[2]
	_next_day = ints[3]
	_verdict = ints[4]
	_visits = ints[5]
	_rng.state = ints[6]
	_roll_day = ints[7]
	_by_air = ints[8] == 1
	_event = ints[9]
	_rate = ints[10]
	_why = ints[11]
