class_name Pests
extends RefCounted
## Pests (6.5): a hotel room left dirty too long gets pests, and pests spread along the floor to
## the neighbouring hotel rooms. Cleaning does not cure an infested room; the fix is demolition
## (Tower calls remove_room when a room is bulldozed or replaced). More cleaning capacity helps
## only by keeping rooms from reaching the limit.
##
## Once a day (the first tick of each TICKS_PER_DAY block):
##   1. A dirty room, not yet infested, that has been dirty for WARN_DAYS or more, and has not been
##      warned about yet, logs PESTS_WARNING (our own improvement, owner ruling on #149).
##   2. A dirty room dirty for INFEST_DAYS or more becomes infested and logs PESTS_FOUND.
##   3. Every room that was infested before today's step infects ONE adjacent hotel room on its
##      floor, chosen with the seeded sim RNG among its uninfested neighbours (left and right).
## Infested rooms take no guests (Hotel checks is_infested) and Hotel.is_dirty reports them as
## not dirty, so housekeepers do not waste time on them. No stress or population penalty (owner
## ruling). Every number is an UNVERIFIED tunable; the rules come from the gameplay review.
##
## Saved state: last day index, infested room ids, warned room ids (both ascending).

const ClockScript := preload("res://scripts/sim/clock.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")

const TICKS_PER_DAY := ClockScript.PERIOD_1_TICKS + ClockScript.PERIOD_2_TICKS + ClockScript.PERIOD_3_TICKS \
		+ ClockScript.PERIOD_4_TICKS + ClockScript.PERIOD_5_TICKS + ClockScript.PERIOD_6_TICKS
const INFEST_DAYS := 3  ## Days dirty before pests (owner-accepted tunable guess).
const WARN_DAYS := 2  ## Days dirty before the warning in the message log.

var _rooms: RoomsScript
var _last_day: int = -1  ## Day index of the last daily step.
var _infested: Array[int] = []  ## Room ids, ascending.
var _warned: Array[int] = []  ## Rooms already warned about, ascending.


func _init(rooms: RoomsScript = null) -> void:
	_rooms = rooms


func is_infested(room: int) -> bool:
	return _infested.has(room)


func infested_count() -> int:
	return _infested.size()


func infested_rooms() -> Array[int]:
	return _infested.duplicate()


## Forgets a room (bulldozed or replaced): demolition is the cure.
func remove_room(room: int) -> void:
	_infested.erase(room)
	_warned.erase(room)


## Called every tick after the hotel; does its work once a day.
## Hotel is passed in, not held: Hotel holds Pests, and two RefCounted objects must not hold each other.
func tick(hotel: HotelScript, grid: GridScript, rng: Object, messages: MessagesScript, at_tick: int) -> void:
	var day := at_tick / TICKS_PER_DAY
	if day == _last_day:
		return
	_last_day = day
	var before: Array[int] = _infested.duplicate()
	# Rooms that were cleaned or vanished are no longer warned about.
	var still: Array[int] = []
	for room in _warned:
		if _rooms.has_room(room) and hotel.is_dirty(room):
			still.append(room)
	_warned = still
	for room in _rooms.room_ids():
		if not hotel.is_hotel(room) or is_infested(room):
			continue
		var since := hotel.dirty_since(room)
		if since < 0:
			continue
		var age := at_tick - since
		if age >= INFEST_DAYS * TICKS_PER_DAY:
			_add(room)
			_warned.erase(room)
			messages.add(at_tick, MessagesScript.PESTS_FOUND, room)
		elif age >= WARN_DAYS * TICKS_PER_DAY and not _warned.has(room):
			_warned.append(room)
			messages.add(at_tick, MessagesScript.PESTS_WARNING, room)
	_warned.sort()
	for room in before:
		_spread(hotel, room, grid, rng, messages, at_tick)


func _add(room: int) -> void:
	_infested.append(room)
	_infested.sort()


## One infested room infects one uninfested hotel room beside it on the same floor.
func _spread(hotel: HotelScript, room: int, grid: GridScript, rng: Object, messages: MessagesScript, at_tick: int) -> void:
	var run := grid.run_of(room)
	if run.is_empty():
		return
	var options: Array[int] = []
	for column: int in [run[1] - 1, run[1] + run[2]]:
		if column < 0 or column >= GridScript.WIDTH_UNITS:
			continue
		var next := grid.cell_at(run[0], column)
		if next != GridScript.EMPTY and hotel.is_hotel(next) and not is_infested(next):
			options.append(next)
	if options.is_empty():
		return
	var pick: int = options[rng.next_below(options.size())]
	_add(pick)
	_warned.erase(pick)
	messages.add(at_tick, MessagesScript.PESTS_FOUND, pick)


func state_ints() -> Array[int]:
	var ints: Array[int] = [_last_day, _infested.size()]
	ints.append_array(_infested)
	ints.append(_warned.size())
	ints.append_array(_warned)
	return ints


static func valid_ints(ints: Array) -> bool:
	if ints.size() < 3:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	var n_infested: int = ints[1]
	if n_infested < 0 or ints.size() < 3 + n_infested:
		return false
	var n_warned: int = ints[2 + n_infested]
	if n_warned < 0 or ints.size() != 3 + n_infested + n_warned:
		return false
	for n in range(2, ints.size()):
		if n != 2 + n_infested and ints[n] < 1:
			return false
	return true


func load_ints(ints: Array) -> void:
	_last_day = ints[0]
	var n_infested: int = ints[1]
	_infested.assign(ints.slice(2, 2 + n_infested))
	_warned.assign(ints.slice(3 + n_infested))
