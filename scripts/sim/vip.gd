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
## The VIP is not walked through the tower (no transport model for VIPs): the visit is a booking, a
## night and a verdict. The VIP holds no parking space. All numbers are UNVERIFIED tunables.
##
## Saved state: phase, reserved suite, visit day, next visit day, last verdict, visits so far.

const RoomsScript := preload("res://scripts/sim/rooms.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const GradesScript := preload("res://scripts/sim/grades.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")

const VISIT_STARS := 3  ## No VIP comes before this star rating (the suite itself needs 3 stars).
const RETRY_DAYS := 3  ## After a bad verdict the next VIP comes this many days later.
const VISIT_MINUTE := 1080  ## 18:00: the VIP arrives (the hotel's check-in window opens).
const VISIT_WINDOW := 120  ## A tick may skip minutes, so a visit may start up to this many minutes late.
const VERDICT_MINUTE := 600  ## 10:00 the next morning: the VIP leaves and gives a verdict.
const GOOD_FROM := 150  ## Tower quality must reach this (the B line, which is acceptable) for a good verdict.

## Phases.
const WAITING := 0  ## No VIP in the tower.
const VISITING := 1  ## A VIP is in the reserved suite.

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
var _last_minute: int = -1  ## Not saved: every step is idempotent, so a reload simply rechecks.


func _init(rooms: RoomsScript, hotel: HotelScript) -> void:
	_rooms = rooms
	_hotel = hotel


## The suite held for the VIP, or -1. Hotel reads this to keep the suite empty.
func reserved_suite() -> int:
	return _suite if _phase == VISITING else -1


func is_visiting() -> bool:
	return _phase == VISITING


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


## Called every tick after the clock; acts once per sim minute.
func tick(clock: ClockScript, stars: int, people: PeopleScript, grades: GradesScript, messages: MessagesScript, at_tick: int) -> void:
	var minute := clock.minute_of_day()
	if minute == _last_minute:
		return
	_last_minute = minute
	var day := HotelScript.night_of(clock)
	if _phase == VISITING:
		_visiting(day, minute, people, grades, messages, at_tick)
	elif _verdict != GOOD and day >= _next_day and stars >= VISIT_STARS and minute >= VISIT_MINUTE and minute < VISIT_MINUTE + VISIT_WINDOW:
		_start(day, messages, at_tick)


func _start(day: int, messages: MessagesScript, at_tick: int) -> void:
	if _hotel.parking_free() <= 0:
		return
	for suite in _hotel.suites():  # a finite list, so the loop ends
		if _eligible(suite):
			_phase = VISITING
			_suite = suite
			_visit_day = day
			messages.add(at_tick, MessagesScript.VIP_ARRIVED, suite)
			return


func _visiting(day: int, minute: int, people: PeopleScript, grades: GradesScript, messages: MessagesScript, at_tick: int) -> void:
	if not _rooms.has_room(_suite) or not _hotel.is_suite(_suite):  # bulldozed: the visit is called off
		_phase = WAITING
		_suite = -1
		_next_day = day + 1
		return
	if day <= _visit_day or minute < VERDICT_MINUTE:
		return
	var suite_ok := grades.grade(_rooms, people, _suite) != GradesScript.GRADE_C
	var good := suite_ok and tower_quality(_rooms, people, grades) >= GOOD_FROM
	_verdict = GOOD if good else BAD
	_visits += 1
	_next_day = day + RETRY_DAYS
	messages.add(at_tick, MessagesScript.VIP_GOOD if good else MessagesScript.VIP_BAD, _suite)
	_phase = WAITING
	_suite = -1


func state_ints() -> Array[int]:
	return [_phase, _suite, _visit_day, _next_day, _verdict, _visits]


static func valid_ints(ints: Array) -> bool:
	if ints.size() != 6:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	if ints[0] != WAITING and ints[0] != VISITING:
		return false
	if ints[0] == VISITING and ints[1] < 1:
		return false
	return ints[3] >= 0 and ints[4] >= NONE and ints[4] <= BAD and ints[5] >= 0


func load_ints(ints: Array) -> void:
	_phase = ints[0]
	_suite = ints[1]
	_visit_day = ints[2]
	_next_day = ints[3]
	_verdict = ints[4]
	_visits = ints[5]
	_last_minute = -1
