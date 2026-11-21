extends RefCounted
## Housekeeping tests (6.4): six staff a station, one per floor, soft window of the six nearest
## dirty floors, service cars and stairs only, about 18 rooms a day. Numbers are tunables
## (see housekeeping.gd).

const Fixtures := preload("res://tests/fixtures.gd")
const TowerSim := preload("res://scripts/sim/tower.gd")
const CatalogueScript := preload("res://scripts/sim/room_catalogue.gd")
const HotelScript := preload("res://scripts/sim/hotel.gd")
const HousekeepingScript := preload("res://scripts/sim/housekeeping.gd")
const RoomsScript := preload("res://scripts/sim/rooms.gd")
const TestHotel := preload("res://tests/test_hotel.gd")
const TestOfficeDay := preload("res://tests/test_office_day.gd")
const TestServiceElevator := preload("res://tests/test_service_elevator.gd")
const TestElevatorRoutes := preload("res://tests/test_elevator_routes.gd")

const STATION_FLOOR := 3
const STATION_X := 100  ## The station is 16 wide: columns 100 to 115.
const LINK_X := 116  ## Shaft, stairs or escalator column, just right of the station.
const ROW_X: Array[int] = [100, 104, 108, 112, 120, 124, 128]  ## Seven rooms fit on a floor above the station.


## Floors 1 to top (lobby on 1 and 2), a housekeeping station on floor 3. No links yet.
static func _tower(top: int, station: bool = true) -> TowerSim:
	var t := TestElevatorRoutes._plain(top)
	Fixtures.connect_floors(t, top, 132)  # a local lift for guests (#368: rooms no route reaches are not used); staff ride service shafts only
	if station:
		_place(t, "housekeeping", STATION_FLOOR, STATION_X)
	return t


static func _room(t: TowerSim, floor_number: int, x: int) -> int:
	return _place(t, "hotel_single", floor_number, x)


## Places a room and returns its id (place_room returns only a code), or -1 when refused.
static func _place(t: TowerSim, kind: String, floor_number: int, x: int) -> int:
	if t.rooms.place_room(t.grid, t.floors, t.ledger, 0, CatalogueScript.IDS.find(kind), floor_number, x) != RoomsScript.OK:
		return -1
	return t.grid.cell_at(floor_number, x)


## Marks a room dirty since the tick, as a check-out would.
static func _dirty(t: TowerSim, room: int, since: int = 0) -> void:
	t.hotel._records[room] = [HotelScript.VACANT, -1, -1, 420, -1, 0, since, 0] as Array[int]


## A room on the floor at x, already dirty.
static func _dirty_room(t: TowerSim, floor_number: int, x: int, since: int = 0) -> int:
	var room := _room(t, floor_number, x)
	_dirty(t, room, since)
	return room


static func _service_link(t: TowerSim, top: int) -> void:
	var shaft := TestServiceElevator._shaft(t, "service_shaft", 1, top, LINK_X)
	t.rooms.add_car(t.ledger, 0, 3, shaft, 1)


static func _dirty_count(t: TowerSim, rooms: Array) -> int:
	var n := 0
	for room: int in rooms:
		if t.hotel.is_dirty(room):
			n += 1
	return n


## Starts the day at 7:00 (day 0) and steps to the minute of day.
static func _day_to(t: TowerSim, minute: int) -> void:
	TestHotel._jump(t, HousekeepingScript.SHIFT_FROM, 0)
	TestHotel._step_to(t, minute, 0)


static func run(check: Callable) -> void:
	# A station brings six staff; a second station doubles them; no station, no staff.
	var s := _tower(6)
	var station := s.grid.cell_at(STATION_FLOOR, STATION_X)
	check.call(station > 0 and s.housekeeping.staff_count() == 0, "no staff before the first tick")
	s.step()
	check.call(s.housekeeping.staff_count() == 6 and s.housekeeping.staff_of(station) == 6, "a station employs six housekeepers")
	var second := _place(s, "housekeeping", 4, STATION_X)
	TestHotel._jump(s, 8 * 60, 0)
	s.step()
	check.call(second > 0 and s.housekeeping.staff_count() == 12 and s.housekeeping.staff_of(second) == 6, "a second station adds six more")
	var bare := _tower(6, false)
	bare.step()
	check.call(bare.housekeeping.staff_count() == 0, "no station, no housekeepers")
	var removal := s.rooms.check_bulldoze(s.grid, s.floors, STATION_FLOOR, STATION_X)
	check.call(removal["reason"] == RoomsScript.PERMANENT, "a housekeeping station cannot be bulldozed")

	# With a service shaft the staff clean rooms on every floor, and the rooms are clean by noon.
	var w := _tower(6)
	_service_link(w, 6)
	var rooms: Array = []
	for f in range(3, 7):
		rooms.append(_dirty_room(w, f, 120))
	TestHotel._jump(w, HousekeepingScript.SHIFT_FROM, 0)
	w.step()
	check.call(_dirty_count(w, rooms) == 4 and w.housekeeping.busy_count() == 4, "at the start of the shift all four rooms are dirty and four staff are on the way")
	TestHotel._step_to(w, 12 * 60, 0)
	check.call(_dirty_count(w, rooms) == 0, "with a service shaft all rooms are clean by noon")
	check.call(w.housekeeping.busy_count() == 0, "the staff are idle once the work is done")

	# Without a service shaft only the station's own floor is reached (they walk, they never fly).
	var n := _tower(6)
	var n_rooms: Array = []
	for f in range(3, 7):
		n_rooms.append(_dirty_room(n, f, 120))
	_day_to(n, 12 * 60)
	check.call(not n.hotel.is_dirty(n_rooms[0]) and _dirty_count(n, n_rooms) == 3, "without a service shaft only the home floor is cleaned")
	TestHotel._step_to(n, 17 * 60 + 30, 0)
	check.call(_dirty_count(n, n_rooms) == 3, "an unreachable dirty room stays dirty all day")

	# Standard cars and escalators are never used by staff; stairs are.
	var std := _tower(6)
	var std_shaft := TestServiceElevator._shaft(std, "local_shaft", 1, 6, LINK_X)
	std.rooms.add_car(std.ledger, 0, 3, std_shaft, 1)
	var std_room := _dirty_room(std, 4, 120)
	_day_to(std, 12 * 60)
	check.call(std.hotel.is_dirty(std_room), "housekeepers never ride a standard elevator")
	var esc := _tower(6)
	check.call(esc.rooms.place_escalator(esc.grid, esc.floors, esc.ledger, 0, STATION_FLOOR, LINK_X) == RoomsScript.OK, "the test escalator is placed")
	var esc_room := _dirty_room(esc, 4, 124)
	_day_to(esc, 12 * 60)
	check.call(esc.hotel.is_dirty(esc_room), "housekeepers never ride an escalator")
	var stairs := _tower(6)
	check.call(stairs.rooms.place_stairs(stairs.grid, stairs.floors, stairs.ledger, 0, STATION_FLOOR, LINK_X) == RoomsScript.OK, "the test stairs are placed")
	var stairs_room := _dirty_room(stairs, 4, 124)
	_day_to(stairs, 12 * 60)
	check.call(not stairs.hotel.is_dirty(stairs_room), "housekeepers use stairs")

	# One staff per floor: seven dirty rooms on one floor keep only one housekeeper busy.
	var one := _tower(6)
	_service_link(one, 6)
	for x in ROW_X:
		_dirty_room(one, 4, x)
	_day_to(one, 7 * 60 + 15)
	check.call(one.housekeeping.busy_count() == 1, "one housekeeper per floor: seven rooms on one floor keep one busy")

	# The oldest dirty room goes first.
	var old := _tower(6)
	_service_link(old, 6)
	var newer := _dirty_room(old, 4, 120, 50)
	var older := _dirty_room(old, 4, 124, 10)
	_day_to(old, 7 * 60 + 40)
	check.call(not old.hotel.is_dirty(older) and old.hotel.is_dirty(newer), "the oldest dirty room is cleaned first")

	# About 18 rooms a day: one housekeeper on a floor whose rooms keep getting dirty again.
	var rate := _tower(6)
	_service_link(rate, 6)
	var rate_rooms: Array = []
	for x in ROW_X:
		rate_rooms.append(_dirty_room(rate, 4, x))
	TestHotel._jump(rate, HousekeepingScript.SHIFT_FROM, 0)
	var cleaned := 0
	var rate_target := TestOfficeDay._tick_at(18 * 60, 0)
	var guard := 0
	while rate.tick < rate_target and guard < TestHotel.MAX_TICKS:
		rate.step()
		guard += 1
		for room: int in rate_rooms:
			if not rate.hotel.is_dirty(room):
				cleaned += 1
				_dirty(rate, room, rate.tick)
	check.call(cleaned >= 16 and cleaned <= 22, "one housekeeper cleans about 18 rooms in a day (got %d)" % cleaned)

	# The soft window: seven dirty floors, six staff, the six nearest are worked first.
	var tall := _tower(10)
	_service_link(tall, 10)
	var by_floor: Dictionary = {}
	for f in range(4, 11):
		by_floor[f] = _dirty_room(tall, f, 120)
	_day_to(tall, 7 * 60 + 5)
	check.call(tall.housekeeping.busy_count() == 6, "six housekeepers take six floors at once")
	check.call(tall.hotel.is_dirty(by_floor[10]) and tall.housekeeping.is_claimed(by_floor[4]) and not tall.housekeeping.is_claimed(by_floor[10]), "the six nearest dirty floors are worked first; the seventh waits")
	TestHotel._step_to(tall, 12 * 60, 0)
	check.call(_dirty_count(tall, by_floor.values()) == 0, "the far floor is cleaned once a housekeeper is free")

	# Saving mid-job restores the same tower, and a damaged record is refused.
	var sv := _tower(6)
	_service_link(sv, 6)
	_dirty_room(sv, 5, 120)
	_day_to(sv, 7 * 60 + 10)
	var copy := TowerSim.new(1, 100000000)
	check.call(sv.housekeeping.busy_count() == 1 and copy.load_state(sv.save()) and copy.state_hash() == sv.state_hash() and copy.housekeeping.busy_count() == 1, "save: a housekeeper mid-job survives a save and load")
	var ints := sv.housekeeping.state_ints()
	ints[1 + 3] = 9
	check.call(not HousekeepingScript.valid_ints(ints) and not HousekeepingScript.valid_ints([3] as Array[int]), "damaged housekeeper records are refused")
