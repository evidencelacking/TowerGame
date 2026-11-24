class_name Stall
extends RefCounted
## Stuck elevator (M9 9.11, #473): our own event, no original equivalent. Integers only.
##
## Scope: passenger LOCAL shafts only for now. Express shafts are left out on purpose (a stalled express would strand the
## sky lobbies; that needs its own design) and service cars never stall.
##
## When it happens: its own PCG32 stream (seed XOR SEED_SALT), one draw at the start of every period whatever else is true.
## A draw of 0 in `arm_one_in` on a rush period (1 and 2 morning, 5 evening) arms a stall for that period. While armed, every
## tick the tower is checked (a ride is short, so a slower check would rarely catch a loaded car): it needs MIN_STARS stars and MIN_SHAFTS passenger shafts; the stalled car is the
## first car (lowest shaft id, then oldest) that is carrying riders, in a local shaft that has at least two cars (so the
## shaft is never left with none) and has not already stalled today (one stall per shaft per day). The window ends with
## the period.
##
## Stalled: the car holds still (Rooms.stalled): no motion, no doors, no hall calls, not counted as waiting, and it keeps
## its stops and schedule settings; the shaft's other cars run on. Its riders stay aboard and their stress climbs by
## STRESS_PER_MINUTE each minute (on top of the usual travel stress, on the normal 0-300 scale) while the card is open.
## The card (Events.open, manual kind 105) has two choices; 0 is the default, taken at the timeout:
##   0 routine repair  free: the car is out for the rest of the day; the riders are let out at once with a RUN_JUMP stress jump.
##   1 rescue crew     RESCUE_COST dollars: the riders are let out at once with a smaller RESCUE_JUMP; the car is back after one period.
## Letting the riders out (Rooms.eject_riders) leaves them in People; Trips then gives their ride up, so each goes back to where
## they came from and tries again later. Nobody is lost or duplicated. The car idles where it stood and resumes from there.
##
## Saved: the stream, the phase, the stalled car as (shaft id, nth car of that shaft), the open card's id, the tick the car
## resumes, the tick the armed window ends (0 for none) and the shafts that already stalled today.
## All numbers are UNVERIFIED tunables except the rescue price and the one-per-shaft-per-day cap (gameplay review).

const EventsScript := preload("res://scripts/sim/events.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const CarsScript := preload("res://scripts/sim/cars.gd")
const Rng := preload("res://scripts/sim/sim_rng.gd")

const SEED_SALT := 0x5354414C  ## "STAL".
const KIND := 105
const MIN_STARS := 2
const MIN_SHAFTS := 2  ## Passenger shafts (local and express) the tower needs.
const SHAFT_KIND := "local_shaft"
const PASSENGER_KINDS: Array[String] = ["local_shaft", "express_shaft"]
const RUSH_PERIODS: Array[int] = [1, 2, 5]  ## Residents leave in period 1, offices fill at 9:00 (period 2), everyone leaves from 17:00 (period 5).
const ARM_ONE_IN := 24  ## A rush period arms a stall with this chance (about one day in eight).
const NOTICE_TICKS := 100  ## About 40 game minutes to answer; then routine repair applies.
const RESCUE_COST := 10000
const STRESS_PER_MINUTE := 4  ## Extra stress a stalled car's riders gain each minute while aboard.
const RUN_JUMP := 60  ## Routine repair: each rider's one-off stress jump.
const RESCUE_JUMP := 15  ## Rescue crew: each rider's one-off stress jump.
const DEFAULT_STREAM := 0x2545F4914F6CDD1D  ## A mixed state: a tiny one (0) draws 0 first. A migrated old save starts its stream here (save_migration.gd, v48 to v49).

const IDLE := 0
const STALLED := 1  ## A car is stalled (its card may still be open).

const CHOICE_REPAIR := 0
const CHOICE_RESCUE := 1

var arm_one_in: int = ARM_ONE_IN  ## A test sets 1 to arm every rush period.
var _rooms: RoomsScript
var _rng := Rng.new()
var _phase: int = IDLE
var _shaft: int = 0
var _nth: int = 0
var _event: int = 0
var _resume: int = 0  ## Tick the car is back, 0 while the card is still open.
var _armed_until: int = 0
var _today: Array[int] = []  ## Shaft ids that stalled since the day began.


func _init(rooms: RoomsScript) -> void:
	_rooms = rooms


func reseed(tower_seed: int) -> void:
	_rng.reseed(tower_seed ^ SEED_SALT)


## The save's ints at rest, with the stream at DEFAULT_STREAM (the migration step).
static func rest_ints() -> Array[int]:
	return [DEFAULT_STREAM, 0, 0, 0, 0, 0, 0, 0] as Array[int]


## True while a car is stalled.
func is_stalled() -> bool:
	return _phase == STALLED


## The stalled car as [shaft id, floor] for the view and the alerts, or [] when none.
func stalled_car() -> Array[int]:
	if _phase != STALLED:
		return [] as Array[int]
	var index := _car_index()
	if index == -1:
		return [] as Array[int]
	return [_shaft, _rooms.cars_of(_shaft)[_nth][CarsScript.FLOOR]] as Array[int]


## Shafts that have stalled today.
func stalled_today() -> Array[int]:
	return _today.duplicate()


func kind() -> Dictionary:
	return {"id": KIND, "class": EventsScript.ORDINARY, "manual": true, "choices": 2, "timeout": NOTICE_TICKS, "floor": 0,
		"default": CHOICE_REPAIR, "costs": [0, RESCUE_COST], "title": "Stuck elevator",
		"text": "An elevator car has stalled with riders aboard and their stress is climbing. A rescue crew ($10,000) frees them and the car is back after one period. Routine repair (free) frees them too, but the car is out for the rest of the day and the riders are far more upset.",
		"labels": ["Routine repair (free)", "Rescue crew ($10,000)"],
		"ignored": "Routine repair: the car is out for the rest of the day."}


## Called once a tick after the clock.
func tick(clock: ClockScript, stars: int, people: PeopleScript, events: EventsScript, messages: MessagesScript, at_tick: int) -> void:
	if clock.day_started:
		_today = []
	if clock.ticks_in_period() == 0:
		var draw := _rng.next_below(maxi(1, arm_one_in))  # every period start, always
		if draw == 0 and RUSH_PERIODS.has(clock.period()):
			_armed_until = at_tick + ClockScript.period_ticks(clock.period() - 1)
	if _armed_until != 0 and at_tick >= _armed_until:
		_armed_until = 0
	if _phase == IDLE:
		if _armed_until != 0 and stars >= MIN_STARS:
			_try_stall(events, messages, at_tick)
		return
	var index := _car_index()
	if index == -1:  # the shaft or car is gone: nothing is stalled any more
		_end(events, messages, at_tick, false)
		return
	_rooms.stalled = {index: true}
	if _event != 0:
		_wait_for_answer(index, clock, people, events, at_tick)
	elif at_tick >= _resume:
		_end(events, messages, at_tick, true)


func _try_stall(events: EventsScript, messages: MessagesScript, at_tick: int) -> void:
	var passenger := 0
	for shaft in _rooms.shaft_ids():  # a finite list
		if PASSENGER_KINDS.has(_rooms.kind_of(shaft)):
			passenger += 1
	if passenger < MIN_SHAFTS:
		return
	for shaft in _rooms.shaft_ids():  # a finite list
		if _rooms.kind_of(shaft) != SHAFT_KIND or _today.has(shaft):
			continue
		var cars := _rooms.car_indexes_of(shaft)
		if cars.size() < 2:
			continue
		for nth in cars.size():
			if _rooms.riders_of(cars[nth]).is_empty():
				continue
			var floor_now: int = _rooms.cars_of(shaft)[nth][CarsScript.FLOOR]
			var card := events.open(KIND, floor_now, at_tick)
			if card == 0:
				return  # the event list is full: ask again on a later check
			_event = card
			_phase = STALLED
			_shaft = shaft
			_nth = nth
			_resume = 0
			_armed_until = 0
			_today.append(shaft)
			_rooms.stalled = {cars[nth]: true}
			for call: Array in _rooms._calls:
				if call[CarsScript.CALL_CAR] == cars[nth]:
					call[CarsScript.CALL_CAR] = -1  # its hall calls go to the other cars
			messages.add(at_tick, MessagesScript.CAR_STALLED, shaft, floor_now)
			return


func _wait_for_answer(index: int, clock: ClockScript, people: PeopleScript, events: EventsScript, at_tick: int) -> void:
	if events.event_of(_event).is_empty():
		var choice := CHOICE_REPAIR
		for entry in events.resolved():  # a finite log
			if entry[0] == _event:
				choice = entry[2]
		_event = 0
		var jump := RESCUE_JUMP if choice == CHOICE_RESCUE else RUN_JUMP
		for id in _rooms.eject_riders(index):  # a finite list
			var i := people.index_of(id)
			if i != -1:
				people.add_stress(i, jump)
		_resume = at_tick + (ClockScript.period_ticks(clock.period() - 1) if choice == CHOICE_RESCUE else clock.ticks_until_minute(ClockScript.PERIOD_1_START))
		return
	if clock.minutes_over_last(1) > 0:  # a new sim minute began this tick (read from the clock, so a load cannot repeat it)
		for id in _rooms.riders_of(index):  # a finite list
			var i := people.index_of(id)
			if i != -1:
				people.add_stress(i, STRESS_PER_MINUTE)


func _end(events: EventsScript, messages: MessagesScript, at_tick: int, resumed: bool) -> void:
	if _event != 0:
		events.withdraw(_event)
	if resumed:
		messages.add(at_tick, MessagesScript.CAR_RESUMED, _shaft)
	_phase = IDLE
	_rooms.stalled = {}
	_shaft = 0
	_nth = 0
	_event = 0
	_resume = 0


func _car_index() -> int:
	var cars := _rooms.car_indexes_of(_shaft)
	return cars[_nth] if _nth < cars.size() else -1


func state_ints() -> Array[int]:
	var ints: Array[int] = [_rng.state, _phase, _shaft, _nth, _event, _resume, _armed_until, _today.size()]
	ints.append_array(_today)
	return ints


## What the state hash takes: nothing while the system is at rest (the stream only follows the seed and the period count).
func hash_ints() -> Array[int]:
	if _phase == IDLE and _armed_until == 0 and _today.is_empty():
		return [] as Array[int]
	return state_ints().slice(1)


static func valid_ints(ints: Array) -> bool:
	if ints.size() < 8:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	var today: int = ints[7]
	if today < 0 or ints.size() != 8 + today or ints[1] < IDLE or ints[1] > STALLED or ints[2] < 0 or ints[3] < 0 or ints[4] < 0 or ints[5] < 0 or ints[6] < 0:
		return false
	return ints[1] == IDLE or ints[2] >= 1


func load_ints(ints: Array) -> void:
	_rng.state = ints[0]
	_phase = ints[1]
	_shaft = ints[2]
	_nth = ints[3]
	_event = ints[4]
	_resume = ints[5]
	_armed_until = ints[6]
	_today = []
	for n in int(ints[7]):
		_today.append(ints[8 + n])
	_rooms.stalled = {}
