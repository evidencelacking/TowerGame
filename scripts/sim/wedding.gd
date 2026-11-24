class_name Wedding
extends RefCounted
## The top-rank wedding (M11 11.5, #33): our own trigger, timing and reward. Integers only; no random draw.
##
## The gate (StarRules.meets_top_rank): 5 stars, 15,000 permanent population and a cathedral that is reached and not charred.
## Checked on the star-check cadence (Tower.promote_stars). When it first holds the wedding sets itself for the next weekend
## day (WE) and a notice goes out. The owner does nothing; it is not a card.
##
## The day: from ARRIVE_START the guests arrive over ARRIVE_MINUTES (GUESTS in all, spread evenly by integer division).
## The ceremony runs from CEREMONY_START for CEREMONY_MINUTES. At its end MIN_GUESTS arrived means success, fewer means a
## failure with a hint, and it retries the next weekend. A fire anywhere in the tower, or the cathedral cut off or charred,
## calls it off on the day and it retries the next weekend.
##
## Guests are visitors, not people: like the street festival's crowd they are never counted in the population. They come
## through the lobby, so a guest who finds CROWD_LIMIT or more people waiting in the floor 1 hall queue turns away (the
## tower has to carry them). UNVERIFIED tunables: every number here.
##
## Reward: celebration only (owner ruling on #33). Success sets top_rank for good (saved, never cleared); the view plays the
## celebration and shows the badge. Nothing ends: play carries on as a sandbox.
##
## Saved: phase, the top-rank flag, guests arrived, wedding days that failed or were called off.

const MessagesScript := preload("res://scripts/sim/messages.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")

const GUESTS := 40  ## Invited. Tunable.
const MIN_GUESTS := 20  ## At least this many must arrive for the wedding to count. Tunable.
const ARRIVE_START := 660  ## 11:00: guests start to arrive.
const ARRIVE_MINUTES := 60  ## They arrive over this long.
const CEREMONY_START := 720  ## Midday.
const CEREMONY_MINUTES := 60  ## Tunable.
const RESOLVE_WINDOW := 30  ## The result is read in the first minutes after the ceremony ends (a tick is under a minute, so one is hit).
const CROWD_LIMIT := 30  ## Waiting in the lobby hall queue at or above this and a guest turns away. Tunable.
const LOBBY_FLOOR := 1

const IDLE := 0
const SCHEDULED := 1  ## Set for the next weekend day.
const DAY := 2  ## It is the wedding day.

const CALLED_OFF_FIRE := 0
const CALLED_OFF_CATHEDRAL := 1

var _phase: int = IDLE
var _top_rank: bool = false
var _arrived: int = 0
var _failed: int = 0


## The save's ints at rest (the migration step, v49 to v50).
static func rest_ints() -> Array[int]:
	return [0, 0, 0, 0] as Array[int]


## True once a wedding has succeeded. Saved, never cleared.
func top_rank() -> bool:
	return _top_rank


func is_scheduled() -> bool:
	return _phase == SCHEDULED


## True on the wedding day, until it ends.
func is_day() -> bool:
	return _phase == DAY


## Guests who have arrived so far today.
func arrived() -> int:
	return _arrived


## Wedding days that failed or were called off.
func failed_count() -> int:
	return _failed


## Called on the star-check cadence with whether the top-rank gate holds. Sets the wedding for the next weekend.
func check(gate_holds: bool, clock: ClockScript, messages: MessagesScript, at_tick: int) -> void:
	if _top_rank or _phase != IDLE or not gate_holds:
		return
	_phase = SCHEDULED
	var quarter := clock.quarter()
	var year := clock.year()
	if clock.day_of_week() == ClockScript.WE:  # today's weekend is already under way: the next one
		quarter += 1
		if quarter > ClockScript.QUARTERS_PER_YEAR:
			quarter = 1
			year += 1
	messages.add(at_tick, MessagesScript.WEDDING_SET, quarter, year)


## Called once a tick after the clock. `fire` is true while any room burns; `cathedral_ok` is whether the cathedral is
## reached and not charred (only read on the wedding day); `lobby_crowd` is how many wait in the lobby hall queue.
func tick(clock: ClockScript, fire: bool, cathedral_ok: bool, lobby_crowd: int, messages: MessagesScript, at_tick: int, cheated: bool = false) -> void:
	if clock.day_started:
		if _phase == DAY:
			_phase = IDLE  # the day ended without a result: it is tried again at the next check
			_arrived = 0
		elif _phase == SCHEDULED and clock.day_of_week() == ClockScript.WE:
			_phase = DAY
			_arrived = 0
	if _phase != DAY:
		return
	if fire or not cathedral_ok:
		_call_off(messages, at_tick, CALLED_OFF_FIRE if fire else CALLED_OFF_CATHEDRAL)
		return
	if clock.minutes_over_last(1) == 0:
		return  # no new sim minute this tick
	var minute := clock.minute_of_day()
	if minute >= ARRIVE_START and minute < ARRIVE_START + ARRIVE_MINUTES:
		var k := minute - ARRIVE_START
		var due := GUESTS * (k + 1) / ARRIVE_MINUTES - GUESTS * k / ARRIVE_MINUTES
		if due > 0 and lobby_crowd < CROWD_LIMIT:
			_arrived += due
	elif minute >= CEREMONY_START + CEREMONY_MINUTES and minute < CEREMONY_START + CEREMONY_MINUTES + RESOLVE_WINDOW:
		_finish(messages, at_tick, cheated)


func _finish(messages: MessagesScript, at_tick: int, cheated: bool = false) -> void:
	if _arrived >= MIN_GUESTS:
		_top_rank = true
		messages.add(at_tick, MessagesScript.WEDDING_DONE, _arrived, 1 if cheated else 0)
	else:
		_failed += 1
		messages.add(at_tick, MessagesScript.WEDDING_FAILED, _arrived, MIN_GUESTS)
	_phase = IDLE
	_arrived = 0


func _call_off(messages: MessagesScript, at_tick: int, reason: int) -> void:
	_failed += 1
	_phase = IDLE
	_arrived = 0
	messages.add(at_tick, MessagesScript.WEDDING_CALLED_OFF, reason)


func state_ints() -> Array[int]:
	return [_phase, 1 if _top_rank else 0, _arrived, _failed] as Array[int]


## What the state hash takes: nothing while no wedding has been set, so a tower that never reached the gate hashes as before.
func hash_ints() -> Array[int]:
	if _phase == IDLE and not _top_rank and _arrived == 0 and _failed == 0:
		return [] as Array[int]
	return state_ints()


static func valid_ints(ints: Array) -> bool:
	if ints.size() != 4:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	return ints[0] >= IDLE and ints[0] <= DAY and (ints[1] == 0 or ints[1] == 1) and ints[2] >= 0 and ints[3] >= 0


func load_ints(ints: Array) -> void:
	_phase = ints[0]
	_top_rank = ints[1] == 1
	_arrived = ints[2]
	_failed = ints[3]
