class_name Housekeeping
extends RefCounted
## Housekeeping (6.4): each placed housekeeping station holds STAFF_PER_STATION housekeepers, one
## per floor, who clean dirty hotel rooms (Hotel.mark_clean) during a shift. All staff state lives
## here; Tower only calls tick and the save hooks.
##
## A housekeeper on shift with no job looks at the dirty hotel rooms nobody has claimed. They
## consider the WINDOW_FLOORS nearest floors that have dirty rooms (nearest the station first,
## the lower floor on a tie). That is a soft window (owner ruling, #148): there is no hard floor
## limit, the six staff simply take the six nearest dirty floors. One staff per floor per station:
## a floor a station-mate is already working is skipped. On a floor the oldest dirty room goes
## first. A room with no staff route from where the housekeeper stands (Routes.find with
## staff = true: service cars and stairs, never standard cars or escalators) is skipped and stays
## dirty.
##
## A job is travel (route minutes, see _minutes) then CLEAN_MINUTES of cleaning, then the room is
## marked clean and the housekeeper stands in it, ready for the next job. Staff do not occupy
## service cars or queue for them: travel is an estimate from the route (a documented
## simplification). Every number is an UNVERIFIED tunable except the staff count and the rough
## 18 rooms a day (gameplay review, #148).
##
## Saved state: one RECORD of ints per housekeeper.

const RoutesScript := preload("res://scripts/sim/routes.gd")
const TripsScript := preload("res://scripts/sim/trips.gd")
const GridScript := preload("res://scripts/sim/grid.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")

const STATION_KIND := "housekeeping"
const STAFF_PER_STATION := 6  ## One per floor (gameplay review, #148).
const WINDOW_FLOORS := 6  ## "About 6 floors": the soft window of nearest dirty floors.
const SHIFT_FROM := 420  ## 7:00: staff start looking for work (tunable guess).
const SHIFT_TO := 1020  ## 17:00: no new job at or after this (tunable guess).
const CLEAN_MINUTES := 30  ## Minutes to clean one room; with travel about 18 to 20 rooms a shift (tunable).
const RETRY_MINUTES := 5  ## Minutes an idle housekeeper waits after finding nothing reachable (tunable).
const MAX_ROUTE_TRIES := 12  ## Most route searches one housekeeper makes when picking a job.
const ELEVATOR_BOARD_MINUTES := 2  ## Waiting for and boarding a service car, per elevator leg (tunable guess).
const ELEVATOR_FLOORS_PER_MINUTE := 2  ## Floors a service car climbs per minute (tunable guess).

## Phases.
const IDLE := 0  ## Standing in the location room; minutes is the retry cooldown.
const TRAVEL := 1  ## On the way to the target; minutes left.
const CLEAN := 2  ## Cleaning the target; minutes left.

## Record fields: a flat list of ints per housekeeper.
const RECORD := 5
const _STATION := 0  ## Station room id.
const _LOCATION := 1  ## Room the housekeeper stands in (the origin while travelling).
const _TARGET := 2  ## Room being walked to or cleaned, or -1.
const _PHASE := 3
const _MINUTES := 4

var _rooms: RoomsScript
var _hotel: HotelScript
var _staff: Array = []  ## Array of Array[int] RECORD ints, ordered by station then hire order.
var _last_minute: int = -1  ## Not saved: a reload rechecks once and every step is idempotent.


func _init(rooms: RoomsScript = null, hotel: HotelScript = null) -> void:
	_rooms = rooms
	_hotel = hotel


## Housekeepers employed now (6 per placed station).
func staff_count() -> int:
	return _staff.size()


## Housekeepers belonging to a station.
func staff_of(station: int) -> int:
	var n := 0
	for r: Array in _staff:
		if r[_STATION] == station:
			n += 1
	return n


## Housekeepers cleaning or on their way to a room, tower-wide.
func busy_count() -> int:
	var n := 0
	for r: Array in _staff:
		if r[_PHASE] != IDLE:
			n += 1
	return n


## True when some housekeeper has claimed the room (travelling to or cleaning it).
func is_claimed(room: int) -> bool:
	for r: Array in _staff:
		if r[_PHASE] != IDLE and r[_TARGET] == room:
			return true
	return false


## Called once per tick after the hotel; acts once per sim minute.
func tick(clock: ClockScript, floors: FloorsScript, grid: GridScript) -> void:
	var minute := clock.minute_of_day()
	if minute == _last_minute:
		return
	_last_minute = minute
	_sync_staff()
	for r: Array in _staff:
		match r[_PHASE]:
			IDLE:
				if r[_MINUTES] > 0:
					r[_MINUTES] -= 1
				elif minute >= SHIFT_FROM and minute < SHIFT_TO:
					_pick(r, floors, grid)
			TRAVEL:
				if not _target_ok(r[_TARGET]):
					_drop_job(r)
				else:
					r[_MINUTES] -= 1
					if r[_MINUTES] <= 0:
						r[_LOCATION] = r[_TARGET]
						r[_PHASE] = CLEAN
						r[_MINUTES] = CLEAN_MINUTES
			CLEAN:
				if not _target_ok(r[_TARGET]):
					_drop_job(r)
				else:
					r[_MINUTES] -= 1
					if r[_MINUTES] <= 0:
						_hotel.mark_clean(r[_TARGET])
						_drop_job(r)


## A job target is still worth working: the room exists and is still dirty.
func _target_ok(room: int) -> bool:
	return _rooms.has_room(room) and _hotel.is_dirty(room)


func _drop_job(r: Array) -> void:
	r[_TARGET] = -1
	r[_PHASE] = IDLE
	r[_MINUTES] = 0


## Hires STAFF_PER_STATION for each placed station, lets go staff of vanished stations, and sends
## anyone standing in a vanished room back to their station.
func _sync_staff() -> void:
	var kept: Array = []
	for station in _rooms.room_ids():
		if _rooms.kind_of(station) != STATION_KIND:
			continue
		var have: Array = []
		for r: Array in _staff:
			if r[_STATION] == station:
				have.append(r)
		for n in STAFF_PER_STATION:
			if n < have.size():
				var r: Array = have[n]
				if not _rooms.has_room(r[_LOCATION]):
					r[_LOCATION] = station
					_drop_job(r)
				kept.append(r)
			else:
				var fresh: Array[int] = [station, station, -1, IDLE, 0]
				kept.append(fresh)
	_staff = kept


## The floor a room sits on, or 0 when it has no placement.
func _floor_of(grid: GridScript, room: int) -> int:
	var run := grid.run_of(room)
	return 0 if run.is_empty() else run[0]


func _pick(r: Array, floors: FloorsScript, grid: GridScript) -> void:
	var here := grid.run_of(r[_LOCATION])
	var home := grid.run_of(r[_STATION])
	if here.is_empty() or home.is_empty():
		return
	# Floors the station-mates are working.
	var taken: Dictionary = {}
	for o: Array in _staff:
		if not is_same(o, r) and o[_STATION] == r[_STATION] and o[_PHASE] != IDLE:
			taken[_floor_of(grid, o[_TARGET])] = true
	# Unclaimed dirty hotel rooms by floor.
	var by_floor: Dictionary = {}
	for id in _rooms.room_ids():
		if _hotel.is_hotel(id) and _hotel.is_dirty(id) and not is_claimed(id):
			var f := _floor_of(grid, id)
			if f != 0:
				if not by_floor.has(f):
					by_floor[f] = [] as Array[int]
				by_floor[f].append(id)
	if by_floor.is_empty():
		r[_MINUTES] = RETRY_MINUTES
		return
	var order: Array = by_floor.keys()
	var base := GridScript.floor_to_index(home[0])
	order.sort_custom(func(a: int, b: int) -> bool:
		var da := absi(GridScript.floor_to_index(a) - base)
		var db := absi(GridScript.floor_to_index(b) - base)
		return da < db or (da == db and GridScript.floor_to_index(a) < GridScript.floor_to_index(b)))
	var tries := 0
	for n in mini(WINDOW_FLOORS, order.size()):
		var f: int = order[n]
		if taken.has(f):
			continue
		var rooms_here: Array = by_floor[f]
		rooms_here.sort_custom(func(a: int, b: int) -> bool:
			var sa := _hotel.dirty_since(a)
			var sb := _hotel.dirty_since(b)
			return sa < sb or (sa == sb and a < b))
		for room: int in rooms_here:
			if tries >= MAX_ROUTE_TRIES:
				r[_MINUTES] = RETRY_MINUTES
				return
			tries += 1
			var there := grid.run_of(room)
			var route := RoutesScript.find(floors, _rooms, grid, here[0], here[1], there[0], there[1], true)
			if route["reason"] != RoutesScript.OK:
				continue  # unreachable by staff: stays dirty
			r[_TARGET] = room
			r[_PHASE] = TRAVEL
			r[_MINUTES] = _minutes(route["legs"])
			return
	r[_MINUTES] = RETRY_MINUTES


## Whole minutes a staff route takes: the walking and stairs time of Trips plus an estimate for
## each service car ride. At least 1.
static func _minutes(legs: Array) -> int:
	var minutes := TripsScript.route_minutes(legs)
	for leg: Dictionary in legs:
		if leg["kind"] == RoutesScript.ELEVATOR:
			var rise := absi(GridScript.floor_to_index(leg["to_floor"]) - GridScript.floor_to_index(leg["floor"]))
			minutes += ELEVATOR_BOARD_MINUTES + (rise + ELEVATOR_FLOORS_PER_MINUTE - 1) / ELEVATOR_FLOORS_PER_MINUTE
	return maxi(1, minutes)


## Flat ints for hashing and saving: count, then the records.
func state_ints() -> Array[int]:
	var ints: Array[int] = [_staff.size()]
	for r: Array in _staff:
		ints.append_array(r as Array[int])
	return ints


static func valid_ints(ints: Array) -> bool:
	if ints.is_empty() or typeof(ints[0]) != TYPE_INT or ints[0] < 0 or ints.size() != 1 + RECORD * ints[0]:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	for n in ints[0]:
		var b: int = 1 + n * RECORD
		if ints[b + _STATION] < 0 or ints[b + _LOCATION] < 0 or ints[b + _TARGET] < -1:
			return false
		if ints[b + _PHASE] < IDLE or ints[b + _PHASE] > CLEAN or ints[b + _MINUTES] < 0:
			return false
	return true


func load_ints(ints: Array) -> void:
	_staff = []
	for n in ints[0]:
		var b: int = 1 + n * RECORD
		var r: Array[int] = []
		r.assign(ints.slice(b, b + RECORD))
		_staff.append(r)
