class_name Hotel
extends RefCounted
## Hotel rooms (6.2): single, twin and suite. Guests check in on the evening, sleep the night and
## check out in the morning; the room pays its nightly price once, at check-out, into the ledger
## as HOTEL income. All hotel state lives here (rooms.gd and tower.gd only call in).
##
## A night, for each clean vacant hotel room:
##   1. PLAN: once per night, on the first minute inside the check-in window, a seeded draw books
##      the room (BOOK_PERCENT) and picks an arrival minute and a check-out minute.
##   2. CHECK-IN: at the arrival minute (never after CHECK_IN_TO) the guests are added outside the
##      tower with a trip to the room (People.add_guest), so they walk, ride and queue like anyone
##      and take real travel stress. A suite also needs a free parking space (see parking_free).
##   3. STAY: once every guest is in the room the stay begins (guests count toward population).
##   4. CHECK-OUT: next morning from the room's check-out minute: the guests go, the nightly price
##      (the room's rent level, see Rent) is credited once, and the room turns DIRTY.
## A guest who cannot reach the room within PATIENCE_MINUTES gives up: the guests leave (with the
## stress they took on the way), nothing is paid and the room logs a complaint (unreached(room),
## read by Complaints as UNREACHED, cleared by the next successful arrival).
##
## Dirty rooms (#147): is_dirty / dirty_since(room) read the tick the room turned
## dirty (-1 when clean), and mark_clean(room) makes it rentable again. A dirty room never takes
## guests and check-out logs ROOM_DIRTY. Only housekeeping staff clean a room (Housekeeping, #148,
## calls mark_clean); with no station, or no staff route to it, a room stays dirty.
##
## Suites are flagged in the catalogue ("suite") for the VIP task: see suites() and is_suite().
## Every number below is an UNVERIFIED tunable (owner rulings, #146).
##
## Saved state: one RECORD of ints per hotel room touched so far.

const RoomsScript := preload("res://scripts/sim/rooms.gd")
const PeopleScript := preload("res://scripts/sim/people.gd")
const ClockScript := preload("res://scripts/sim/clock.gd")
const LedgerScript := preload("res://scripts/sim/ledger.gd")
const FloorsScript := preload("res://scripts/sim/floors.gd")
const RentScript := preload("res://scripts/sim/rent.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const MessagesScript := preload("res://scripts/sim/messages.gd")

const KINDS: Array[String] = ["hotel_single", "hotel_twin", "hotel_suite"]

const CHECK_IN_FROM := 1080  ## 18:00 (tunable guess).
const CHECK_IN_TO := 1380  ## 23:00: no check-in at or after this (tunable guess).
const CHECK_IN_MARGIN := 5  ## Arrival minutes are drawn this far before CHECK_IN_TO: one tick can span a few minutes.
const CHECK_OUT_FROM := 420  ## 7:00 (tunable guess).
const CHECK_OUT_TO := 600  ## 10:00: check-out minutes are drawn from [CHECK_OUT_FROM, CHECK_OUT_TO).
const BOOK_PERCENT := 70  ## Chance a clean vacant room is booked on a night (tunable guess).
const PATIENCE_MINUTES := 90  ## Sim minutes guests keep trying to reach the room before giving up (tunable guess).
const GIVE_UP_MINUTES := 240  ## Even guests still in transit give up after this long, so a stay can never hang.
const PARKING_KIND := "parking_space"

## Room states.
const VACANT := 0
const ARRIVING := 1  ## Guests checked in and are on their way to the room.
const STAYING := 2  ## Guests are in the room.

## Record fields: a flat list of ints per room, in this order.
const RECORD := 8  ## Ints per record.
const _STATE := 0
const _PLANNED_NIGHT := 1  ## Night index the room was last planned for, or -1.
const _ARRIVE := 2  ## Planned arrival minute, or -1 once checked in or lapsed.
const _LEAVE := 3  ## Check-out minute of day for the current stay.
const _CHECKIN_NIGHT := 4  ## Night index of the current stay.
const _CHECKIN_MINUTE := 5  ## Minute the guests actually checked in (for patience).
const _DIRTY_SINCE := 6  ## Tick the room turned dirty, or -1 when clean.
const _UNREACHED := 7  ## 1 while the latest stay failed because the guests could not reach the room.

var _rooms: RoomsScript
var _rent: RentScript  ## The room's nightly price is its rent level.
var _records: Dictionary = {}  ## Room id -> Array[int] of RECORD ints.
var _last_minute: int = -1  ## Not saved: a reload rechecks once and every step is idempotent.


func _init(rooms: RoomsScript = null, rent: RentScript = null) -> void:
	_rooms = rooms
	_rent = rent


## True for the three hotel room kinds.
static func is_hotel_kind(kind: String) -> bool:
	return KINDS.has(kind)


## True when the placed room is a hotel room.
func is_hotel(room: int) -> bool:
	return is_hotel_kind(_rooms.kind_of(room))


## True when the room is a suite (the catalogue's "suite" flag): VIP guests will want these.
func is_suite(room: int) -> bool:
	return bool(CatalogueScript.field(_rooms.kind_of(room), "suite"))


## Every placed suite, ascending room id. The VIP task (4-star gate) reads this.
func suites() -> Array[int]:
	var found: Array[int] = []
	for id in _rooms.room_ids():
		if is_suite(id):
			found.append(id)
	return found


## Guests the room holds (1, 2, 2).
func capacity(room: int) -> int:
	return _rooms.people_in(room)


## VACANT, ARRIVING or STAYING.
func state_of(room: int) -> int:
	return _records[room][_STATE] if _records.has(room) else VACANT


## The tick the room turned dirty at its last check-out, or -1 when it is clean. Pure read: the
## hook for housekeeping (#148).
func dirty_since(room: int) -> int:
	return _records[room][_DIRTY_SINCE] if _records.has(room) else -1


func is_dirty(room: int) -> bool:
	return dirty_since(room) >= 0 and not is_infested(room)


## Housekeeping hook (#148): the room has been cleaned and may take guests again.
func mark_clean(room: int) -> void:
	if _records.has(room):
		_records[room][_DIRTY_SINCE] = -1


## True while the latest stay failed because the guests could not reach the room (a complaint).
func unreached(room: int) -> bool:
	return _records[room][_UNREACHED] == 1 if _records.has(room) else false


## Set by Tower (#172): the number of working parking spaces (chained to the ramp column). Left
## unset, every placed parking_space room counts.
var working_spaces: Callable = Callable()


## Working parking spaces not held by a suite stay, tower-wide. Each suite stay holds one from
## check-in to check-out. Spaces cut off from the ramp column (Parking) do not count.
func parking_free() -> int:
	var spaces := 0
	if working_spaces.is_valid():
		spaces = int(working_spaces.call())
	else:
		for id in _rooms.room_ids():
			if _rooms.kind_of(id) == PARKING_KIND:
				spaces += 1
	var held := 0
	for id: int in _records:
		if _rooms.has_room(id) and is_suite(id) and _records[id][_STATE] != VACANT:
			held += 1
	return spaces - held


## Forgets a room (bulldozed or replaced). Tower calls it beside People.remove_room.
## Set by Tower (#149). An infested room takes no guests and reads as not dirty, so cleaning staff skip it.
var pests: Object = null
## Set by Tower (#173): returns the suite held for the VIP (or -1). It takes no guests meanwhile.
var reserved_room: Callable = Callable()


func is_infested(room: int) -> bool:
	return pests != null and pests.is_infested(room)


func remove_room(room: int) -> void:
	_records.erase(room)


## The nightly price: the room's catalogue price at its rent level.
func price(room: int) -> int:
	var prices: Array = CatalogueScript.row(_rooms.kind_of(room)).get("rent", [])
	if prices.is_empty():
		return 0
	var level := _rent.level_of(room) if _rent != null else RentScript.DEFAULT_LEVEL
	return int(prices[level])


## A sim-wide day index that changes at the clock's day start (5:00).
static func night_of(clock: ClockScript) -> int:
	return ((clock.year() - 1) * ClockScript.QUARTERS_PER_YEAR + clock.quarter() - 1) * ClockScript.DAYS_PER_QUARTER + clock.day_of_week()


## Called once per tick after the clock; acts once per sim minute.
func tick(clock: ClockScript, floors: FloorsScript, people: PeopleScript, rng: Object, ledger: LedgerScript, messages: MessagesScript, at_tick: int) -> void:
	var minute := clock.minute_of_day()
	if minute == _last_minute:
		return
	_last_minute = minute
	var night := night_of(clock)
	for id in _rooms.room_ids():
		if not is_hotel(id) or _rooms.is_charred(id):
			continue
		if not _records.has(id):
			var fresh: Array[int] = [VACANT, -1, -1, CHECK_OUT_FROM, -1, 0, -1, 0]
			_records[id] = fresh
		var r: Array[int] = _records[id]
		match r[_STATE]:
			VACANT:
				_vacant(id, r, minute, night, floors, people, rng)
			ARRIVING:
				_arriving(id, r, minute, people, messages, at_tick)
			STAYING:
				_staying(id, r, minute, night, people, ledger, messages, at_tick)


func _vacant(id: int, r: Array[int], minute: int, night: int, floors: FloorsScript, people: PeopleScript, rng: Object) -> void:
	if r[_DIRTY_SINCE] >= 0 or is_infested(id) or not floors.has_lobby():
		return
	if reserved_room.is_valid() and int(reserved_room.call()) == id:
		return
	if minute >= CHECK_IN_FROM and minute < CHECK_IN_TO and r[_PLANNED_NIGHT] != night:
		r[_PLANNED_NIGHT] = night
		r[_ARRIVE] = -1
		if rng.next_below(100) < BOOK_PERCENT:
			r[_ARRIVE] = CHECK_IN_FROM + rng.next_below(CHECK_IN_TO - CHECK_IN_MARGIN - CHECK_IN_FROM + 1)
			r[_LEAVE] = CHECK_OUT_FROM + rng.next_below(CHECK_OUT_TO - CHECK_OUT_FROM)
	if r[_ARRIVE] < 0 or r[_PLANNED_NIGHT] != night:
		return
	if minute >= CHECK_IN_TO or minute < CHECK_IN_FROM:  # the window closed before they came
		r[_ARRIVE] = -1
		return
	if minute < r[_ARRIVE] or not _parking_ok(id):
		return
	for n in capacity(id):
		people.add_guest(id, rng)
	r[_STATE] = ARRIVING
	r[_CHECKIN_NIGHT] = night
	r[_CHECKIN_MINUTE] = minute
	r[_ARRIVE] = -1


## True if a room may rent tonight as far as parking goes (only suites need a space).
func _parking_ok(room: int) -> bool:
	return not bool(CatalogueScript.field(_rooms.kind_of(room), "needs_parking")) or parking_free() > 0


func _arriving(id: int, r: Array[int], minute: int, people: PeopleScript, messages: MessagesScript, at_tick: int) -> void:
	var inside := 0
	var moving := false
	for i in people.count():
		if people.home_of(i) == id:
			if people.location_of(i) == id:
				inside += 1
			elif people.trip_state(i) == PeopleScript.TRIP_MOVING or people.trip_state(i) == PeopleScript.TRIP_RIDING:
				moving = true
	if inside >= capacity(id):
		r[_STATE] = STAYING
		r[_UNREACHED] = 0
		return
	var waited := (minute - r[_CHECKIN_MINUTE] + ClockScript.MINUTES_PER_DAY) % ClockScript.MINUTES_PER_DAY
	if waited >= GIVE_UP_MINUTES or (waited >= PATIENCE_MINUTES and not moving):
		people.remove_room(id)  # the guests leave, with whatever stress they took
		r[_STATE] = VACANT
		r[_UNREACHED] = 1
		messages.add(at_tick, MessagesScript.GUEST_UNREACHED, id)


func _staying(id: int, r: Array[int], minute: int, night: int, people: PeopleScript, ledger: LedgerScript, messages: MessagesScript, at_tick: int) -> void:
	if night <= r[_CHECKIN_NIGHT] or minute < r[_LEAVE]:
		return
	people.remove_room(id)
	ledger.hotel(at_tick, price(id), id)
	r[_STATE] = VACANT
	r[_DIRTY_SINCE] = at_tick
	messages.add(at_tick, MessagesScript.ROOM_DIRTY, id)


## Flat ints for hashing and saving: count, then (room id, record) ordered by room id.
func state_ints() -> Array[int]:
	var ids: Array = _records.keys()
	ids.sort()
	var ints: Array[int] = [ids.size()]
	for id: int in ids:
		ints.append(id)
		ints.append_array(_records[id] as Array[int])
	return ints


static func valid_ints(ints: Array) -> bool:
	if ints.is_empty() or typeof(ints[0]) != TYPE_INT or ints[0] < 0 or ints.size() != 1 + (RECORD + 1) * ints[0]:
		return false
	for value in ints:
		if typeof(value) != TYPE_INT:
			return false
	for n in ints[0]:
		var b: int = 1 + n * (RECORD + 1)
		if ints[b] < 1 or ints[b + 1 + _STATE] < VACANT or ints[b + 1 + _STATE] > STAYING:
			return false
		if ints[b + 1 + _UNREACHED] < 0 or ints[b + 1 + _UNREACHED] > 1:
			return false
	return true


func load_ints(ints: Array) -> void:
	_records.clear()
	for n in ints[0]:
		var b: int = 1 + n * (RECORD + 1)
		var r: Array[int] = []
		r.assign(ints.slice(b + 1, b + 1 + RECORD))
		_records[ints[b]] = r
