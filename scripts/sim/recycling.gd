class_name Recycling
extends RefCounted
## Recycling centres (7.6, #171): underground rooms two floors tall that take the tower's rubbish.
## Each centre holds up to CAPACITY units. Every game hour from FIRST_HOUR to LAST_HOUR the tower
## adds one unit per person inside, shared out over the centres that still have room (equally, the
## lowest ids taking any remainder). A centre at CAPACITY is full and idle: it takes nothing more.
## Rubbish that no centre can take is overflow. At TRUCK_HOUR the truck empties every centre.
##
## Overflow keeps the "needs recycling" demand open (Demands, RECYCLING): short() is true while the
## current or the previous day overflowed. A day with room to spare for all of it clears the demand,
## so more centres (they must touch, see Rooms) are the fix. No service elevator is needed to reach a
## centre: the owner dropped that rule (#162).
##
## Tuning: CAPACITY is chosen so about 9 centres serve a full tower (owner ruling, #171):
## 10,000 people (the 5-star mark) for the 16 hours is 160,000 units, and 160,000 / 9 is about 17,800.
## The numbers are UNVERIFIED tunables. A centre costs a quarterly upkeep (the catalogue's upkeep).
##
## Saved state: last hour handled, overflow today, overflow yesterday, then (room id, fill) pairs.

const ClockScript := preload("res://scripts/sim/clock.gd")

const KIND := "recycling"
const CAPACITY := 18000  ## Units one centre holds (tunable; about 9 centres serve 10,000 people).
const TRUCK_HOUR := 6  ## The truck empties every centre at the start of this hour.
const FIRST_HOUR := 6  ## Rubbish is added on each hour from here to LAST_HOUR inclusive.
const LAST_HOUR := 21

var _rooms: Rooms
var _fill: Dictionary = {}  ## centre room id -> units held
var _last_hour: int = -1  ## The last in-game hour handled, so each hour acts once (saved).
var _overflow_today: bool = false
var _overflow_before: bool = false


func _init(rooms: Rooms) -> void:
	_rooms = rooms


## The placed centres, ordered by id.
func centres() -> Array[int]:
	var found: Array[int] = []
	for id in _rooms.room_ids():
		if _rooms.kind_of(id) == KIND:
			found.append(id)
	return found


func fill_of(room: int) -> int:
	return int(_fill.get(room, 0))


## A full centre is idle: it takes no more rubbish until the truck comes.
func is_idle(room: int) -> bool:
	return _rooms.kind_of(room) == KIND and fill_of(room) >= CAPACITY


## Units the placed centres can hold in total.
func capacity() -> int:
	return centres().size() * CAPACITY


## True while the tower has overflowed rubbish today or yesterday (the demand's test).
func short() -> bool:
	return _overflow_today or _overflow_before


## Called every tick: acts once when the in-game hour changes. inside is the people in the tower.
func tick(clock: ClockScript, inside: int) -> void:
	var hour := clock.hour()
	if hour == _last_hour:
		return
	_last_hour = hour
	_prune()
	if hour == TRUCK_HOUR:
		_fill.clear()
		_overflow_before = _overflow_today
		_overflow_today = false
	if hour >= FIRST_HOUR and hour <= LAST_HOUR:
		_add(inside)


## Drops the fill of centres that no longer exist.
func _prune() -> void:
	for id: int in _fill.keys():
		if _rooms.kind_of(id) != KIND:
			_fill.erase(id)


## Shares load_units over the centres that are not full. What is left over is overflow. Each pass
## either finishes (nothing left over) or fills at least one centre, so the open list shrinks and
## the loop ends.
func _add(load_units: int) -> void:
	var open: Array[int] = []
	for id in centres():
		if fill_of(id) < CAPACITY:
			open.append(id)
	var left := load_units
	while left > 0 and not open.is_empty():
		var share := left / open.size()
		var extra := left % open.size()
		var still: Array[int] = []
		left = 0
		for i in open.size():
			var id := open[i]
			var give := share + (1 if i < extra else 0)
			var room_left := CAPACITY - fill_of(id)
			if give >= room_left:
				_fill[id] = CAPACITY
				left += give - room_left
			else:
				_fill[id] = fill_of(id) + give
				still.append(id)
		open = still
	if left > 0:
		_overflow_today = true


func state_ints() -> Array[int]:
	var ids: Array = _fill.keys()
	ids.sort()
	var ints: Array[int] = [_last_hour, 1 if _overflow_today else 0, 1 if _overflow_before else 0, ids.size()]
	for id: int in ids:
		ints.append_array([id, _fill[id]] as Array[int])
	return ints


static func valid_ints(ints: Array) -> bool:
	if ints.size() < 4:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	if ints[0] < -1 or ints[0] > 23 or ints[3] < 0 or ints.size() != 4 + 2 * ints[3]:
		return false
	for flag in [ints[1], ints[2]]:
		if flag != 0 and flag != 1:
			return false
	for n in ints[3]:
		if ints[4 + 2 * n] < 1 or ints[5 + 2 * n] < 0 or ints[5 + 2 * n] > CAPACITY:
			return false
	return true


func load_ints(ints: Array) -> void:
	_last_hour = ints[0]
	_overflow_today = ints[1] == 1
	_overflow_before = ints[2] == 1
	_fill = {}
	for n in ints[3]:
		_fill[ints[4 + 2 * n]] = ints[5 + 2 * n]
